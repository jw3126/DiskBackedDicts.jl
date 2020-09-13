using DiskBackedDicts
using Documenter

makedocs(;
    modules=[DiskBackedDicts],
    authors="Jan Weidner <jw3126@gmail.com> and contributors",
    repo="https://github.com/jw3126/DiskBackedDicts.jl/blob/{commit}{path}#L{line}",
    sitename="DiskBackedDicts.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://jw3126.github.io/DiskBackedDicts.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/jw3126/DiskBackedDicts.jl",
)
