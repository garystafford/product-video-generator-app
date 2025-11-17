#!/bin/bash

# Product Video Generator - CloudFormation Deployment Script
# This script deploys the entire infrastructure using CloudFormation

set -euo pipefail

# Configuration (can be overridden via environment variables)
PROJECT_NAME="${PROJECT_NAME:-product-video-generator}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-${PROJECT_NAME}-${ENVIRONMENT}}"

# Image tags
FRONTEND_TAG="${FRONTEND_TAG:-1.05}"
BACKEND_TAG="${BACKEND_TAG:-1.05}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to validate AWS CLI and credentials
validate_aws() {
    print_status "Validating AWS CLI and credentials..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    print_success "AWS credentials validated. Account ID: $ACCOUNT_ID"
}

# Function to get user input for required parameters
get_parameters() {
    print_status "Gathering deployment parameters..."
    
    # Get VPC ID
    if [ -z "${VPC_ID:-}" ]; then
        echo "Available VPCs:"
        aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' --output table
        read -p "Enter VPC ID: " VPC_ID
    fi
    
    # Get Subnet IDs
    if [ -z "${SUBNET_IDS:-}" ]; then
        echo -e "\nAvailable subnets in VPC $VPC_ID:"
        aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table
        read -p "Enter subnet IDs (comma-separated, minimum 2): " SUBNET_IDS_INPUT
        SUBNET_IDS=$(echo "$SUBNET_IDS_INPUT" | tr ',' ' ')
    fi
    
    # Get Security Group ID
    if [ -z "${SECURITY_GROUP_ID:-}" ]; then
        echo -e "\nAvailable security groups in VPC $VPC_ID:"
        aws ec2 describe-security-groups --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].[GroupId,GroupName,Description]' --output table
        read -p "Enter existing security group ID for ECS tasks: " SECURITY_GROUP_ID
    fi
    
    # Optional certificate ARN
    if [ -z "${CERTIFICATE_ARN:-}" ]; then
        echo -e "\nAvailable ACM certificates:"
        aws acm list-certificates --region "$REGION" --query 'CertificateSummaryList[*].[CertificateArn,DomainName]' --output table 2>/dev/null || echo "No certificates found"
        read -p "Enter ACM certificate ARN for HTTPS (press Enter to skip): " CERTIFICATE_ARN
    fi
    
    # Optional allowed CIDR
    if [ -z "${ALLOWED_CIDR:-}" ]; then
        CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
        print_warning "Your current public IP: $CURRENT_IP"
        read -p "Enter allowed CIDR for ALB access (default: 0.0.0.0/0 for public): " ALLOWED_CIDR_INPUT
        ALLOWED_CIDR="${ALLOWED_CIDR_INPUT:-0.0.0.0/0}"
    fi
}

# Function to build and push Docker images
build_and_push_images() {
    print_status "Building and pushing Docker images..."
    
    # Get ECR repository URIs (they will be created by CloudFormation if they don't exist)
    FRONTEND_REPO_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$PROJECT_NAME-frontend"
    BACKEND_REPO_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$PROJECT_NAME-backend"
    
    print_status "ECR URIs will be:"
    echo "  Frontend: $FRONTEND_REPO_URI"
    echo "  Backend:  $BACKEND_REPO_URI"
    
    # Login to ECR
    print_status "Logging into ECR..."
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
    
    # Build and push frontend
    print_status "Building frontend image..."
    docker build --platform linux/amd64 -f Dockerfile.frontend -t "$PROJECT_NAME-frontend:$FRONTEND_TAG" .
    docker tag "$PROJECT_NAME-frontend:$FRONTEND_TAG" "$FRONTEND_REPO_URI:$FRONTEND_TAG"
    
    print_status "Pushing frontend image..."
    docker push "$FRONTEND_REPO_URI:$FRONTEND_TAG"
    
    # Build and push backend
    print_status "Building backend image..."
    docker build --platform linux/amd64 -f Dockerfile.backend -t "$PROJECT_NAME-backend:$BACKEND_TAG" .
    docker tag "$PROJECT_NAME-backend:$BACKEND_TAG" "$BACKEND_REPO_URI:$BACKEND_TAG"
    
    print_status "Pushing backend image..."
    docker push "$BACKEND_REPO_URI:$BACKEND_TAG"
    
    print_success "Docker images built and pushed successfully"
}

# Function to deploy CloudFormation stack
deploy_stack() {
    print_status "Deploying CloudFormation stack: $STACK_NAME"
    
    # Prepare parameters
    PARAMETERS=(
        "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
        "ParameterKey=VpcId,ParameterValue=$VPC_ID"
        "ParameterKey=SubnetIds,ParameterValue=\"$(echo $SUBNET_IDS | tr ' ' ',')\""
        "ParameterKey=ExistingSecurityGroupId,ParameterValue=$SECURITY_GROUP_ID"
        "ParameterKey=FrontendImageTag,ParameterValue=$FRONTEND_TAG"
        "ParameterKey=BackendImageTag,ParameterValue=$BACKEND_TAG"
        "ParameterKey=AllowedCidr,ParameterValue=$ALLOWED_CIDR"
    )
    
    # Add certificate ARN if provided
    if [ -n "$CERTIFICATE_ARN" ]; then
        PARAMETERS+=("ParameterKey=CertificateArn,ParameterValue=$CERTIFICATE_ARN")
    fi
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        print_status "Stack exists. Updating..."
        OPERATION="update-stack"
    else
        print_status "Stack does not exist. Creating..."
        OPERATION="create-stack"
    fi
    
    # Deploy stack
    aws cloudformation "$OPERATION" \
        --stack-name "$STACK_NAME" \
        --template-body file://cloudformation-deployment.yaml \
        --parameters "${PARAMETERS[@]}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" \
        --tags "Key=Project,Value=$PROJECT_NAME" "Key=Environment,Value=$ENVIRONMENT"
    
    print_status "Waiting for stack operation to complete..."
    if [ "$OPERATION" = "create-stack" ]; then
        aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
    else
        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
    fi
    
    print_success "CloudFormation stack deployed successfully!"
}

# Function to display deployment outputs
show_outputs() {
    print_status "Fetching stack outputs..."
    
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs')
    
    if [ "$OUTPUTS" != "null" ]; then
        echo -e "\n${GREEN}=== DEPLOYMENT OUTPUTS ===${NC}"
        echo "$OUTPUTS" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"'
        
        # Get ALB DNS name for easy access
        ALB_DNS=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="LoadBalancerDNS") | .OutputValue')
        if [ "$ALB_DNS" != "null" ]; then
            echo -e "\n${GREEN}=== ACCESS URLs ===${NC}"
            echo -e "  HTTP:  ${BLUE}http://$ALB_DNS${NC}"
            if [ -n "$CERTIFICATE_ARN" ]; then
                echo -e "  HTTPS: ${BLUE}https://$ALB_DNS${NC}"
            fi
        fi
    fi
}

# Function to check service health
check_service_health() {
    print_status "Checking ECS service health..."
    
    # Get cluster and service names from outputs
    CLUSTER_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECSClusterName`].OutputValue' \
        --output text)
    
    SERVICE_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECSServiceName`].OutputValue' \
        --output text)
    
    if [ -n "$CLUSTER_NAME" ] && [ -n "$SERVICE_NAME" ]; then
        print_status "Waiting for ECS service to stabilize..."
        aws ecs wait services-stable \
            --cluster "$CLUSTER_NAME" \
            --services "$SERVICE_NAME" \
            --region "$REGION" || print_warning "Service stabilization timed out, check manually"
        
        # Check target group health
        TARGET_GROUP_ARN=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' \
            --output text)
        
        if [ -n "$TARGET_GROUP_ARN" ]; then
            print_status "Target group health status:"
            aws elbv2 describe-target-health \
                --target-group-arn "$TARGET_GROUP_ARN" \
                --region "$REGION" \
                --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Description]' \
                --output table
        fi
    fi
}

# Main deployment function
main() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "Product Video Generator - CF Deployment"
    echo "========================================"
    echo -e "${NC}"
    
    validate_aws
    get_parameters
    
    echo -e "\n${YELLOW}=== DEPLOYMENT SUMMARY ===${NC}"
    echo "  Project Name: $PROJECT_NAME"
    echo "  Environment:  $ENVIRONMENT"
    echo "  Region:       $REGION"
    echo "  Stack Name:   $STACK_NAME"
    echo "  VPC ID:       $VPC_ID"
    echo "  Subnets:      $SUBNET_IDS"
    echo "  Security Group: $SECURITY_GROUP_ID"
    echo "  Frontend Tag: $FRONTEND_TAG"
    echo "  Backend Tag:  $BACKEND_TAG"
    echo "  Allowed CIDR: $ALLOWED_CIDR"
    [ -n "$CERTIFICATE_ARN" ] && echo "  Certificate:  $CERTIFICATE_ARN"
    
    read -p "Proceed with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled."
        exit 0
    fi
    
    build_and_push_images
    deploy_stack
    show_outputs
    check_service_health
    
    echo -e "\n${GREEN}========================================"
    echo "        DEPLOYMENT COMPLETE!"
    echo "========================================"
    echo -e "${NC}"
    print_success "Your Product Video Generator is now deployed and accessible!"
}

# Script entry point
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi