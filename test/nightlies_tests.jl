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
            @test collect(keys(channel_dict)) == ["files"]

            files = channel_dict["files"]
            @test files isa AbstractArray
            @test !isempty(files)

            # (triplet, extension, variants) identifies a file within a channel
            found = Set()

            for filedict in files
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
                    "variants",
                ]
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
                @test startswith(url, "https://julialangnightlies-s3.julialang.org/bin/")
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

                variants = get(filedict, "variants", String[])
                if haskey(filedict, "variants")
                    @test variants isa AbstractVector
                    @test !isempty(variants)
                    @test all(v -> occursin(r"^[a-z0-9]+$", v), variants)
                    @test allunique(variants)
                    # only published as tarballs
                    @test filedict["extension"] == "tar.gz"
                end

                key = (filedict["triplet"], filedict["extension"], variants)
                @test !(key in found)
                push!(found, key)
            end

            if channel == "nightly"
                @testset "Tier 1 platforms always have nightlies" begin
                    for key in [
                        ("x86_64-linux-gnu", "tar.gz", []),
                        ("x86_64-w64-mingw32", "tar.gz", []),
                        ("x86_64-w64-mingw32", "exe", []),
                        ("aarch64-apple-darwin14", "tar.gz", []),
                        ("aarch64-apple-darwin14", "dmg", []),
                    ]
                        @test key in found
                    end
                end
            end
        end
    end
end
