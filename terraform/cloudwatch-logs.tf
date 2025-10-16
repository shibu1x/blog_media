# CloudWatch Log Groups for Lambda@Edge
# Lambda@Edge logs are restricted to ap-northeast-1 only via IAM policy
# This prevents automatic log group creation in other regions

resource "aws_cloudwatch_log_group" "lambda_edge_viewer_request" {
  # Use main provider (ap-northeast-1)
  name              = "/aws/lambda/us-east-1.${module.viewer_request_function.function_name}"
  retention_in_days = 1

  tags = {
    Environment  = var.environment
    FunctionType = "lambda-edge-viewer-request"
  }
}

resource "aws_cloudwatch_log_group" "lambda_edge_origin_response" {
  # Use main provider (ap-northeast-1)
  name              = "/aws/lambda/us-east-1.${module.origin_response_function.function_name}"
  retention_in_days = 1

  tags = {
    Environment  = var.environment
    FunctionType = "lambda-edge-origin-response"
  }
}
