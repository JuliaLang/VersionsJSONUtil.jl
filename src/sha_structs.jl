const SHA1 = Base.SHA1

@static if isdefined(Base, :SHA256)
    const SHA256 = Base.SHA256
else
    # const SHA256 = Compat.SHA256

    struct SHA256
        bytes::NTuple{32, UInt8}
    end
    function SHA256(bytes::Vector{UInt8})
        length(bytes) == 32 ||
            throw(ArgumentError("wrong number of bytes for SHA1: Expected 32 bytes, got $(length(bytes))"))
        return SHA256(ntuple(i->bytes[i], Val(32)))
    end
    SHA256(s::AbstractString) = SHA256(hex2bytes(s))
    Base.parse(::Type{SHA256}, s::AbstractString) = SHA256(s)
    function Base.tryparse(::Type{SHA256}, s::AbstractString)
        try
            return parse(SHA256, s)
        catch e
            if isa(e, ArgumentError)
                return nothing
            end
            rethrow(e)
        end
    end

    Base.string(hash::SHA256) = bytes2hex(hash.bytes)
    Base.print(io::IO, hash::SHA256) = bytes2hex(io, hash.bytes)
    Base.show(io::IO, hash::SHA256) = print(io, SHA256str * "(\"", hash, "\")")

    Base.isless(a::SHA256, b::SHA256) = isless(a.bytes, b.bytes)
    Base.hash(a::SHA256, h::UInt) = hash((SHA256, a.bytes), h)
    Base.:(==)(a::SHA256, b::SHA256) = a.bytes == b.bytes
end
