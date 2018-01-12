__precompile__()
module DiskBackedDicts

export DiskBackedDict

using JLD2
# using JLD2

const CONTENT_DICT = "CONTENT_DICT"
"""
    DiskBackedDict{T} <: Associative{String, T}

# Example

```jldoctest
julia> using DiskBackedDicts

julia> d = DiskBackedDict("mypath.jld")
DiskBackedDicts.DiskBackedDict{Any} with 0 entries

julia> d["a"] = 5
5

julia> d
DiskBackedDicts.DiskBackedDict{Any,Any} with 1 entry:
  "a" => 5

julia> d["a"]
5
"""
struct DiskBackedDict{K,V} <: Associative{K,V}
    path::String
    cache::Dict{K,V}
    function DiskBackedDict{K,V}(path::String) where {K,V}
        local cache :: Dict{K,V}
        if !ispath(path)
            cache = Dict{K,V}()
            jldopen(path, "w") do file
                file[CONTENT_DICT] = cache
            end
        else
            jldopen(path, "r") do file
                d = file[CONTENT_DICT]
                Kgot = eltype(keys(d))
                if Kgot != K
                    msg = "mismatch between expected key type and loaded type"
                    err = TypeError(:DiskBackedDict, msg, K, Kgot)
                    throw(err)
                end
                Vgot = eltype(values(d))
                if Vgot != V
                    msg = "mismatch between expected value type and loaded type"
                    err = TypeError(:DiskBackedDict, msg, V, Vgot)
                    throw(err)
                end
                cache = d
            end
        end
        new(path, cache)
    end
end

function DiskBackedDict(path::String)
    if ispath(path)
        d = jldopen(path, "r") do file
            d = file[CONTENT_DICT]
            @assert d isa Dict
            d
        end
        K = eltype(keys(d))
        V = eltype(values(d))
    else
        K = Any
        V = Any
    end
    DiskBackedDict{K,V}(path)
end

function Base.delete!(o::DiskBackedDict, k)
    ret = delete!(o.cache, k)
    _save(o)
    ret
end

_save(o::DiskBackedDict) = jldopen(o.path, "w") do file
    file[CONTENT_DICT] = o.cache
end

function Base.setindex!(o::DiskBackedDict, key, val)
    ret = setindex!(o.cache, key, val)
    _save(o)
    ret
end

for f ∈ (:getindex, :keys, :values, :length, :start, :next, :done, :get)
    @eval Base.$f(o::DiskBackedDict, args...) = $f(o.cache, args...)
end

function Base.get!(o::DiskBackedDict, key, val)
    haskey(o, key) || setindex!(o,val,key)
    o[key]
end

include("util_for_tests.jl")

end # module
