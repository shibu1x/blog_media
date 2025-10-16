# S3 Bucket for CloudFront Origin
resource "aws_s3_bucket" "origin" {
  bucket = var.bucket_name

  tags = var.tags
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "origin" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning disabled
resource "aws_s3_bucket_versioning" "origin" {
  bucket = aws_s3_bucket.origin.id

  versioning_configuration {
    status = "Disabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "origin" {
  bucket = aws_s3_bucket.origin.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle rules for resized images (mandatory)
resource "aws_s3_bucket_lifecycle_configuration" "origin" {
  bucket = aws_s3_bucket.origin.id

  # Clean up old resized images
  rule {
    id     = "cleanup-resized-images"
    status = "Enabled"

    filter {
      prefix = "resize/"
    }

    expiration {
      days = var.resized_images_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  # Clean up incomplete multipart uploads
  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.bucket_name}-oac"
  description                       = "OAC for ${var.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Note: Bucket policy is managed in main.tf to avoid circular dependencies
# with Lambda@Edge function roles

# CORS configuration (optional)
resource "aws_s3_bucket_cors_configuration" "origin" {
  count  = var.enable_cors ? 1 : 0
  bucket = aws_s3_bucket.origin.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
