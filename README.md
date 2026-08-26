# Gtool3.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://kodamail.github.io/Gtool3.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://kodamail.github.io/Gtool3.jl/dev/)
[![Build Status](https://github.com/kodamail/Gtool3.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/kodamail/Gtool3.jl/actions/workflows/CI.yml?query=branch%3Amain)


## Usage
```julia
Pkg.add(url="https://github.com/kodamail/Gtool3.jl")
using Gtool3

r = read_gt3("var.gt3")

headerinfo(r[1])
r[1].data
```
