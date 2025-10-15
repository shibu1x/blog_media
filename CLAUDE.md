# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Lambda@Edge image optimization system that dynamically resizes images at CloudFront edge locations. The infrastructure is managed with Terraform and deployed via GitHub Actions using OIDC authentication.

### Key Architecture

1. **Viewer Request Function** (`lambda-functions/viewer-request/`): Intercepts CloudFront requests and rewrites URIs based on query parameters. Parses `?d=WxH` dimension parameter and detects WebP support from Accept headers to construct optimized paths like `/resize/{path}/{width}x{height}/{format}/{filename}`.

2. **Origin Response Function** (`lambda-functions/origin-response/`): Handles 404/403 responses for missing resized images. Fetches original from S3, resizes using Sharp library, uploads result to S3 (fire-and-forget), and returns base64-encoded image immediately. Uses pattern `origin/{subpath}/{filename}` for source images.

3. **Terraform Module Structure**: Two reusable modules in `terraform/modules/`:
   - `lambda-edge`: Creates Lambda function with empty placeholder code (uses lifecycle ignore_changes for filename/hash)
   - `github-actions-role`: Sets up GitHub OIDC trust with minimal Lambda update permissions

4. **Environment Separation**: Separate tfvars in `terraform/environments/{dev,prod}/` control environment-specific deployments. Dev and prod use separate workspaces.

### Critical Constraints

- Lambda@Edge functions **must** be in us-east-1 region (enforced via provider alias)
- Lambda@Edge cannot use environment variables (S3 bucket name hardcoded as `__S3_BUCKET_PLACEHOLDER__` in origin-response/index.mjs:12)
- Function code uses `.mjs` extension (ES modules), but package.json references `index.js` - this is intentional for Lambda compatibility
- Terraform ignores code changes after initial deployment (line 95-98 in modules/lambda-edge/main.tf) - code updates go through GitHub Actions only
- GitHub OIDC provider must exist before Terraform runs (see README.md section 3)

## Commands

### Task Runner (Preferred Method)

This project uses [Task](https://taskfile.dev/). All commands below assume you're in the project root.

```bash
# Terraform operations
task init                    # Initialize Terraform
task plan ENV=dev            # Plan changes (specify dev or prod)
task apply ENV=prod          # Apply changes
task dev:plan                # Shortcut for dev environment
task prod:apply              # Shortcut for prod environment

# Lambda development
task install-deps            # Install dependencies for all functions
task test                    # Run tests for all functions
task lint                    # Run linter for all functions

# Maintenance
task format                  # Format Terraform code
task validate                # Validate Terraform configuration
task clean                   # Remove .terraform, builds, node_modules
```

### Direct Commands (Alternative)

If Task is not available:

```bash
# Terraform via Docker Compose
cd terraform
docker compose run --rm terraform init
docker compose run --rm terraform plan -var-file="environments/dev/terraform.tfvars"
docker compose run --rm terraform apply -var-file="environments/prod/terraform.tfvars"

# Lambda function development
cd lambda-functions/viewer-request
npm install
npm test                     # Run all tests
npm run lint                 # Run ESLint
npm run package              # Create function.zip

# Manual Lambda deployment (rarely needed - prefer GitHub Actions)
aws lambda update-function-code \
  --function-name blog-media-viewer-request-prod \
  --zip-file fileb://function.zip \
  --region us-east-1
```

### GitHub Actions Deployment

Push to main branch automatically deploys Lambda functions to prod environment. The workflow:
1. Detects changes under `lambda-functions/`
2. Runs tests (continues on failure)
3. Builds zip package excluding test files
4. Updates Lambda code via OIDC authentication
5. Publishes new version and outputs qualified ARN

## Important Implementation Notes

### When Modifying Lambda Functions

1. **S3 Bucket Configuration**: Update `BUCKET` constant in `origin-response/index.mjs:12` when deploying to new environments
2. **Handler Path**: Lambda handler is `index.handler` but files are `.mjs` - this works because Lambda Node.js runtime supports ES modules
3. **Sharp Library**: Origin-response uses Sharp for image processing - it has native dependencies that require Linux build environment (handled automatically by GitHub Actions)
4. **Response Size Limits**: Lambda@Edge viewer/origin request functions have 1MB response limit; origin-response can return up to 1MB base64-encoded image

### When Modifying Terraform

1. **Provider Context**: Lambda@Edge resources must use `provider = aws.us-east-1` alias (already configured in modules)
2. **State Management**: Currently using local state. Backend config commented out in `terraform/main.tf:11-18` - uncomment and configure for team usage
3. **Module Updates**: If changing Lambda function name/ARN, update `lambda_function_arns` in `terraform/main.tf:94-98` to maintain GitHub Actions permissions

### GitHub Actions Setup Requirements

GitHub repository secrets needed:
- `AWS_ROLE_ARN`: Output from Terraform (terraform/outputs.tf)
- `PROJECT_NAME`: Used to construct function names (e.g., "blog-media")

The deploy-lambda workflow derives environment from branch (main = prod) and constructs function name as: `{PROJECT_NAME}-{function-type}-{environment}`

## Deployment Flow

1. **Initial Setup**: Run Terraform to create empty Lambda functions and GitHub Actions IAM role
2. **Code Deployment**: Push code to main branch → GitHub Actions builds and deploys → publishes versioned ARN
3. **CloudFront Attachment**: Use qualified ARN from deployment output to attach functions to CloudFront distribution (example commented in terraform/main.tf:109-154)
