using DiskBackedDicts
using Base.Test
using DiskBackedDicts.TestUtils

function test_dict_interface(d_candidate, d_test)
    @assert isempty(d_candidate)
    @assert !isempty(d_test)
    
    @test isempty(d_candidate)
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
end

function associative_elements_equal(d1,d2)
    @test length(d1) == length(d2)
    for (k,v) in d1
        @test haskey(d2, k)
        @test d2[k] == v
    end
end

@testset "associative interface" begin
    d = DiskBackedDict(tempname()*".jld")
    @test d isa DiskBackedDict{Any, Any}
    d_test = Dict("a"=>1, "b"=>2)
    test_dict_interface(d, d_test)

    d = DiskBackedDict(tempname()*".jld")
    t = MyInt(1)
    s = MyString("s")
    st = MyPair(s,t)
    d_test = Dict("a"=>1, "b"=>2, "s" => s,
                  st => t)

    d = @inferred DiskBackedDict{MyString,MyInt}(tempname()*".jld")
    @test d isa Associative{MyString,MyInt}
    d_test = Dict(MyString("a") => MyInt(2), MyString("") => MyInt(0))
    test_dict_interface(d, d_test)
    
    path = tempname()*".jld"
    d = DiskBackedDict{Int, String}(path)
    d[1] = "one"
    @test_throws TypeError DiskBackedDict{MyString,MyInt}(path)

    @assert ispath(path)
    d2 = DiskBackedDict{Int, String}(path)
    @test typeof(d2) == typeof(d)
    @test d2[1] == "one"
    @test length(d2) == 1
    
    d3 = DiskBackedDict(path)
    @test typeof(d3) == typeof(d2)
    @test d3[1] == "one"
    @test length(d3) == 1
end

function test_long_term_persistence(path, d::Dict{K,V}) where {K,V}
    if !ispath(path)
        d_save = DiskBackedDict{K,V}(path)
        info("$path does not exist, create it with content $d")
        merge!(d_save, d)
    end
    d_loaded = DiskBackedDict{K,V}(path)
    associative_elements_equal(d, d_loaded)
end

assetpath(args...) = joinpath(@__DIR__, "assets", args...)
@testset "long term persistence" begin
    for (s, d) ∈ [
                  "empty.jld" => Dict(),
                  "1.jld"     => Dict(1 => 1),
                  "mixed.jld"=> Dict(1 => "1", :two => [1,2]),
                  "custom_types.jld" => Dict(MyInt(1) => MyString("two")),
                  "parametric_type.jld" => Dict(MyContainer(1) => MyContainer(MyInt(1))),
                 ]

        path = assetpath(s)
        test_long_term_persistence(path, d)
    end
end

@testset "modify existing DiskBackedDict" begin
    path = assetpath("dict_to_be_extended.jld")
    if !ispath(path)
        info("$path does not exist, create it")
        d = DiskBackedDict{Int, MyContainer{Int}}(path)
        d[1] = MyContainer(1)
    else
        d = DiskBackedDict{Int, MyContainer{Int}}(path)
        @test !isempty(d)
        m = maximum(keys(d))
        @test m == length(d)
        info("m = $m")
        d[m+1] = MyContainer(m+1)
        for (k,v) in d
            @test k == v.inner
        end
    end
end
