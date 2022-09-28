####################################################
# OpenID Connect Provider
####################################################
resource "aws_iam_openid_connect_provider" "github_oidc" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

####################################################
# IAM Role/Policy
####################################################

data "aws_iam_policy_document" "principal_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_oidc.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:hiropppp/bff:*"]
    }
  }
}

resource "aws_iam_role" "oidc_iam_role" {
  name               = "GitHubActionsOIDCRole"
  assume_role_policy = data.aws_iam_policy_document.principal_policy.json
}


data "aws_iam_policy_document" "allowed_action_policy" {
  statement {
    effect = "Allow"
    actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateServicePrimaryTaskSet",
        "ecs:DescribeServices",
        "ecs:UpdateService",
        "iam:PassRole",
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "oidc_iam_policy" {
  name   = "GitHubActionsOIDCPolicy"
  policy = data.aws_iam_policy_document.allowed_action_policy.json
}

resource "aws_iam_role_policy_attachment" "oidc_iam_role_policy_attachment" {
  role       = aws_iam_role.oidc_iam_role.name
  policy_arn = aws_iam_policy.oidc_iam_policy.arn
}
