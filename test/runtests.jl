using DiskBackedDicts
using Base.Test

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
    for (k,v) ∈ d_candidate
        @test d_test[k] == v
    end
end

struct S
    a::String
end
struct T
    b::Int
end

@testset "DiskBackedDict" begin
    d = DiskBackedDict(tempname()*".jld")
    @test d isa DiskBackedDict{Any, Any}
    d_test = Dict("a"=>1, "b"=>2)
    test_dict_interface(d, d_test)

    d = @inferred DiskBackedDict{S,T}(tempname()*".jld")
    @test d isa Associative{S,T}
    d_test = Dict(S("a") => T(2), S("") => T(0))
    test_dict_interface(d, d_test)
    
    path = tempname()*".jld"
    d = DiskBackedDict{Int, String}(path)
    d[1] = "one"
    @test_throws TypeError DiskBackedDict{S,T}(path)
    close(d.file)

    @assert ispath(path)
    d2 = DiskBackedDict{Int, String}(path)
    @test typeof(d2) == typeof(d)
    @test d2[1] == "one"
    @test length(d2) == 1
    close(d2.file)
    
    d3 = DiskBackedDict(path)
    @test typeof(d3) == typeof(d2)
    @test d3[1] == "one"
    @test length(d3) == 1
end
