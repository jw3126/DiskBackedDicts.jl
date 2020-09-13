module DiskBackedDicts

export DiskBackedDict

using ArgCheck
using JLD2

################################################################################
##### JLD2BlobDict
################################################################################
struct JLD2BlobDict{K,V} <: AbstractDict{K,V}
    path::String
    function JLD2BlobDict{K,V}(path::AbstractString) where {K,V}
        if !(splitext(path)[2] == ".jld2")
            msg = """Path must end with .jld2, got:
            path = $path"""
            throw(ArgumentError(msg))
        end
        new(String(path))
    end
end

function get_dict(obj::JLD2BlobDict{K,V}) where {K,V}
    if !(ispath(obj.path))
        dir = splitdir(obj.path)[1]
        mkpath(dir)
        data = Dict{K,V}()
        JLD2.@save obj.path data
    end
    JLD2.@load(obj.path, data)

    return convert(Dict{K,V},data)
end

function set_dict(obj::JLD2BlobDict{K,V}, data::AbstractDict{K,V}) where {K,V}
    return JLD2.@save obj.path data
end

const PURE_DICT_INTERFACE = [:getindex, :keys, :values, :length, :get, :iterate]
const MUT_DICT_INTERFACE = [:delete!, :setindex!, :get!, :empty!]


for f ∈ PURE_DICT_INTERFACE
    @eval function Base.$f(obj::JLD2BlobDict, args...)
        d = get_dict(obj)
        $f(d, args...)
    end
end

for f in MUT_DICT_INTERFACE
    @eval function Base.$f(obj::JLD2BlobDict, args...)
        d = get_dict(obj)
        ret = $f(d, args...)
        set_dict(obj, d)
        ret
    end
end

################################################################################
##### FullyCachedDict
################################################################################
"""
    FullyCachedDict([cache,] storage) <: AbstractDict

A fully cached variant of storage. That is `cache` is a copy
of `storage`, but hopefully faster to read. For instance `cache::Dict`
and `storage::JLD2BlobDict`.
"""
struct FullyCachedDict{K,V,C,S} <: AbstractDict{K,V}
    cache::C
    storage::S
    function FullyCachedDict{K,V}(cache::C, storage::S) where {K,V,C,S}
        @argcheck keytype(storage) === keytype(cache) === K
        @argcheck valtype(storage) === valtype(cache) === V
        empty!(cache)
        _merge!(cache, storage)
        return new{K,V,C,S}(cache, storage)
    end
end

function FullyCachedDict(cache, storage)
    @argcheck keytype(storage) === keytype(cache)
    @argcheck valtype(storage) === valtype(cache)
    K = keytype(storage)
    V = valtype(storage)
    return FullyCachedDict{K,V}(cache, storage)
end

function FullyCachedDict(storage::AbstractDict{K,V}) where {K,V}
    cache = Dict{K,V}()
    _merge!(cache, storage)
    return FullyCachedDict{K,V}(cache, storage)
end

for f ∈ PURE_DICT_INTERFACE
    @eval function Base.$f(obj::FullyCachedDict, args...)
        d = obj.cache
        $f(d, args...)
    end
end

for f in MUT_DICT_INTERFACE
    @eval function Base.$f(obj::FullyCachedDict, args...)
        $f(obj.storage, args...)
        $f(obj.cache,   args...)
    end
end

################################################################################
##### DiskBackedDict
################################################################################
struct DiskBackedDict{K,V} <: AbstractDict{K,V}
    inner::FullyCachedDict{K,V,Dict{K,V}, JLD2BlobDict{K,V}}
    function DiskBackedDict{K,V}(path::AbstractString) where {K,V}
        storage = JLD2BlobDict{K,V}(path)
        inner = FullyCachedDict(storage)
        return new(inner)
    end
end

DiskBackedDict(path::AbstractString) = DiskBackedDict{Any,Any}(path)

for f in [PURE_DICT_INTERFACE;MUT_DICT_INTERFACE]
    @eval (Base.$f)(d::DiskBackedDict, args...) = $f(d.inner, args...)
end

################################################################################
##### JLD2FilesStringDict
################################################################################
struct JLD2FilesStringDict{V} <: AbstractDict{String, V}
    root::String
    function JLD2FilesStringDict{V}(path::AbstractString) where {V}
        root = String(path)
        ret = new{V}(root)
        mkpath(valuedir(ret))
        return ret
    end
end

function Base.delete!(o::JLD2FilesStringDict, key)
    rm(valuepath(o, key), force=true)
    return o
end

headerpath(o::JLD2FilesStringDict) = joinpath(o.root, "header.jld2")
valuedir(o::JLD2FilesStringDict) = joinpath(o.root, "values")
valuepath(o::JLD2FilesStringDict, key::AbstractString) = joinpath(valuedir(o), key)

function JLD2FilesStringDict(root::AbstractString)
    V = Any
    JLD2FilesStringDict{V}(root)
end

function Base.empty!(o::JLD2FilesStringDict)
    dir = valuedir(o)
    for filename in readdir(dir)
        path = joinpath(dir, filename)
        rm(path)
    end
    return o
end

function Base.getindex(o::JLD2FilesStringDict, key::AbstractString)
    path = valuepath(o, key)
    ispath(path) || throw(KeyError(key))
    JLD2.@load path value
    return value
end

function Base.keys(o::JLD2FilesStringDict)
    readdir(valuedir(o))
end

function Base.setindex!(o::JLD2FilesStringDict, value, key::AbstractString)
    path = valuepath(o, key)
    value = convert(valtype(o), value)
    JLD2.@save path value
    value
end

Base.length(o::JLD2FilesStringDict) = length(keys(o))

function iterate_pairs_key_based(o)
    ks = keys(o)
    next = iterate(ks)
    if next === nothing
        return nothing
    else
        key, keystate = next
        key => o[key], (keystate=keystate, keys=ks)
    end
end
function iterate_pairs_key_based(o, state)
    next = iterate(state.keys, state.keystate)
    if next === nothing
        return nothing
    else
        key, keystate = next
        key => o[key], (keystate=keystate, keys=state.keys)
    end
end

################################################################################
##### JLD2FilesDict
################################################################################
struct JLD2FilesDict{K, V, H} <: AbstractDict{K,V}
    stringdict::JLD2FilesStringDict{Dict{K,V}}
    hash::H
end

function JLD2FilesDict{K,V}(path::AbstractString, hash=string∘Base.hash) where {K,V}
    H = typeof(hash)
    stringdict = JLD2FilesStringDict{Dict{K,V}}(path)
    return JLD2FilesDict{K,V,H}(stringdict, hash)
end

function JLD2FilesDict(path::AbstractString, hash=string∘Base.hash)
    K = V = Any
    return JLD2FilesDict{K,V}(path, hash)
end

function Base.keys(o::JLD2FilesDict)
    ret = keytype(o)[]
    for skey in keys(o.stringdict)
        append!(ret, keys(o.stringdict[skey]))
    end
    return ret
end

function Base.delete!(o::JLD2FilesDict, key)
    if haskey(o, key)
        skey = _skey(o, key)
        d = o.stringdict[skey]
        if length(d) == 1
            Base.delete!(o.stringdict, skey)
        else
            Base.delete!(d, key)
            o.stringdict[skey] = d
        end
    end
    return o
end
Base.length(o::JLD2FilesDict) = length(keys(o))

Base.iterate(o::Union{JLD2FilesStringDict, JLD2FilesDict}) = iterate_pairs_key_based(o)
Base.iterate(o::Union{JLD2FilesStringDict, JLD2FilesDict}, state) = iterate_pairs_key_based(o, state)

_skey(o, key)::String = o.hash(convert(keytype(o), key))

function Base.get(o::JLD2FilesDict, key, val)
    if haskey(o, key)
        o[key]
    else
        val
    end
end
Base.empty!(o::JLD2FilesDict) = empty!(o.stringdict)

function Base.getindex(o::JLD2FilesDict, key)
    skey = _skey(o, key)
    d = try
        o.stringdict[skey]
    catch err
        if err isa KeyError
            throw(KeyError(key))
        else
            rethrow(err)
        end
    end
    try
        return d[key]
    catch err
        if err isa KeyError
            throw(KeyError(key))
        else
            rethrow(err)
        end
    end
end

function Base.setindex!(o::JLD2FilesDict, val, key)
    K = keytype(o)
    V = valtype(o)
    key = convert(K, key)
    val = convert(V, val)
    skey = _skey(o, key)
    d = get!(o.stringdict, skey) do
        Dict{K,V}()
    end
    d[key] = val
    o.stringdict[skey] = d
    return val
end

################################################################################
##### CachedDict
################################################################################
"""
    CachedDict([cache,] storage) <: AbstractDict

A cached variant of storage. See also [`FullyCachedDict`](@ref).
"""
struct CachedDict{K,V,C,S} <: AbstractDict{K,V}
    cache::C
    storage::S
    function CachedDict{K,V}(cache::C, storage::S) where {K,V,C,S}
        @argcheck keytype(storage) === keytype(cache) === K
        @argcheck valtype(storage) === valtype(cache) === V
        return new{K,V,C,S}(cache, storage)
    end
end

function CachedDict(cache, storage)
    @argcheck keytype(storage) === keytype(cache)
    @argcheck valtype(storage) === valtype(cache)
    K = keytype(storage)
    V = valtype(storage)
    return CachedDict{K,V}(cache, storage)
end

function CachedDict(storage::AbstractDict{K,V}) where {K,V}
    cache = Dict{K,V}()
    return CachedDict{K,V}(cache, storage)
end

function Base.getindex(o::CachedDict, key)
    get!(o.cache, key) do
        o.storage[key]
    end
end
function Base.haskey(o::CachedDict, key)
    haskey(o.cache, key) || haskey(o.storage, key)
end
function Base.setindex!(o::CachedDict, val, key)
    ret = o.storage[key] = val
    o.cache[key] = val
    return ret
end
Base.iterate(o::CachedDict) = iterate_pairs_key_based(o)
Base.iterate(o::CachedDict, state) = iterate_pairs_key_based(o, state)

for f in [:(Base.keys), :(Base.values), :(Base.length)]
    @eval $f(o::CachedDict) = $f(o.storage)
end

function Base.empty!(o::CachedDict)
    empty!(o.cache)
    empty!(o.storage)
end
function Base.delete!(o::CachedDict, key)
    if haskey(o.cache, key)
        Base.delete!(o.cache, key)
    end
    return Base.delete!(o.storage, key)
end
function Base.get(o::CachedDict, key, val)
    get(o.cache, key) do
        get(o.storage, key, val)
    end
end
function Base.get!(o::CachedDict, key, val)
    get!(o.cache, key) do
        get!(o.storage, key, val)
    end
end

################################################################################
##### merge!
################################################################################

# merge! is an important operation, since it allows to do "batch" otherwise slow
# transactions
function Base.merge!(
        o1::Union{FullyCachedDict,JLD2BlobDict,DiskBackedDict},
        d2::AbstractDict)
    _merge!(o1, d2)
end

function _merge!(d1, d2)
    _merge1!(d1, _batch_reader(d2))
end

_batch_reader(d::JLD2BlobDict) = get_dict(d)
_batch_reader(d::AbstractDict) = d

function _merge1!(o1::JLD2BlobDict, r2)
    d1 = get_dict(o1)
    merge!(d1, r2)
    set_dict(o1, d1)
    o1
end
function _merge1!(d1, r2)
    merge!(d1, r2)
end
function _merge1!(o1::FullyCachedDict, r2)
    _merge1!(o1.cache,   r2)
    _merge1!(o1.storage, r2)
    o1
end
function _merge1!(o1::DiskBackedDict, r2)
    _merge1!(o1.inner, r2)
    o1
end

end # module
