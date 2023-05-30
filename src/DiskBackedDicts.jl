module DiskBackedDicts
using CachedDicts

export DiskBackedDict
export JLD2FilesDict

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

function Base.get(f::Base.Callable, o::JLD2BlobDict, key)
    d = get_dict(o)
    get(f,d,key)
end
function Base.get!(f::Base.Callable, o::JLD2BlobDict, key)
    if haskey(o, key)
        nothing
    else
        o[key] = f()
    end
    return o[key]
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

function Base.get(f::Base.Callable, o::FullyCachedDict, key)
    get(f, o.cache, key)
end
function Base.get!(f::Base.Callable, o::FullyCachedDict, key)
    if haskey(o, key)
        val = o[key]
    else
        val = f()
        o[key] = val
    end
    return val
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
Base.get(f::Base.Callable, o::DiskBackedDict, key) = Base.get(f, o.inner, key)

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

function Base.haskey(o::JLD2FilesStringDict, key)
    return isfile(valuepath(o, key))
end

function Base.delete!(o::JLD2FilesStringDict, key)
    rm(valuepath(o, key), force=true)
    return o
end

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
function getwith_naive!(f, o, key)
    if haskey(o, key)
        return o[key]
    else
        val = convert(valtype(o), f())
        o[key] = val
        return val
    end
end
function getwith_naive(f, o, key)
    if haskey(o, key)
        return o[key]
    else
        f()
    end
end

Base.get!(f::Base.Callable, o::JLD2FilesStringDict, key) = getwith_naive!(f,o,key)
Base.get(f::Base.Callable, o::JLD2FilesStringDict, key) = getwith_naive(f,o,key)

################################################################################
##### JLD2FilesDict
################################################################################
struct JLD2FilesDict{K, V} <: AbstractDict{K,V}
    stringdict::JLD2FilesStringDict{Dict{K,V}}
end

Base.get!(f::Base.Callable, o::JLD2FilesDict, key) = getwith_naive!(f,o,key)
Base.get(f::Base.Callable, o::JLD2FilesDict, key) = getwith_naive(f,o,key)

function JLD2FilesDict{K,V}(path::AbstractString) where {K,V}
    stringdict = JLD2FilesStringDict{Dict{K,V}}(path)
    return JLD2FilesDict{K,V}(stringdict)
end

function JLD2FilesDict(path::AbstractString)
    K = V = Any
    return JLD2FilesDict{K,V}(path)
end

function Base.keys(o::JLD2FilesDict)
    ret = keytype(o)[]
    for skey in keys(o.stringdict)
        append!(ret, keys(o.stringdict[skey]))
    end
    return ret
end

function Base.haskey(o::JLD2FilesDict, key)::Bool
    skey = get_stringkey(o, key)
    if haskey(o.stringdict, skey)
        haskey(o.stringdict[skey], key)
    else
        false
    end
end

function Base.delete!(o::JLD2FilesDict, key)
    if haskey(o, key)
        skey = get_stringkey(o, key)
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

function get_stringkey(o::JLD2FilesDict, key)::String 
    h = Base.hash(convert(keytype(o), key))
    filename = "$(repr(h)).jld2"
    filename
end

function Base.get(o::JLD2FilesDict, key, val)
    if haskey(o, key)
        o[key]
    else
        val
    end
end
Base.empty!(o::JLD2FilesDict) = empty!(o.stringdict)

function Base.getindex(o::JLD2FilesDict, key)
    skey = get_stringkey(o, key)
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
    skey = get_stringkey(o, key)
    d = get!(o.stringdict, skey) do
        Dict{K,V}()
    end
    d[key] = val
    o.stringdict[skey] = d
    return val
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

################################################################################
#### DictWithStats
################################################################################
mutable struct DictWithStats{K,V,D} <: AbstractDict{K,V}
    const dict::D
    empty!::Int
    getindex::Int
    haskey::Int
    keys::Int
    length::Int
    setindex!::Int
    delete!::Int
    isempty::Int
    iterate::Int
    get::Int
end
function Base.show(io::IO, o::DictWithStats)
    pnames = collect(Symbol,Base.tail(propertynames(o)))
    @assert !(:dict in pnames)
    println(io, "$(typeof(o)) with $(length(o)) entries and stats:")
    pnames = sort!(pnames, by=pname->getproperty(o, pname), rev=true)
    for pname in pnames
        println(io, "  ", pname, " = ", getproperty(o, pname))
    end
    println(io)
end

function Base.get(f::Base.Callable, o::DictWithStats, key)
    o.get += 1
    get(f, o.dict, key)
end
function Base.get(o::DictWithStats, key, val)
    o.get += 1
    get(o.dict, key, val)
end
function DictWithStats(d::AbstractDict{K,V}) where {K,V}
    DictWithStats{K,V,typeof(d)}(d, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
end
function Base.iterate(o::DictWithStats)
    o.iterate += 1
    iterate(o.dict)
end
function Base.iterate(o::DictWithStats, state)
    o.iterate += 1
    iterate(o.dict, state)
end

function Base.length(o::DictWithStats)
    o.length += 1
    length(o.dict)
end
function Base.getindex(o::DictWithStats, key)
    o.getindex += 1
    getindex(o.dict, key)
end
function Base.setindex!(o::DictWithStats, val, key)
    o.setindex! += 1
    setindex!(o.dict, val, key)
end
function Base.haskey(o::DictWithStats, key)
    o.haskey += 1
    haskey(o.dict, key)
end
function Base.keys(o::DictWithStats)
    o.keys += 1
    keys(o.dict)
end
function Base.empty!(o::DictWithStats)
    o.empty! += 1
    empty!(o.dict)
end
function Base.delete!(o::DictWithStats, key)
    o.delete! += 1
    delete!(o.dict, key)
end
function Base.isempty(d::DictWithStats)
    d.isempty += 1
    isempty(d.dict)
end

end # module
