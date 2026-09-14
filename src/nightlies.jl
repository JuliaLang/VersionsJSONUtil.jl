# ------------------------------------------------------------------------------------------
# nightlies.json: the channels of in-development Julia builds and the files they are served
# from.
#
# This complements versions.json: that file describes immutable release artifacts,
# identified by version and content hash, whereas every URL listed here is overwritten by
# CI after each successful build on its branch. So nightlies.json records neither a
# version nor hashes, only which files exist. Consumers are expected to track changes
# through the server's ETag / Last-Modified headers (as juliaup does).
#
# Channels follow the juliaup vocabulary: `nightly` tracks `master`, `x.y-nightly` tracks
# the x.y release series (`release-x.y` once that branch exists, `master` before). Each
# channel has:
#   "files":    the standard builds, described with the same keys as in versions.json
#               (minus version, size and hashes), plus "asc-url", the URL of the detached
#               GPG signature when one is published.
#   "variants": build variants of the standard binaries (e.g. the PGO+LTO+BOLT optimized
#               build, or the GPL-free build), as a separate list so that consumers
#               selecting a file from "files" by platform never pick up a variant by
#               accident. Entries have the keys of "files" plus "variants", the names of
#               the variants applied to the build (a list, so that combinations can be
#               expressed later; julia-buildkite currently only ever builds one). Absent
#               when the channel has no variants. This is the shape intended for variants
#               of releases in versions.json.

const nightlies_base_url = "https://julialangnightlies-s3.julialang.org/bin/"
const nogpl_nightlies_base_url = "https://julialang-nogpl.s3.amazonaws.com/bin-nogpl/"

# Build variants of the nightlies, and the bucket they are uploaded to. julia-buildkite
# names the artifacts of a variant by appending its name to the OS (the `OS` of its
# utilities/extract_triplet.sh), e.g. `bin/linuxopt/x86_64/julia-latest-linuxopt-x86_64.tar.gz`.
const nightly_variants = [
    "opt"    => nightlies_base_url,        # PGO + LTO + BOLT optimized build
    "assert" => nightlies_base_url,        # build with Julia and LLVM assertions enabled
    "nogpl"  => nogpl_nightlies_base_url,  # build without GPL-licensed dependencies
]

# The platform types of `julia_platforms` (as opposed to its wrappers selecting another
# file format of the same platform).
const BasePlatform = Union{Linux, MacOS, Windows, FreeBSD}

"A build variant of a `BasePlatform` entry of `julia_platforms`. Only published as a tarball."
struct Variant{P <: BasePlatform}
    platform::P
    name::String
    base_url::String
end
Variant(platform, name) = Variant(platform, name, Dict(nightly_variants)[name])
@forward Variant.platform (up_os, tar_os, triplet, arch)

nightly_base_url(p) = nightlies_base_url
nightly_base_url(v::Variant) = v.base_url

jlext(v::Variant) = "tar.gz"
meta_os(v::Variant) = meta_os(v.platform)

# The nightly URL scheme differs from the release one (see build_envs.sh in julia-buildkite):
#     bin/<os>/<arch>/[<x.y>/]julia-latest-<name>.<ext>
# For the standard builds these are the folder and file names juliaup and julialang.org use.
nightly_os(p::Windows) = "winnt"
nightly_os(p::MacOS) = "macos"
nightly_os(p::Linux) = up_os(p)
nightly_os(p::FreeBSD) = "freebsd"
nightly_arch(p::Windows) = up_arch(p)
nightly_arch(p) = string(arch(p))
nightly_name(p::Windows) = "julia-latest-win$(wordsize(p))"
nightly_name(p) = "julia-latest-$(nightly_os(p))-$(arch(p))"
for f in (:nightly_os, :nightly_arch, :nightly_name)
    @eval $f(p::Union{WindowsPortable, WindowsTarball}) = $f(p.windows)
    @eval $f(p::MacOSTarball) = $f(p.macos)
end

# Variants only exist under julia-buildkite's canonical names, i.e. with the full OS
# (`windows`, not `winnt`) and architecture (`x86_64`, not `x64`) names.
variant_os(p::Windows) = "windows"
variant_os(p::MacOS) = "macos"
variant_os(p::Linux) = up_os(p)
variant_os(p::FreeBSD) = "freebsd"
nightly_os(v::Variant) = variant_os(v.platform) * v.name
nightly_arch(v::Variant) = string(arch(v.platform))
nightly_name(v::Variant) = "julia-latest-$(nightly_os(v))-$(arch(v.platform))"

"URL of the latest build for `platform`, of the `series` (`v\"1.13\"`) or of `master` (`nothing`)."
function nightly_url(platform, series::Union{Nothing, VersionNumber} = nothing)
    folder = series === nothing ? "" : "$(series.major).$(series.minor)/"
    return string(
        nightly_base_url(platform),
        nightly_os(platform), "/",
        nightly_arch(platform), "/",
        folder,
        nightly_name(platform), ".", jlext(platform),
    )
end

# The standard platforms, then every variant of every base platform. Like in `main`, we
# don't know which of these exist and simply probe them all.
function nightly_platforms()
    base = filter(p -> p isa BasePlatform, julia_platforms)
    return vcat(julia_platforms, [Variant(p, name, url) for (name, url) in nightly_variants for p in base])
end

function nightly_file_dict(platform, url; asc_url = nothing)
    kind, extension = kind_and_extension(basename(url))
    file_dict = Dict{String, Any}(
        "triplet" => triplet(platform),
        "os" => meta_os(platform),
        "arch" => string(arch(platform)),
        "kind" => kind,
        "extension" => extension,
        "url" => url,
    )
    if asc_url !== nothing
        file_dict["asc-url"] = asc_url
    end
    if platform isa Variant
        file_dict["variants"] = [platform.name]
    end
    return file_dict
end

# The files of one channel, as a channel dict: every probed platform whose URL exists, the
# standard builds under "files" and the variants under "variants". A 404 means the platform
# isn't built for this channel; any other failure is logged and the file is left out of this
# run (the next run will see it again).
function probe_nightly_channel(series)
    platforms = nightly_platforms()
    urls = [nightly_url(p, series) for p in platforms]
    heads = asyncmap(head_url, urls; ntasks = 8)
    found = []
    for (platform, url, head) in zip(platforms, urls, heads)
        if head.status == 200
            push!(found, (platform, url))
        elseif head.status != 404
            @warn "HEAD returned $(head.status) for $(url); skipping it for this run"
        end
    end
    # Signatures are only published for tarballs; record the ones that exist.
    asc_urls = [jlext(p) == "tar.gz" ? url * ".asc" : nothing for (p, url) in found]
    asc_heads = asyncmap(u -> u === nothing ? nothing : head_url(u), asc_urls; ntasks = 8)
    files = []
    variants = []
    for ((p, url), asc_url, h) in zip(found, asc_urls, asc_heads)
        file_dict = nightly_file_dict(p, url; asc_url = (h !== nothing && h.status == 200) ? asc_url : nothing)
        push!(p isa Variant ? variants : files, file_dict)
    end
    channel = Dict{String, Any}("files" => files)
    if !isempty(variants)
        channel["variants"] = variants
    end
    return channel
end

# The x.y series that may have nightlies: every series with a tag, and the next two, so
# that master (whose series has no tags until its first prerelease) and a freshly created
# release branch are covered too. Newest first.
function candidate_series(tag_versions)
    series = unique!(sort!([VersionNumber(v.major, v.minor) for v in tag_versions]))
    latest = series[end]
    for i in 1:2
        push!(series, VersionNumber(latest.major, latest.minor + i))
    end
    return reverse(series)
end

function nightlies(out_path)
    tags = get_tags()
    tag_versions = filter(x -> x !== nothing, [vnum_maybe(basename(t["ref"])) for t in tags])

    # (JSON.print writes keys sorted, so the output is deterministic)
    meta = Dict{String, Any}()
    @info "Probing nightly"
    meta["nightly"] = probe_nightly_channel(nothing)
    for series in candidate_series(tag_versions)
        channel = "$(series.major).$(series.minor)-nightly"
        # Nightlies of inactive series expire from the bucket. Check the tier-1 Linux
        # x86_64 tarball first so we don't probe all platforms of every series ever tagged.
        if head_url(nightly_url(Linux(:x86_64), series)).status != 200
            continue
        end
        @info "Probing $(channel)"
        channel_dict = probe_nightly_channel(series)
        if !isempty(channel_dict["files"])
            meta[channel] = channel_dict
        end
    end

    open(out_path, "w") do io
        JSON.print(io, meta, 2)
    end
    @info "Wrote $(length(meta)) channels to $(out_path)"
end
