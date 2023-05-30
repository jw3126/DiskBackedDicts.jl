using DiskBackedDicts
const DBD = DiskBackedDicts
using Test

@testset "DictWithStats" begin
    d = DBD.DictWithStats(Dict())
    d[1] = 1
    @test d.setindex! == 1
    d[2] = 2
    @test d.setindex! == 2
    @test d.getindex == 0
    @test length(d) == 2
    @test d.length == 1
    sprint(show, d)

    d[1]
    @test d.getindex == 1
end

struct HashCollision
    payload::Int
end
function Base.hash(o::HashCollision,h::UInt)
    h
end

function test_dict_interface(d_candidate, d_test)
    @assert isempty(d_candidate)
    @assert !isempty(d_test)

    @test isempty(d_candidate)
    @test isempty(keys(d_candidate))
    @test isempty(values(d_candidate))
    @test length(d_candidate) == 0

    k, v = first(d_test)
    @test !haskey(d_candidate, k)
    @test v === get(d_candidate, k, v)
    d_candidate[k] = v
    @test !isempty(d_candidate)
    @test !isempty(keys(d_candidate))
    @test !isempty(values(d_candidate))
    @test haskey(d_candidate, k)
    @test d_candidate[k] == v
    @test d_candidate == delete!(d_candidate, k)
    @test_throws KeyError d_candidate[k]
    @test d_candidate == delete!(d_candidate, k)
    @test isempty(d_candidate)
    @test v === get!(d_candidate, k, v)
    get!(error, d_candidate, k)
    get(error, d_candidate, k)
    delete!(d_candidate, k)
    @test v === get(() -> v, d_candidate, k)
    @test !haskey(d_candidate, k)
    @test v === get!(() -> v, d_candidate, k)
    @test d_candidate[k] === v

    merge!(d_candidate, d_test)
    @test length(d_candidate) == length(d_test)
    @test length(d_candidate) == length(keys(d_candidate))
    @test length(d_candidate) == length(values(d_candidate))
    associative_elements_equal(d_candidate, d_test)

    @test !isempty(d_candidate)
    @test isempty(empty!(d_candidate))
end

function associative_elements_equal(d1,d2)
    @test length(d1) == length(d2)
    for (k,v) in d1
        @test haskey(d2, k)
        @test d2[k] == v
    end
end

struct MyString
    a::String
end
Base.:(==)(s1::MyString, s2::MyString) = s1.a == s2.a
struct MyInt
    b::Int
end
struct MyPair
    s::MyString
    t::MyInt
end
struct MyContainer{T}
    inner::T
end

@testset "AbstractDict interface" begin
    test_dicts = []

    d_test = Dict("a"=>1, "b"=>2)
    push!(test_dicts, d_test)

    t = MyInt(1)
    s = MyString("s")
    st = MyPair(s,t)
    d_test = Dict("a"=>1, "b"=>2, "s" => s, st => t)
    push!(test_dicts, d_test)

    d_test = Dict(MyString("a") => MyInt(2), MyString("") => MyInt(0))
    push!(test_dicts, d_test)

    d_test = Dict(HashCollision(1) =>1, HashCollision(2) => 2, HashCollision(3) => 3)
    push!(test_dicts, d_test)

    for d_test in test_dicts
        K = eltype(keys(d_test))
        V = eltype(values(d_test))
        candidates = [
            DiskBackedDict{K,V}(tempname()*".jld2"),
            DBD.JLD2BlobDict{K,V}(tempname()*".jld2"),
            DBD.FullyCachedDict(DBD.JLD2BlobDict{K,V}(tempname()*".jld2")),
            DBD.CachedDict{K,V}(Dict{K,V}(), Dict{K,V}()),
            Dict{K,V}(),
            DBD.JLD2FilesDict{K,V}(tempname()*".jld2"),
            DBD.CachedDict{K,V}(Dict{K,V}(), DBD.JLD2FilesDict{K,V}(tempname()*".jld2")),
            DBD.DictWithStats(Dict{K,V}()),
        ]
        for d_candidate in candidates
            test_dict_interface(d_candidate, d_test)
        end
    end

end

@testset "DiskBackedDict" begin
    d = DiskBackedDict(tempname()*".jld2")
    @test d isa DiskBackedDict{Any, Any}

    d = @inferred DiskBackedDict{MyString,MyInt}(tempname()*".jld2")
    @test d isa AbstractDict{MyString,MyInt}

    path = tempname()*".jld2"
    d = DiskBackedDict{Int, String}(path)
    d[1] = "one"
    @test_throws MethodError DiskBackedDict{MyString,MyInt}(path)

    @assert ispath(path)
    d2 = DiskBackedDict{Int, String}(path)
    @test typeof(d2) == typeof(d)
    @test d2[1] == "one"
    @test length(d2) == 1

    d3 = DiskBackedDict(path)
    @test_broken typeof(d3) == typeof(d2)
    @test d3[1] == "one"
    @test length(d3) == 1
end

function test_long_term_persistence(path, d::Dict{K,V}) where {K,V}
    if !ispath(path)
        d_save = DiskBackedDict{K,V}(path)
        @info("$path does not exist, create it with content $d.")
        merge!(d_save, d)
    else
        @info("Using $path from previous run.")
    end
    d_loaded = DiskBackedDict{K,V}(path)
    associative_elements_equal(d, d_loaded)
end

assetpath(args...) = joinpath(@__DIR__, "assets", args...)
@testset "long term persistence" begin
    for (s, d) ∈ [
                  "empty.jld2" => Dict(),
                  "1.jld2"     => Dict(1 => 1),
                  "mixed.jld2"=> Dict(1 => "1", :two => [1,2]),
                  "custom_types.jld2" => Dict(MyInt(1) => MyString("two")),
                  "parametric_type.jld2" => Dict(MyContainer(1) => MyContainer(MyInt(1))),
                 ]

        path = assetpath(s)
        test_long_term_persistence(path, d)
    end
end

@testset "merge!" begin
    dst_ref = Dict(1=>1, 2=>2)
    src_ref = Dict(2=>2.5, 3=>3)
    res_ref = Dict(1=>1, 2=>2.5, 3=>3)
    function _replace!(dst, src)
        empty!(dst)
        merge!(dst, src)
    end
    srcs = [DBD.JLD2BlobDict{Any,Any}(tempname() * ".jld2"),
            DBD.FullyCachedDict(Dict(),Dict()),
            DBD.DiskBackedDict(tempname() * ".jld2"),
            Dict(),
           ]
    dsts = [DBD.JLD2BlobDict{Any,Any}(tempname() * ".jld2"),
            DBD.FullyCachedDict(Dict(),Dict()),
            DBD.DiskBackedDict(tempname() * ".jld2"),
            Dict(),
           ]
    for src in srcs
        for dst in dsts
            _replace!(src, src_ref)
            _replace!(dst, dst_ref)
            associative_elements_equal(src, src_ref)
            associative_elements_equal(dst, dst_ref)
            res = merge!(dst, src)
            @test res === dst
            @test typeof(res) == typeof(dst)
            associative_elements_equal(res, res_ref)
        end
    end
end

@testset "HashCollision" begin
    ds = [DBD.JLD2BlobDict{Any,Any}(tempname() * ".jld2"),
            DBD.FullyCachedDict(Dict(),Dict()),
            DBD.DiskBackedDict(tempname() * ".jld2"),
            DBD.JLD2FilesDict{HashCollision,Int}(tempname() * ".jld2"),
            Dict(),
           ]
    k1 = HashCollision(1)
    k2 = HashCollision(2)
    k3 = HashCollision(3)
    @test hash(k1) == hash(k2)
    for d in ds
        @test isempty(d)
        d[k1] = 1
        @test haskey(d, k1)
        @test !haskey(d, k2)
        @test !haskey(d, k3)
        @test length(d) == 1

        d[k2] = 2
        @test haskey(d, k1)
        @test haskey(d, k2)
        @test !haskey(d, k3)
        @test length(d) == 2
        @test d[k1] == 1
        @test d[k2] == 2

        d[k3] = 3
        @test haskey(d, k1)
        @test haskey(d, k2)
        @test haskey(d, k3)
        @test length(d) == 3
        @test d[k1] == 1
        @test d[k2] == 2
        @test d[k3] == 3

        delete!(d, k2)
        @test haskey(d, k1)
        @test !haskey(d, k2)
        @test haskey(d, k3)
        @test length(d) == 2
        @test d[k1] == 1
        @test_throws KeyError d[k2]
        @test d[k3] == 3
    end
end

