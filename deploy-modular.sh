#!/bin/bash

# Product Video Generator - Modular CloudFormation Deployment Script
# This script deploys infrastructure in logical stages using separate templates

set -uo pipefail

# Configuration (can be overridden via environment variables)
PROJECT_NAME="${PROJECT_NAME:-product-video-generator}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
S3_REGION="${S3_REGION:-us-west-2}"           # Region for S3 bucket
INFRA_REGION="${INFRA_REGION:-us-east-1}"     # Region for ECS/ALB/etc infrastructure

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

# Function to check if stack exists
stack_exists() {
    local stack_name=$1
    local region=${2:-$INFRA_REGION}
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$region" &>/dev/null
}

# Function to get stack status
get_stack_status() {
    local stack_name=$1
    local region=${2:-$INFRA_REGION}
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "DOES_NOT_EXIST"
}

# Function to check if stack is in a stable state
stack_is_stable() {
    local status=$1
    case $status in
        CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to check if stack needs update
stack_needs_update() {
    local status=$1
    case $status in
        CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
            return 0  # Can be updated
            ;;
        DOES_NOT_EXIST)
            return 1  # Needs creation
            ;;
        *)
            print_error "Stack is in unstable state: $status"
            return 2  # Error state
            ;;
    esac
}

# Function to wait for stack operation
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    local region=${3:-$INFRA_REGION}
    
    print_status "Waiting for stack $operation to complete: $stack_name"
    
    # Add timeout and better error handling
    local wait_result=0
    
    if [ "$operation" = "create" ]; then
        aws cloudformation wait stack-create-complete --stack-name "$stack_name" --region "$region" || wait_result=$?
    elif [ "$operation" = "update" ]; then
        aws cloudformation wait stack-update-complete --stack-name "$stack_name" --region "$region" || wait_result=$?
    elif [ "$operation" = "delete" ]; then
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$region" || wait_result=$?
    fi
    
    if [ $wait_result -ne 0 ]; then
        print_error "Stack $operation failed or timed out: $stack_name"
        # Show recent stack events for debugging
        print_status "Recent stack events:"
        aws cloudformation describe-stack-events \
            --stack-name "$stack_name" \
            --region "$region" \
            --max-items 5 \
            --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
            --output table 2>/dev/null || true
        return $wait_result
    fi
    
    print_success "Stack $operation completed successfully: $stack_name"
}

# Function to deploy a single stack
deploy_stack() {
    local template_file=$1
    local stack_name=$2
    local region=$3
    shift 3
    local parameters=("$@")
    
    print_status "Checking stack: $stack_name (region: $region)"
    
    # Get current stack status
    local current_status=$(get_stack_status "$stack_name" "$region")
    print_status "Current status: $current_status"
    
    # Check if stack is already in a good state
    if stack_is_stable "$current_status"; then
        print_success "Stack already deployed and stable: $stack_name ($current_status)"
        return 0
    fi
    
    # Debug: Print parameters being passed
    if [ ${#parameters[@]} -gt 0 ]; then
        print_status "Debug: Parameters for $stack_name:"
        for param in "${parameters[@]}"; do
            print_status "  $param"
        done
    fi
    
    # Convert parameters to deploy format
    local deploy_params=""
    if [ ${#parameters[@]} -gt 0 ]; then
        for param in "${parameters[@]}"; do
            # Extract key and value from ParameterKey=Key,ParameterValue=Value format
            key=$(echo "$param" | sed 's/ParameterKey=\([^,]*\),ParameterValue=.*/\1/')
            value=$(echo "$param" | sed 's/ParameterKey=[^,]*,ParameterValue=\(.*\)/\1/')
            if [ -n "$deploy_params" ]; then
                deploy_params="$deploy_params $key=$value"
            else
                deploy_params="$key=$value"
            fi
        done
    fi
    
    # Use aws cloudformation deploy for reliable parameter handling
    print_status "Deploying/updating stack: $stack_name"
    print_status "Debug: Converted deploy_params: '$deploy_params'"
    
    if [ -n "$deploy_params" ]; then
        aws cloudformation deploy \
            --template-file "$template_file" \
            --stack-name "$stack_name" \
            --parameter-overrides $deploy_params \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$region" \
            --tags Project="$PROJECT_NAME" Environment="$ENVIRONMENT"
    else
        aws cloudformation deploy \
            --template-file "$template_file" \
            --stack-name "$stack_name" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$region" \
            --tags Project="$PROJECT_NAME" Environment="$ENVIRONMENT"
    fi
    
    # Check final status
    local final_status=$(get_stack_status "$stack_name" "$region")
    if stack_is_stable "$final_status"; then
        print_success "Stack deployed successfully: $stack_name ($final_status)"
    else
        print_error "Stack deployment failed: $stack_name ($final_status)"
        return 1
    fi
}

# Function to create security group for ECS tasks
create_security_group() {
    local sg_name="$PROJECT_NAME-ecs-$ENVIRONMENT"
    local sg_description="Security group for $PROJECT_NAME ECS tasks"
    
    print_status "Creating security group: $sg_name"
    
    # Check if security group already exists
    local existing_sg=$(aws ec2 describe-security-groups \
        --region "$INFRA_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$sg_name" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)
    
    if [ "$existing_sg" != "None" ] && [ "$existing_sg" != "" ]; then
        print_status "Security group already exists: $existing_sg"
        SECURITY_GROUP_ID="$existing_sg"
        return
    fi
    
    # Create security group
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$sg_description" \
        --vpc-id "$VPC_ID" \
        --region "$INFRA_REGION" \
        --query 'GroupId' \
        --output text)
    
    if [ $? -eq 0 ]; then
        print_success "Created security group: $SECURITY_GROUP_ID"
        
        # Add HTTP ingress rule
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 80 \
            --cidr "${ALLOWED_CIDR:-0.0.0.0/0}" \
            --region "$INFRA_REGION" >/dev/null
        
        # Add HTTPS ingress rule  
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 443 \
            --cidr "${ALLOWED_CIDR:-0.0.0.0/0}" \
            --region "$INFRA_REGION" >/dev/null
        
        # Add EFS ingress rule (port 2049)
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 2049 \
            --source-group "$SECURITY_GROUP_ID" \
            --region "$INFRA_REGION" >/dev/null
        
        # Add all egress (outbound) rule
        aws ec2 authorize-security-group-egress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol -1 \
            --cidr 0.0.0.0/0 \
            --region "$INFRA_REGION" >/dev/null 2>&1 || true
        
        print_success "Security group configured with HTTP, HTTPS, and EFS access"
    else
        print_error "Failed to create security group"
        exit 1
    fi
}

# Function to get user input for required parameters
get_deployment_parameters() {
    print_status "Gathering deployment parameters..."
    
    # Get VPC ID
    if [ -z "${VPC_ID:-}" ]; then
        echo "Available VPCs:"
        aws ec2 describe-vpcs --region "$INFRA_REGION" --query 'Vpcs[*].{VpcId:VpcId,Name:Tags[?Key==`Name`].Value|[0],CidrBlock:CidrBlock}' --output text | while read -r vpc_id name cidr; do
            echo "  VPC ID: $vpc_id, Name: ${name:-N/A}, CIDR: $cidr"
        done
        echo ""
        read -e -p "Enter VPC ID: " VPC_ID
    fi
    
    # Get Subnet IDs
    if [ -z "${SUBNET_IDS:-}" ]; then
        echo -e "\nAvailable subnets in VPC $VPC_ID:"
        aws ec2 describe-subnets --region "$INFRA_REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' --output text | while read -r subnet_id az cidr name; do
            echo "  Subnet ID: $subnet_id, AZ: $az, CIDR: $cidr, Name: ${name:-N/A}"
        done
        echo ""
        read -e -p "Enter subnet IDs (comma-separated, minimum 2): " SUBNET_IDS_INPUT
        SUBNET_IDS=$(echo "$SUBNET_IDS_INPUT" | tr ',' ' ' | xargs)
        
        # Validate subnet count
        subnet_count=$(echo "$SUBNET_IDS" | wc -w)
        if [ "$subnet_count" -lt 2 ]; then
            print_error "At least 2 subnets are required. You provided: $subnet_count"
            exit 1
        fi
        print_status "Using $subnet_count subnets: $SUBNET_IDS"
    fi
    
    # Create or use existing security group
    if [ -z "${SECURITY_GROUP_ID:-}" ]; then
        # Set ALLOWED_CIDR first if not set
        if [ -z "${ALLOWED_CIDR:-}" ]; then
            CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
            print_warning "Your current public IP: $CURRENT_IP"
            read -e -p "Enter allowed CIDR for ALB access (default: $CURRENT_IP/32): " ALLOWED_CIDR_INPUT
            ALLOWED_CIDR="${ALLOWED_CIDR_INPUT:-$CURRENT_IP/32}"
        fi
        
        create_security_group
    else
        print_status "Using existing security group: $SECURITY_GROUP_ID"
    fi
    
    # Optional certificate ARN
    if [ -z "${CERTIFICATE_ARN:-}" ]; then
        echo -e "\n=== SSL/TLS Certificate Configuration ==="
        echo "Available ACM certificates in this account ($INFRA_REGION):"
        
        if aws acm list-certificates --region "$INFRA_REGION" --query 'CertificateSummaryList[*].{CertificateArn:CertificateArn,DomainName:DomainName,Status:Status}' --output text 2>/dev/null | while read -r cert_arn domain_name status; do
            echo "  Certificate ARN: $cert_arn"
            echo "  Domain: $domain_name, Status: $status"
            echo ""
        done; then
            echo ""
        else
            echo "  No certificates found in this account/region"
            echo ""
        fi
        
        echo "Certificate Options:"
        echo "  1. Leave empty for HTTP-only deployment (port 80)"
        echo "  2. Use existing certificate ARN from above list"
        echo "  3. Create new certificate for subdomain (e.g., dev-app.example.com)"
        echo "  4. For cross-account certificates, first share or recreate in this account"
        echo ""
        print_warning "Note: Certificate must be ISSUED status and in $INFRA_REGION region"
        echo ""
        read -e -p "Enter ACM certificate ARN for HTTPS (press Enter for HTTP-only): " CERTIFICATE_ARN
    fi
    
    # Image tags
    if [ -z "${FRONTEND_TAG:-}" ]; then
        read -e -p "Enter frontend image tag (default: 1.0.0): " FRONTEND_TAG_INPUT
        FRONTEND_TAG="${FRONTEND_TAG_INPUT:-1.0.0}"
    fi
    
    if [ -z "${BACKEND_TAG:-}" ]; then
        read -e -p "Enter backend image tag (default: 1.0.0): " BACKEND_TAG_INPUT
        BACKEND_TAG="${BACKEND_TAG_INPUT:-1.0.0}"
    fi
    
    print_status "Using image tags - Frontend: $FRONTEND_TAG, Backend: $BACKEND_TAG"
    
    # Set default ALLOWED_CIDR if not already set during security group creation
    ALLOWED_CIDR="${ALLOWED_CIDR:-0.0.0.0/0}"
}

# Function to build and push Docker images
build_and_push_images() {
    print_status "Building and pushing Docker images..."
    
    # Get ECR repository URIs from stack outputs
    FRONTEND_ECR=$(aws cloudformation describe-stacks \
        --stack-name "$PROJECT_NAME-ecr-$ENVIRONMENT" \
        --region "$INFRA_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`FrontendECRRepository`].OutputValue' \
        --output text)
    
    BACKEND_ECR=$(aws cloudformation describe-stacks \
        --stack-name "$PROJECT_NAME-ecr-$ENVIRONMENT" \
        --region "$INFRA_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`BackendECRRepository`].OutputValue' \
        --output text)
    
    # Login to ECR
    print_status "Logging into ECR..."
    aws ecr get-login-password --region "$INFRA_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$INFRA_REGION.amazonaws.com"
    
    # Build and push frontend
    print_status "Building and pushing frontend image..."
    docker build --platform linux/amd64 -f Dockerfile.frontend -t "$PROJECT_NAME-frontend:$FRONTEND_TAG" .
    docker tag "$PROJECT_NAME-frontend:$FRONTEND_TAG" "$FRONTEND_ECR:$FRONTEND_TAG"
    docker push "$FRONTEND_ECR:$FRONTEND_TAG"
    
    # Build and push backend
    print_status "Building and pushing backend image..."
    docker build --platform linux/amd64 -f Dockerfile.backend -t "$PROJECT_NAME-backend:$BACKEND_TAG" .
    docker tag "$PROJECT_NAME-backend:$BACKEND_TAG" "$BACKEND_ECR:$BACKEND_TAG"
    docker push "$BACKEND_ECR:$BACKEND_TAG"
    
    print_success "Docker images built and pushed successfully"
}

# Function to deploy all stacks in order
deploy_infrastructure() {
    print_status "Starting modular infrastructure deployment..."
    
    # Common parameters
    local common_params=(
        "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    )
    
    # Step 1: S3 Storage (in S3_REGION)
    print_status "Step 1: Deploying S3 storage to $S3_REGION..."
    
    # Generate unique identifier (epoch timestamp)
    UNIQUE_ID=$(date +%s)
    print_status "Using unique bucket identifier: $UNIQUE_ID"
    
    local s3_params=(
        "${common_params[@]}"
        "ParameterKey=UniqueId,ParameterValue=$UNIQUE_ID"
    )
    deploy_stack "templates/00-s3-storage.yaml" "$PROJECT_NAME-s3-$ENVIRONMENT" "$S3_REGION" "${s3_params[@]}"
    
    # Step 2: ECR Repositories (in INFRA_REGION)
    print_status "Step 2: Deploying ECR repositories to $INFRA_REGION..."
    deploy_stack "templates/01-ecr-repositories.yaml" "$PROJECT_NAME-ecr-$ENVIRONMENT" "$INFRA_REGION" "${common_params[@]}"
    
    # Build and push images after ECR is created
    build_and_push_images
    
    # Step 3: EFS Storage
    print_status "Step 3: Deploying EFS storage..."
    local subnet_list=$(echo $SUBNET_IDS | tr ' ' ',')
    print_status "Debug: VPC_ID=$VPC_ID, SUBNET_IDS='$SUBNET_IDS', subnet_list='$subnet_list'"
    local efs_params=(
        "${common_params[@]}"
        "ParameterKey=VpcId,ParameterValue=$VPC_ID"
        "ParameterKey=SubnetIds,ParameterValue=$subnet_list"
        "ParameterKey=ECSSecurityGroupId,ParameterValue=$SECURITY_GROUP_ID"
    )
    deploy_stack "templates/02-efs-storage.yaml" "$PROJECT_NAME-efs-$ENVIRONMENT" "$INFRA_REGION" "${efs_params[@]}"
    
    # Step 4: Load Balancer
    print_status "Step 4: Deploying load balancer..."
    local alb_params=(
        "${common_params[@]}"
        "ParameterKey=VpcId,ParameterValue=$VPC_ID"
        "ParameterKey=SubnetIds,ParameterValue=$subnet_list"
        "ParameterKey=AllowedCidr,ParameterValue=$ALLOWED_CIDR"
        "ParameterKey=ECSSecurityGroupId,ParameterValue=$SECURITY_GROUP_ID"
    )
    
    # Add certificate if provided
    if [ -n "$CERTIFICATE_ARN" ]; then
        alb_params+=("ParameterKey=CertificateArn,ParameterValue=$CERTIFICATE_ARN")
    fi
    
    deploy_stack "templates/03-load-balancer.yaml" "$PROJECT_NAME-alb-$ENVIRONMENT" "$INFRA_REGION" "${alb_params[@]}"
    
    # Step 5: IAM Roles
    print_status "Step 5: Deploying IAM roles..."
    deploy_stack "templates/04-iam-roles.yaml" "$PROJECT_NAME-iam-$ENVIRONMENT" "$INFRA_REGION" "${common_params[@]}"
    
    # Step 6: ECS Application
    print_status "Step 6: Deploying ECS application..."
    
    # Get S3 bucket name from the S3 stack in S3_REGION
    S3_BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$PROJECT_NAME-s3-$ENVIRONMENT" \
        --region "$S3_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`VideoStorageBucketName`].OutputValue' \
        --output text)
    
    if [ "$S3_BUCKET_NAME" = "None" ] || [ -z "$S3_BUCKET_NAME" ]; then
        print_error "Could not retrieve S3 bucket name from stack in $S3_REGION"
        return 1
    fi
    
    print_status "Using S3 bucket: $S3_BUCKET_NAME (from $S3_REGION)"
    
    local ecs_params=(
        "${common_params[@]}"
        "ParameterKey=SubnetIds,ParameterValue=$subnet_list"
        "ParameterKey=ECSSecurityGroupId,ParameterValue=$SECURITY_GROUP_ID"
        "ParameterKey=FrontendImageTag,ParameterValue=$FRONTEND_TAG"
        "ParameterKey=BackendImageTag,ParameterValue=$BACKEND_TAG"
        "ParameterKey=S3BucketName,ParameterValue=$S3_BUCKET_NAME"
    )
    deploy_stack "templates/05-ecs-application.yaml" "$PROJECT_NAME-app-$ENVIRONMENT" "$INFRA_REGION" "${ecs_params[@]}"
}

# Function to display deployment outputs
show_deployment_summary() {
    print_status "Fetching deployment summary..."
    
    # Get ALB DNS from load balancer stack
    ALB_DNS=$(aws cloudformation describe-stacks \
        --stack-name "$PROJECT_NAME-alb-$ENVIRONMENT" \
        --region "$INFRA_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
        --output text)
    
    echo -e "\n${GREEN}=== DEPLOYMENT COMPLETE ===${NC}"
    echo -e "  Project:       $PROJECT_NAME"
    echo -e "  Environment:   $ENVIRONMENT"
    echo -e "  S3 Region:     $S3_REGION"
    echo -e "  Infra Region:  $INFRA_REGION"
    echo ""
    echo -e "${GREEN}=== DEPLOYED STACKS ===${NC}"
    echo -e "  1. S3 Storage:       $PROJECT_NAME-s3-$ENVIRONMENT ($S3_REGION)"
    echo -e "  2. ECR Repositories: $PROJECT_NAME-ecr-$ENVIRONMENT ($INFRA_REGION)"
    echo -e "  3. EFS Storage:      $PROJECT_NAME-efs-$ENVIRONMENT ($INFRA_REGION)"
    echo -e "  4. Load Balancer:    $PROJECT_NAME-alb-$ENVIRONMENT ($INFRA_REGION)"
    echo -e "  5. IAM Roles:        $PROJECT_NAME-iam-$ENVIRONMENT ($INFRA_REGION)"
    echo -e "  6. ECS Application:  $PROJECT_NAME-app-$ENVIRONMENT ($INFRA_REGION)"
    echo ""
    if [ "$ALB_DNS" != "None" ]; then
        echo -e "${GREEN}=== ACCESS URLs ===${NC}"
        echo -e "  HTTP:  ${BLUE}http://$ALB_DNS${NC}"
        if [ -n "$CERTIFICATE_ARN" ]; then
            echo -e "  HTTPS: ${BLUE}https://$ALB_DNS${NC}"
        fi
    fi
    echo ""
}

# Function to delete all stacks (cleanup)
cleanup_deployment() {
    echo -e "${YELLOW}WARNING: This will delete all infrastructure for $PROJECT_NAME-$ENVIRONMENT${NC}"
    read -e -p "Are you sure you want to delete all stacks? (yes/no): " -r
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Starting cleanup (reverse order)..."
        
        # Delete infrastructure stacks (in INFRA_REGION) in reverse order
        local infra_stacks=(
            "$PROJECT_NAME-app-$ENVIRONMENT"
            "$PROJECT_NAME-iam-$ENVIRONMENT"
            "$PROJECT_NAME-alb-$ENVIRONMENT"
            "$PROJECT_NAME-efs-$ENVIRONMENT"
            "$PROJECT_NAME-ecr-$ENVIRONMENT"
        )
        
        for stack in "${infra_stacks[@]}"; do
            if stack_exists "$stack" "$INFRA_REGION"; then
                print_status "Deleting infrastructure stack: $stack (region: $INFRA_REGION)"
                aws cloudformation delete-stack --stack-name "$stack" --region "$INFRA_REGION"
                wait_for_stack "$stack" "delete" "$INFRA_REGION"
                print_success "Stack deleted: $stack"
            else
                print_warning "Stack does not exist: $stack"
            fi
        done
        
        # Delete S3 stack (in S3_REGION)
        local s3_stack="$PROJECT_NAME-s3-$ENVIRONMENT"
        if stack_exists "$s3_stack" "$S3_REGION"; then
            print_status "Deleting S3 stack: $s3_stack (region: $S3_REGION)"
            aws cloudformation delete-stack --stack-name "$s3_stack" --region "$S3_REGION"
            wait_for_stack "$s3_stack" "delete" "$S3_REGION"
            print_success "Stack deleted: $s3_stack"
        else
            print_warning "Stack does not exist: $s3_stack"
        fi
        
        print_success "Cleanup complete!"
    else
        print_status "Cleanup cancelled."
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [deploy|cleanup|status]"
    echo ""
    echo "Commands:"
    echo "  deploy   - Deploy all infrastructure stacks (default)"
    echo "  cleanup  - Delete all infrastructure stacks"
    echo "  status   - Show current deployment status"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME - Project name (default: product-video-generator)"
    echo "  ENVIRONMENT  - Environment (default: prod)"
    echo "  S3_REGION    - Region for S3 bucket (default: us-west-2)"
    echo "  INFRA_REGION - Region for infrastructure (default: us-east-1)"
    echo "  VPC_ID       - VPC ID for deployment"
    echo "  SUBNET_IDS   - Space-separated subnet IDs"
    echo "  SECURITY_GROUP_ID - Security group for ECS tasks"
    echo "  CERTIFICATE_ARN   - ACM certificate ARN (optional)"
}

# Function to show deployment status
show_status() {
    print_status "Checking deployment status..."
    
    echo -e "\n${BLUE}=== STACK STATUS ===${NC}"
    
    # Check S3 stack in S3_REGION
    local s3_stack="$PROJECT_NAME-s3-$ENVIRONMENT"
    if stack_exists "$s3_stack" "$S3_REGION"; then
        status=$(aws cloudformation describe-stacks \
            --stack-name "$s3_stack" \
            --region "$S3_REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text)
        echo -e "  $s3_stack ($S3_REGION): ${GREEN}$status${NC}"
    else
        echo -e "  $s3_stack ($S3_REGION): ${RED}NOT_DEPLOYED${NC}"
    fi
    
    # Check infrastructure stacks in INFRA_REGION
    local infra_stacks=(
        "$PROJECT_NAME-ecr-$ENVIRONMENT"
        "$PROJECT_NAME-efs-$ENVIRONMENT"
        "$PROJECT_NAME-alb-$ENVIRONMENT"
        "$PROJECT_NAME-iam-$ENVIRONMENT"
        "$PROJECT_NAME-app-$ENVIRONMENT"
    )
    
    for stack in "${infra_stacks[@]}"; do
        if stack_exists "$stack" "$INFRA_REGION"; then
            status=$(aws cloudformation describe-stacks \
                --stack-name "$stack" \
                --region "$INFRA_REGION" \
                --query 'Stacks[0].StackStatus' \
                --output text)
            echo -e "  $stack ($INFRA_REGION): ${GREEN}$status${NC}"
        else
            echo -e "  $stack ($INFRA_REGION): ${RED}NOT_DEPLOYED${NC}"
        fi
    done
}

# Main function
main() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "Product Video Generator - Modular CF Deployment"
    echo "========================================"
    echo -e "${NC}"
    
    local command=${1:-deploy}
    
    case $command in
        deploy)
            validate_aws
            get_deployment_parameters
            deploy_infrastructure
            show_deployment_summary
            ;;
        cleanup)
            validate_aws
            cleanup_deployment
            ;;
        status)
            validate_aws
            show_status
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Script entry point
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi