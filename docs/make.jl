using Gtool3
using Documenter

DocMeta.setdocmeta!(Gtool3, :DocTestSetup, :(using Gtool3); recursive=true)

makedocs(;
    modules=[Gtool3],
    authors="Chihiro Kodama",
    sitename="Gtool3.jl",
    format=Documenter.HTML(;
        canonical="https://kodamail.github.io/Gtool3.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/kodamail/Gtool3.jl",
    devbranch="main",
)
