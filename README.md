# VersionsJSONUtil: Generate `versions.json` files that contain the list of Julia versions

S3 URL:
- v1: https://julialang-s3.julialang.org/bin/versions.json
- v2: [coming soon][^1]

[^1]: v2 is not available yet. When it becomes available, the S3 URL will *probably* be `https://julialang-s3.julialang.org/bin/versions.v2.json`

## JSON Schema

[`schema.json`](schema.json) contains a [JSON Schema](https://json-schema.org/) for the `versions.json` file.

It can be used to validate the versions file or to [generate code](https://json-schema.org/implementations.html) from the schema.

## Downstream tools using `versions.json`

This is a (not necessarily complete) list of known tools that make use of `versions.json`.
If you maintain such a tool, please make a PR to add it to this list.
This allows us to check if changes might break downstream tooling.

Installers and version managers:

- [abelsiqueira/jill](https://github.com/abelsiqueira/jill) ([usage](https://github.com/abelsiqueira/jill/blob/6dec7984c4fa9af541ae92c1fced7a902d8df2c7/jill.sh#L67)): A Julia installer written in Bash.
- [johnnychen94/jill.py](https://github.com/johnnychen94/jill.py) ([usage](https://github.com/johnnychen94/jill.py/blob/53abfce0a514dec8e74be54f142653ef94418ff4/jill/utils/defaults.py#L33)): A Julia installer written in Python.
- [JuliaLang/Juliaup](https://github.com/JuliaLang/juliaup) ([usage](https://github.com/JuliaLang/juliaup/blob/9557a1c36e644c4d633fca9d5d426e8797bb4ee4/scripts/versiondb/updateversiondb.jl#L266)): Julia installer and version manager[^2].
- [jdx/mise](https://github.com/jdx/mise) ([usage](https://github.com/jdx/mise/blob/105274d77b657bfbab4dd367fe42cfddb48ecd67/registry/julia.toml#L10)): Manage multiple versions of various programming languages.

CI tools:

- [julia-actions/setup-julia](https://github.com/julia-actions/setup-julia) ([usage](https://github.com/julia-actions/setup-julia/blob/4a12c5f801ca5ef0458bba44687563ef276522dd/src/installer.ts#L59)): Installs Julia in GitHub Actions CI jobs.
- [JuliaCI/julia-buildkite-plugin](https://github.com/JuliaCI/julia-buildkite-plugin) ([usage](https://github.com/JuliaCI/julia-buildkite-plugin/blob/c23bdcdef057ef4f54f9da0dfd0eb48e04a5fe09/hooks/expand-major-only.py#L51)): Buildkite plugin to install Julia for use in a pipeline. This plugin is used in Base Julia CI.
- [actions/runner-images](https://github.com/actions/runner-images) ([usage](https://github.com/actions/runner-images/blob/a8a3c8258504963ec70a688d16079d5c43622410/images/ubuntu/scripts/build/install-julia.sh#L11)): Ships Julia in runner images.

Packaging:

- [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) ([usage](https://github.com/Homebrew/homebrew-cask/blob/4f59334cb085c0c2e99f5cfd6915b3cb637d05f6/Casks/j/julia-app.rb#L15)): Uses `versions.json` for the `julia-app` Cask in Homebrew.
- [JuliaCI/julia-snap](https://github.com/JuliaCI/julia-snap) ([usage](https://github.com/JuliaCI/julia-snap/blob/cfef2493c9a62888cbc14728c8385fe075554f9d/scripts/create-snapcraft-yaml.jl#L13)): Snap setup for Julia.

Other:

- [JuliaCI/PkgEval.jl](https://github.com/JuliaCI/PkgEval.jl) ([usage](https://github.com/JuliaCI/PkgEval.jl/blob/b3eb65eebfc604cbb576e56eb8aea621e81afecc/src/julia.jl#L6)): A package to test one or more Julia versions against the Julia package ecosystem.
- [JuliaLang/www.julialang.org](https://github.com/JuliaLang/www.julialang.org) ([usage](https://github.com/JuliaLang/www.julialang.org/blob/cbfac612a7bd0c8d90dad2a0f882bc152074dc7e/downloads/oldreleases.jl#L16)): The Julia website repo (uses `versions.json` to auto-generate the list of Julia releases).
- [StefanKarpinski/Resolver.jl](https://github.com/StefanKarpinski/Resolver.jl) ([usage](https://github.com/StefanKarpinski/Resolver.jl/blob/9353ca543fb83012cc8fb9fb427febbc01b34ccf/bin/Registries.jl#L16)): Next generation of Pkg resolver.

[^2]: This means that every tool that uses Juliaup is indirectly downstream of `versions.json`.

## Devdocs

See [`./devdocs/README.md`](./devdocs/README.md).

## Background and motivation

This issue provides background info that explains the motivation: https://github.com/JuliaLang/julia/issues/33817
