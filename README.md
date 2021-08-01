# VersionsJSONUtil

[![CI](https://github.com/JuliaLang/VersionsJSONUtil.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaLang/VersionsJSONUtil.jl/actions/workflows/CI.yml)

More info: https://github.com/JuliaLang/julia/issues/33817

## Triggering a rebuild

To trigger a rebuild of the `versions.json` file and to upload it to S3, you need to manually trigger the `CI` workflow in this repo.
You can either trigger it through the GitHub UI or via an authenticated HTTP request.

### GitHub's UI

TODO

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
**Consider using a [machine user](https://docs.github.com/en/developers/overview/managing-deploy-keys#machine-users) solely for this purpose.**

For more info, check the [GitHub Docs](https://docs.github.com/en/rest/reference/actions#create-a-workflow-dispatch-event).

## Adding a new platform
