module VersionsJSONUtil

using HTTP: HTTP
using JSON: JSON
using Lazy: Lazy, @forward
using Pkg.BinaryPlatforms: Windows, MacOS, Linux, FreeBSD, libc, wordsize
using SHA: SHA, sha256
using WebCacheUtilities: WebCacheUtilities, hit_file_cache

# These two need to be `import` (not `using`), because we add methods to them:
import Pkg.BinaryPlatforms: triplet, arch
using OrderedCollections: OrderedDict

"Wrapper types to define three jlext methods for portable, tarball and installer Windows"
struct WindowsPortable
    windows::Windows
end
WindowsPortable(arch::Symbol) = WindowsPortable(Windows(arch))
@forward WindowsPortable.windows (up_os, tar_os, triplet, arch)

struct WindowsTarball
    windows::Windows
end
WindowsTarball(arch::Symbol) = WindowsTarball(Windows(arch))
@forward WindowsTarball.windows (up_os, tar_os, triplet, arch)

"Wrapper type to define two jlext methods for macOS DMG and macOS tarball"
struct MacOSTarball
    macos::MacOS
end
MacOSTarball(arch::Symbol) = MacOSTarball(MacOS(arch))
@forward MacOSTarball.macos (up_os, tar_os, triplet, arch)

up_os(p::Windows) = "winnt"
up_os(p::MacOS) = "mac"
up_os(p::Linux) = libc(p) == :glibc ? "linux" : "musl"
up_os(p::FreeBSD) = "freebsd"
up_os(p) = error("Unknown OS for $(p)")

up_arch(p) = up_arch(arch(p))
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
jlext(p::WindowsPortable) = "zip"
jlext(p::WindowsTarball) = "tar.gz"
jlext(p::MacOS) = "dmg"
jlext(p) = "tar.gz"

# OS to use in the metadata
# The OS in the download URL for Linux with musl is "musl"
# But the OS in the metadata should be "linux"
meta_os(p) = up_os(p)
meta_os(p::Linux) = "linux"

function download_url(version::VersionNumber, platform)
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
const julia_platforms = [
    # *-linux-gnu
    Linux(:x86_64; libc = :glibc),
    Linux(:i686; libc = :glibc),
    Linux(:aarch64; libc = :glibc),
    Linux(:armv7l; libc = :glibc),
    Linux(:powerpc64le; libc = :glibc),
    # *-linux-musl
    Linux(:x86_64; libc = :musl),
    # *-apple-darwin
    MacOS(:x86_64),
    MacOS(:aarch64),
    MacOSTarball(:x86_64),
    MacOSTarball(:aarch64),
    # *-w64-mingw32
    Windows(:x86_64),
    Windows(:i686),
    WindowsPortable(:x86_64),
    WindowsPortable(:i686),
    WindowsTarball(:x86_64),
    WindowsTarball(:i686),
    # *-unknown-freebsd
    FreeBSD(:x86_64),
]

function vnum_maybe(x::AbstractString)
    try
        return VersionNumber(x)
    catch ex
        @info "Ignoring the following exception" x exception=ex
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
    unique!(tag_versions)
    sort!(tag_versions)

    meta = OrderedDict()
    number_urls_tried = 0
    number_urls_success = 0
    for version in tag_versions
        for platform in julia_platforms
            url = download_url(version, platform)
            filename = basename(url)

            # Download this URL to a local file
            number_urls_tried += 1
            local filepath
            try
                print(stdout, "Downloading $(filename)...")
                filepath = WebCacheUtilities.download_to_cache(filename, url)
            catch ex
                if isa(ex, InterruptException)
                    rethrow(ex)
                end
                println(stdout, " ✗")
                continue
            end
            number_urls_success += 1
            println(stdout, " ✓")

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
                meta[version] = OrderedDict()
                meta[version]["stable"] = is_stable(version)
                meta[version]["files"] = Vector{OrderedDict}()
                sort!(meta[version])
            end

            # Test to see if there is an asc signature:
            asc_signature = nothing
            if !isa(platform, MacOS) && !isa(platform, Windows)
                asc_url = string(url, ".asc")
                print(stdout, "    Downloading $(basename(asc_url))")
                try
                    asc_filepath = WebCacheUtilities.download_to_cache(basename(asc_url), asc_url)
                    asc_signature = String(read(asc_filepath))
                    println(stdout, " ✓")
                catch ex
                    if isa(ex, InterruptException)
                        rethrow(ex)
                    end
                    println(stdout, " ✗")
                end

            end

            # Build up metadata about this file
            if endswith(filename, ".dmg")
                kind = "archive"
                extension = "dmg"
            elseif endswith(filename, ".exe")
                kind = "installer"
                extension = "exe"
            elseif endswith(filename, ".tar.gz")
                kind = "archive"
                extension = "tar.gz"
            elseif endswith(filename, ".zip")
                kind = "archive"
                extension = "zip"
            else
                error("Unsupported file extension in filename: $(filename)")
            end
            file_dict = OrderedDict()
            file_dict["triplet"] = triplet(platform)
            file_dict["os"] = meta_os(platform)
            file_dict["arch"] = string(arch(platform))
            file_dict["version"] = string(version)
            file_dict["sha256"] = tarball_hash
            file_dict["size"] = filesize(filepath)
            file_dict["kind"] = kind
            file_dict["extension"] = extension
            file_dict["url"] = url
            # Add in `.asc` signature content, if applicable
            if asc_signature !== nothing
                file_dict["asc"] = asc_signature
            end

            # Explicitly sort the file_dict
            sort!(file_dict)

            # Right now, all we have are archives, but let's be forward-thinking
            # and make this an array of dictionaries that is easy to extensibly match
            push!(meta[version]["files"], file_dict)

            # Write out new versions of our versions.json as we go
            open(out_path, "w") do io
                JSON.print(io, meta; pretty_print = true, sort_keys = false)
            end

            # Delete downloaded file
            rm(filepath)
        end
    end
    @info "Tried $(number_urls_tried) versions, successfully downloaded $(number_urls_success)"
end

end # module
