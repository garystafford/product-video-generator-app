# Modular CloudFormation Deployment

This directory contains a modular CloudFormation approach that breaks the monolithic infrastructure template into logical, manageable components.

## Architecture Overview

The infrastructure is deployed in 5 stages, each with clear dependencies and purposes:

```text
Stage 1: ECR Repositories → Stage 2: EFS Storage → Stage 3: Load Balancer → Stage 4: IAM Roles → Stage 5: ECS Application
```

## Template Structure

| Template                   | Purpose                                   | Depends On          | Exports                    |
| -------------------------- | ----------------------------------------- | ------------------- | -------------------------- |
| `01-ecr-repositories.yaml` | Container image repositories              | None                | ECR repository URIs        |
| `02-efs-storage.yaml`      | Shared file system for keyframes/uploads  | VPC/Subnets         | EFS file system ID         |
| `03-load-balancer.yaml`    | Application Load Balancer & target groups | VPC/Subnets         | ALB ARN, target group ARNs |
| `04-iam-roles.yaml`        | ECS execution and task roles              | None                | IAM role ARNs              |
| `05-ecs-application.yaml`  | ECS cluster, services, and tasks          | All previous stacks | ECS service ARNs           |

## Quick Start

### Prerequisites

1. **AWS CLI configured** with appropriate permissions for the target AWS account
2. **Docker installed** for building images
3. **VPC with public subnets** (minimum 2 AZs)
4. **EC2 permissions** to create security groups (automatic)

### AWS Account Configuration

The deployment script automatically detects your AWS account ID from your configured credentials:

```bash
# Check your current AWS account
aws sts get-caller-identity

# To deploy to a different account, configure AWS CLI with that account's credentials:
aws configure --profile myaccount
export AWS_PROFILE=myaccount

# Or set credentials directly
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
```

### SSL Certificate Options

The deployment supports multiple certificate strategies for multi-account deployments:

```bash
# Option 1: HTTP-only deployment (no certificate needed)
export CERTIFICATE_ARN=""
./deploy-modular.sh deploy

# Option 2: Use existing certificate in current account
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
./deploy-modular.sh deploy

# Option 3: Create certificate for environment-specific subdomain
# First create certificate for: dev-app.example.com, staging-app.example.com, etc.
aws acm request-certificate \
    --domain-name dev-app.example.com \
    --validation-method DNS \
    --region us-east-1

# Option 4: Cross-account certificate sharing (advanced)
# Use AWS Resource Access Manager or recreate certificate in target account
```

#### Multi-Account Domain Strategies

| Strategy | Production Account | Development Account | Certificate Location |
|----------|-------------------|-------------------|-------------------|
| **Subdomains** | `app.example.com` | `dev-app.example.com` | Each account |
| **Environment Domains** | `myapp.com` | `myapp-dev.com` | Each account |
| **Shared Certificate** | `*.example.com` | Uses shared wildcard | Production account (shared) |

### Deploy Everything

```bash
# Make script executable
chmod +x deploy-modular.sh

# Deploy with interactive prompts
./deploy-modular.sh deploy

# Or set environment variables to skip prompts
export VPC_ID="vpc-12345678"
export SUBNET_IDS="subnet-12345678 subnet-87654321"
# SECURITY_GROUP_ID will be auto-created if not specified
./deploy-modular.sh deploy
```

### Environment Variables

| Variable            | Description                         | Required | Default                   |
| ------------------- | ----------------------------------- | -------- | ------------------------- |
| `AWS_PROFILE`       | AWS CLI profile to use              | No       | Default profile           |
| `PROJECT_NAME`      | Project identifier                  | No       | `product-video-generator` |
| `ENVIRONMENT`       | Environment name (dev/staging/prod) | No       | `prod`                    |
| `AWS_REGION`        | Target AWS region                   | No       | `us-east-1`               |
| `VPC_ID`            | VPC for deployment                  | Yes      | Interactive prompt        |
| `SUBNET_IDS`        | Space-separated subnet IDs          | Yes      | Interactive prompt        |
| `SECURITY_GROUP_ID` | Security group for ECS tasks        | No       | Auto-created             |
| `CERTIFICATE_ARN`   | ACM certificate ARN for HTTPS       | No       | HTTP only (see cert options below) |
| `ALLOWED_CIDR`      | Allowed CIDR for ALB access         | No       | `0.0.0.0/0`               |
| `FRONTEND_TAG`      | Frontend image tag                  | No       | `1.0.0`                   |
| `BACKEND_TAG`       | Backend image tag                   | No       | `1.0.0`                   |

## Deployment Commands

### Deploy Infrastructure

```bash
./deploy-modular.sh deploy
```

### Check Status

```bash
./deploy-modular.sh status
```

### Cleanup (Delete All)

```bash
./deploy-modular.sh cleanup
```

## Manual Deployment Steps

If you prefer to deploy stages manually:

### Stage 1: ECR Repositories

```bash
aws cloudformation deploy \
    --template-file templates/01-ecr-repositories.yaml \
    --stack-name product-video-generator-ecr-prod \
    --parameter-overrides \
        ProjectName=product-video-generator \
        Environment=prod \
    --capabilities CAPABILITY_NAMED_IAM
```

### Stage 2: Build and Push Images

```bash
# Get ECR URIs from stack outputs
FRONTEND_ECR=$(aws cloudformation describe-stacks \
    --stack-name product-video-generator-ecr-prod \
    --query 'Stacks[0].Outputs[?OutputKey==`FrontendECRRepository`].OutputValue' \
    --output text)

BACKEND_ECR=$(aws cloudformation describe-stacks \
    --stack-name product-video-generator-ecr-prod \
    --query 'Stacks[0].Outputs[?OutputKey==`BackendECRRepository`].OutputValue' \
    --output text)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build and push images
docker build --platform linux/amd64 -f Dockerfile.frontend -t frontend:1.0.0 .
docker tag frontend:1.0.0 $FRONTEND_ECR:1.0.0
docker push $FRONTEND_ECR:1.0.0

docker build --platform linux/amd64 -f Dockerfile.backend -t backend:1.0.0 .
docker tag backend:1.0.0 $BACKEND_ECR:1.0.0
docker push $BACKEND_ECR:1.0.0
```

### Stage 3: EFS Storage

```bash
aws cloudformation deploy \
    --template-file templates/02-efs-storage.yaml \
    --stack-name product-video-generator-efs-prod \
    --parameter-overrides \
        ProjectName=product-video-generator \
        Environment=prod \
        VpcId=vpc-12345678 \
        SubnetIds="subnet-12345678,subnet-87654321" \
        ECSSecurityGroupId=sg-12345678
```

### Stage 4: Load Balancer

```bash
aws cloudformation deploy \
    --template-file templates/03-load-balancer.yaml \
    --stack-name product-video-generator-alb-prod \
    --parameter-overrides \
        ProjectName=product-video-generator \
        Environment=prod \
        VpcId=vpc-12345678 \
        SubnetIds="subnet-12345678,subnet-87654321" \
        AllowedCidr=0.0.0.0/0 \
        ECSSecurityGroupId=sg-12345678
```

### Stage 5: IAM Roles

```bash
aws cloudformation deploy \
    --template-file templates/04-iam-roles.yaml \
    --stack-name product-video-generator-iam-prod \
    --parameter-overrides \
        ProjectName=product-video-generator \
        Environment=prod \
    --capabilities CAPABILITY_NAMED_IAM
```

### Stage 6: ECS Application

```bash
aws cloudformation deploy \
    --template-file templates/05-ecs-application.yaml \
    --stack-name product-video-generator-app-prod \
    --parameter-overrides \
        ProjectName=product-video-generator \
        Environment=prod \
        SubnetIds="subnet-12345678,subnet-87654321" \
        ECSSecurityGroupId=sg-12345678 \
        FrontendImageTag=1.0.0 \
        BackendImageTag=1.0.0 \
    --capabilities CAPABILITY_NAMED_IAM
```

## Stack Outputs and Cross-References

### ECR Repositories Stack Exports:

- `FrontendECRRepository`: Frontend ECR repository URI
- `BackendECRRepository`: Backend ECR repository URI

### EFS Storage Stack Exports:

- `EFSFileSystemId`: EFS file system ID for mounting

### Load Balancer Stack Exports:

- `LoadBalancerArn`: ALB ARN for ECS service configuration
- `FrontendTargetGroupArn`: Frontend target group ARN
- `BackendTargetGroupArn`: Backend target group ARN

### IAM Roles Stack Exports:

- `ECSExecutionRoleArn`: ECS task execution role ARN
- `ECSTaskRoleArn`: ECS task role ARN

## Monitoring and Troubleshooting

### Check Stack Status

```bash
aws cloudformation describe-stacks \
    --stack-name product-video-generator-app-prod \
    --query 'Stacks[0].StackStatus'
```

### View Stack Events

```bash
aws cloudformation describe-stack-events \
    --stack-name product-video-generator-app-prod \
    --max-items 10
```

### Check ECS Service Status

```bash
aws ecs describe-services \
    --cluster product-video-generator-prod \
    --services product-video-generator-frontend-prod product-video-generator-backend-prod
```

### View Application Logs

```bash
# Frontend logs
aws logs filter-log-events \
    --log-group-name /ecs/product-video-generator-frontend-prod \
    --start-time $(date -d '1 hour ago' +%s)000

# Backend logs
aws logs filter-log-events \
    --log-group-name /ecs/product-video-generator-backend-prod \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Benefits of Modular Approach

### 1. **Independent Lifecycle Management**

- Update ECR repositories without touching ECS services
- Modify load balancer configuration independently
- Manage IAM roles separately from compute resources

### 2. **Better Error Isolation**

- Failures in one stack don't affect others
- Easier to identify and fix specific issues
- Faster rollback of individual components

### 3. **Reusability**

- Reuse ECR repositories across environments
- Share IAM roles between multiple applications
- Template components can be used in other projects

### 4. **Security and Compliance**

- Different teams can manage different stacks
- Fine-grained permissions per infrastructure layer
- Easier to audit and validate specific components

### 5. **Faster Deployments**

- Only deploy changed components
- Parallel development of different infrastructure layers
- Reduced deployment time for updates

## Best Practices

### 1. **Parameter Validation**

- All templates include comprehensive parameter validation
- Use allowed values where appropriate
- Provide sensible defaults for optional parameters

### 2. **Resource Tagging**

- Consistent tagging strategy across all resources
- Environment, project, and component tags
- Cost allocation and resource management

### 3. **Security Configuration**

- Least privilege IAM roles
- VPC-based security groups
- Optional HTTPS with ACM certificates

### 4. **Monitoring and Logging**

- CloudWatch log groups for all ECS tasks
- Application Load Balancer access logs
- ECS service and task monitoring

## Migration from Monolithic Template

If migrating from the original `cloudformation-deployment.yaml`:

1. **Export existing resources** (if possible)
2. **Deploy new modular stacks** in a different environment first
3. **Test functionality** thoroughly
4. **Plan cutover strategy** for production
5. **Update CI/CD pipelines** to use new deployment script

## Troubleshooting Common Issues

### Deployment Script Issues

**Issue**: Script gets stuck when displaying resource options

```bash
# Solution 1: Use environment variables to skip interactive prompts
export VPC_ID="vpc-12345678"
export SUBNET_IDS="subnet-12345678 subnet-87654321"
# Security group will be auto-created
./deploy-modular.sh deploy

# Solution 2: If stuck, press Ctrl+C and use manual commands instead
```

### Stack Creation Failures

**Issue**: "Subnet must belong to VPC"

```bash
# Solution: Verify subnet IDs belong to specified VPC
aws ec2 describe-subnets --subnet-ids subnet-12345678 --query 'Subnets[*].VpcId'
```

**Issue**: "Security group creation failed"

```bash
# Solution: Check EC2 permissions and VPC limits
aws iam get-user
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=YOUR_VPC_ID" --query 'length(SecurityGroups)'
```

### Image Push Failures

**Issue**: "No basic auth credentials"

```bash
# Solution: Re-authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

### ECS Task Failures

**Issue**: Tasks fail to start

```bash
# Check ECS service events
aws ecs describe-services \
    --cluster product-video-generator-prod \
    --services product-video-generator-frontend-prod

# Check task definition
aws ecs describe-task-definition \
    --task-definition product-video-generator-frontend-prod
```

## Cost Optimization

- **ECR repositories**: Lifecycle policies remove old images automatically
- **EFS storage**: Intelligent Tiering moves infrequent data to lower-cost tiers
- **ALB**: Only provision what's needed, scale target groups appropriately
- **ECS Fargate**: Right-size CPU and memory allocations
- **CloudWatch**: Set log retention periods to control storage costs
