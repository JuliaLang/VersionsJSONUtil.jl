# IAM roles assumed by this repository's GitHub Actions workflows through GitHub's OIDC
# provider (see devdocs/README.md). The provider itself already exists in the account and
# is shared with other repositories, so it is only looked up here, not managed.

locals {
  repo   = "JuliaLang/VersionsJSONUtil.jl"
  bucket = "julialang2"
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ------------------------------------------------------------------------------------------
# Read-only role: the full-build-regular job lists and reads bin/ while building
# versions.json. It runs on push to main, on merge-queue refs, and on workflow_dispatch
# (restricted to main in CI.yml); pull_request runs of this repo are allowed too, fork PRs
# can never get an OIDC token.

data "aws_iam_policy_document" "readonly_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.repo}:ref:refs/heads/main",
        "repo:${local.repo}:ref:refs/heads/gh-readonly-queue/*",
        "repo:${local.repo}:pull_request",
      ]
    }
  }
}

data "aws_iam_policy_document" "readonly" {
  statement {
    sid       = "ListBinPrefix"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["bin/*"]
    }
  }
  statement {
    sid       = "ReadBinaries"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.bucket}/bin/*"]
  }
}

resource "aws_iam_role" "readonly" {
  name               = "VersionsJSONUtil-readonly"
  description        = "Read access to bin/ in the julialang2 bucket for JuliaLang/VersionsJSONUtil.jl CI"
  assume_role_policy = data.aws_iam_policy_document.readonly_trust.json
  # A full rebuild runs for hours; matches role-duration-seconds and the job timeout in CI.yml
  max_session_duration = 21600
}

resource "aws_iam_role_policy" "readonly" {
  name   = "s3-read-bin"
  role   = aws_iam_role.readonly.id
  policy = data.aws_iam_policy_document.readonly.json
}

# ------------------------------------------------------------------------------------------
# Deploy role: the upload-*-to-s3 jobs in CI.yml and deploy-schema.yml write exactly the
# four deployed files. Deploys only ever run from main.

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repo}:ref:refs/heads/main"]
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid = "DeployVersionsJSON"
    # PutObjectAcl because the uploads use --acl public-read
    actions = ["s3:PutObject", "s3:PutObjectAcl"]
    resources = [
      for f in ["versions.json", "versions-schema.json", "nightlies.json", "nightlies-schema.json"] :
      "arn:aws:s3:::${local.bucket}/bin/${f}"
    ]
  }
}

resource "aws_iam_role" "deploy" {
  name               = "VersionsJSONUtil-deploy"
  description        = "Deploy versions.json and versions-schema.json for JuliaLang/VersionsJSONUtil.jl CI"
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
}

resource "aws_iam_role_policy" "deploy" {
  name   = "s3-deploy-versions-json"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

output "readonly_role_arn" {
  value = aws_iam_role.readonly.arn
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}
