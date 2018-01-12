module TestUtils
export MyString, MyInt, MyPair, MyContainer
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

end
