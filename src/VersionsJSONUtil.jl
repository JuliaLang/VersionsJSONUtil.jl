module VersionsJSONUtil

##### --------------------------------------------------------------------------------------
##### Import dependencies

using Downloads: Downloads
using EnumX: EnumX, @enumx
using GitHub: GitHub
using HTTP: HTTP
using JSON: JSON
using Lazy: Lazy, @forward
using Pkg: Pkg
using Pkg.BinaryPlatforms: Platform, AbstractPlatform, Windows, MacOS, Linux, FreeBSD, libc, wordsize
using ProgressMeter: Progress, next!, update!
using SHA: SHA, sha256
using StructUtils: StructUtils, @kwarg
using Tar: Tar
using URIs: URIs, URI

# These two need to be `import` (not `using`), because we add methods to them:
import Pkg.BinaryPlatforms: triplet, arch
import Pkg.PlatformEngines: exe7z

##### --------------------------------------------------------------------------------------

include("sha_structs.jl")

include("typed_json.jl")

include("web_cache_utilities.jl")

##### --------------------------------------------------------------------------------------
##### Config, OutputJsonContent

Base.@kwdef struct Config
    versions_json_filename::AbstractString
    internal_json_filename::AbstractString
end
function Config(output_directory::AbstractString)
    versions_json_filename = joinpath(output_directory, "versions.json")
    internal_json_filename = joinpath(output_directory, "internal.json")

    cfg = Config(;
        versions_json_filename,
        internal_json_filename,
    )
    return cfg
end

struct OutputJsonContent
    versions_json::VersionsJsonDocument # this variable was previously named `meta`
    internal_json::InternalJsonDocument
end
function OutputJsonContent(cfg::Config)
    if isfile(cfg.versions_json_filename)
        versions_json = JSON.parsefile(cfg.versions_json_filename, VersionsJsonDocument; style = OurCustomStyle())
    else
        versions_json = VersionsJsonDocument()
    end
    if isfile(cfg.internal_json_filename)
        internal_json = JSON.parsefile(cfg.internal_json_filename, InternalJsonDocument; style = OurCustomStyle())
    else
        internal_json = InternalJsonDocument()
    end
    return OutputJsonContent(versions_json, internal_json)
end

##### --------------------------------------------------------------------------------------
##### Platform types

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
up_os(p) = error("Unknown OS for $p")

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
    return URI(string(
        "https://julialang-s3.julialang.org/bin/",
        up_os(platform), "/",
        up_arch(platform), "/",
        version.major, ".", version.minor, "/",
        "julia-", version, "-", tar_os(platform), ".", jlext(platform),
    ))
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

unwrap_platform(plat::Linux) = plat.p
unwrap_platform(plat::MacOS) = plat.p
unwrap_platform(plat::Windows) = plat.p
unwrap_platform(plat::FreeBSD) = plat.p
unwrap_platform(plat::WindowsPortable) = plat.windows.p
unwrap_platform(plat::WindowsTarball) = plat.windows.p
unwrap_platform(plat::MacOSTarball) = plat.macos.p

function is_stable(v::VersionNumber)
    return v.prerelease == () && v.build == ()
end

##### --------------------------------------------------------------------------------------
##### Writing JSON

function our_serialize_json(io::IO, dict::Union{VersionsJsonDocument, InternalJsonDocument})
    JSON.json(
        io, dict;
        style = OurCustomStyle(),
        pretty = true,
        sort_keys = true,
        omit_null = true,
    )
    return nothing
end

function checkpoint(content::OutputJsonContent, cfg::Config)
    mktempdir() do tmpdir
        version_json_tempfile = joinpath(tmpdir, "version.json.temp")
        internal_json_tempfile = joinpath(tmpdir, "internal.json.temp")

        version_json_truefile = cfg.versions_json_filename
        internal_json_truefile = cfg.internal_json_filename

        open(version_json_tempfile, "w") do io
            our_serialize_json(io, content.versions_json)
        end
        open(internal_json_tempfile, "w") do io
            our_serialize_json(io, content.internal_json)
        end

        # We don't move to the true location until we've completely finished serializing.
        # That way, if an error is thrown during serialization, we don't have a broken JSON file.
        mv(version_json_tempfile, version_json_truefile; force = true)
        mv(internal_json_tempfile, internal_json_truefile; force = true)
    end
    return nothing
end

##### --------------------------------------------------------------------------------------
##### Some utilities related to re-using existing versions.json and internal.json

function url_is_known_nonexistent(content::OutputJsonContent, version::VersionNumber, url::URI)
    internal_json = content.internal_json
    if haskey(internal_json, version)
        return url in internal_json[version].known_nonexistent_urls
    end
    return false
end

function mark_url_as_nonexistent!(content::OutputJsonContent, version::VersionNumber, url::URI)
    internal_json = content.internal_json
    get!(internal_json, version) do
        InternalJsonSingleVersion()
    end
    push!(internal_json[version].known_nonexistent_urls, url)
    return nothing
end

function find_filedict(content::OutputJsonContent, version::VersionNumber, url::URI)
    versions_json = content.versions_json
    if !haskey(versions_json, version)
        return nothing
    end
    for file in versions_json[version].files
        if file.url == url
            return file
        end
    end
    return nothing
end

function delete_filedicts_for_url!(content, version, url)
    versions_json = content.versions_json
    if !haskey(versions_json, version)
        return nothing
    end
    filter!(file -> file.url != url, versions_json[version].files)
    return nothing
end

function filedict_is_complete_and_good(content::OutputJsonContent, version::VersionNumber, url::URI)
    filedict = find_filedict(content, version, url)
    if isnothing(filedict)
        return false
    end
    return filedict_is_complete_and_good(filedict)
end

function filedict_is_complete_and_good(filedict::FileDict)
    required_fields = [
        :arch,
        :extension,
        :kind,
        :os,
        :sha256,
        :size,
        :triplet,
        :url,
        :version,

        # So, as a general rule, `etag` is not actually a required key.
        # But in this function, we pretend that it is required.
        # Because if we didn't previously record an ETag, then we have no way of knowing now
        # if the info (e.g. sha256) that we previously recorded is stale now.
        :etag,
        # Same goes for `last_modified`
        :last_modified,
    ]
    optional_fields = [
        :asc,
        :git_tree_sha1,
        :git_tree_sha256,
        :optional_field, # TODO: delete this line
    ]
    for k in required_fields
        if isnothing(getfield(filedict, k))
            # The filedict is missing one or more required fields
            return false
        end
    end
    if !(fieldnames(typeof(filedict)) ⊆ union(required_fields, optional_fields))
        # The filedict contains a non-allowed field
        # This is unexpected, so throw an error
        for k in fieldnames(typeof(filedict))
            if !(k in union(required_fields, optional_fields))
                @error "Filedict contains non-allowed field: $k"
            end
        end
        error("filedict contains a non-allowed field")
    end

    ext = (filedict.extension)::ExtensionEnum.T
    # git-tree-sha1 and git-tree-sha256 are required for .tar.gz files
    # They are optional for other files
    if ext == ExtensionEnum.tar_gz
        required_for_targz = [:git_tree_sha1, :git_tree_sha256]
        for k in required_for_targz
            if isnothing(getfield(filedict, k))
                # The filedict is missing one or more required targz-specific keys
                # TODO: Implement the "required for .tar.gz" part, by uncommenting the following line:
                return false
            end
        end
    end

    # Now the (compared to the rest of this function) expensive part: Check our Etag.
    url = filedict.url
    old_etag = filedict.etag
    old_last_modified = filedict.last_modified
    new_headinfo = get_new_headinfo_for_url(url)
    if isnothing(new_headinfo)
        return false
    end
    if old_etag != new_headinfo.etag
        @warn "ETag for URL $url has changed from $(old_etag) to $(new_headinfo.etag)"
        return false
    end
    if old_last_modified != new_headinfo.last_modified
        @warn "Last-Modified for URL $url has changed from $(old_last_modified) to $(new_headinfo.last_modified)"
        return false
    end

    return true
end

##### --------------------------------------------------------------------------------------
##### Get ETag and Last-Modified, so we know if we need to re-download and re-checksum files

Base.@kwdef struct HeadInfo
    status::Int
    etag::Union{String, Nothing}
    last_modified::Union{String, Nothing}
end

# We call this function before hitting an upstream server.
# By default, it is a sleep(0), but we can make this user-configurable.
# So that way, if a user is using a mirror that has rate-limits, they can configure this
# to help them stay under the limits.
function my_sleep()
    sleep(0)
    return nothing
end

function get_new_headinfo_for_url(url::URI)
    my_sleep()
    response = HTTP.head(url; status_exception = false)
    status = response.status
    if status != 200
        return HeadInfo(; status, etag=nothing, last_modified=nothing)
    end
    headers = Dict(HTTP.headers(response))
    etag = get(headers, "ETag", "")
    last_modified = get(headers, "Last-Modified", "")
    if isempty(strip(etag))
        @warn "Got empty new ETag for URL: $etag"
        etag = nothing
    end
    if isempty(strip(last_modified))
        @warn "Got empty new ETag for URL: $last_modified"
        last_modified = nothing
    end
    head_info = HeadInfo(; status, etag, last_modified)
    return head_info
end

##### --------------------------------------------------------------------------------------
##### Other stuff - TODO write a better description here

function assert_sanity_check_tag_number(tag_versions::Vector{VersionNumber})
    # IIRC, we have never deleted a tag from JuliaLang/julia
    # So this number should be monotonically non-decreasing over time
    sanity_check_minimum = 200  # Increase this number from time to time
    num_found_tags = length(tag_versions)
    if num_found_tags < sanity_check_minimum
        println(stderr, "Found $num_found_tags tags, here is the full list:")
        for (i, x) in enumerate(tag_versions)
            println(stderr, "$(i). $x")
        end
        error("Expected >= $sanity_check_minimum tags, but only found $num_found_tags")
    end
end

##### --------------------------------------------------------------------------------------
##### Utility function for calculating the treehash of a tarball file

# Example values for algorithm:
# algorithm = "git-sha1"
# algorithm = "git-sha256"
function tarball_git_tree_hash(; tarball_path::AbstractString, algorithm::AbstractString)
    return open(io -> Tar.tree_hash(io; algorithm), `$(exe7z()) x $tarball_path -so`)
end

function tarball_git_tree_sha1(tarball_path::AbstractString)
    return SHA1(tarball_git_tree_hash(; tarball_path, algorithm = "git-sha1"))
end

function tarball_git_tree_sha256(tarball_path::AbstractString)
    return SHA256(tarball_git_tree_hash(; tarball_path, algorithm = "git-sha256"))
end

const tarball_git_tree_hash_skiplist = [
    # Corrupt gzip stream: `7z` reports a CRC failure for the embedded tarball.
    URI("https://julialang-s3.julialang.org/bin/linux/x86/0.7/julia-0.7.0-alpha-linux-i686.tar.gz"),
]

##### --------------------------------------------------------------------------------------
##### Get list of tags

# Use the GitHub API to get the list of tags from the Julia repo
function get_tags()
    @info("Probing for tag list...")
    request_path = "repos/JuliaLang/julia/git/refs/tags"
    token = strip(get(ENV, "GITHUB_TOKEN", ""))



    if !isempty(token)
        # The user provided GITHUB_TOKEN, so we use that to authenticate to GitHub API.
        # We don't cache this result - this ensures we get the freshest data.
        auth = GitHub.authenticate(token)

        # Note: GitHub.jl now has rate-limit support built-in.
        # So we don't call my_sleep() here.
        return GitHub.gh_get_json(GitHub.DEFAULT_API, "/$request_path"; auth)
    else
        # The user didn't provide GITHUB_TOKEN, so we have to make an unauthenticated call
        # to the GitHub API.
        # The rate limit for unauthenticated calls is very low, so we cache this.
        @warn "GITHUB_TOKEN not detected. It is recommended that you provide a GITHUB_TOKEN (with read-only access to only public repos)."
        tags_json_path = download_to_cache(
            "julia_tags.json",
            "https://api.github.com/$request_path",
        )
        return JSON.parse(String(read(tags_json_path)))
    end
end

##### --------------------------------------------------------------------------------------
##### The main() function, which is the entrypoint into building versions.json

function main(output_directory::AbstractString)
    cfg = Config(output_directory)
    return main(cfg)
end

function main(cfg::Config)
    content = OutputJsonContent(cfg)
    return main!(content, cfg)
end

# If we ever end up adding a tag to the Julia repo that's not parseable as a VersionNumber,
# we can add that tag to this skiplist here.
#
# And then we'll skip those tags when building versions.json
const tag_skiplist = String[]

function main!(content::OutputJsonContent, cfg::Config)
    tags = get_tags()
    filter!(t -> !(basename(t["ref"]) in tag_skiplist), tags)
    tag_versions = filter(x -> !isnothing(x), [VersionNumber(basename(t["ref"])) for t in tags])
    unique!(tag_versions)
    sort!(tag_versions)
    if isempty(tag_versions)
        error("Did not find any tags, which is obviously incorrect")
    end
    @info "Found $(length(tag_versions)) tags"
    # yes I know it's not "oldest" and "newest" in the temporal sense, it's just minimum and maximum
    @info "Oldest tag: $(first(tag_versions))"
    @info "Newest tag: $(last(tag_versions))"
    assert_sanity_check_tag_number(tag_versions)

    meta = content.versions_json
    internal_json = content.internal_json
    number_urls_tried = 0
    number_urls_success = 0
    num_urls_already_complete = 0
    number_urls_already_known_nonexistent = 0
    number_urls_to_probe = length(tag_versions) * length(julia_platforms)
    url_probe_index = 0
    download_progress = Progress(number_urls_to_probe; desc = "Building versions.json: ", output = stdout)

    function download_progress_showvalues(version, filename)
        return [
            ("Version", version),
            ("Filename", filename),
            ("Tried", number_urls_tried),
            ("Remaining", number_urls_to_probe - (url_probe_index - 1)),
            ("Succeeded", number_urls_success),
            ("Already complete", num_urls_already_complete),
            ("Known nonexistent", number_urls_already_known_nonexistent),
        ]
    end

    function update_download_progress!(version, filename; advance::Bool = false)
        showvalues = download_progress_showvalues(version, filename)
        if advance
            next!(download_progress; showvalues)
        else
            update!(download_progress, url_probe_index - 1; showvalues)
        end
        return nothing
    end

    for version in tag_versions
        # Write out new versions of our versions.json every time we finish a version.
        # The fact that we wait until we've finished a version is intentional.
        # We don't want to write out a partial version - we want to wait until we've finished the version.
        checkpoint(content, cfg)
        for platform in julia_platforms
            url_probe_index += 1
            url = download_url(version, platform)
            filename = basename(string(url))
            update_download_progress!(version, filename)

            if url_is_known_nonexistent(content, version, url)
                number_urls_already_known_nonexistent += 1
                @debug "Skipping $filename as known-bad"
                update_download_progress!(version, filename; advance = true)
                continue # skip the rest of this for-loop iteration
            end

            if filedict_is_complete_and_good(content, version, url)
                num_urls_already_complete += 1
                @debug "Skipping $filename as known-complete-filedict"
            else
                # If a stale filedict exists, we need to remove it
                # Otherwise, we end up with duplicate entries in the `files` list
                delete_filedicts_for_url!(content, version, url)

                headinfo = get_new_headinfo_for_url(url)
                if headinfo.status == 404
                    mark_url_as_nonexistent!(content, version, url)
                    update_download_progress!(version, filename; advance = true)
                    continue # skip the rest of this for-loop iteration
                end

                # Download this URL to a local file in a temp directory
                number_urls_tried += 1

                # This will download the file to a tempfile
                my_sleep()
                filepath = Downloads.download(string(url))

                if filesize(filepath) == 0
                    # The file is empty
                    rm(filepath; force = true)
                    update_download_progress!(version, filename; advance = true)
                    continue # skip the rest of this for-loop iteration
                end

                number_urls_success += 1

                tarball_hash = open(filepath, "r") do io
                    bytes2hex(sha256(io))
                end

                # Initialize overall version key, if needed
                if !haskey(meta, version)
                    meta[version] = SingleVersionInfo(; stable = is_stable(version))
                end

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
                    error("Unsupported file extension in filename: filename")
                end

                if extension == "tar.gz" && !(url in tarball_git_tree_hash_skiplist)
                    tree_hash_path_sha1 = tarball_git_tree_sha1(filepath)
                    tree_hash_path_sha256 = tarball_git_tree_sha256(filepath)
                else
                    tree_hash_path_sha1 = nothing
                    tree_hash_path_sha256 = nothing
                end

                # Build up file_dict, which contains the metadata about this file
                file_dict = Dict()
                file_dict["arch"] = ArchEnum.T(arch(platform))
                file_dict["triplet"] = unwrap_platform(platform)
                file_dict["os"] = OsEnum.T(meta_os(platform))
                file_dict["version"] = version
                file_dict["sha256"] = tarball_hash
                file_dict["size"] = filesize(filepath)
                file_dict["kind"] = KindEnum.T(kind)
                file_dict["extension"] = ExtensionEnum.T(extension)
                file_dict["url"] = url

                if !isnothing(headinfo.etag)
                    file_dict["etag"] = headinfo.etag
                end
                if !isnothing(headinfo.last_modified)
                    file_dict["last-modified"] = headinfo.last_modified
                end

                if !isnothing(tree_hash_path_sha1)
                    file_dict["git-tree-sha1"] = tree_hash_path_sha1
                end
                if !isnothing(tree_hash_path_sha256)
                    file_dict["git-tree-sha256"] = string(tree_hash_path_sha256) # TODO: remove string()
                end

                # Let's be forward-thinking: Make this an array of dictionaries that is
                # easy to extensibly match.
                push!(meta[version].files, FileDict(file_dict))

                # Delete the downloaded file
                rm(filepath; force = true)
            end

            file_dict = find_filedict(content, version, url)
            if isnothing(file_dict)
                error("A very unexpected error occured: file_dict is nothing")
            end

            if !isnothing(file_dict.asc)
                # Nothing to do in this branch. No need to re-download the asc signature file
                # if the file_dict already has the `asc` key.
            else
                # Test to see if there is an asc signature file available for download
                asc_signature = nothing
                if !isa(platform, MacOS) && !isa(platform, Windows)
                    asc_url = URI(string(url, ".asc"))
                    asc_filename = basename(string(asc_url))
                    @debug "Downloading $asc_filename"
                    try
                        my_sleep()
                        asc_filepath = Downloads.download(string(asc_url))
                        asc_signature = String(read(asc_filepath))
                        rm(asc_filepath)
                    catch ex
                        if (ex isa Downloads.RequestError) && (ex.response.status == 404)
                            mark_url_as_nonexistent!(content, version, url)
                            update_download_progress!(version, filename; advance = true)
                            continue # skip the rest of this for-loop iteration
                        else
                            rethrow()
                        end
                    end
                end

                # Add in `.asc` signature content, if applicable
                if !isnothing(asc_signature)
                    file_dict.asc = asc_signature
                end
            end
            update_download_progress!(version, filename; advance = true)
        end
    end # for version in tag_versions

    # One last checkpoint, now that we've finished the for-loop
    checkpoint(content, cfg)

    @info "Tried $(number_urls_tried) versions, successfully downloaded $(number_urls_success). Skipped $num_urls_already_complete already good. Skipped $(number_urls_already_known_nonexistent) known bad."

    return_value = (;
        cfg.versions_json_filename,
    )
    return cfg
end

end # module
