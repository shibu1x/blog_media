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
