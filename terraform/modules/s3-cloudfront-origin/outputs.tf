output "bucket_id" {
  description = "The name of the bucket"
  value       = aws_s3_bucket.origin.id
}

output "bucket_arn" {
  description = "The ARN of the bucket"
  value       = aws_s3_bucket.origin.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name (for CloudFront origin)"
  value       = aws_s3_bucket.origin.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name"
  value       = aws_s3_bucket.origin.bucket_regional_domain_name
}

output "origin_access_control_id" {
  description = "The ID of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.this.id
}

output "origin_access_control_arn" {
  description = "The ARN of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.this.id
}
