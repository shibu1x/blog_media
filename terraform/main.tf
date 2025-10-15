terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "lambda-edge/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Lambda@Edge functions must be in us-east-1
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Viewer Request Function
module "viewer_request_function" {
  source = "./modules/lambda-edge"

  providers = {
    aws.us-east-1 = aws.us-east-1
  }

  function_name = "${var.project_name}-viewer-request-${var.environment}"
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  timeout       = 5
  memory_size   = 128

  tags = {
    FunctionType = "viewer-request"
  }
}


# Origin Response Function
module "origin_response_function" {
  source = "./modules/lambda-edge"

  providers = {
    aws.us-east-1 = aws.us-east-1
  }

  function_name = "${var.project_name}-origin-response-${var.environment}"
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  timeout       = 5
  memory_size   = 128

  tags = {
    FunctionType = "origin-response"
  }
}

# GitHub Actions IAM Role
module "github_actions_role" {
  source = "./modules/github-actions-role"

  github_org  = var.github_org
  github_repo = var.github_repo
  role_name   = "${var.project_name}-github-actions-${var.environment}"

  lambda_function_arns = [
    module.viewer_request_function.function_arn,
    module.origin_response_function.function_arn,
    "${module.viewer_request_function.function_arn}:*",
    "${module.origin_response_function.function_arn}:*"
  ]

  enable_cloudfront_invalidation = false

  tags = {
    Purpose = "GitHub Actions Deployment"
  }
}

# Example CloudFront distribution (optional - uncomment if needed)
# resource "aws_cloudfront_distribution" "main" {
#   enabled = true
#   comment = "${var.project_name} distribution"
#
#   origin {
#     domain_name = "your-origin.example.com"
#     origin_id   = "primary-origin"
#   }
#
#   default_cache_behavior {
#     target_origin_id       = "primary-origin"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["GET", "HEAD", "OPTIONS"]
#     cached_methods         = ["GET", "HEAD"]
#
#     forwarded_values {
#       query_string = true
#       cookies {
#         forward = "none"
#       }
#     }
#
#     # Attach Lambda@Edge functions
#     lambda_function_association {
#       event_type   = "viewer-request"
#       lambda_arn   = module.viewer_request_function.qualified_arn
#       include_body = false
#     }
#
#     lambda_function_association {
#       event_type   = "origin-response"
#       lambda_arn   = module.origin_response_function.qualified_arn
#       include_body = false
#     }
#   }
#
#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }
#
#   viewer_certificate {
#     cloudfront_default_certificate = true
#   }
# }
