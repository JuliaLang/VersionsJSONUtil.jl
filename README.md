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

- [abelsiqueira/jill](https://github.com/abelsiqueira/jill): A Julia installer written in Bash.
- [johnnychen94/jill.py](https://github.com/johnnychen94/jill.py): A Julia installer written in Python.
- [julia-actions/setup-julia](https://github.com/julia-actions/setup-julia): Installs Julia in GitHub Actions CI jobs.
- [JuliaLang/Juliaup](https://github.com/JuliaLang/juliaup): Julia installer and version manager[^2]

[^2]: This also means that every tool that uses Juliaup is thus also downstream of `versions.json`.

## Devdocs

See [`./devdocs/README.md`](./devdocs/README.md).

## Background and motivation

This issue provides background info that explains the motivation: https://github.com/JuliaLang/julia/issues/33817
