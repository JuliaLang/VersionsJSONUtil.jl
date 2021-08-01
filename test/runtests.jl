using Pkg.BinaryPlatforms, JSON
using VersionsJSONUtil
import VersionsJSONUtil: PortableWindows
using Test

const download_urls = Dict(
    # v"1.7.0-beta3" => Dict(
    #     MacOS(:aarch64) =>              "https://julialang-s3.julialang.org/bin/mac/aarch64/1.7/julia-1.7.0-beta3-macaarch64.dmg",
    # ),
    v"1.6.2" => Dict(
        Linux(:x86_64) =>               "https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.2-linux-x86_64.tar.gz",
        Linux(:i686) =>                 "https://julialang-s3.julialang.org/bin/linux/x86/1.6/julia-1.6.2-linux-i686.tar.gz",
        Linux(:aarch64) =>              "https://julialang-s3.julialang.org/bin/linux/aarch64/1.6/julia-1.6.2-linux-aarch64.tar.gz",
        Linux(:armv7l) =>               "https://julialang-s3.julialang.org/bin/linux/armv7l/1.6/julia-1.6.2-linux-armv7l.tar.gz",
        Linux(:powerpc64le) =>          "https://julialang-s3.julialang.org/bin/linux/ppc64le/1.6/julia-1.6.2-linux-ppc64le.tar.gz",
        Linux(:x86_64, libc = :musl) => "https://julialang-s3.julialang.org/bin/musl/x64/1.6/julia-1.6.2-musl-x86_64.tar.gz",
        MacOS(:x86_64) =>               "https://julialang-s3.julialang.org/bin/mac/x64/1.6/julia-1.6.2-mac64.dmg",
        Windows(:x86_64) =>             "https://julialang-s3.julialang.org/bin/winnt/x64/1.6/julia-1.6.2-win64.exe",
        Windows(:i686) =>               "https://julialang-s3.julialang.org/bin/winnt/x86/1.6/julia-1.6.2-win32.exe",
        PortableWindows(:x86_64) =>     "https://julialang-s3.julialang.org/bin/winnt/x64/1.6/julia-1.6.2-win64.zip",
        PortableWindows(:i686) =>       "https://julialang-s3.julialang.org/bin/winnt/x86/1.6/julia-1.6.2-win32.zip",
        FreeBSD(:x86_64) =>             "https://julialang-s3.julialang.org/bin/freebsd/x64/1.6/julia-1.6.2-freebsd-x86_64.tar.gz",
    ),
)

@testset "VersionsJSONUtil.jl" begin
    @testset "Download URLs for $v" for v in keys(download_urls)
        for (p, url) in download_urls[v]
            @test VersionsJSONUtil.download_url(v, p) == url
        end
    end
end
