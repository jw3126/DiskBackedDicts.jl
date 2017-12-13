using DiskBackedDicts
using Base.Test

@testset "DiskBackedDict" begin
    path = string(tempname(), ".jld")
    d = DiskBackedDict{Int}(path)
    @test isempty(d)
    val = rand(Int)
    d["a"] = val
    @test length(d) == 1
    @test d["a"] === val
    @inferred d["a"]
    
    d["a"] = 2
    @test d["a"] === 2
    @test_throws KeyError d["b"]
    d[:b] = 1.0
    dict = @inferred Dict(d)
    @test dict isa Dict{String, Int}
    @test dict == Dict("a"=>2, "b"=>1)
    
    path = string(tempname(), ".jld")
    dict = Dict("a" => [1,2.], "b" => Float64[])
    d2 = DiskBackedDict(path, dict)
    @test Dict(d2) == dict

    path = string(tempname(), ".jld")
    d3 = DiskBackedDict(path)
    @test d3 isa Associative{String,Any}
end
