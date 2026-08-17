module VersionsJSONUtil

using AWS, Dates, HTTP, JSON, Pkg.BinaryPlatforms, SHA, Lazy

AWS.@service S3
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

# Minimal file-based cache: one file per key, recreated when older than `lifetime`
function hit_file_cache(creator::Function, filename::AbstractString;
                        lifetime::Dates.Period = Dates.Hour(24))
    cache_dir = joinpath(tempdir(), "VersionsJSONUtil-cache")
    mkpath(cache_dir)
    path = joinpath(cache_dir, String(filename))
    if stat(path).mtime < time() - Dates.value(Dates.Second(lifetime))
        try
            creator(path)
        catch
            # don't leave a partial file behind as a future cache hit
            rm(path; force = true)
            rethrow()
        end
    end
    return path
end

# Get list of tags from the Julia repo
function get_tags()
    @info("Probing for tag list...")
    tags_json_path = hit_file_cache("julia_tags.json") do path
        response = HTTP.get("https://api.github.com/repos/JuliaLang/julia/git/refs/tags")
        write(path, response.body)
    end
    JSON.parse(String(read(tags_json_path)))
end

# ------------------------------------------------------------------------------------------
# The public download host (julialang-s3.julialang.org) is the Fastly CDN in front of the
# julialang2 S3 bucket. The build talks to the bucket directly instead: the CDN rate-limits
# the thousands of requests a sweep makes and can serve stale per-POP 404s, while S3 answers
# authoritatively. All bucket access (metadata queries and downloads) goes through AWS.jl,
# signed when credentials are in the environment (in CI via an assumed OIDC role, see
# devdocs/README.md); unsigned requests also work since the bucket is public, but are more
# likely to be throttled. The URLs recorded in versions.json stay on the CDN host.

const cdn_url_prefix = "https://julialang-s3.julialang.org/"
const s3_bucket = "julialang2"
const s3_region = "us-east-1"

s3_key(url::AbstractString) = replace(url, cdn_url_prefix => "")

# Sign only with explicit env credentials (the credential chain would error out otherwise);
# local runs without them send unsigned requests instead
const _aws_config = Ref{Union{Nothing, AWS.AWSConfig}}(nothing)
function aws_config()
    if _aws_config[] === nothing
        _aws_config[] = if !isempty(get(ENV, "AWS_ACCESS_KEY_ID", ""))
            AWS.AWSConfig(; region = s3_region)
        else
            AWS.AWSConfig(; creds = nothing, region = s3_region)
        end
    end
    return _aws_config[]
end
aws_signs() = aws_config().credentials !== nothing

# The objects are public-read, so an auth error on a signed request means the credentials
# are broken; the caller should fail fast instead of silently degrading every check into
# keep-existing/skip-transient
function is_credential_error(ex)
    return ex isa AWS.AWSException && ex.code in (
        "AccessDenied", "InvalidAccessKeyId", "SignatureDoesNotMatch",
        "ExpiredToken", "TokenRefreshRequired",
    )
end

# S3 reports timestamps in ISO 8601 ("2023-12-26T19:08:53.000Z"); versions.json
# has always recorded the HTTP-date form from the download headers ("Tue, 26 Dec 2023
# 19:08:53 GMT"), so convert to keep seeded entries comparable. nothing = unparsable.
function http_date(timestamp::AbstractString)
    stripped = replace(strip(timestamp), r"(\.\d+)?(\+00:00|Z)$" => "")
    dt = tryparse(DateTime, stripped, dateformat"yyyy-mm-dd\THH:MM:SS")
    dt === nothing && return nothing
    return Dates.format(dt, dateformat"e, dd u yyyy HH:MM:SS \G\M\T")
end

function s3_download_to_cache(filename::AbstractString, url::AbstractString)
    return hit_file_cache(String(filename)) do path
        # stream to disk instead of buffering the whole binary in memory; a failure
        # throws, and hit_file_cache removes the partial file when the creator throws
        open(path, "w") do io
            S3.get_object(s3_bucket, s3_key(url),
                          Dict("response_stream" => io); aws_config = aws_config())
        end
    end
end

# ------------------------------------------------------------------------------------------
# Incremental rebuilds: seed from the deployed versions.json and only download what's
# missing. A seeded entry is kept after a cross-check of its recorded
# size/etag/last-modified against the live bucket listing. The full-rebuild input in
# CI.yml re-downloads everything from scratch.

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

const head_absent = (; status = 0, content_length = nothing, etag = nothing, last_modified = nothing)

# All files for a version/platform live under one bin/<os>/<arch>/<major.minor>/ prefix,
# so one (paginated) list-objects-v2 per prefix replaces the ~17
# per-object existence checks per version and stays far away from any request limits.

s3_prefix(url::AbstractString) = dirname(s3_key(url)) * "/"

function list_objects(prefix::AbstractString)
    listing = Dict{String, Any}()
    params = Dict{String, Any}("prefix" => String(prefix))
    while true
        page = try
            S3.list_objects_v2(s3_bucket, params; aws_config = aws_config())
        catch ex
            isa(ex, InterruptException) && rethrow(ex)
            if aws_signs() && is_credential_error(ex)
                error("S3 rejected the signed list-objects-v2 request for $(prefix) " *
                      "($(ex.code)); check the AWS credentials")
            end
            # a failed request must not kill the run; nothing = transient, retried next run
            @warn "list-objects-v2 failed for $(prefix)" exception=(ex,)
            return nothing
        end
        # a prefix with no objects yields no Contents key at all, and the XML parsing
        # returns a lone Dict instead of a one-element vector for a single object
        contents = get(page, "Contents", [])
        contents isa AbstractVector || (contents = [contents])
        for obj in contents
            etag = strip(get(obj, "ETag", ""))
            # nothing = field missing/unparsable
            listing[obj["Key"]] = (;
                content_length = tryparse(Int, get(obj, "Size", "")),
                etag = isempty(etag) ? nothing : String(etag),
                last_modified = http_date(get(obj, "LastModified", "")),
            )
        end
        get(page, "IsTruncated", "false") == "true" || break
        params["continuation-token"] = page["NextContinuationToken"]
    end
    return listing
end

# Answer "does this URL exist and with what metadata" from the (memoized) listing of its
# prefix, in the shape a HEAD request would have produced: 200 = exists, 404 = does not
# exist, 0 = the listing failed so we don't know (transient).
function object_info(prefix_cache::AbstractDict, url::AbstractString)
    listing = get!(() -> list_objects(s3_prefix(url)), prefix_cache, s3_prefix(url))
    listing === nothing && return head_absent
    info = get(listing, s3_key(url), nothing)
    info === nothing && return (; head_absent..., status = 404)
    return (; status = 200, info...)
end

# Existence checks ask the bucket directly, so a 404 is authoritative. Still, never drop
# a released binary based on a live check alone: a non-200 for a URL already in
# versions.json keeps the entry. A 404 for an unknown URL means that version/platform
# doesn't exist; anything else is transient and retried next run.
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

# A seeded entry is stale if any recorded field disagrees with the live headers.
# A field the entry doesn't have is skipped (etag/last-modified are being added to old
# entries incrementally); a header the server didn't send is `nothing` and can't be
# checked, so that comparison is skipped too.
function entry_matches_head(file_dict, head; url = "")
    for (field, live) in [("size", head.content_length),
                          ("etag", head.etag),
                          ("last-modified", head.last_modified)]
        # only etag/last-modified can be absent here; the filedict_is_complete check
        # that runs before this already required size
        haskey(file_dict, field) || continue
        live === nothing && continue
        if file_dict[field] != live
            @warn "$(field) has changed from $(file_dict[field]) to $(live); the published file was replaced" url
            return false
        end
    end
    return true
end

# Can this seeded filedict be carried over as-is?
function filedict_is_complete(file_dict, url)
    required = [
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
    for k in required
        haskey(file_dict, k) || return false
        v = file_dict[k]
        v isa AbstractString && isempty(strip(v)) && return false
    end
    # tarballs also need the tree hashes, except the skiplisted corrupt one which can never have them
    if endswith(lowercase(url), ".tar.gz") && !(url in tarball_git_tree_hash_skiplist)
        occursin(r"^[0-9a-f]{40}$", get(file_dict, "git-tree-sha1", "")) || return false
        occursin(r"^[0-9a-f]{64}$", get(file_dict, "git-tree-sha256", "")) || return false
    end
    return true
end

function find_filedict(meta, version, url)
    haskey(meta, version) || return nothing
    haskey(meta[version], "files") || return nothing
    for file_dict in meta[version]["files"]
        file_dict["url"] == url && return file_dict
    end
    return nothing
end

function delete_filedicts_for_url!(meta, version, url)
    # Remove any stale entry so a re-download can't produce duplicates
    haskey(meta, version) || return nothing
    haskey(meta[version], "files") || return nothing
    filter!(file_dict -> file_dict["url"] != url, meta[version]["files"])
    return nothing
end

function main(out_path; only_version = nothing)
    tags = get_tags()
    tag_versions = filter(x -> x !== nothing, [vnum_maybe(basename(t["ref"])) for t in tags])

    meta = load_seed(out_path)
    if only_version !== nothing
        version = VersionNumber(only_version)
        version in tag_versions || error("$(version) is not a tag in the JuliaLang/julia repository")
        # a missing seed would produce a versions.json containing only this version
        isempty(meta) && error("refusing to run with only_version = $(version) without a seeded versions.json")
        tag_versions = [version]
    end
    number_urls_tried = 0
    number_urls_success = 0
    number_carried_over = 0
    prefix_cache = Dict{String, Any}()
    for version in tag_versions
        for platform in julia_platforms
            url = download_url(version, platform)
            filename = basename(url)

            existing = find_filedict(meta, version, url)
            head = object_info(prefix_cache, url)
            action = action_for_head_status(head.status, existing !== nothing)
            if action == :keep_existing
                @warn "S3 says previously-published $(url) is gone or unknown (status $(head.status)); keeping the existing entry"
                number_carried_over += 1
                continue
            elseif action == :skip_nonexistent
                continue
            elseif action == :skip_transient
                @warn "the existence of $(url) could not be determined; skipping it for this run"
                continue
            end

            if action == :proceed && existing !== nothing && filedict_is_complete(existing, url) &&
                    entry_matches_head(existing, head; url)
                number_carried_over += 1
                continue
            end
            delete_filedicts_for_url!(meta, version, url)

            # Download this URL to a local file
            number_urls_tried += 1
            local filepath
            try
                print(stdout, "Downloading $(filename)...")
                filepath = s3_download_to_cache(filename, url)
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
                    asc_filepath = s3_download_to_cache(basename(asc_url), asc_url)
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
            # so later incremental runs can cross-check the headers
            if head.etag !== nothing
                file_dict["etag"] = head.etag
            end
            if head.last_modified !== nothing
                file_dict["last-modified"] = head.last_modified
            end
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
