# Post-build tests for a generated nightlies.json (the nightlies counterpart of more_tests.jl)
import JSON

using Test: @testset, @test

const filename = only(ARGS)

const dict = JSON.parsefile(filename)

@testset "nightlies.json post-build tests" begin
    @test dict isa AbstractDict
    @test haskey(dict, "nightly")

    for (channel, channel_dict) in pairs(dict)
        @testset "$(channel)" begin
            @test occursin(r"^(\d+\.\d+-)?nightly$", channel)
            @test collect(keys(channel_dict)) ⊆ ["files", "variants"]
            @test haskey(channel_dict, "files")

            files = channel_dict["files"]
            @test files isa AbstractArray
            @test !isempty(files)
            variants = get(channel_dict, "variants", [])
            @test variants isa AbstractArray
            # (an absent "variants" is how an empty one is expressed)
            @test !haskey(channel_dict, "variants") || !isempty(variants)

            # (triplet, extension, variant) identifies a file within a channel
            found = Set()

            for (list, filedict) in Iterators.flatten((zip(Iterators.repeated("files"), files),
                                                       zip(Iterators.repeated("variants"), variants)))
                required_keys = [
                    "arch",
                    "extension",
                    "kind",
                    "os",
                    "triplet",
                    "url",
                ]
                optional_keys = [
                    "asc-url",
                ]
                if list == "variants"
                    push!(required_keys, "variant")
                end
                @test required_keys ⊆ collect(keys(filedict))
                @test collect(keys(filedict)) ⊆ union(required_keys, optional_keys)

                @test filedict["arch"] in ["x86_64", "i686", "aarch64", "armv7l", "powerpc64le"]
                @test filedict["extension"] in ["exe", "dmg", "tar.gz", "zip"]
                @test filedict["kind"] in ["archive", "installer"]
                @test filedict["os"] in ["mac", "winnt", "linux", "freebsd"]
                @test filedict["triplet"] in [
                    "x86_64-linux-gnu",
                    "i686-linux-gnu",
                    "x86_64-linux-musl",
                    "aarch64-linux-gnu",
                    "armv7l-linux-gnueabihf",
                    "powerpc64le-linux-gnu",
                    "aarch64-apple-darwin14",
                    "x86_64-apple-darwin14",
                    "x86_64-w64-mingw32",
                    "i686-w64-mingw32",
                    "x86_64-unknown-freebsd11.1",
                ]

                url = filedict["url"]
                @test startswith(url, "https://julialangnightlies-s3.julialang.org/bin/") ||
                      startswith(url, "https://julialang-nogpl.s3.amazonaws.com/bin-nogpl/")
                @test endswith(url, "." * filedict["extension"])
                # every URL is a "latest" one: the file behind it changes with every build
                @test occursin("/julia-latest-", url)
                if channel == "nightly"
                    @test !occursin(r"/\d+\.\d+/", url)
                else
                    series = replace(channel, "-nightly" => "")
                    @test occursin("/$(series)/julia-latest-", url)
                end

                if haskey(filedict, "asc-url")
                    @test filedict["asc-url"] == url * ".asc"
                    @test filedict["extension"] == "tar.gz"
                end

                variant = get(filedict, "variant", nothing)
                if list == "variants"
                    @test occursin(r"^[a-z0-9]+$", variant)
                    # only published as tarballs
                    @test filedict["extension"] == "tar.gz"
                    # the nogpl builds live in their own bucket
                    @test (variant == "nogpl") == startswith(url, "https://julialang-nogpl.s3.amazonaws.com/")
                end

                key = (filedict["triplet"], filedict["extension"], variant)
                @test !(key in found)
                push!(found, key)
            end

            if channel == "nightly"
                @testset "Tier 1 platforms always have nightlies" begin
                    for key in [
                        ("x86_64-linux-gnu", "tar.gz", nothing),
                        ("x86_64-w64-mingw32", "tar.gz", nothing),
                        ("x86_64-w64-mingw32", "exe", nothing),
                        ("aarch64-apple-darwin14", "tar.gz", nothing),
                        ("aarch64-apple-darwin14", "dmg", nothing),
                    ]
                        @test key in found
                    end
                end
            end
        end
    end
end
