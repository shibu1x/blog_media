terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key            = "lambda-edge/terraform.tfstate"
    encrypt        = false
    use_lockfile   = true
  }
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

# S3 Bucket for CloudFront Origin (created first)
module "s3_origin_bucket" {
  source = "./modules/s3-cloudfront-origin"

  bucket_name                    = "${var.project_name}-origin-${var.environment}"
  resized_images_expiration_days = 1

  tags = {
    Purpose = "CloudFront Origin Storage"
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
  s3_bucket_arn = module.s3_origin_bucket.bucket_arn
  log_region    = var.aws_region

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
  s3_bucket_arn = module.s3_origin_bucket.bucket_arn
  log_region    = var.aws_region

  tags = {
    FunctionType = "origin-response"
  }
}

# Additional S3 bucket policy to allow Lambda@Edge access
resource "aws_s3_bucket_policy" "lambda_access" {
  bucket = module.s3_origin_bucket.bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${module.s3_origin_bucket.bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      },
      {
        Sid    = "AllowLambdaEdgeWrite"
        Effect = "Allow"
        Principal = {
          AWS = [
            module.viewer_request_function.role_arn,
            module.origin_response_function.role_arn
          ]
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${module.s3_origin_bucket.bucket_arn}/resize/*"
      },
      {
        Sid    = "AllowLambdaEdgeRead"
        Effect = "Allow"
        Principal = {
          AWS = [
            module.viewer_request_function.role_arn,
            module.origin_response_function.role_arn
          ]
        }
        Action = [
          "s3:GetObject"
        ]
        Resource = "${module.s3_origin_bucket.bucket_arn}/origin/*"
      }
    ]
  })
}

# GitHub Actions IAM Role
module "github_actions_role" {
  source = "./modules/github-actions-role"

  github_repo = var.github_repo
  role_name   = "${var.project_name}-github-actions-${var.environment}"

  lambda_function_arns = [
    module.viewer_request_function.function_arn,
    module.origin_response_function.function_arn,
    "${module.viewer_request_function.function_arn}:*",
    "${module.origin_response_function.function_arn}:*"
  ]

  enable_cloudfront_management = true

  tags = {
    Purpose = "GitHub Actions Deployment"
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  enabled              = true
  wait_for_deployment  = false
  price_class          = "PriceClass_200"
  comment              = "${var.project_name} ${var.environment} distribution"

  # S3 Origin with OAC
  origin {
    domain_name              = module.s3_origin_bucket.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = module.s3_origin_bucket.origin_access_control_id
    origin_path              = "/origin"
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = aws_cloudfront_cache_policy.optimized.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.custom.id

    # Attach Lambda@Edge functions
    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = module.viewer_request_function.qualified_arn
      include_body = false
    }

    lambda_function_association {
      event_type   = "origin-response"
      lambda_arn   = module.origin_response_function.qualified_arn
      include_body = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

# Cache Policy for optimized image caching
resource "aws_cloudfront_cache_policy" "optimized" {
  name        = "${var.project_name}-cache-policy-${var.environment}"
  comment     = "Optimized cache policy for image resizing"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept"]
      }
    }

    query_strings_config {
      query_string_behavior = "whitelist"
      query_strings {
        items = ["d"]
      }
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# Origin Request Policy to forward necessary headers
resource "aws_cloudfront_origin_request_policy" "custom" {
  name    = "${var.project_name}-origin-request-policy-${var.environment}"
  comment = "Custom origin request policy for Lambda@Edge"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Accept"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}
