locals {
  # Format parameters into usable values if needed
  thumbprint     = data.aws_ssm_parameter.thumbprint.value
  environments   = split(",", replace(data.aws_ssm_parameter.environment.value, " ", ""))
  repositories   = split(",", replace(data.aws_ssm_parameter.github_repos.value, " ", ""))
  plan_policies  = split(",", replace(data.aws_ssm_parameter.policies.value, " ", ""))
  apply_policies = split(",", replace(data.aws_ssm_parameter.policies.value, " ", ""))

}

# Data 
data "aws_ssm_parameter" "github_repos" {
  name = "/aft/account-request/custom-fields/github/oidc/repositories"
}

data "aws_ssm_parameter" "environments" {
  name = "/aft/account-request/custom-fields/github/oidc/environments"
}

data "aws_ssm_parameter" "plan_policy" {
  name = "/aft/account-request/custom-fields/github/oidc/policies/plan"
}
data "aws_ssm_parameter" "apply_policy" {
  name = "/aft/account-request/custom-fields/github/oidc/policies/apply"
}

data "aws_ssm_parameter" "thumbprint" {
  name = "/aft/account-request/custom-fields/github/oidc/thumbprint"
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list = [
    "sts.amazonaws.com",
  ]
  thumbprint_list = [ local.thumbprint ]
  url             = "https://token.actions.githubusercontent.com"
  # tags            = var.tags
}

resource "aws_iam_role" "terraform_plan" {
  name                 = "github-role-plan"
  description          = "Role created by AFT for Github OIDC Connector"
  max_session_duration = 60
  assume_role_policy   = data.aws_iam_policy_document.this.json
  # tags                 = var.tags
  # path                  = var.iam_role_path
  # permissions_boundary  = var.iam_role_permissions_boundary
  depends_on = [aws_iam_openid_connect_provider.this]

  tags = {
    Repositories = join(",", local.repositories)
    Environment  = each.key
  }
}

resource "aws_iam_role_policy_attachment" "attach_plan_policies" {
  for_each = toset(local.plan_policies)

  policy_arn = each.key
  role       = aws_iam_role.terraform_plan.name

  depends_on = [aws_iam_role.terraform_plan]
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    # Token must be from approved repositories
    condition {
      test   = "StringLike"
      values = [ for repo in local.repositories : "repo:${repo}:*" ]
      variable = "token.actions.githubusercontent.com:sub"
    }

    # Token must be for AWS sts
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Token must be for the correct environment
    condition {
      test     = "StringEquals"
      values   = [ for env in local.environments : env ]
      variable = "token.actions.githubusercontent.com:environment"
    }

    principals {
      identifiers = aws_iam_openid_connect_provider.this.arn
      type        = "Federated"
    }
  }
}