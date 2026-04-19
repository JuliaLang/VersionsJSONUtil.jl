import JSON
import Test

using Test: @testset, @test

const filename = only(ARGS)

const dict = JSON.parsefile(filename)

# This catches regressions like https://github.com/JuliaLang/VersionsJSONUtil.jl/pull/32#issuecomment-2617551478
for (k_str, _) in pairs(dict)
    k_ver = VersionNumber(k_str)
    @test k_ver isa VersionNumber
end

@testset "Post-build tests" begin
    # This is used in the "Make sure we found at least X files" testset below
    total_files_all_julia_versions = 0

    @testset "Main stuff" begin
        @test dict isa AbstractDict
        @test !isempty(dict)
        for (ver_str, ver_dict) in pairs(dict)
            ver = VersionNumber(ver_str)

            @test ver isa VersionNumber

            @test ver_dict isa AbstractDict
            @test !isempty(ver_dict)

            expected_keys = [
                "stable",
                "files",
            ]
            @test Set(collect(keys(ver_dict))) == Set(expected_keys)

            @test ver_dict["stable"] isa Bool
            if ver_dict["stable"]
                @test ver.prerelease == ()
            else
                @test ver.prerelease != ()
                @test !isempty(strip(join(ver.prerelease)))
            end

            filedicts_array = ver_dict["files"]
            @test filedicts_array isa AbstractArray
            @test !isempty(filedicts_array)

            # This will be used in the "Tier 1" testset below
            found_platforms = []

            @testset "Iterate over filedicts in the filedicts_array" begin
                for filedict in filedicts_array
                    # This is used in the "Make sure we found at least X files" testset below
                    total_files_all_julia_versions += 1

                    required_keys = [
                        "arch",
                        "extension",
                        "kind",
                        "os",
                        "sha256",
                        "size",
                        "triplet",
                        "url",
                        "version",
                    ]
                    optional_keys = [
                        "asc",
                        "git-tree-sha1",
                        "git-tree-sha256",
                    ]
                    allowed_keys = union(required_keys, optional_keys)
                    @test required_keys ⊆ collect(keys(filedict))
                    @test collect(keys(filedict)) ⊆ allowed_keys

                    # This will be used in the "Tier 1" testset below
                    push!(found_platforms, (filedict["triplet"], filedict["extension"]))

                    @testset "arch field" begin
                        allowed_arches = [
                            "x86_64",
                            "i686",
                            "aarch64",
                            "armv7l",
                            "powerpc64le",
                        ]
                        @test filedict["arch"] isa AbstractString
                        @test filedict["arch"] in allowed_arches
                    end
                    @testset "extension field" begin
                        allowed_extensions = [
                            "exe",
                            "dmg",
                            "tar.gz",
                            "zip",
                        ]
                        @test filedict["extension"] isa AbstractString
                        @test filedict["extension"] in allowed_extensions
                    end
                    @testset "kind field" begin
                        allowed_kinds = [
                            "archive",
                            "installer",
                        ]
                        @test filedict["kind"] isa AbstractString
                        @test filedict["kind"] in allowed_kinds
                    end
                    @testset "os field" begin
                        allowed_os = [
                            "mac",
                            "winnt",
                            "linux",
                            "freebsd",
                        ]
                        @test filedict["os"] isa AbstractString
                        @test filedict["os"] in allowed_os
                    end
                    @testset "sha256 field" begin
                        @test filedict["sha256"] isa AbstractString
                        @test occursin(r"^[a-z0-9]*?$", filedict["sha256"])
                        @test length(filedict["sha256"]) == 64
                    end
                    @testset "size field" begin
                        @test filedict["size"] isa Integer
                        @test filedict["size"] >= 0 # TODO: Make this strictly >
                    end
                    @testset "triplet field" begin
                        allowed_triplets = [
                            # Linux:
                            "x86_64-linux-gnu",
                            "i686-linux-gnu",
                            "x86_64-linux-musl",
                            "aarch64-linux-gnu",
                            "armv7l-linux-gnueabihf",
                            "powerpc64le-linux-gnu",

                            # macOS:
                            "aarch64-apple-darwin14",
                            "x86_64-apple-darwin14",

                            # Windows:
                            "x86_64-w64-mingw32",
                            "i686-w64-mingw32",

                            # FreeBSD:
                            "x86_64-unknown-freebsd11.1",
                        ]
                        @test filedict["triplet"] isa AbstractString
                        @test filedict["triplet"] in allowed_triplets
                    end
                    @testset "url field" begin
                        @test filedict["url"] isa AbstractString
                        @test !isempty(strip(filedict["url"]))
                        # TODO: Parse the url as a URIs.URI and do some checks on it
                        # (1) Make sure it parses validly
                        # (2) Make sure it is HTTP
                        # (3) Make sure the domain is julialang-s3.julialang.org
                    end
                    @testset "version field" begin
                        @test VersionNumber(filedict["version"]) isa VersionNumber
                        @test VersionNumber(filedict["version"]) == ver
                    end

                    @testset "asc field (optional)" begin
                        if haskey(filedict, "asc")
                            @test filedict["asc"] isa AbstractString
                            @test startswith(filedict["asc"], "-----BEGIN PGP SIGNATURE-----")
                            @test endswith(chomp(filedict["asc"]), "-----END PGP SIGNATURE-----")
                        end
                    end
                end # for filedict in filedicts_array
            end # testset "Iterate over filedicts in the filedicts_array"

            @testset "Tier 1 platforms always have binaries" begin
                # These tests catch regressions like https://github.com/JuliaLang/VersionsJSONUtil.jl/issues/49

                # We omit these tests for pre-1.0 versions of Julia
                # We also omit these tests for prereleases
                if (ver >= v"1.0.0") && (ver.prerelease == ())
                    tier1_platform_list = [
                        # These are always Tier 1, regardless of the Julia version:
                        ("x86_64-linux-gnu", "tar.gz"), # Linux glibc x86_64 (64-bit)
                        ("x86_64-w64-mingw32", "tar.gz"), # Windows x86_64 (64-bit)
                        ("x86_64-w64-mingw32", "exe"), # Windows x86_64 (64-bit)

                        # These are currently Tier 1, might eventually get deprecated:
                        ("x86_64-apple-darwin14", "tar.gz"), # macOS x86_64 (64-bit)
                        ("x86_64-apple-darwin14", "dmg"), # macOS x86_64 (64-bit)
                    ]

                    if ver >= v"1.7.4"
                        # macOS Apple Silicon is only a Tier 1 for newer Julia versions
                        # Older Julia versions don't have native builds for Apple Silicon
                        push!(tier1_platform_list, ("aarch64-apple-darwin14", "tar.gz")) # macOS aarch64 (64-bit)
                        push!(tier1_platform_list, ("aarch64-apple-darwin14", "dmg")) # macOS aarch64 (64-bit)
                    end

                    @test length(tier1_platform_list) >= 5

                    # Very specific bug:
                    # Julia 1.4.0 is missing the .tar.gz for macOS x86_64
                    # We should fix this, but for now, exclude the .tar.gz in the tests
                    # Keep the .dmg
                    if ver == v"1.4.0"
                        filter!(x -> x != ("x86_64-apple-darwin14", "tar.gz"), tier1_platform_list)
                    end

                    @test length(tier1_platform_list) >= 4

                    if !(tier1_platform_list ⊆ found_platforms)
                        println(stderr, "Version is missing Tier 1 platforms: $(ver)")
                        for plat in tier1_platform_list
                            if !(plat in found_platforms)
                                println(stderr, "Version $ver is missing: $plat")
                            end
                        end
                    end
                    @test tier1_platform_list ⊆ found_platforms
                end
            end

        end
    end

    @testset "Make sure we found at least X files" begin
        @test total_files_all_julia_versions >= 2190 # increase this value over time
    end

    @testset "Make sure we found at least N Julia versions" begin
        julia_versions_str = collect(keys(dict))
        julia_versions = VersionNumber.(julia_versions_str)
        unique!(julia_versions)
        @test length(julia_versions) >= 193 # increase this value over time

        julia_versions_v1 = filter(x -> x.major == 1, julia_versions)
        @test length(julia_versions_v1) >= 140 # increase this value over time

        julia_stable_versions_v1 = filter(x -> x.prerelease == (), julia_versions_v1)
        @test length(julia_stable_versions_v1) >= 71 # increase this value over time
    end
end
