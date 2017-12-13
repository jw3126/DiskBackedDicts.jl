# DiskBackedDicts


[![Build Status](https://travis-ci.org/jw3126/DiskBackedDicts.jl.svg?branch=master)](https://travis-ci.org/jw3126/DiskBackedDicts.jl)
[![codecov.io](https://codecov.io/github/jw3126/DiskBackedDicts.jl/coverage.svg?branch=master)](http://codecov.io/github/jw3126/DiskBackedDicts.jl?branch=master)

## Usage

```julia
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

# one week later "a" will still be stored
julia> using DiskBackedDicts

julia> d = DiskBackedDict("mypath.jld")
DiskBackedDicts.DiskBackedDict{Any} with 1 entry:
  "a" => 5
```

## Performance

The whole `Dict` is cached in memory. `getindex` is as fast as for an
ordinary `Dict`, while `setindex!` is slow.

##$ Limitations

* Only `String` keys are supported.
* Only one julia process can write access a `DiskBackedDict` at a particular path.
