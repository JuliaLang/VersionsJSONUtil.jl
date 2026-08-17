# Devdocs

## Triggering a rebuild

To trigger a rebuild of the `versions.json` file and to upload it to S3, you need to manually trigger the `CI` workflow in this repo.
You can either trigger it through the GitHub UI or via an authenticated HTTP request.

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

## AWS authentication (GitHub OIDC)

The CI jobs that talk to AWS authenticate by assuming per-job IAM roles through GitHub's
OIDC provider, so no long-lived access keys are stored in this repo. Two roles with
different scopes are used; their ARNs are not secret (they are only assumable from this
repo's workflows) and are inlined in the workflow files:

- a **read-only role** (`arn:aws:iam::873569884612:role/VersionsJSONUtil-readonly`) for
  the `full-test` job, which lists the `julialang2` bucket while building `versions.json`;
- a **deploy role** (`arn:aws:iam::873569884612:role/VersionsJSONUtil-deploy`) for the
  `upload-to-s3` and `deploy-schema` jobs, which write the two deployed files.

The GitHub OIDC identity provider (`token.actions.githubusercontent.com`) already exists
in the AWS account; the roles below only reference it.

A note on pull requests: the read-only role is also assumable from `pull_request` runs of
this repo (their tokens carry the `sub` `repo:JuliaLang/VersionsJSONUtil.jl:pull_request`),
but only for PRs from branches of this repo — GitHub refuses `id-token: write` to
fork-triggered `pull_request` runs entirely, so fork PRs can never assume any role and
fall back to unsigned requests (which the public bucket accepts). The deploy role is not
assumable from PRs at all: its trust matches only `refs/heads/main`, and tokens minted for
`pull_request` runs carry a `sub` ending in `:pull_request` instead of a branch ref, so
even a future workflow mistake (like granting `id-token: write` to a PR job) could not
deploy from a PR.

### Role documents

The trust and permissions policy documents are checked in under [`devdocs/aws/`](aws/):

- [`VersionsJSONUtil-readonly.trust.json`](aws/VersionsJSONUtil-readonly.trust.json) —
  matches `refs/heads/main` (push and `workflow_dispatch`, which `full-test` restricts to
  `main` with a matching `if:` guard), merge-queue refs
  (`refs/heads/gh-readonly-queue/...`), and `pull_request` runs as described above.
- [`VersionsJSONUtil-readonly.policy.json`](aws/VersionsJSONUtil-readonly.policy.json) —
  listing and reading the `bin/` prefix: the build lists it to decide what is missing and
  downloads the binaries through authenticated requests (`s3:GetObject`), so neither part
  is subject to anonymous rate limits.
- [`VersionsJSONUtil-deploy.trust.json`](aws/VersionsJSONUtil-deploy.trust.json) —
  deploys only ever run from `main`, so this one matches exactly that ref
  (`StringEquals`, no wildcard needed).
- [`VersionsJSONUtil-deploy.policy.json`](aws/VersionsJSONUtil-deploy.policy.json) —
  writing exactly the two deployed files (`s3:PutObjectAcl` is required because the
  uploads use `--acl public-read`).

### Creating the roles

From the repository root, run:

```bash
aws iam create-role \
  --role-name VersionsJSONUtil-readonly \
  --description "Read access to bin/ in the julialang2 bucket for JuliaLang/VersionsJSONUtil.jl CI" \
  --assume-role-policy-document file://devdocs/aws/VersionsJSONUtil-readonly.trust.json \
  --max-session-duration 21600

aws iam put-role-policy \
  --role-name VersionsJSONUtil-readonly \
  --policy-name s3-read-bin \
  --policy-document file://devdocs/aws/VersionsJSONUtil-readonly.policy.json

aws iam create-role \
  --role-name VersionsJSONUtil-deploy \
  --description "Deploy versions.json and versions-schema.json for JuliaLang/VersionsJSONUtil.jl CI" \
  --assume-role-policy-document file://devdocs/aws/VersionsJSONUtil-deploy.trust.json

aws iam put-role-policy \
  --role-name VersionsJSONUtil-deploy \
  --policy-name s3-deploy-versions-json \
  --policy-document file://devdocs/aws/VersionsJSONUtil-deploy.policy.json
```

`--max-session-duration 21600` (6 h) on the read-only role matches the `full-test` job
timeout: the job requests a 6 h session (`role-duration-seconds` in `CI.yml`) because a
full rebuild runs for hours and the credentials must outlive it (the IAM default of 1 h
would expire mid-build). The deploy jobs finish in minutes, so the deploy role keeps the
default 1 h.

To change a permissions policy later, re-run the corresponding `aws iam put-role-policy`
command (it replaces the named inline policy). For trust policies, use
`aws iam update-assume-role-policy --role-name <name> --policy-document file://<file>`.

Locally, `VersionsJSONUtil.main` sends unsigned requests when no AWS credentials are in
the environment, which the public bucket accepts.
