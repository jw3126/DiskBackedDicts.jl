__precompile__()
module DiskBackedDicts

export DiskBackedDict

using JLD

const SKeyType = "KeyType"
const SValueType = "ValueType"

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
    keystrings::Dict{K, String}
    file::JLD.JldFile
    function DiskBackedDict{K,V}(path::String) where {K,V}
        local cache :: Dict{K,V}
        local keystrings::Dict{K, String}
        if !ispath(path)
            jldopen(path, "w") do file
                file[SKeyType] = K
                file[SValueType] = V
            end
        end
        keystrings, cache = get_keystrings_cache(K,V,path)
        file = jldopen(path, "r+")
        new(path, cache, keystrings, file)
    end
end

function DiskBackedDict(path::String)
    if ispath(path)
        jldopen(path, "r+") do file
            K = read(file, SKeyType)
            V = read(file, SValueType)
        end
    else
        K,V = Any,Any
    end
    DiskBackedDict{K,V}(path)
end

function get_keystrings_cache(K,V,pairdict::Dict{String})
    cache = Dict{K,V}()
    keystrings = Dict{K,String}()
    for (s, (k,v)) ∈ pairdict
        keystrings[k] = s
        cache[k] = v
    end
    keystrings, cache
end


function get_keystrings_cache(K::Type,V::Type,path::String)
    @assert ispath(path)
    d = jldopen(read, path, "r")::Dict
    K_file = d[SKeyType]
    V_file = d[SValueType]
    if K_file != K
        msg = "$SKeyType in $path does not match expectation."
        err = TypeError(:get_keystrings_cache, msg, K, K_file)
        throw(err)
    end
    if V_file != V
        msg = "$SValueType in $path does not match expectation."
        err = TypeError(:get_keystrings_cache, msg, V, V_file)
        throw(err)
    end
    delete!(d,SKeyType)
    delete!(d,SValueType)
    get_keystrings_cache(K,V,d)
end

function Base.delete!(o::DiskBackedDict, k)
    delete!(o.cache, k)
    s = o.keystrings[k]
    delete!(o.keystrings, k)
    delete!(o.file, s)
    o
end

function Base.setindex!(o::DiskBackedDict{K,V}, val::V, key::K) where {K,V}
    key ∈ keys(o) && delete!(o, key)
    
    o.keystrings[key] = string(Base.Random.uuid1())
    s = o.keystrings[key]
    o.file[s] = (key => val)
    o.cache[key] = val
    val
end

function Base.setindex!(o::DiskBackedDict{K,V}, val, key) where {K,V}
    k = convert(K, key)
    v = convert(V, val)
    o[k] = v
    val
end

for f ∈ (:getindex, :keys, :values, :length, :start, :next, :done)
    @eval Base.$f(o::DiskBackedDict, args...) = $f(o.cache, args...)
end

end # module
