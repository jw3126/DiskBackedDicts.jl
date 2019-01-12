# DiskBackedDicts


[![Build Status](https://travis-ci.org/jw3126/DiskBackedDicts.jl.svg?branch=master)](https://travis-ci.org/jw3126/DiskBackedDicts.jl)
[![codecov.io](https://codecov.io/github/jw3126/DiskBackedDicts.jl/coverage.svg?branch=master)](http://codecov.io/github/jw3126/DiskBackedDicts.jl?branch=master)

## Usage

```julia
julia> using DiskBackedDicts

julia> d = DiskBackedDict("somepath.jld2")
DiskBackedDict{Any,Any} with 0 entries

julia> d["hello"] = "world"
"world"

julia> d
DiskBackedDict{Any,Any} with 1 entry:
  "hello" => "world"

julia> exit()
```
Now start a new session:
```julia
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.0.1 (2018-09-29)
 _/ |\__'_|_|_|\__'_|  |  Official https://julialang.org/ release
|__/                   |

julia> using DiskBackedDicts

julia> d = DiskBackedDict("somepath.jld2")
DiskBackedDict{Any,Any} with 1 entry:
  "hello" => "world"

```

## Performance

The whole dictionary is cached in memory. `getindex` performs no disk operations and is as fast as for an
ordinary `Dict`. `setindex!` performs disk operations and is slow.

## Limitations

* Only one julia process can access a `DiskBackedDict` at a particular path simultaneously.
