output "viewer_request_function" {
  description = "Viewer request function details"
  value = {
    arn           = module.viewer_request_function.function_arn
    qualified_arn = module.viewer_request_function.qualified_arn
    version       = module.viewer_request_function.version
  }
}


output "origin_response_function" {
  description = "Origin response function details"
  value = {
    arn           = module.origin_response_function.function_arn
    qualified_arn = module.origin_response_function.qualified_arn
    version       = module.origin_response_function.version
  }
}

output "github_actions_role" {
  description = "GitHub Actions IAM role details"
  value = {
    role_arn          = module.github_actions_role.role_arn
    role_name         = module.github_actions_role.role_name
    oidc_provider_arn = module.github_actions_role.oidc_provider_arn
  }
}

output "s3_origin_bucket" {
  description = "S3 origin bucket details"
  value = {
    bucket_id                   = module.s3_origin_bucket.bucket_id
    bucket_arn                  = module.s3_origin_bucket.bucket_arn
    bucket_domain_name          = module.s3_origin_bucket.bucket_domain_name
    bucket_regional_domain_name = module.s3_origin_bucket.bucket_regional_domain_name
    origin_access_control_id    = module.s3_origin_bucket.origin_access_control_id
  }
}

output "cloudfront_distribution" {
  description = "CloudFront distribution details"
  value = {
    id                       = aws_cloudfront_distribution.main.id
    arn                      = aws_cloudfront_distribution.main.arn
    domain_name              = aws_cloudfront_distribution.main.domain_name
    hosted_zone_id           = aws_cloudfront_distribution.main.hosted_zone_id
    status                   = aws_cloudfront_distribution.main.status
    cache_policy_id          = aws_cloudfront_cache_policy.optimized.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.custom.id
  }
}
