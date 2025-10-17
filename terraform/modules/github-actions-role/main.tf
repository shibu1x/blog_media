variable "github_repo" {
  description = "GitHub repository in the format 'owner/repo-name'"
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role"
  type        = string
}

variable "lambda_function_arns" {
  description = "List of Lambda function ARNs that GitHub Actions can update"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# GitHub Actions OIDC Provider (must exist in AWS account)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Policy for Lambda function updates
resource "aws_iam_role_policy" "lambda_update" {
  name = "lambda-update-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:PublishVersion",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:DeleteFunction"
        ]
        Resource = var.lambda_function_arns
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:ListVersionsByFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for CloudFront management
resource "aws_iam_role_policy" "cloudfront_management" {
  count = var.enable_cloudfront_management ? 1 : 0

  name = "cloudfront-management-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:ListDistributions",
          "cloudfront:UpdateDistribution"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations"
        ]
        Resource = "*"
      }
    ]
  })
}

variable "enable_cloudfront_management" {
  description = "Enable CloudFront management permissions (update distribution, invalidation)"
  type        = bool
  default     = false
}

output "role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = data.aws_iam_openid_connect_provider.github.arn
}
