using JSON: JSON
using StatsBase: StatsBase
using Test: Test, @testset, @test, @test_skip
using URIs: URIs, URI

# We intentionally don't load VersionsJSONUtils in these tests.
# This is because we want these tests to be as independent from VersionsJSONUtils as possible.

function check_usage()
    scriptname = basename(@__FILE__)
    if length(ARGS) != 2
        usage_msg = "Usage: julia $scriptname \$filename \$test_type"
        println(stderr, usage_msg)
        println(stderr, "\$filename should be the filename of the versions.json file")
        println(stderr, "\$test_type should be either partial or full")
        println(stderr, "")
        error(usage_msg)
    end
    return nothing
end

function get_cli_args()
    check_usage()
    filename = strip(ARGS[1])
    if !isfile(filename)
        error("File does not exist: $filename")
    end
    test_type_str = strip(ARGS[2])
    if test_type_str == "partial"
        test_type = :partial
    elseif test_type_str == "full"
        test_type = :full
    else
        error("Invalid value for test_type: $test_type. Valid values are: partial, full")
    end
    return (; filename, test_type)
end

const tarball_git_tree_hash_skiplist = [
    # Corrupt gzip stream: `7z` reports a CRC failure for the embedded tarball.
    URI("https://julialang-s3.julialang.org/bin/linux/x86/0.7/julia-0.7.0-alpha-linux-i686.tar.gz"),
]

check_usage()

@testset "Post-build tests" begin
    opts = get_cli_args()
    dict = JSON.parsefile(opts.filename)

    # This is used in the "Make sure we found at least X files" testset below
    total_files_all_julia_versions = 0

    @testset "Main stuff" begin
        @test dict isa AbstractDict
        @test !isempty(dict)
        for (ver_str, ver_dict) in pairs(dict)
            ver = VersionNumber(ver_str)

            # This catches regressions like https://github.com/JuliaLang/VersionsJSONUtil.jl/pull/32#issuecomment-2617551478
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
            found_urls = []

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

                        # etag and last-modified are technically optional.
                        # Because in theory we don't know what the upstream is, and if it
                        # supports these headers.
                        # But in practice, we know that the upstream is S3
                        # and we know that it supports these two headers.
                        # So for the purpose of these tests, we treat these as required
                        "etag",
                        "last-modified",
                    ]
                    optional_keys = [
                        "asc",
                    ]

                    # Technically, git-tree-sha1 and git-tree-sha256 are optional keys.
                    # However, for the purposes of these tests, we treat them as required
                    # for tar.gz files, and optional for other files.
                    @test haskey(filedict, "extension")
                    ext = filedict["extension"]
                    treehash_keys = [
                        "git-tree-sha1",
                        "git-tree-sha256",
                    ]
                    file_url = URI(filedict["url"])
                    if ext == "tar.gz" && !(file_url in tarball_git_tree_hash_skiplist)
                        append!(required_keys, treehash_keys)
                    else
                        append!(optional_keys, treehash_keys)
                    end

                    allowed_keys = union(required_keys, optional_keys)

                    observed_keys_this_filedict = collect(keys(filedict))

                    if !(required_keys ⊆ observed_keys_this_filedict)
                        for k in required_keys
                            if !(k in observed_keys_this_filedict)
                                @info "Missing required key: $k"
                            end
                        end
                    end
                    if !(observed_keys_this_filedict ⊆ allowed_keys)
                        for k in observed_keys_this_filedict
                            if !(k in allowed_keys)
                                @info "Key is present, but it shouldn't be: $k"
                            end
                        end
                    end

                    @test required_keys ⊆ observed_keys_this_filedict
                    @test observed_keys_this_filedict ⊆ allowed_keys

                    # This will be used in the "Tier 1" testset below
                    push!(found_platforms, (filedict["triplet"], filedict["extension"]))

                    # This will be used in the "No duplicate URLs" testset below
                    push!(found_urls, filedict["url"])

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
                        @test occursin(r"^[0-9a-f]*?$", filedict["sha256"])
                        @test length(filedict["sha256"]) == 64
                        bytes = hex2bytes(filedict["sha256"])
                        @test length(bytes) == 32
                    end
                    @testset "size field" begin
                        @test filedict["size"] isa Integer
                        @test filedict["size"] > 0
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
                        url_obj = URI(filedict["url"])
                        @test url_obj isa URI
                        @test url_obj.scheme == "https"
                        allowed_hosts = [
                            "julialang-s3.julialang.org",
                        ]
                        @test url_obj.host in allowed_hosts
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
                    @testset "etag field (optional)" begin
                        if haskey(filedict, "etag")
                            etag = lowercase(strip(filedict["etag"]))
                            @test !isempty(etag)
                            @test etag != "null"
                            @test etag != "nothing"

                            # Guaranteed to be ASCII, per spec
                            # > Entity tag that uniquely represents the requested resource.
                            # It is a string of ASCII characters placed between double quotes
                            # Source: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/ETag
                            @test isascii(etag)
                        end
                    end
                    @testset "last-modified field (optional)" begin
                        if haskey(filedict, "last-modified")
                            @test !isempty(strip(filedict["last-modified"]))
                            last_modified = lowercase(strip(filedict["last-modified"]))
                            @test !isempty(last_modified)
                            @test last_modified != "null"
                            @test last_modified != "nothing"

                            @test isascii(last_modified)
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

            @testset "No duplicate URLs" begin
                for (url, count) in StatsBase.countmap(found_urls)
                    if count != 1
                        @info "URL $url appeared $count times"
                    end
                    @test count == 1
                end
            end
        end
    end

    @testset "Testset to make sure we found at least N versions and files" begin
        skip_these_tests = opts.test_type == :partial

        @testset "Make sure we found at least N files" begin
            # Increase this value over time:
            @test total_files_all_julia_versions >= 2190 skip=skip_these_tests
        end

        @testset "Make sure we found at least N Julia versions" begin
            julia_versions_str = collect(keys(dict))
            julia_versions = VersionNumber.(julia_versions_str)
            unique!(julia_versions)
            julia_versions_v1 = filter(x -> x.major == 1, julia_versions)
            julia_stable_versions_v1 = filter(x -> x.prerelease == (), julia_versions_v1)

            # Increase these values over time:
            @test length(julia_versions) >= 193 skip=skip_these_tests
            @test length(julia_versions_v1) >= 140 skip=skip_these_tests
            @test length(julia_stable_versions_v1) >= 71 skip=skip_these_tests
        end

    end
end
