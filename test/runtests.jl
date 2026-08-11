using JSON: JSON
using Pkg: Pkg
using Test: Test, @testset, @test
using Pkg.BinaryPlatforms: Linux, MacOS, Windows, FreeBSD
using URIs: URIs, URI
using VersionsJSONUtil: VersionsJSONUtil, WindowsPortable, WindowsTarball, MacOSTarball

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
            @test VersionsJSONUtil.download_url(v, p) == URI(url)
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
        # A 404 for a URL we never knew is recorded as nonexistent
        @test action(404, false) == :mark_nonexistent
        # Any other status for an unknown URL is transient: record nothing
        @test action(500, false) == :skip_transient
        @test action(503, false) == :skip_transient
    end

    @testset "stored_headinfo_matches" begin
        matches = VersionsJSONUtil.stored_headinfo_matches
        HeadInfo = VersionsJSONUtil.HeadInfo
        StoredHeadInfo = VersionsJSONUtil.StoredHeadInfo
        stored = StoredHeadInfo(; etag = "\"abc\"", last_modified = "Mon, 01 Jan 2024 00:00:00 GMT")
        fresh(; status = 200, etag = stored.etag, last_modified = stored.last_modified) =
            HeadInfo(; status, etag, last_modified)
        @test matches(stored, fresh())
        # No recorded headers -> we cannot know whether the record is stale
        @test !matches(nothing, fresh())
        @test !matches(StoredHeadInfo(), fresh())
        # Changed headers -> stale
        @test !matches(stored, fresh(; etag = "\"xyz\""))
        @test !matches(stored, fresh(; last_modified = "Tue, 02 Jan 2024 00:00:00 GMT"))
        # Non-200 -> not a usable comparison
        @test !matches(stored, HeadInfo(; status = 404, etag = nothing, last_modified = nothing))
    end

    @testset "filedict_is_complete_and_good" begin
        complete = VersionsJSONUtil.filedict_is_complete_and_good
        FileDict = VersionsJSONUtil.FileDict
        base = Dict{String, Any}(
            "arch" => VersionsJSONUtil.ArchEnum.x86_64,
            "extension" => VersionsJSONUtil.ExtensionEnum.T("tar.gz"),
            "kind" => VersionsJSONUtil.KindEnum.T("archive"),
            "os" => VersionsJSONUtil.OsEnum.T("linux"),
            "sha256" => "0" ^ 64,
            "size" => 1,
            "triplet" => Linux(:x86_64).p,
            "url" => "https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.2-linux-x86_64.tar.gz",
            "version" => v"1.6.2",
        )
        # A .tar.gz entry additionally requires the git tree hashes
        @test !complete(FileDict(base))
        targz = merge(base, Dict{String, Any}(
            "git-tree-sha1" => VersionsJSONUtil.SHA1("1" ^ 40),
            "git-tree-sha256" => "2" ^ 64,
        ))
        @test complete(FileDict(targz))
        # Non-tarball entries don't need tree hashes
        exe = merge(base, Dict{String, Any}(
            "extension" => VersionsJSONUtil.ExtensionEnum.T("exe"),
            "kind" => VersionsJSONUtil.KindEnum.T("installer"),
        ))
        @test complete(FileDict(exe))
    end
end
