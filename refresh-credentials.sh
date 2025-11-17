#!/bin/bash

# Refresh AWS Credentials and Restart Docker Stack

set -e

echo "==========================================="
echo "AWS Credentials Refresh & Stack Restart"
echo "==========================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Checking current AWS credentials...${NC}"

# Try to get credentials from default profile
AWS_ACCESS_KEY=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
AWS_SECRET_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
AWS_SESSION=$(aws configure get aws_session_token 2>/dev/null || echo "")

# If not found, try from environment
if [ -z "$AWS_ACCESS_KEY" ]; then
    AWS_ACCESS_KEY="${AWS_ACCESS_KEY_ID}"
    AWS_SECRET_KEY="${AWS_SECRET_ACCESS_KEY}"
    AWS_SESSION="${AWS_SESSION_TOKEN}"
fi

if [ -z "$AWS_ACCESS_KEY" ]; then
    echo -e "${RED}No AWS credentials found!${NC}"
    echo ""
    echo "Please set up AWS credentials first:"
    echo "  aws sso login"
    echo "  OR"
    echo "  aws configure"
    exit 1
fi

echo -e "${GREEN}✓ Found AWS credentials${NC}"
echo "  Access Key: ${AWS_ACCESS_KEY:0:10}..."
echo "  Has Session Token: $([ -n "$AWS_SESSION" ] && echo "Yes (temporary)" || echo "No (permanent)")"
echo ""

echo -e "${BLUE}Step 2: Testing credentials...${NC}"

# Test credentials
if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    echo -e "${GREEN}✓ Credentials are valid${NC}"
    echo "  Account: $ACCOUNT_ID"
    echo "  Identity: $USER_ARN"
else
    echo -e "${RED}✗ Credentials are invalid or expired${NC}"
    echo ""
    echo "Please refresh your credentials:"
    echo "  aws sso login"
    exit 1
fi
echo ""

echo -e "${BLUE}Step 3: Updating .env file...${NC}"

# Backup existing .env
if [ -f .env ]; then
    cp .env .env.backup
    echo -e "${YELLOW}  Backed up existing .env to .env.backup${NC}"
fi

# Write new credentials
cat > .env << EOF
# AWS Credentials - Refreshed $(date)
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_KEY}
$([ -n "$AWS_SESSION" ] && echo "AWS_SESSION_TOKEN=${AWS_SESSION}")
AWS_DEFAULT_REGION=us-west-2
AWS_REGION=us-west-2
EOF

echo -e "${GREEN}✓ Updated .env file${NC}"
echo ""

echo -e "${BLUE}Step 4: Initializing Docker Swarm (if needed)...${NC}"

# Check if swarm is already initialized
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "  Swarm not active, initializing..."
    docker swarm init
    echo -e "${GREEN}✓ Swarm initialized${NC}"
else
    echo -e "${GREEN}✓ Swarm already active${NC}"
fi
echo ""

echo -e "${BLUE}Step 5: Setting stack name...${NC}"
STACK_NAME="product-videos"
echo "  Stack name: $STACK_NAME"
echo ""

echo -e "${BLUE}Step 6: Restarting Docker Stack...${NC}"

# Remove existing stack
echo "  Removing existing stack..."
docker stack rm $STACK_NAME 2>/dev/null || true

# Wait for cleanup
echo "  Waiting for cleanup..."
sleep 10

# Deploy new stack
echo "  Deploying stack with new credentials..."
docker stack deploy -c docker-compose.yml $STACK_NAME

echo -e "${GREEN}✓ Stack deployed${NC}"
echo ""

echo -e "${BLUE}Step 7: Waiting for services to start...${NC}"
sleep 15

# Check service status
echo ""
docker stack services $STACK_NAME

echo ""
echo "==========================================="
echo -e "${GREEN}✓ Credentials refreshed and stack restarted!${NC}"
echo "==========================================="
echo ""
echo "Services should be available at:"
echo -e "  Frontend: ${BLUE}http://localhost${NC}"
echo -e "  Backend:  ${BLUE}http://localhost:8000${NC}"
echo ""

# Verify credentials in container
echo -e "${BLUE}Verifying credentials in backend container...${NC}"
sleep 5

BACKEND_CONTAINER=$(docker ps -q --filter "name=${STACK_NAME}_backend" | head -1)

if [ -n "$BACKEND_CONTAINER" ]; then
    if docker exec $BACKEND_CONTAINER python -c "import boto3; info=boto3.client('sts').get_caller_identity(); print(f'✓ Backend can access AWS Account: {info[\"Account\"]}')" 2>/dev/null; then
        echo -e "${GREEN}✓ Backend credentials working!${NC}"
    else
        echo -e "${YELLOW}⚠ Backend credentials not yet available (container may still be starting)${NC}"
        echo "  Wait 30 seconds and test manually:"
        echo "  docker exec \$(docker ps -q --filter \"name=backend\") python -c \"import boto3; print(boto3.client('sts').get_caller_identity())\""
    fi
else
    echo -e "${YELLOW}⚠ Backend container not yet ready${NC}"
fi

echo ""
echo "You can now generate videos!"
echo ""
echo -e "${BLUE}Useful Docker Swarm commands:${NC}"
echo "  docker stack ls"
echo "  docker stack services $STACK_NAME"
echo "  docker service logs ${STACK_NAME}_backend"
echo "  docker service logs ${STACK_NAME}_frontend"
echo "  docker stack rm $STACK_NAME"
