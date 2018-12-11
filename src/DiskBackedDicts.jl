__precompile__()
module DiskBackedDicts
export DiskBackedDict

using FileIO
using JLD2

const SJLD2DICT = "data"
struct JLD2Dict{K,V} <: AbstractDict{K,V}
    path::String
    function JLD2Dict{K,V}(path::AbstractString) where {K,V}
        if !(splitext(path)[2] == ".jld2")
            msg = """Path must end with .jld2, got:
            path = $path"""
            throw(ArgumentError(msg))
        end
        new(String(path))
    end
end

function get_dict(obj::JLD2Dict{K,V}) where {K,V}
    if !(ispath(obj.path))
        dir = splitdir(obj.path)[1]
        mkpath(dir)
        FileIO.save(obj.path, Dict(SJLD2DICT => Dict{K,V}()))
    end
    ret::Dict{K,V} = FileIO.load(obj.path, SJLD2DICT)
end

function set_dict(obj::JLD2Dict{K,V}, d) where {K,V}
    FileIO.save(obj.path, Dict(SJLD2DICT => Dict{K,V}(d)))
end

const PURE_DICT_INTERFACE = [:getindex, :keys, :values, :length, :get, :iterate]
const MUT_DICT_INTERFACE = [:delete!, :setindex!, :get!, :empty!]


for f ∈ PURE_DICT_INTERFACE
    @eval function Base.$f(obj::JLD2Dict, args...)
        d = get_dict(obj)
        $f(d, args...)
    end
end

for f in MUT_DICT_INTERFACE
    @eval function Base.$f(obj::JLD2Dict, args...)
        d = get_dict(obj)
        ret = $f(d, args...)
        set_dict(obj, d)
        ret
    end
end

struct CachedDict{K,V,D} <: AbstractDict{K,V}
    cache::Dict{K,V}
    storage::D
end

function CachedDict(storage::AbstractDict{K,V}) where {K,V}
    cache = Dict{K,V}()
    merge!(cache, storage)
    CachedDict(cache, storage)
end

for f ∈ PURE_DICT_INTERFACE
    @eval function Base.$f(obj::CachedDict, args...)
        d = obj.cache
        $f(d, args...)
    end
end

for f in MUT_DICT_INTERFACE
    @eval function Base.$f(obj::CachedDict, args...)
        $f(obj.storage, args...)
        $f(obj.cache,   args...)
    end
end

struct DiskBackedDict{K,V} <: AbstractDict{K,V}
    inner::CachedDict{K,V,JLD2Dict{K,V}}
    function DiskBackedDict{K,V}(path::AbstractString) where {K,V}
        storage = JLD2Dict{K,V}(path)
        inner = CachedDict(storage)
        new(inner)
    end
end

DiskBackedDict(path::AbstractString) = DiskBackedDict{Any,Any}(path)


for f in [PURE_DICT_INTERFACE;MUT_DICT_INTERFACE]
    @eval (Base.$f)(d::DiskBackedDict, args...) = $f(d.inner, args...)
end

end # module
