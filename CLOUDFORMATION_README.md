# CloudFormation Deployment Guide

## Overview

This CloudFormation deployment replaces the `ecr_ecs_deployment.sh` script with Infrastructure as Code (IaC) using AWS CloudFormation. It creates all the same resources but in a more reliable, repeatable, and parameterized way.

## Files

- `cloudformation-deployment.yaml` - Complete CloudFormation template
- `cloudformation-deploy.sh` - Interactive deployment script
- This README

## What Gets Deployed

### Infrastructure Components
- **ECR Repositories**: For frontend and backend Docker images
- **EFS File System**: Encrypted shared storage with mount targets across AZs
- **Application Load Balancer**: Internet-facing ALB with HTTP/HTTPS listeners
- **Security Groups**: For ALB, EFS, and ECS task communication
- **ECS Cluster**: Fargate-enabled cluster with container insights
- **ECS Service**: Auto-scaling service with health checks
- **IAM Roles**: Task execution and task roles with Bedrock/S3 permissions
- **CloudWatch**: Log groups for centralized logging

### Key Features
- Fully parameterized - no hardcoded values
- Environment-specific naming (dev/staging/prod)
- Encrypted EFS with transit encryption
- HTTPS support with ACM certificates
- Target group health checks
- Auto-scaling and rolling deployments
- Comprehensive tagging strategy

## Quick Start

### Prerequisites
- AWS CLI installed and configured
- Docker installed and running
- Appropriate AWS permissions (ECS, ECR, ALB, EFS, IAM, CloudFormation)

### Basic Deployment

1. **Interactive Mode** (Recommended for first deployment):
```bash
./cloudformation-deploy.sh
```

2. **Environment Variables Mode**:
```bash
export PROJECT_NAME="product-video-generator"
export ENVIRONMENT="prod"
export VPC_ID="vpc-12345678"
export SUBNET_IDS="subnet-12345678 subnet-87654321"
export SECURITY_GROUP_ID="sg-12345678"
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/..."

./cloudformation-deploy.sh
```

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | `product-video-generator` | Project name for resource naming |
| `ENVIRONMENT` | `prod` | Environment (dev/staging/prod) |
| `AWS_REGION` | `us-east-1` | AWS region for deployment |
| `STACK_NAME` | `${PROJECT_NAME}-${ENVIRONMENT}` | CloudFormation stack name |
| `VPC_ID` | _(required)_ | VPC ID for deployment |
| `SUBNET_IDS` | _(required)_ | Space-separated subnet IDs (min 2) |
| `SECURITY_GROUP_ID` | _(required)_ | Existing security group for ECS tasks |
| `CERTIFICATE_ARN` | _(optional)_ | ACM certificate for HTTPS |
| `ALLOWED_CIDR` | `0.0.0.0/0` | CIDR block for ALB access |
| `FRONTEND_TAG` | `1.05` | Frontend Docker image tag |
| `BACKEND_TAG` | `1.05` | Backend Docker image tag |

### CloudFormation Parameters

The template supports additional parameters:

- **TaskCpu**: CPU units (256, 512, 1024, 2048, 4096)
- **TaskMemory**: Memory in MB (512-8192)
- **DesiredCount**: Number of ECS tasks (1-10)
- **BackendAwsRegion**: AWS region for backend app config

## Advanced Usage

### Different Environments

Deploy multiple environments:

```bash
# Development environment
ENVIRONMENT=dev PROJECT_NAME=my-video-gen ./cloudformation-deploy.sh

# Staging environment  
ENVIRONMENT=staging PROJECT_NAME=my-video-gen ./cloudformation-deploy.sh

# Production environment
ENVIRONMENT=prod PROJECT_NAME=my-video-gen ./cloudformation-deploy.sh
```

### Custom Resource Sizing

```bash
# Deploy with larger resources
aws cloudformation update-stack \
  --stack-name product-video-generator-prod \
  --template-body file://cloudformation-deployment.yaml \
  --parameters \
    ParameterKey=TaskCpu,ParameterValue=1024 \
    ParameterKey=TaskMemory,ParameterValue=2048 \
    ParameterKey=DesiredCount,ParameterValue=2 \
  --capabilities CAPABILITY_NAMED_IAM
```

### HTTPS-Only Deployment

```bash
# With SSL certificate
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/abcd1234-..."
./cloudformation-deploy.sh
```

## Deployment Process

The script performs these steps:

1. **Validation**: Checks AWS CLI, credentials, and permissions
2. **Parameter Collection**: Interactive prompts or environment variables
3. **Docker Build**: Builds and tags frontend/backend images
4. **ECR Push**: Pushes images to ECR repositories
5. **CloudFormation Deploy**: Creates/updates infrastructure stack
6. **Health Check**: Waits for ECS service to stabilize
7. **Output Display**: Shows access URLs and resource ARNs

## Monitoring and Management

### View Stack Status
```bash
aws cloudformation describe-stacks --stack-name product-video-generator-prod
```

### Check Service Health
```bash
aws ecs describe-services \
  --cluster product-video-generator-cluster-prod \
  --services product-video-generator-service-prod
```

### View Application Logs
```bash
aws logs tail /ecs/product-video-generator-prod --follow
```

### Update Service (New Images)
```bash
# Update image tags and redeploy
FRONTEND_TAG=1.06 BACKEND_TAG=1.06 ./cloudformation-deploy.sh
```

## Troubleshooting

### Common Issues

1. **Stack Creation Fails**:
   - Check IAM permissions
   - Verify VPC/subnet configuration
   - Ensure subnet count >= 2 and in different AZs

2. **ECS Tasks Fail to Start**:
   - Check ECR repository permissions
   - Verify EFS mount targets are available
   - Review CloudWatch logs

3. **ALB Health Checks Fail**:
   - Verify security group rules
   - Check ECS task health
   - Review target group configuration

### Stack Cleanup

```bash
# Delete stack and all resources
aws cloudformation delete-stack --stack-name product-video-generator-prod

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name product-video-generator-prod
```

**Note**: ECR repositories with images and EFS file systems will need manual cleanup.

## Differences from Original Script

### Improvements
- **Infrastructure as Code**: Version controlled, repeatable deployments
- **Parameterization**: No hardcoded values, environment-specific configs
- **Error Handling**: CloudFormation rollback on failures
- **Dependency Management**: Proper resource dependencies and ordering
- **Tagging Strategy**: Consistent tagging across all resources
- **Security**: Least privilege IAM roles, security group isolation

### Migration from ecr_ecs_deployment.sh
- VPC/subnet discovery is now interactive/parameterized
- Certificate ARN must be provided (not hardcoded)
- Security groups are properly managed with ingress rules
- EFS encryption enabled by default
- Enhanced logging and monitoring setup

## Security Considerations

- EFS is encrypted at rest and in transit
- IAM roles follow least privilege principle
- Security groups have specific ingress rules
- ALB can be restricted to specific CIDR blocks
- ECR repositories have image scanning enabled
- CloudWatch logs retention is configured

## Cost Optimization

- Fargate Spot can be enabled for cost savings
- EFS uses bursting mode (can be changed to provisioned)
- CloudWatch log retention prevents indefinite storage
- ECR lifecycle policies clean up old images
- Resources are tagged for cost allocation