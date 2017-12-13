__precompile__()
module DiskBackedDicts

export DiskBackedDict
using JLD

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
DiskBackedDicts.DiskBackedDict{Any} with 1 entry:
  "a" => 5

julia> d["a"]
5
"""
struct DiskBackedDict{T} <: Associative{String, T}
    path::String
    cache::Dict{String, T}
    file::JLD.JldFile

    function DiskBackedDict{T}(path::String, cache::Dict{String, T}) where {T}
        @assert !ispath(path)
        jldopen(path, "w") do file
            for (k,v) in cache
                file[k] = v
            end
        end
        file = jldopen(path, "r+")
        new(path, cache, file)
    end

    function DiskBackedDict{T}(path::String) where {T}
        D = Dict{String, T}
        if ispath(path)
            local cache::D
            cache = jldopen(read, path, "r")
            file = jldopen(path, "r+")
            new(path, cache, file)
        else
            DiskBackedDict{T}(path, D())
        end
    end
end

function DiskBackedDict(path, cache::Associative{String, V}) where {V}
    DiskBackedDict{V}(String(path), Dict(cache))
end
function DiskBackedDict(path, args...)
    DiskBackedDict(path, Dict(args...))
end
DiskBackedDict(path) = DiskBackedDict{Any}(path)

function Base.setindex!(o::DiskBackedDict{T}, val, key) where {T}
    k = convert(String, key)
    v = convert(T, val)
    o[k] = v
    val
end
function Base.setindex!(o::DiskBackedDict{T}, val::T, key::String) where {T}
    if key in keys(o)
        delete!(o.file[key])
    end
    o.file[key] = val
    o.cache[key] = val
end

for f ∈ (:getindex, :keys, :values, :length, :start, :next, :done)
    @eval Base.$f(o::DiskBackedDict, args...) = $f(o.cache, args...)
end

end # module
