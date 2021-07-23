module VersionsJSONUtil

using HTTP, JSON, Pkg.BinaryPlatforms, WebCacheUtilities, SHA, Lazy
import Pkg.BinaryPlatforms: triplet, arch

"Wrapper type to define two jlext methods for portable and installer Windows"
struct PortableWindows
    windows::Windows
end
PortableWindows(arch::Symbol) = PortableWindows(Windows(arch))
@forward PortableWindows.windows (up_os, tar_os, triplet, arch)

up_os(p::Windows) = "winnt"
up_os(p::MacOS) = "mac"
up_os(p::Linux) = libc(p) == :glibc ? "linux" : "musl"
up_os(p::FreeBSD) = "freebsd"
up_os(p) = error("Unknown OS for $(p)")

up_arch(p#=::Platform=#) = up_arch(arch(p))
function up_arch(arch::Symbol)
    if arch == :x86_64
        return "x64"
    elseif arch == :i686
        return "x86"
    elseif arch == :powerpc64le
        return "ppc64le"
    else
        return string(arch)
    end
end

tar_os(p::Windows) = "win$(wordsize(p))"
tar_os(p::FreeBSD) = "freebsd-$(arch(p))"
function tar_os(p::MacOS)
    if arch(p) == :aarch64
        return "macaarch$(wordsize(p))"
    else
        return "mac$(wordsize(p))"
    end
end
function tar_os(p::Linux)
    if arch(p) == :powerpc64le
        return "$(up_os(p))-ppc64le"
    else
        return "$(up_os(p))-$(arch(p))"
    end
end

jlext(p::Windows) = "exe"
jlext(p::PortableWindows) = "zip"
jlext(p::MacOS) = "dmg"
jlext(p#=::Platform=#) = "tar.gz"

# OS to use in the metadata
# The OS in the download URL for Linux with musl is "musl"
# But the OS in the metadata should be "linux"
meta_os(p#=::Platform=#) = up_os(p)
meta_os(p::Linux) = "linux"

function download_url(version::VersionNumber, platform#=::Platform=#)
    return string(
        "https://julialang-s3.julialang.org/bin/",
        up_os(platform), "/",
        up_arch(platform), "/",
        version.major, ".", version.minor, "/", 
        "julia-", version, "-", tar_os(platform), ".", jlext(platform),
    )
end

# We're going to collect the combinatorial explosion of version/os-arch possible downloads.
# We don't have a nice, neat list of what is or is not available, and so we're just going to
# try and download each file, and if it exists, yay.  Otherwise, bleh.
julia_platforms = [
    Linux(:x86_64),
    Linux(:i686),
    Linux(:aarch64),
    Linux(:armv7l),
    Linux(:powerpc64le),
    Linux(:x86_64, libc = :musl),
    MacOS(:x86_64),
    MacOS(:aarch64),
    Windows(:x86_64),
    Windows(:i686),
    PortableWindows(:x86_64),
    PortableWindows(:i686),
    FreeBSD(:x86_64),
]

function vnum_maybe(x::AbstractString)
    try
        return VersionNumber(x)
    catch
        return nothing
    end
end

function is_stable(v::VersionNumber)
    return v.prerelease == () && v.build == ()
end

# Get list of tags from the Julia repo
function get_tags()
    @info("Probing for tag list...")
    tags_json_path = WebCacheUtilities.download_to_cache(
        "julia_tags.json",
        "https://api.github.com/repos/JuliaLang/julia/git/refs/tags",
    )
    JSON.parse(String(read(tags_json_path)))
end

function main(out_path)
    tags = get_tags()
    tag_versions = filter(x -> x !== nothing, [vnum_maybe(basename(t["ref"])) for t in tags])

    meta = Dict()
    for version in tag_versions
        for platform in julia_platforms
            url = download_url(version, platform)
            filename = basename(url)

            # Download this URL to a local file
            local filepath
            try
                @info("Downloading $(filename)...")
                filepath = WebCacheUtilities.download_to_cache(filename, url)
            catch e
                if isa(e, InterruptException)
                    rethrow(e)
                end
                continue
            end

            tarball_hash_path = hit_file_cache("$(filename).sha256") do tarball_hash_path
                open(filepath, "r") do io
                    open(tarball_hash_path, "w") do hash_io
                        write(hash_io, bytes2hex(sha256(io)))
                    end
                end
            end
            tarball_hash = String(read(tarball_hash_path))

            # Initialize overall version key, if needed
            if !haskey(meta, version)
                meta[version] = Dict(
                    "stable" => is_stable(version),
                    "files" => Vector{Dict}(),
                )
            end

            # Test to see if there is an asc signature:
            asc_signature = nothing
            if !isa(platform, MacOS) && !isa(platform, Windows)
                try
                    asc_url = string(url, ".asc")
                    @info("Downloading $(basename(asc_url))")
                    asc_filepath = WebCacheUtilities.download_to_cache(basename(asc_url), asc_url)
                    asc_signature = String(read(asc_filepath))
                catch e
                    if isa(e, InterruptException)
                        rethrow(e)
                    end
                end
            end

            # Build up metadata about this file
            kind = "archive"
            if endswith(filename, ".exe")
                kind = "installer"
            end
            file_dict = Dict(
                "triplet" => triplet(platform),
                "os" => meta_os(platform),
                "arch" => string(arch(platform)),
                "version" => string(version),
                "sha256" => tarball_hash,
                "size" => filesize(filepath),
                "kind" => kind,
                "url" => url,
            )
            # Add in `.asc` signature content, if applicable
            if asc_signature !== nothing
                file_dict["asc"] = asc_signature
            end

            # Right now, all we have are archives, but let's be forward-thinking
            # and make this an array of dictionaries that is easy to extensibly match
            push!(meta[version]["files"], file_dict)

            # Write out new versions of our versions.json as we go
            open(out_path, "w") do io
                JSON.print(io, meta, 2)
            end

            # Delete downloaded file
            rm(filepath)
        end
    end
end

end # module
