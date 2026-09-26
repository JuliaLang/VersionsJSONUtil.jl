# VersionsJSONUtil: Generate `versions.json` files that contain the list of Julia versions

| File             | Version | URL                                                   | Schema                                                       |
| ---------------- | ------- | ----------------------------------------------------- | ------------------------------------------------------------ |
| `versions.json`  | v1      | https://julialang-s3.julialang.org/bin/versions.json  | https://julialang-s3.julialang.org/bin/versions-schema.json  |
| `nightlies.json` | v1      | https://julialang-s3.julialang.org/bin/nightlies.json | https://julialang-s3.julialang.org/bin/nightlies-schema.json |

Table of contents:
1. [`versions.json`](#1-versionsjson)
2. [`nightlies.json`](#2-nightliesjson)
3. [Downstream consumers](#3-downstream-consumers)
4. [Devdocs](#4-devdocs)

## 1. `versions.json`

### `versions.json`: public API

TODO: Write this section.

### `versions.json`: experimental API

[none]

## 2. `nightlies.json`

### `nightlies.json`: public API

None. All of `nightlies.json` is currently experimental

### `nightlies.json`: experimental API

> [!WARNING]
> Everything in this section may be changed in breaking ways (or removed entirely).

`nightlies.json` is the counterpart of `versions.json` for in-development builds. Its top-level keys are the
nightly channels in juliaup's vocabulary: `nightly` (builds of `master`) and `x.y-nightly` (the latest build of the
x.y release series, i.e. of `release-x.y` once that branch exists). Each channel has a `files` list describing the
standard builds with the same keys as `versions.json` (`triplet`, `os`, `arch`, `kind`, `extension`, `url`), with two
differences:

- There is no `version`, `size`, `sha256` or tree hash: every URL is a `julia-latest-*` file that is overwritten
  after each successful build on its branch, so nothing content-specific can be recorded. Consumers should
  track changes through the server's `ETag` / `Last-Modified` headers (as juliaup does). The detached signature,
  when one is published, is referenced by URL in `asc-url` rather than inlined.
- Build variants of the standard binaries are listed in a separate `variants` list (absent when there are none),
  so that tools selecting a file from `files` by platform never pick up a variant by accident. Its entries have the
  keys of `files` plus `variants`, the names of the variants applied to that build: `opt` (the PGO+LTO+BOLT
  optimized build), `assert` (Julia and LLVM assertions enabled) and `nogpl` (no GPL-licensed dependencies).
  Every build currently has a single variant; the list leaves room for combinations.

[`schema-nightlies.json`](schema-nightlies.json) contains its JSON Schema. See the
[devdocs](./devdocs/README.md#nightliesjson) for how the file is generated.

## 3. Downstream consumers

This is a (not necessarily complete) list of known tools that make use of `versions.json` and `nightlies.json`
If you maintain such a tool, please make a PR to add it to this list.
This allows us to check if changes might break downstream tooling.

- [abelsiqueira/jill](https://github.com/abelsiqueira/jill): A Julia installer written in Bash.
- [johnnychen94/jill.py](https://github.com/johnnychen94/jill.py): A Julia installer written in Python.
- [nhz2/install-julia-linux](https://github.com/nhz2/install-julia-linux): A Julia installer written in Shell.
- [julia-actions/setup-julia](https://github.com/julia-actions/setup-julia): Installs Julia in GitHub Actions CI jobs.
- [JuliaCI/julia-buildkite-plugin](https://github.com/JuliaCI/julia-buildkite-plugin): Buildkite plugin to install Julia for use in a pipeline. This plugin is used in Base Julia CI.
- [JuliaCI/julia-snap](https://github.com/JuliaCI/julia-snap): Snap setup for Julia.
- [JuliaCI/PkgEval.jl](https://github.com/JuliaCI/PkgEval.jl): A package to test one or more Julia versions against the Julia package ecosystem.
- [JuliaLang/Juliaup](https://github.com/JuliaLang/juliaup): Julia installer and version manager[^1].
- [JuliaLang/www.julialang.org](https://github.com/JuliaLang/www.julialang.org): The Julia website repo (uses `versions.json` to auto-generate the list of Julia releases).

[^1]: This means that every tool that uses Juliaup is indirectly downstream of `versions.json`.

## 4. Devdocs

See [`./devdocs/README.md`](./devdocs/README.md).

This issue provides background info that explains the motivation: https://github.com/JuliaLang/julia/issues/33817

## END END END


## `nightlies.json`



**`nightlies.json` is experimental: its format may still change in breaking ways.**



## Downstream tools using `versions.json`




