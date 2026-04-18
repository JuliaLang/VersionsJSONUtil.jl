using JSON: JSON

struct OurCustomStyle <: JSON.JSONStyle
end

### versions.json:

@enumx ArchEnum aarch64 armv7l i686 powerpc64le x86_64
function ArchEnum.T(arch::Symbol)::ArchEnum.T
    if arch == :aarch64
        return ArchEnum.aarch64
    elseif arch == :armv7l
        return ArchEnum.armv7l
    elseif arch == :i686
        return ArchEnum.i686
    elseif arch == :powerpc64le
        return ArchEnum.powerpc64le
    elseif arch == :x86_64
        return ArchEnum.x86_64
    else
        error("Unknown arch: $arch")
    end
end

@enumx ExtensionEnum dmg exe tar_gz zip
function ExtensionEnum.T(ext::String)::ExtensionEnum.T
    if ext == "dmg"
        return ExtensionEnum.dmg
    elseif ext == "exe"
        return ExtensionEnum.exe
    elseif ext == "tar.gz"
        return ExtensionEnum.tar_gz
    elseif ext == "zip"
        return ExtensionEnum.zip
    else
        error("Unknown extension: $ext")
    end
end
function StructUtils.lift(style::OurCustomStyle, ::Type{ExtensionEnum.T}, ext::String)
    return ExtensionEnum.T(ext), StructUtils.defaultstate(style)
end
function StructUtils.lower(::OurCustomStyle, ext::ExtensionEnum.T)::String
    if ext == ExtensionEnum.dmg
        return "dmg"
    elseif ext == ExtensionEnum.exe
        return "exe"
    elseif ext == ExtensionEnum.tar_gz
        return "tar.gz"
    elseif ext == ExtensionEnum.zip
        return "zip"
    else
        error("Unknown extension: $ext")
    end
end

@enumx KindEnum archive installer
function KindEnum.T(kind::String)::KindEnum.T
    if kind == "archive"
        return KindEnum.archive
    elseif kind == "installer"
        return KindEnum.installer
    else
        error("Unnown kind: $kind")
    end
end

@enumx OsEnum freebsd linux mac winnt
function OsEnum.T(os::String)::OsEnum.T
    if os == "freebsd"
        return OsEnum.freebsd
    elseif os == "linux"
        return OsEnum.linux
    elseif os == "mac"
        return OsEnum.mac
    elseif os == "winnt"
        return OsEnum.winnt
    else
        error("Unknown OS: $os")
    end
end

StructUtils.structlike(::OurCustomStyle, ::Type{Platform}) = false
function StructUtils.lift(style::OurCustomStyle, ::Type{Platform}, triplet_str::String)
    return parse(Platform, triplet_str), StructUtils.defaultstate(style)
end
function StructUtils.lower(::OurCustomStyle, plat::Platform)::String
    return triplet(plat)
end

StructUtils.structlike(::OurCustomStyle, ::Type{URI}) = false
function StructUtils.lift(style::OurCustomStyle, ::Type{URI}, url::String)
    return URI(url), StructUtils.defaultstate(style)
end
function StructUtils.lower(::OurCustomStyle, url::URI)::String
    return string(url)
end

StructUtils.structlike(::OurCustomStyle, ::Type{SHA1}) = false
function StructUtils.lift(style::OurCustomStyle, ::Type{SHA1}, hash::String)
    return SHA1(hash), StructUtils.defaultstate(style)
end
function StructUtils.lower(::OurCustomStyle, hash::SHA1)::String
    return string(hash)
end

@kwarg mutable struct FileDict
    # The order of fields in this struct is important.
    # JSON.jl will serialize the JSON in the exact same order as the order of fields here.
    # We choose to order the fields as follows:
    # - Required fields first, then optional fields.
    # - Within each group, order alphabetically.
    #
    # Note: The order of fields is not part of our stability guarantees. We are allowed to
    # change the order of fields in the future.

    # Required fields:
    arch::ArchEnum.T
    extension::ExtensionEnum.T
    kind::KindEnum.T
    os::OsEnum.T
    sha256::String
    size::Int
    triplet::Platform
    url::URI
    version::VersionNumber

    # Optional fields:
    asc::Union{String, Nothing} = nothing
    etag::Union{String, Nothing} = nothing
    git_tree_sha1::Union{SHA1, Nothing} = nothing &(json=(name="git-tree-sha1",),)
    git_tree_sha256::Union{String, Nothing} = nothing &(json=(name="git-tree-sha256",),) # TODO: Use SHA256 (instead of String)
    last_modified::Union{String, Nothing} = nothing &(json=(name="last-modified",),)
end
function FileDict(dict::Dict)::FileDict
    file = FileDict(;
        # Required fields:
        arch = dict["arch"],
        extension = dict["extension"],
        kind = dict["kind"],
        os = dict["os"],
        sha256 = dict["sha256"],
        size = dict["size"],
        triplet = dict["triplet"],
        url = URI(dict["url"]),
        version = dict["version"],

        # Optional fields:
        asc = get(dict, "asc", nothing),
        etag = get(dict, "etag", nothing),
        git_tree_sha1 = get(dict, "git-tree-sha1", nothing),
        git_tree_sha256 = get(dict, "git-tree-sha256", nothing),
        last_modified = get(dict, "last-modified", nothing),
    )
    return file
end

Base.@kwdef struct SingleVersionInfo
    stable::Bool
    files::Vector{FileDict} = []
end

const VersionsJsonDocument = Dict{VersionNumber, SingleVersionInfo}

### internal.json:

struct InternalJsonSingleVersion
    known_nonexistent_urls::Vector{URI}
end
InternalJsonSingleVersion() = InternalJsonSingleVersion([])

const InternalJsonDocument = Dict{VersionNumber, InternalJsonSingleVersion}
