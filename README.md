# VersionsJSONUtil: Generate `versions.json` files that contain the list of Julia versions

## Table of contents

1. [`versions.json`](#1-docs-for-versionsjson)
2. [`nightlies.json`](#2-docs-for-nightliesjson)
3. [Downstream consumers](#3-downstream-consumers)
4. [Devdocs](#4-devdocs)

## 1. Docs for `versions.json`

| File             | Version | Canonical URL                                         | Schema                                                       |
| ---------------- | ------- | ----------------------------------------------------- | ------------------------------------------------------------ |
| `versions.json`  | v1      | https://julialang-s3.julialang.org/bin/versions.json  | https://julialang-s3.julialang.org/bin/versions-schema.json  |

### 1.1. `versions.json`: public API

[This section forthcoming]

### 1.2. `versions.json`: experimental API

> [!WARNING]
> The `variants` list and its contents are experimental and are not stable. In the future, they may be change in breaking ways (or removed entirely).

From Julia 1.14, a version may also have a `variants` list next to `files`, which contains the build variants for that Julia version.

A `variants` entry has all the same keys as a `files` entry, and additionally contains a key named `variants`, which is a list containing the names of the variants applied to that build:
- `opt` (the PGO+LTO+BOLT optimized build)
- `assert` (Julia and LLVM assertions enabled)
- `nogpl` (no GPL-licensed dependencies).

## 2. Docs for `nightlies.json`

> [!WARNING]
> All of `nightlies.json` is currently experimental. Its format may still change in breaking ways (or be removed entirely).

| File             | Version | Canonical URL                                         | Schema                                                       |
| ---------------- | ------- | ----------------------------------------------------- | ------------------------------------------------------------ |
| `nightlies.json` | v1      | https://julialang-s3.julialang.org/bin/nightlies.json | https://julialang-s3.julialang.org/bin/nightlies-schema.json |

### 2.1. `nightlies.json`: public API

None. All of `nightlies.json` is currently experimental. It may still change in breaking ways (or be removed entirely).

### 2.2. `nightlies.json`: experimental API

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

## 3. Downstream consumers

This is a (not necessarily complete) list of known tools that make use of `versions.json`
and/or `nightlies.json`.
If you maintain such a tool, please make a PR to add it to this list.
This allows us to check if changes might break downstream tooling.

Installers and version managers:

- [abelsiqueira/jill](https://github.com/abelsiqueira/jill) ([usage](https://github.com/abelsiqueira/jill/blob/6dec7984c4fa9af541ae92c1fced7a902d8df2c7/jill.sh#L67)): A Julia installer written in Bash.
- [johnnychen94/jill.py](https://github.com/johnnychen94/jill.py) ([usage](https://github.com/johnnychen94/jill.py/blob/53abfce0a514dec8e74be54f142653ef94418ff4/jill/utils/defaults.py#L33)): A Julia installer written in Python.
- [JuliaLang/Juliaup](https://github.com/JuliaLang/juliaup) ([usage](https://github.com/JuliaLang/juliaup/blob/9557a1c36e644c4d633fca9d5d426e8797bb4ee4/scripts/versiondb/updateversiondb.jl#L266)): Julia installer and version manager.
- [jdx/mise](https://github.com/jdx/mise) ([usage](https://github.com/jdx/mise/blob/105274d77b657bfbab4dd367fe42cfddb48ecd67/registry/julia.toml#L10)): Manage multiple versions of various programming languages.
- [nhz2/install-julia-linux](https://github.com/nhz2/install-julia-linux) ([usage](https://github.com/nhz2/install-julia-linux/blob/6f8ebc7c585b2fd996201984d6bff948e17bb146/src/install-julia.sh#L510)): A Julia installer written in Shell.

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

## 4. Devdocs

See [`./devdocs/README.md`](./devdocs/README.md).
