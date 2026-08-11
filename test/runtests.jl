using Pkg.BinaryPlatforms, JSON
using VersionsJSONUtil
import VersionsJSONUtil: WindowsPortable, WindowsTarball, MacOSTarball
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
        # A live URL proceeds to the completeness/staleness checks
        @test action(200, false) == :proceed
        @test action(200, true) == :proceed
        # A URL that is already in versions.json must never be deleted or marked
        # nonexistent because of a non-200 HEAD (the CDN is known to serve stale
        # per-POP 404s): keep the existing entry
        @test action(404, true) == :keep_existing
        @test action(500, true) == :keep_existing
        # A 404 for a URL we never knew: that version/platform simply doesn't exist
        @test action(404, false) == :skip_nonexistent
        # Any other status for an unknown URL is transient: retry next run
        @test action(500, false) == :skip_transient
        @test action(503, false) == :skip_transient
        # status 0 = the HEAD request itself failed (DNS, connection reset, ...)
        @test action(0, true) == :keep_existing
        @test action(0, false) == :skip_transient
    end

    @testset "entry_size_matches" begin
        matches = VersionsJSONUtil.entry_size_matches
        entry = Dict("size" => 1234)
        @test matches(entry, 1234)
        # A different Content-Length means the published file was replaced
        @test !matches(entry, 1235)
        # An absent Content-Length cannot be checked; trust the seed
        @test matches(entry, 0)
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
        # Missing a required field
        @test !complete(delete!(copy(targz), "sha256"), url)
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
end
