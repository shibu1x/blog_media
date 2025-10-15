# Lambda@Edge Functions with Terraform

This project provides an AWS Lambda@Edge-based image resizing system that dynamically resizes and optimizes images at CloudFront edge locations. Infrastructure is managed with Terraform and deployed via GitHub Actions.

## Directory Structure

```
.
├── lambda-functions/           # Lambda@Edge function source code
│   ├── viewer-request/        # Viewer request function
│   └── origin-response/       # Origin response function
├── terraform/                 # Terraform code
│   ├── modules/
│   │   ├── lambda-edge/      # Lambda@Edge module
│   │   └── github-actions-role/  # GitHub Actions IAM role module
│   ├── environments/         # Environment-specific settings
│   │   ├── dev/
│   │   └── prod/
│   ├── main.tf               # Main Terraform configuration
│   ├── variables.tf          # Variable definitions
│   ├── outputs.tf            # Output definitions
│   └── terraform.tfvars.example
├── .github/
│   └── workflows/            # CI/CD workflows
│       ├── deploy-lambda.yaml   # Lambda function deployment
│       └── terraform-plan.yaml  # Terraform plan
└── Taskfile.yaml             # Task runner configuration
```

## How It Works

This project implements on-demand image resizing using two Lambda@Edge functions:

### 1. Viewer Request Function
**Location**: `lambda-functions/viewer-request/`

Intercepts CloudFront requests and rewrites URIs based on query parameters:

- Parses `?d=WIDTHxHEIGHT` dimension parameter (e.g., `?d=300x300`)
- Detects WebP support from `Accept` header
- Rewrites URI to: `/resize/{path}/{width}x{height}/{format}/{filename}.{ext}`

**Example**:
- Input: `/blog/posts/image.jpg?d=300x300` (with WebP support)
- Output: `/resize/blog/posts/300x300/webp/image.jpg`

### 2. Origin Response Function
**Location**: `lambda-functions/origin-response/`

Handles 404/403 responses for missing resized images:

- Fetches original image from S3: `origin/{path}/{filename}`
- Resizes using Sharp library with the specified dimensions
- Uploads resized image to S3 (fire-and-forget for performance)
- Returns base64-encoded image immediately to CloudFront

**Features**:
- WebP format conversion support
- Maximum dimension limit: 4000px
- `fit: inside` with `withoutEnlargement: true` (maintains aspect ratio)
- Auto-rotation based on EXIF data

### Image Storage Structure

```
S3 Bucket:
├── origin/              # Original images
│   └── {path}/
│       └── {filename}
└── resize/              # Cached resized images
    └── {path}/
        └── {width}x{height}/
            └── {format}/
                └── {filename}
```

## Setup

### Prerequisites

- AWS CLI configured
- Terraform >= 1.0
- Node.js >= 22.x (for Lambda function development)
- [Task](https://taskfile.dev/) (optional, task runner)

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Configure S3 Bucket

**Important**: Before deploying, update the S3 bucket name in the origin-response function:

Edit `lambda-functions/origin-response/index.mjs`:
```javascript
const BUCKET = 'your-s3-bucket-name';  // Change from '__S3_BUCKET_PLACEHOLDER__'
```

### 3. Create Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to set values for your environment
```

### 4. Create GitHub Actions OIDC Provider (First Time Only)

Create an OIDC Provider to allow GitHub Actions to access AWS. **Execute once per AWS account**.

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd
```

Skip this step if the OIDC Provider already exists.

### 5. Deploy Lambda Functions and GitHub Actions IAM Role

Terraform will deploy the following:
- Lambda@Edge functions (created with empty code)
- GitHub Actions IAM role (using existing OIDC Provider)

```bash
# Check the plan
terraform plan

# Execute deployment
terraform apply
```

**Important**:
- Terraform uses `lifecycle { ignore_changes = [filename, source_code_hash] }`, so function code changes after initial deployment are not managed by Terraform.
- Update code manually or via CI/CD.

### 6. Update Lambda Function Code (Manual)

Build and upload code from each function directory:

```bash
cd lambda-functions/viewer-request
npm install
zip -r function.zip index.mjs package.json node_modules/
aws lambda update-function-code \
  --function-name <function-name> \
  --zip-file fileb://function.zip \
  --region us-east-1
```

**Note**: Function code uses `.mjs` extension (ES modules), not `.js`.

## Task Management with Taskfile

This project uses [Task](https://taskfile.dev/) to manage commonly used commands.

### Available Tasks

```bash
# Show all tasks
task --list

# Initialize Terraform
task init

# Deploy to dev environment
task plan ENV=dev
task apply ENV=dev

# Deploy to prod environment
task plan ENV=prod
task apply ENV=prod

# Or use shortcuts
task dev:plan
task dev:apply
task prod:plan
task prod:apply

# Lambda function development
task install-deps    # Install dependencies for all functions
task test            # Run tests for all functions
task lint            # Run linter for all functions

# Terraform maintenance
task format          # Format Terraform code
task validate        # Validate Terraform configuration

# Clean up
task clean           # Remove .terraform, builds, node_modules, *.zip
```

## Environment-Specific Deployment (Direct Terraform Execution)

If not using Task:

Dev environment:
```bash
cd terraform
terraform workspace new dev  # First time only
terraform workspace select dev
terraform apply -var-file="environments/dev/terraform.tfvars"
```

Prod environment:
```bash
cd terraform
terraform workspace new prod  # First time only
terraform workspace select prod
terraform apply -var-file="environments/prod/terraform.tfvars"
```

## Lambda@Edge Constraints

- **Region**: Functions must be created in the us-east-1 region
- **Timeout**: Maximum 30 seconds (5 seconds recommended for viewer/origin request)
- **Memory**: Maximum 10,240 MB
- **Package Size**:
  - viewer request/response: 1 MB (compressed)
  - origin request/response: 50 MB (compressed)
- **Environment Variables**: Not available (use constants in code instead)
- **VPC**: Cannot run inside a VPC
- **Runtime**: Uses Node.js ES modules (`.mjs` files)

## CloudFront Integration

Refer to the CloudFront distribution configuration (commented section) in `terraform/main.tf` to attach Lambda@Edge functions to CloudFront.

```hcl
lambda_function_association {
  event_type   = "viewer-request"
  lambda_arn   = module.viewer_request_function.qualified_arn
  include_body = false
}
```

## Automated Deployment with GitHub Actions

### Setup

1. **Configure GitHub Actions**

Add the following to terraform.tfvars:

```hcl
github_org  = "your-github-username"
github_repo = "your-repo-name"
```

2. **Create Infrastructure and Role with Terraform**

```bash
cd terraform
terraform apply -var-file="environments/prod/terraform.tfvars"
```

3. **Register in GitHub Repository Secrets**

Set the following Secrets:
- `AWS_ROLE_ARN`: Role ARN obtained from Terraform output
- `PROJECT_NAME`: Project name (e.g., `blog-media`)

4. **Execute Deployment**

Lambda functions will be automatically deployed when you push to the main branch:

```bash
git add lambda-functions/
git commit -m "Update Lambda functions"
git push origin main
```

### Workflows

- **deploy-lambda.yaml**: Lambda function code update and deployment
  - Deploys to prod environment on push to main branch
  - Detects changes under `lambda-functions/`
  - Automatically publishes new versions

- **terraform-plan.yaml**: Terraform change preview
  - Executes terraform plan on PRs
  - Displays results as PR comments

## Development Workflow

### Local Development

1. Modify Lambda function code
2. Run tests locally
3. Push to GitHub
4. GitHub Actions automatically deploys
5. Verify on CloudFront

### Manual Deployment (Optional)

To deploy manually without using GitHub Actions:

```bash
cd lambda-functions/viewer-request
npm install
zip -r function.zip index.mjs package.json node_modules/
aws lambda update-function-code \
  --function-name blog-media-viewer-request-prod \
  --zip-file fileb://function.zip \
  --region us-east-1
```

## Testing

### Run All Tests

```bash
task test
```

Or manually in each function directory:

```bash
cd lambda-functions/viewer-request
npm test
```

### Local Testing with Debug Scripts

Each function includes a `debug.mjs` file for local testing:

```bash
# Test viewer request function
cd lambda-functions/viewer-request
node debug.mjs

# Test origin response function (requires S3 access)
cd lambda-functions/origin-response
node debug.mjs
```

The debug scripts simulate CloudFront events and test various scenarios:
- Viewer request: Tests dimension parsing, WebP detection, URI rewriting
- Origin response: Tests image fetching, resizing, and base64 encoding

## Linting

```bash
task lint
```

Or manually:

```bash
cd lambda-functions/viewer-request
npm run lint
```

## Troubleshooting

### Lambda@Edge Function Not Updating

Lambda@Edge functions are replicated across the entire CloudFront distribution, so updates take time. They are not deleted immediately upon deletion either.

### Checking Function Logs

Lambda@Edge logs are recorded in CloudWatch Logs in the region of each edge location.

### S3 Bucket Not Found Error

If you see errors like "NoSuchBucket" in the origin-response function:
1. Ensure the S3 bucket exists in the specified region (ap-northeast-1)
2. Update `BUCKET` constant in `lambda-functions/origin-response/index.mjs`
3. Verify the Lambda execution role has S3 read/write permissions

### Image Not Resizing

1. Check CloudWatch Logs for errors in the origin-response function
2. Verify original image exists at `origin/{path}/{filename}` in S3
3. Ensure image dimensions are within limits (max 4000px)
4. Confirm Sharp library is properly bundled with node_modules

## References

- [AWS Lambda@Edge Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-edge.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [CloudFront Functions vs Lambda@Edge](https://aws.amazon.com/blogs/aws/introducing-cloudfront-functions-run-your-code-at-the-edge-with-low-latency-at-any-scale/)

## License

MIT
