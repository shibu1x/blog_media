variable "function_name" {
  description = "Name of the Lambda@Edge function"
  type        = string
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs22.x"
}

variable "handler" {
  description = "Lambda function handler"
  type        = string
  default     = "index.handler"
}

variable "timeout" {
  description = "Function timeout in seconds (max 30 for Lambda@Edge)"
  type        = number
  default     = 5
}

variable "memory_size" {
  description = "Memory allocated to the function in MB (max 10240 for Lambda@Edge)"
  type        = number
  default     = 128
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Create a minimal empty Lambda function code
data "archive_file" "empty_lambda" {
  type        = "zip"
  output_path = "${path.module}/builds/${var.function_name}-empty.zip"

  source {
    content  = "exports.handler = async (event) => { return event.Records[0].cf.request; };"
    filename = "index.js"
  }
}

# IAM role for Lambda@Edge
resource "aws_iam_role" "lambda_edge_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = var.tags
}

# Attach basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_edge_policy" {
  role       = aws_iam_role.lambda_edge_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function
resource "aws_lambda_function" "function" {
  # Lambda@Edge functions must be created in us-east-1
  provider = aws.us-east-1

  filename         = data.archive_file.empty_lambda.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_edge_role.arn
  handler          = var.handler
  source_code_hash = data.archive_file.empty_lambda.output_base64sha256
  runtime          = var.runtime
  timeout          = var.timeout
  memory_size      = var.memory_size
  publish          = true # Must be true for Lambda@Edge

  tags = var.tags

  # Ignore changes to filename to allow manual updates
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash
    ]
  }
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.function.arn
}

output "qualified_arn" {
  description = "Qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.function.qualified_arn
}

output "version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.function.version
}

output "role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.lambda_edge_role.arn
}
