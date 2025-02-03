# VersionsJSONUtil

More info: https://github.com/JuliaLang/julia/issues/33817

## Triggering a rebuild

To trigger a rebuild of the `versions.json` file and to upload it to S3, you need to manually trigger the `CI` workflow in this repo.
You can either trigger it through the GitHub UI or via an authenticated HTTP request.

### Setting the LTS field

Julia LTS versions are set via the `JULIA_LTS` variable in the [CI workflow](.github/workflows/CI.yml).

### GitHub's UI

![grafik](https://user-images.githubusercontent.com/20866761/127783220-fd8167db-5051-4a18-b70a-ea42085a7cb5.png)

### HTTP request

```bash
curl \
  -u USERNAME:PERSONAL_ACCESS_TOKEN \
  -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/JuliaLang/VersionsJSONUtil.jl/actions/workflows/CI.yml/dispatches \
  -d '{"ref":"main"}'
```

Replace `USERNAME` with your GitHub username, and `PERSONAL_ACCESS_TOKEN` with a [personal access token](https://docs.github.com/en/github/authenticating-to-github/keeping-your-account-and-data-secure/creating-a-personal-access-token) with `repo` scope.

**Note that it is not possible to restrict personal access tokens to individual repos.**
**The token will have access to all repositories your GH account has access to.**
**Consider using a [machine user](https://docs.github.com/en/developers/overview/managing-deploy-keys#machine-users) solely created for this purpose.**

For more info, check the [GitHub Docs](https://docs.github.com/en/rest/reference/actions#create-a-workflow-dispatch-event).

## Adding a new platform

1. Add the version that introduces the platform to the `download_urls` dictionary in [`test/runtests.jl`](test/runtests.jl).
2. Add the platform the `julia_platforms` in [`src/VersionsJSONUtil.jl`](src/VersionsJSONUtil.jl).
3. Add any missing methods such as `tar_os` until all tests for the new platform pass.

### Example

For an example, adding the M1 MacOS binaries takes the following additions:

#### `test/runtests.jl`

```julia
const download_urls = Dict(
    v"1.7.0-beta3" => Dict(
        MacOS(:aarch64) =>              "https://julialang-s3.julialang.org/bin/mac/aarch64/1.7/julia-1.7.0-beta3-macaarch64.dmg",
    ),
    ...
)
```

#### `src/VersionsJSONUtil.jl`

```julia
julia_platforms = [
    ...
    MacOS(:aarch64),
    ...
]
```

and changing `tar_os(p::MacOS)` from

```julia
tar_os(p::MacOS) = "mac$(wordsize(p))"
```

to

```julia
function tar_os(p::MacOS)
    if arch(p) == :aarch64
        return "macaarch$(wordsize(p))"
    else
        return "mac$(wordsize(p))"
    end
end
```

## JSON Schema

[`schema.json`](schema.json) contains a [JSON Schema](https://json-schema.org/) for the `versions.json` file.

It can be used to validate the versions file or to [generate code](https://json-schema.org/implementations.html) from the schema.

## Tools using version.json

This is an (incomplete) list of tools that make use of the published `versions.json`.
If you maintain such a tool, consider adding info about it in this list.
This allows us to verify if changes might affect downstream tooling.

- [julia-actions/setup-julia](https://github.com/julia-actions/setup-julia)
- [johnnychen94/jill.py](https://github.com/johnnychen94/jill.py): a Julia installer written in Python
- [abelsiqueira/jill](https://github.com/abelsiqueira/jill): a Julia installer

## Third Party Notice

The [schema](schema.json) was generated with [quicktype.io](https://app.quicktype.io/#l=schema).
