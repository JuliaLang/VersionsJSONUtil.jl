module VersionsJSONUtil

using HTTP, JSON, Pkg.BinaryPlatforms, WebCacheUtilities, SHA, Lazy
using Tar: Tar
import Pkg.BinaryPlatforms: triplet, arch
import Pkg.PlatformEngines: exe7z

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
julia_platforms = [
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

const tarball_git_tree_hash_skiplist = [
    # Corrupt gzip stream: `7z` reports a CRC failure for the embedded tarball.
    "https://julialang-s3.julialang.org/bin/linux/x86/0.7/julia-0.7.0-alpha-linux-i686.tar.gz",
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

function tarball_git_tree_hash(; tarball_path::AbstractString, algorithm::AbstractString)
    return open(io -> Tar.tree_hash(io; algorithm), `$(exe7z()) x $tarball_path -so`)
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

# ------------------------------------------------------------------------------------------
# Incremental rebuilds.
#
# We seed from the currently deployed versions.json and only probe what is missing from it:
# an entry already in the seed is carried over (after a cheap HEAD cross-check of its
# recorded size against Content-Length), so a normal run downloads only newly released
# files. The published versions.json format is completely unchanged, and there is no state
# beyond the deployed file itself. Replacing the bytes behind an already-published URL
# without changing their size is the one change this cannot detect; the scheduled full
# rebuild (see CI.yml) re-downloads and re-hashes everything to bound that.

function load_seed(out_path)
    meta = Dict{VersionNumber, Any}()
    if isfile(out_path)
        for (k, v) in JSON.parsefile(out_path)
            ver = vnum_maybe(k)
            ver === nothing && continue
            meta[ver] = v
        end
        @info "Seeded $(length(meta)) versions from $(out_path)"
    else
        @info "No $(out_path) found; building from scratch"
    end
    return meta
end

function checkpoint(out_path, meta)
    open(out_path, "w") do io
        JSON.print(io, meta, 2)
    end
end

function head_url(url)
    response = HTTP.head(url; status_exception = false)
    content_length = tryparse(Int, String(strip(HTTP.header(response, "Content-Length"))))
    return (;
        status = Int(response.status),
        content_length = something(content_length, 0),
    )
end

# Pure policy for a HEAD response.
#   :proceed          - the URL is live; go on to the completeness/size checks
#   :keep_existing    - the URL is in the seed versions.json but the CDN says it is gone.
#                       A published release file should never vanish, and this CDN is known
#                       to serve stale per-POP 404s -- so keep the existing entry and warn,
#                       rather than deleting a released binary from versions.json.
#   :skip_nonexistent - a 404 for a URL we never knew: this version/platform combination
#                       simply doesn't exist
#   :skip_transient   - any other status (5xx, ...): warn and retry next run
function action_for_head_status(status::Integer, have_existing_entry::Bool)
    if status == 200
        return :proceed
    elseif have_existing_entry
        return :keep_existing
    elseif status == 404
        return :skip_nonexistent
    else
        return :skip_transient
    end
end

# Cheap staleness cross-check for a seeded entry, using only data already in
# versions.json: if the live Content-Length disagrees with the recorded size, the bytes
# behind the URL have changed and the recorded hashes are stale. An absent Content-Length
# cannot be checked; trust the seed then (the scheduled full rebuild is the backstop).
function entry_size_matches(file_dict, content_length::Integer; url = "")
    content_length > 0 || return true
    if file_dict["size"] != content_length
        @warn "Size has changed from $(file_dict["size"]) to $(content_length); the published file was replaced" url
        return false
    end
    return true
end

# Does a (seeded) filedict have every field we require, so it can be carried over?
function filedict_is_complete(file_dict, url)
    required = ["arch", "extension", "kind", "os", "sha256", "size", "triplet", "url", "version"]
    all(k -> haskey(file_dict, k), required) || return false
    # tarballs additionally need the git tree hashes (except the skiplisted corrupt one,
    # which can never have them and would otherwise be re-downloaded every run)
    if endswith(url, ".tar.gz") && !(url in tarball_git_tree_hash_skiplist)
        haskey(file_dict, "git-tree-sha1") || return false
        haskey(file_dict, "git-tree-sha256") || return false
    end
    return true
end

function find_filedict(meta, version, url)
    haskey(meta, version) || return nothing
    for file_dict in meta[version]["files"]
        file_dict["url"] == url && return file_dict
    end
    return nothing
end

function delete_filedicts_for_url!(meta, version, url)
    # Remove any stale entry so a re-download can't produce duplicates
    haskey(meta, version) || return nothing
    filter!(file_dict -> file_dict["url"] != url, meta[version]["files"])
    return nothing
end

function main(out_path)
    tags = get_tags()
    tag_versions = filter(x -> x !== nothing, [vnum_maybe(basename(t["ref"])) for t in tags])

    meta = load_seed(out_path)
    number_urls_tried = 0
    number_urls_success = 0
    number_carried_over = 0
    for version in tag_versions
        for platform in julia_platforms
            url = download_url(version, platform)
            filename = basename(url)

            existing = find_filedict(meta, version, url)
            head = head_url(url)
            action = action_for_head_status(head.status, existing !== nothing)
            if action == :keep_existing
                @warn "HEAD returned $(head.status) for previously-published $(url); keeping the existing entry"
                number_carried_over += 1
                continue
            elseif action == :skip_nonexistent
                continue
            elseif action == :skip_transient
                @warn "HEAD returned $(head.status) for $(url); skipping it for this run"
                continue
            end

            if existing !== nothing && filedict_is_complete(existing, url) &&
                    entry_size_matches(existing, head.content_length; url)
                number_carried_over += 1
                continue
            end
            delete_filedicts_for_url!(meta, version, url)

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

            tarball_hash_path = hit_file_cache("$(filename).sha256") do tarball_hash_path
                open(filepath, "r") do io
                    open(tarball_hash_path, "w") do hash_io
                        write(hash_io, bytes2hex(sha256(io)))
                    end
                end
            end
            tarball_hash = String(read(tarball_hash_path))

            if extension == "tar.gz" && !(url in tarball_git_tree_hash_skiplist)
                tarball_git_tree_hashes = Dict{String, String}()
                tree_hash_path_sha1 = hit_file_cache("$(filename).git-tree-sha1") do tree_hash_path
                    open(tree_hash_path, "w") do hash_io
                        write(hash_io, tarball_git_tree_hash(; tarball_path=filepath, algorithm="git-sha1"))
                    end
                end
                tree_hash_path_sha256 = hit_file_cache("$(filename).git-tree-sha256") do tree_hash_path
                    open(tree_hash_path, "w") do hash_io
                        write(hash_io, tarball_git_tree_hash(; tarball_path=filepath, algorithm="git-sha256"))
                    end
                end
                tarball_git_tree_hashes["git-tree-sha1"] = String(read(tree_hash_path_sha1))
                tarball_git_tree_hashes["git-tree-sha256"] = String(read(tree_hash_path_sha256))
            else
                tarball_git_tree_hashes = nothing
            end

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
            file_dict = Dict(
                "triplet" => triplet(platform),
                "os" => meta_os(platform),
                "arch" => string(arch(platform)),
                "version" => string(version),
                "sha256" => tarball_hash,
                "size" => filesize(filepath),
                "kind" => kind,
                "extension" => extension,
                "url" => url,
            )
            if tarball_git_tree_hashes !== nothing
                merge!(file_dict, tarball_git_tree_hashes)
            end
            # Add in `.asc` signature content, if applicable
            if asc_signature !== nothing
                file_dict["asc"] = asc_signature
            end

            # Right now, all we have are archives, but let's be forward-thinking
            # and make this an array of dictionaries that is easy to extensibly match
            push!(meta[version]["files"], file_dict)

            # Write out new versions of our versions.json as we go
            checkpoint(out_path, meta)

            # Delete downloaded file
            rm(filepath)
        end
    end
    # Always write the output, even if nothing needed re-downloading
    checkpoint(out_path, meta)
    @info "Tried $(number_urls_tried) URLs, successfully downloaded $(number_urls_success). Carried over $(number_carried_over) up-to-date entries."
end

end # module
