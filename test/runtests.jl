using Pkg.BinaryPlatforms, JSON
using VersionsJSONUtil
import VersionsJSONUtil: WindowsPortable, WindowsTarball, MacOSTarball, Variant
using Test

const download_urls = Dict(
    v"1.7.0-beta3" => Dict(
        MacOS(:aarch64) =>              "https://julialang-s3.julialang.org/bin/mac/aarch64/1.7/julia-1.7.0-beta3-macaarch64.dmg",
    ),
    v"1.6.2" => Dict(
        Linux(:x86_64) =>               "https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.2-linux-x86_64.tar.gz",
        Linux(:i686) =>                 "https://julialang-s3.julialang.org/bin/linux/x86/1.6/julia-1.6.2-linux-i686.tar.gz",
        Linux(:aarch64) =>              "https://julialang-s3.julialang.org/bin/linux/aarch64/1.6/julia-1.6.2-linux-aarch64.tar.gz",
        Linux(:armv7l) =>               "https://julialang-s3.julialang.org/bin/linux/armv7l/1.6/julia-1.6.2-linux-armv7l.tar.gz",
        Linux(:powerpc64le) =>          "https://julialang-s3.julialang.org/bin/linux/ppc64le/1.6/julia-1.6.2-linux-ppc64le.tar.gz",
        Linux(:x86_64, libc = :musl) => "https://julialang-s3.julialang.org/bin/musl/x64/1.6/julia-1.6.2-musl-x86_64.tar.gz",
        MacOS(:x86_64) =>               "https://julialang-s3.julialang.org/bin/mac/x64/1.6/julia-1.6.2-mac64.dmg",
        MacOSTarball(:x86_64) =>        "https://julialang-s3.julialang.org/bin/mac/x64/1.6/julia-1.6.2-mac64.tar.gz",
        Windows(:x86_64) =>             "https://julialang-s3.julialang.org/bin/winnt/x64/1.6/julia-1.6.2-win64.exe",
        Windows(:i686) =>               "https://julialang-s3.julialang.org/bin/winnt/x86/1.6/julia-1.6.2-win32.exe",
        WindowsPortable(:x86_64) =>     "https://julialang-s3.julialang.org/bin/winnt/x64/1.6/julia-1.6.2-win64.zip",
        WindowsPortable(:i686) =>       "https://julialang-s3.julialang.org/bin/winnt/x86/1.6/julia-1.6.2-win32.zip",
        WindowsTarball(:x86_64) =>      "https://julialang-s3.julialang.org/bin/winnt/x64/1.6/julia-1.6.2-win64.tar.gz",
        WindowsTarball(:i686) =>        "https://julialang-s3.julialang.org/bin/winnt/x86/1.6/julia-1.6.2-win32.tar.gz",
        FreeBSD(:x86_64) =>             "https://julialang-s3.julialang.org/bin/freebsd/x64/1.6/julia-1.6.2-freebsd-x86_64.tar.gz",
    ),
)

@testset "VersionsJSONUtil.jl" begin
    @testset "Download URLs for $v" for v in keys(download_urls)
        for (p, url) in download_urls[v]
            @test VersionsJSONUtil.download_url(v, p) == url
        end
    end

    @testset "action_for_head_status" begin
        action = VersionsJSONUtil.action_for_head_status
        @test action(200, false) == :proceed
        @test action(200, true) == :proceed
        # never drop an already-published URL on a non-200 (the CDN serves stale 404s)
        @test action(404, true) == :keep_existing
        @test action(500, true) == :keep_existing
        # a 404 for an unknown URL: that version/platform doesn't exist
        @test action(404, false) == :skip_nonexistent
        @test action(500, false) == :skip_transient
        @test action(503, false) == :skip_transient
        # status 0 = the HEAD request itself failed
        @test action(0, true) == :keep_existing
        @test action(0, false) == :skip_transient
    end

    @testset "entry_matches_head" begin
        matches = VersionsJSONUtil.entry_matches_head
        head(; content_length = nothing, etag = nothing, last_modified = nothing) =
            (; status = 200, content_length, etag, last_modified)
        entry = Dict("size" => 1234)
        @test matches(entry, head(content_length = 1234))
        @test !matches(entry, head(content_length = 1235))
        # absent Content-Length header can't be checked
        @test matches(entry, head())
        # but a real zero-length response is a mismatch
        @test !matches(entry, head(content_length = 0))
        # entry without etag: size alone decides
        @test matches(entry, head(content_length = 1234, etag = "\"abc\""))
        etag_entry = Dict("size" => 1234, "etag" => "\"abc\"")
        @test matches(etag_entry, head(content_length = 1234, etag = "\"abc\""))
        @test !matches(etag_entry, head(content_length = 1234, etag = "\"xyz\""))
        # absent ETag header can't be checked
        @test matches(etag_entry, head(content_length = 1234))
        # entry without last-modified: reused once size and etag match
        @test matches(etag_entry, head(content_length = 1234, etag = "\"abc\"", last_modified = "Mon, 01 Jan 2024 00:00:00 GMT"))
        full_entry = Dict("size" => 1234, "etag" => "\"abc\"", "last-modified" => "Mon, 01 Jan 2024 00:00:00 GMT")
        @test matches(full_entry, head(content_length = 1234, etag = "\"abc\"", last_modified = "Mon, 01 Jan 2024 00:00:00 GMT"))
        @test !matches(full_entry, head(content_length = 1234, etag = "\"abc\"", last_modified = "Tue, 02 Jan 2024 00:00:00 GMT"))
        @test !matches(full_entry, head(content_length = 1234, etag = "\"xyz\"", last_modified = "Mon, 01 Jan 2024 00:00:00 GMT"))
        # absent Last-Modified header can't be checked
        @test matches(full_entry, head(content_length = 1234, etag = "\"abc\""))
    end

    @testset "filedict_is_complete" begin
        complete = VersionsJSONUtil.filedict_is_complete
        url = "https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.2-linux-x86_64.tar.gz"
        base = Dict(
            "arch" => "x86_64", "extension" => "tar.gz", "kind" => "archive",
            "os" => "linux", "sha256" => "0"^64, "size" => 1,
            "triplet" => "x86_64-linux-gnu", "url" => url, "version" => "1.6.2",
        )
        # A .tar.gz entry additionally requires the git tree hashes
        @test !complete(base, url)
        targz = merge(base, Dict("git-tree-sha1" => "1"^40, "git-tree-sha256" => "2"^64))
        @test complete(targz, url)
        # Non-tarball entries don't need tree hashes
        exe_url = replace(url, ".tar.gz" => ".exe")
        @test complete(base, exe_url)
        # Missing, blank, or malformed fields
        @test !complete(delete!(copy(targz), "sha256"), url)
        @test !complete(merge(targz, Dict("version" => "  ")), url)
        @test !complete(merge(targz, Dict("git-tree-sha1" => "not-a-hash")), url)
        @test !complete(merge(targz, Dict("git-tree-sha256" => "3"^63)), url)
        # extension check is case-insensitive
        @test !complete(base, replace(url, ".tar.gz" => ".TAR.GZ"))
        # The skiplisted corrupt tarball is exempt from the tree-hash requirement
        skiplisted = VersionsJSONUtil.tarball_git_tree_hash_skiplist[1]
        @test complete(base, skiplisted)
    end

    @testset "load_seed / checkpoint round-trip" begin
        mktempdir() do dir
            out_path = joinpath(dir, "versions.json")
            # No seed at all -> empty (a full rebuild)
            meta = VersionsJSONUtil.load_seed(out_path)
            @test isempty(meta)
            meta[v"1.6.2"] = Dict("stable" => true, "files" => [Dict("url" => "https://example.invalid/a.tar.gz")])
            VersionsJSONUtil.checkpoint(out_path, meta)
            meta2 = VersionsJSONUtil.load_seed(out_path)
            @test haskey(meta2, v"1.6.2")
            @test only(meta2[v"1.6.2"]["files"])["url"] == "https://example.invalid/a.tar.gz"
            # A key that doesn't parse as a version is skipped, not fatal
            write(out_path, """{"1.6.2": {"stable": true, "files": []}, "not-a-version": {"stable": false, "files": []}}""")
            meta3 = VersionsJSONUtil.load_seed(out_path)
            @test haskey(meta3, v"1.6.2") && length(meta3) == 1
        end
    end

    @testset "kind_and_extension" begin
        kind_and_extension = VersionsJSONUtil.kind_and_extension
        @test kind_and_extension("julia-1.6.2-linux-x86_64.tar.gz") == ("archive", "tar.gz")
        @test kind_and_extension("julia-1.6.2-win64.zip") == ("archive", "zip")
        @test kind_and_extension("julia-1.6.2-win64.exe") == ("installer", "exe")
        @test kind_and_extension("julia-1.6.2-mac64.dmg") == ("archive", "dmg")
        @test_throws ErrorException kind_and_extension("julia-1.6.2-linux-x86_64.tar.xz")
    end

    @testset "Nightly download URLs" begin
        nightly_url = VersionsJSONUtil.nightly_url
        base = "https://julialangnightlies-s3.julialang.org/bin/"
        # the names juliaup and julialang.org use
        @test nightly_url(Linux(:x86_64)) == base * "linux/x86_64/julia-latest-linux-x86_64.tar.gz"
        @test nightly_url(Linux(:i686)) == base * "linux/i686/julia-latest-linux-i686.tar.gz"
        @test nightly_url(Linux(:aarch64), v"1.13") == base * "linux/aarch64/1.13/julia-latest-linux-aarch64.tar.gz"
        @test nightly_url(Linux(:x86_64; libc = :musl)) == base * "musl/x86_64/julia-latest-musl-x86_64.tar.gz"
        @test nightly_url(MacOS(:x86_64)) == base * "macos/x86_64/julia-latest-macos-x86_64.dmg"
        @test nightly_url(MacOSTarball(:aarch64)) == base * "macos/aarch64/julia-latest-macos-aarch64.tar.gz"
        @test nightly_url(MacOSTarball(:aarch64), v"1.12") == base * "macos/aarch64/1.12/julia-latest-macos-aarch64.tar.gz"
        @test nightly_url(Windows(:x86_64)) == base * "winnt/x64/julia-latest-win64.exe"
        @test nightly_url(Windows(:i686)) == base * "winnt/x86/julia-latest-win32.exe"
        @test nightly_url(WindowsPortable(:x86_64)) == base * "winnt/x64/julia-latest-win64.zip"
        @test nightly_url(WindowsTarball(:i686), v"1.12") == base * "winnt/x86/1.12/julia-latest-win32.tar.gz"
        @test nightly_url(FreeBSD(:x86_64)) == base * "freebsd/x86_64/julia-latest-freebsd-x86_64.tar.gz"
        # variants: julia-buildkite's canonical names only (no winnt/x64 style aliases)
        @test nightly_url(Variant(Linux(:x86_64), "opt")) == base * "linuxopt/x86_64/julia-latest-linuxopt-x86_64.tar.gz"
        @test nightly_url(Variant(Linux(:x86_64), "assert"), v"1.14") == base * "linuxassert/x86_64/1.14/julia-latest-linuxassert-x86_64.tar.gz"
        @test nightly_url(Variant(Linux(:aarch64), "opt")) == base * "linuxopt/aarch64/julia-latest-linuxopt-aarch64.tar.gz"
        @test nightly_url(Variant(MacOS(:aarch64), "opt")) == base * "macosopt/aarch64/julia-latest-macosopt-aarch64.tar.gz"
        @test nightly_url(Variant(Windows(:x86_64), "opt")) == base * "windowsopt/x86_64/julia-latest-windowsopt-x86_64.tar.gz"
        @test nightly_url(Variant(FreeBSD(:x86_64), "opt")) == base * "freebsdopt/x86_64/julia-latest-freebsdopt-x86_64.tar.gz"
    end

    @testset "nightly_platforms" begin
        platforms = VersionsJSONUtil.nightly_platforms()
        # every standard platform, plus each variant for each base (non-wrapped) platform
        @test platforms[1:length(VersionsJSONUtil.julia_platforms)] == VersionsJSONUtil.julia_platforms
        variants = filter(p -> p isa Variant, platforms)
        nbase = count(p -> p isa VersionsJSONUtil.BasePlatform, VersionsJSONUtil.julia_platforms)
        @test nbase == 11
        @test length(variants) == nbase * length(VersionsJSONUtil.nightly_variants)
        @test any(v -> v.name == "opt" && triplet(v) == "x86_64-linux-gnu", variants)
        @test any(v -> v.name == "assert" && triplet(v) == "aarch64-linux-gnu", variants)
        @test allunique(VersionsJSONUtil.nightly_url.(platforms))
    end

    @testset "nightly_file_dict" begin
        nightly_file_dict = VersionsJSONUtil.nightly_file_dict
        url = "https://julialangnightlies-s3.julialang.org/bin/linuxopt/x86_64/julia-latest-linuxopt-x86_64.tar.gz"
        d = nightly_file_dict(Variant(Linux(:x86_64), "opt"), url; asc_url = url * ".asc")
        @test Set(keys(d)) == Set(["triplet", "os", "arch", "kind", "extension", "url", "asc-url", "variants"])
        @test d["triplet"] == "x86_64-linux-gnu"
        @test d["os"] == "linux"
        @test d["arch"] == "x86_64"
        @test d["kind"] == "archive"
        @test d["extension"] == "tar.gz"
        @test d["url"] == url
        @test d["asc-url"] == url * ".asc"
        @test d["variants"] == ["opt"]

        url = "https://julialangnightlies-s3.julialang.org/bin/macos/aarch64/julia-latest-macos-aarch64.dmg"
        d = nightly_file_dict(MacOS(:aarch64), url)
        @test Set(keys(d)) == Set(["triplet", "os", "arch", "kind", "extension", "url"])
        @test d["triplet"] == "aarch64-apple-darwin14"
        @test d["os"] == "mac"
        @test d["extension"] == "dmg"

        url = "https://julialangnightlies-s3.julialang.org/bin/winnt/x64/julia-latest-win64.exe"
        d = nightly_file_dict(Windows(:x86_64), url)
        @test d["os"] == "winnt"
        @test d["arch"] == "x86_64"
        @test d["kind"] == "installer"
        @test !haskey(d, "variants")
    end

    @testset "candidate_series" begin
        candidate_series = VersionsJSONUtil.candidate_series
        # tagged series newest first, followed by the two series after the newest tag
        @test candidate_series([v"1.12.0", v"1.13.0-rc3", v"1.12.5", v"0.7.0"]) ==
            [v"1.15", v"1.14", v"1.13", v"1.12", v"0.7"]
        @test candidate_series([v"1.13.0"]) == [v"1.15", v"1.14", v"1.13"]
    end
end
