using DiskBackedDicts
const DBD = DiskBackedDicts
using Test

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
    @test haskey(d_candidate, k)
    @test d_candidate[k] == v
    delete!(d_candidate, k)
    @test_throws KeyError d_candidate[k]
    @test isempty(d_candidate)
    @test v === get!(d_candidate, k, v)
    
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

    for d_test in test_dicts
        K = eltype(keys(d_test))
        V = eltype(values(d_test))
        candidates = [
                      DiskBackedDict{K,V}(tempname()*".jld2"),
                      DBD.JLD2Dict{K,V}(tempname()*".jld2"),
                      DBD.CachedDict(DBD.JLD2Dict{K,V}(tempname()*".jld2"))]
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
    src_ref = Dict(2=>2, 3=>3)
    res_ref = Dict(1=>1, 2=>2, 3=>3)
    function _replace!(dst, src)
        empty!(dst)
        merge!(dst, src)
    end
    srcs = [DBD.JLD2Dict{Any,Any}(tempname() * ".jld2"),
            DBD.CachedDict(Dict(),Dict()),
            DBD.DiskBackedDict(tempname() * ".jld2")
           ]
    dsts = [DBD.JLD2Dict{Any,Any}(tempname() * ".jld2"),
            DBD.CachedDict(Dict(),Dict()),
            DBD.DiskBackedDict(tempname() * ".jld2")
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
