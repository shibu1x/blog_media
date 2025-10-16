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
   - `s3-cloudfront-origin`: S3 bucket with CloudFront OAC integration

4. **Environment Separation**: Separate tfvars in `terraform/environments/{dev,prod}/` control environment-specific deployments. Backend configuration uses separate `backend.tfvars` files per environment.

### Critical Constraints

- Lambda@Edge functions **must** be in us-east-1 region (enforced via provider alias)
- Lambda@Edge cannot use environment variables (S3 bucket name hardcoded as `__S3_BUCKET_PLACEHOLDER__` in origin-response/index.mjs:12)
- Function code uses `.mjs` extension (ES modules), but package.json references `index.js` - this is intentional for Lambda compatibility
- Terraform ignores code changes after initial deployment (lifecycle ignore_changes in modules/lambda-edge/main.tf) - code updates go through GitHub Actions only
- GitHub OIDC provider must exist before Terraform runs (see README.md section 4)

### S3 Backend Configuration

Terraform uses S3 backend with partial configuration. Backend settings are provided via `backend.tfvars`:
- `terraform/environments/dev/backend.tfvars` - Dev environment backend config
- `terraform/environments/prod/backend.tfvars` - Prod environment backend config
- `terraform/backend.tfvars.example` - Template file (copy to environments/)

Backend configuration includes:
- `bucket`: S3 bucket for state storage (environment-specific)
- `region`: AWS region for state bucket (configurable per environment)
- `key`: State file path (hardcoded: `lambda-edge/terraform.tfstate`)
- `encrypt`: Server-side encryption (set to `false`)
- `use_lockfile`: S3-based locking using `.terraform.lock.hcl` (replaces deprecated DynamoDB locking)

## Commands

### Task Runner (Preferred Method)

This project uses [Task](https://taskfile.dev/). All commands below assume you're in the project root.

```bash
# Terraform operations
task init ENV=dev            # Initialize Terraform with backend config
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
# Terraform via Docker Compose (backend config required)
cd terraform
docker compose run --rm terraform init -backend-config="environments/dev/backend.tfvars"
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
  --function-name {PROJECT_NAME}-viewer-request-prod \
  --zip-file fileb://function.zip \
  --region us-east-1
```

### GitHub Actions Workflows

1. **deploy-lambda.yaml**: Push to main branch automatically deploys Lambda functions to prod environment
   - Detects changes under `lambda-functions/`
   - Runs tests (continues on failure)
   - Replaces `__S3_BUCKET_PLACEHOLDER__` with actual bucket from secrets
   - Builds zip package excluding test files
   - Updates Lambda code via OIDC authentication
   - Publishes new version and outputs qualified ARN

2. **update-cloudfront.yaml**: Manual workflow to update CloudFront distribution with latest Lambda versions
   - Finds CloudFront distribution by project name and environment
   - Fetches latest Lambda function versions
   - Updates Lambda@Edge associations
   - Triggered via `workflow_dispatch`

3. **cleanup-lambda-versions.yaml**: Manual workflow to delete old Lambda versions
   - Keeps N latest versions (default: 3, configurable)
   - Deletes older versions to reduce clutter
   - Runs on prod environment only
   - Triggered via `workflow_dispatch`

## Important Implementation Notes

### When Modifying Lambda Functions

1. **S3 Bucket Configuration**: The deploy-lambda workflow automatically replaces `__S3_BUCKET_PLACEHOLDER__` with the value from GitHub Secrets (`S3_BUCKET`). Do not hardcode bucket names in the source code.

2. **Handler Path**: Lambda handler is `index.handler` but files are `.mjs` - this works because Lambda Node.js runtime supports ES modules

3. **Sharp Library**: Origin-response uses Sharp for image processing - it has native dependencies that require Linux build environment (handled automatically by GitHub Actions using `npm ci --omit=dev`)

4. **Response Size Limits**: Lambda@Edge viewer/origin request functions have 1MB response limit; origin-response can return up to 1MB base64-encoded image

5. **Testing**: Each function includes `debug.mjs` for local testing. Run with `node debug.mjs` to simulate CloudFront events.

### When Modifying Terraform

1. **Provider Context**: Lambda@Edge resources must use `provider = aws.us-east-1` alias (already configured in modules)

2. **State Management**: Uses S3 backend with partial configuration. Must specify `-backend-config` during `terraform init`:
   ```bash
   terraform init -backend-config="environments/prod/backend.tfvars"
   ```

3. **Backend Configuration Files**:
   - Never commit actual `backend.tfvars` with real bucket names to public repos
   - Use `backend.tfvars.example` as template
   - Each environment has separate backend.tfvars with different buckets

4. **Module Updates**: If changing Lambda function name/ARN, update `lambda_function_arns` in `terraform/main.tf` (github_actions_role module) to maintain GitHub Actions permissions

5. **CloudFront Distribution**: CloudFront distribution is managed in `terraform/main.tf` with Lambda@Edge associations. ARNs must be versioned qualifiers (`:N` suffix), not `$LATEST`.

### GitHub Actions Setup Requirements

GitHub repository secrets needed:
- `AWS_ROLE_ARN`: Output from Terraform (`github_actions_role_arn`)
- `PROJECT_NAME`: Used to construct function names (e.g., "blog-media")
- `S3_BUCKET`: S3 origin bucket name (replaced in code during deployment)

The deploy-lambda workflow derives environment from branch:
- `main` branch → `prod` environment
- Other branches → `dev` environment

Function naming convention: `{PROJECT_NAME}-{function-type}-{environment}`

### Security Considerations

When making this repository public, ensure:
1. `terraform/environments/*/terraform.tfvars` are in `.gitignore` (contain org/repo names)
2. `terraform/environments/*/backend.tfvars` are in `.gitignore` (contain bucket names)
3. Only commit `.example` template files
4. GitHub Secrets are properly configured (AWS_ROLE_ARN, PROJECT_NAME, S3_BUCKET)
5. Terraform plan outputs are not exposed in PR comments (terraform-plan.yaml removed)

## Deployment Flow

1. **Initial Setup**:
   - Create GitHub OIDC provider in AWS (one-time per account)
   - Copy `backend.tfvars.example` to each environment and configure
   - Run `terraform init` with backend-config
   - Run `terraform apply` to create Lambda functions, S3 bucket, CloudFront distribution, and GitHub Actions IAM role

2. **Code Deployment**:
   - Push code to main branch → GitHub Actions builds and deploys → publishes versioned ARN
   - Manually trigger "Update CloudFront Distribution" workflow to attach new Lambda versions

3. **Version Cleanup** (optional):
   - Manually trigger "Cleanup Old Lambda Versions" workflow
   - Specify number of versions to keep (default: 3)
   - Removes old versions to reduce Lambda version clutter
