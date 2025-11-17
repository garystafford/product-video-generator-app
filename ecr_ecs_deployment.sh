#!/bin/bash
# Deployment Instructions

# First, login to AWS with your credential.

# Constants
FRONTEND_TAG=1.05
BACKEND_TAG=1.05

REGION="us-east-1"
ACCOUNT="676164205626"
SUBNETS="subnet-8b770cb5 subnet-43a6610e subnet-e2ac45ec"
ECS_SG="sg-56249107"

# Create ECR repositories if they don't exist (1x)
aws ecr create-repository \
  --repository-name product-video-generator-frontend \
  --region ${REGION}

aws ecr create-repository \
  --repository-name product-video-generator-backend \
  --region ${REGION}

# Authenticate Docker to ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com

# Build, tag, and push Docker images to ECR
docker build --platform linux/amd64 -t product-video-generator-backend:${BACKEND_TAG} -f Dockerfile.backend .
docker tag product-video-generator-backend:${BACKEND_TAG} ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/product-video-generator-backend:${BACKEND_TAG}
docker push ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/product-video-generator-backend:${BACKEND_TAG}

docker build --platform linux/amd64 -f Dockerfile.frontend -t product-video-generator-frontend:${FRONTEND_TAG} .
docker tag product-video-generator-frontend:${FRONTEND_TAG} ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/product-video-generator-frontend:${FRONTEND_TAG}
docker push ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/product-video-generator-frontend:${FRONTEND_TAG}

# Create ECS cluster (1x)
aws ecs create-cluster --cluster-name product-video-generator-cluster --region ${REGION}

# Create CloudWatch log group (1x)
aws logs create-log-group \
  --log-group-name /ecs/product-video-generator \
  --region ${REGION}

# Create EFS file system (1x)
EFS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value=product-video-generator-efs \
  --region ${REGION} \
  --query 'FileSystemId' \
  --output text)

echo "Created EFS: ${EFS_ID}"

# Wait for EFS to be available
aws efs describe-file-systems \
  --file-system-id ${EFS_ID} \
  --region ${REGION} \
  --query 'FileSystems[0].LifeCycleState' \
  --output text

# Get VPC ID from subnet
VPC_ID=$(aws ec2 describe-subnets \
  --subnet-ids $(echo ${SUBNETS} | awk '{print $1}') \
  --region ${REGION} \
  --query 'Subnets[0].VpcId' \
  --output text)

echo "VPC ID: ${VPC_ID}"

# Verify VPC has DNS resolution and hostnames enabled
DNS_SUPPORT=$(aws ec2 describe-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --attribute enableDnsSupport \
  --region ${REGION} \
  --query 'EnableDnsSupport.Value' \
  --output text)

DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --attribute enableDnsHostnames \
  --region ${REGION} \
  --query 'EnableDnsHostnames.Value' \
  --output text)

echo "VPC DNS Support: ${DNS_SUPPORT}"
echo "VPC DNS Hostnames: ${DNS_HOSTNAMES}"

if [ "${DNS_SUPPORT}" != "true" ] || [ "${DNS_HOSTNAMES}" != "true" ]; then
  echo "WARNING: VPC DNS settings need to be enabled for EFS to work properly."
  echo "Enabling DNS support and hostnames..."

  aws ec2 modify-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --enable-dns-support \
    --region ${REGION}

  aws ec2 modify-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --enable-dns-hostnames \
    --region ${REGION}

  echo "DNS settings enabled."
fi

# ========================================
# Application Load Balancer Setup
# ========================================

# Create security group for ALB (1x)
echo "Creating ALB security group..."
ALB_SG=$(aws ec2 create-security-group \
  --group-name product-video-generator-alb-sg \
  --description "Security group for Application Load Balancer" \
  --vpc-id ${VPC_ID} \
  --region ${REGION} \
  --query 'GroupId' \
  --output text 2>&1 | grep -oE 'sg-[a-f0-9]+' || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=product-video-generator-alb-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --region ${REGION} \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "ALB Security Group: ${ALB_SG}"

# Allow HTTP traffic from internet to ALB (1x)
echo "Updating ALB security group to allow HTTP traffic from internet..."
aws ec2 authorize-security-group-ingress \
  --group-id ${ALB_SG} \
  --protocol tcp \
  --port 80 \
  --cidr $(curl -s https://checkip.amazonaws.com)/32 \
  --region ${REGION} 2>&1 | grep -v "InvalidPermission.Duplicate" || true

# Allow HTTPS traffic from internet to ALB (1x)
echo "Updating ALB security group to allow HTTPS traffic from internet..."
aws ec2 authorize-security-group-ingress \
  --group-id ${ALB_SG} \
  --protocol tcp \
  --port 443 \
  --cidr $(curl -s https://checkip.amazonaws.com)/32 \
  --region ${REGION} 2>&1 | grep -v "InvalidPermission.Duplicate" || true

echo "Updating ECS security group to allow traffic from ALB..."
# Allow traffic from ALB to ECS on port 80 (1x)
aws ec2 authorize-security-group-ingress \
  --group-id ${ECS_SG} \
  --protocol tcp \
  --port 80 \
  --source-group ${ALB_SG} \
  --region ${REGION} 2>&1 | grep -v "InvalidPermission.Duplicate" || true

echo "Security groups configured for ALB"

# Create security group for EFS (1x)
EFS_SG=$(aws ec2 create-security-group \
  --group-name product-video-generator-efs-sg \
  --description "Security group for EFS mount targets" \
  --vpc-id ${VPC_ID} \
  --region ${REGION} \
  --query 'GroupId' \
  --output text)

# Allow NFS traffic from ECS security group (1x)
aws ec2 authorize-security-group-ingress \
  --group-id ${EFS_SG} \
  --protocol tcp \
  --port 2049 \
  --source-group ${ECS_SG} \
  --region ${REGION}

# Create mount targets for each subnet (1x)
echo "Creating mount target in subnet: subnet-8b770cb5"
aws efs create-mount-target \
  --file-system-id ${EFS_ID} \
  --subnet-id subnet-8b770cb5 \
  --security-groups ${EFS_SG} \
  --region ${REGION} 2>&1 | grep -v "MountTargetConflict" || true

echo "Creating mount target in subnet: subnet-43a6610e"
aws efs create-mount-target \
  --file-system-id ${EFS_ID} \
  --subnet-id subnet-43a6610e \
  --security-groups ${EFS_SG} \
  --region ${REGION} 2>&1 | grep -v "MountTargetConflict" || true

echo "Creating mount target in subnet: subnet-e2ac45ec"
aws efs create-mount-target \
  --file-system-id ${EFS_ID} \
  --subnet-id subnet-e2ac45ec \
  --security-groups ${EFS_SG} \
  --region ${REGION} 2>&1 | grep -v "MountTargetConflict" || true

echo "Waiting for EFS mount targets to be available..."
# Wait for all mount targets to be available
WAIT_COUNT=0
MAX_WAIT=60
while [ ${WAIT_COUNT} -lt ${MAX_WAIT} ]; do
  AVAILABLE_COUNT=$(aws efs describe-mount-targets \
    --file-system-id ${EFS_ID} \
    --region ${REGION} \
    --query 'MountTargets[?LifeCycleState==`available`] | length(@)' \
    --output text)

  EXPECTED_COUNT=$(echo ${SUBNETS} | wc -w | tr -d ' ')

  echo "Mount targets available: ${AVAILABLE_COUNT}/${EXPECTED_COUNT}"

  if [ "${AVAILABLE_COUNT}" -eq "${EXPECTED_COUNT}" ]; then
    echo "All mount targets are available!"
    break
  fi

  sleep 10
  WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ ${WAIT_COUNT} -eq ${MAX_WAIT} ]; then
  echo "Warning: Timeout waiting for mount targets. Proceeding anyway..."
fi

# Create ECS Task Role for Bedrock and S3 access (1x)
echo "Creating ECS task role..."
aws iam create-role \
  --role-name productVideoGeneratorTaskRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' 2>/dev/null || echo "Role may already exist"

# Create and attach policy for Bedrock and S3 (1x)
echo "Creating policy for Bedrock and S3 access..."
POLICY_ARN=$(aws iam create-policy \
  --policy-name ProductVideoGeneratorPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock-runtime:InvokeModel",
          "bedrock-runtime:InvokeModelWithResponseStream",
          "bedrock-runtime:StartAsyncInvoke",
          "bedrock-runtime:GetAsyncInvoke"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        "Resource": "*"
      }
    ]
  }' \
  --query 'Policy.Arn' \
  --output text 2>/dev/null || echo "arn:aws:iam::${ACCOUNT}:policy/ProductVideoGeneratorPolicy")

# Attach policy to role (1x)
aws iam attach-role-policy \
  --role-name productVideoGeneratorTaskRole \
  --policy-arn ${POLICY_ARN} 2>/dev/null || true

echo "Task role configured"

# Create Application Load Balancer (1x)
echo "Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name product-video-generator-alb \
  --subnets $(echo ${SUBNETS}) \
  --security-groups ${ALB_SG} \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --region ${REGION} \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text 2>&1 | grep -oE 'arn:aws:elasticloadbalancing:[^"]+' || \
  aws elbv2 describe-load-balancers \
    --names product-video-generator-alb \
    --region ${REGION} \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

echo "ALB ARN: ${ALB_ARN}"

# Get ALB DNS name for later output
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${ALB_ARN} \
  --region ${REGION} \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB DNS: ${ALB_DNS}"

# Create Target Group (1x)
echo "Creating Target Group..."
TG_ARN=$(aws elbv2 create-target-group \
  --name product-video-generator-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id ${VPC_ID} \
  --target-type ip \
  --health-check-enabled \
  --health-check-protocol HTTP \
  --health-check-path / \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --region ${REGION} \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>&1 | grep -oE 'arn:aws:elasticloadbalancing:[^"]+' || \
  aws elbv2 describe-target-groups \
    --names product-video-generator-tg \
    --region ${REGION} \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "Target Group ARN: ${TG_ARN}"

# Create ALB Listener for port 80 (1x)
echo "Creating ALB Listener on port 80..."
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn ${ALB_ARN} \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
  --region ${REGION} \
  --query 'Listeners[0].ListenerArn' \
  --output text 2>&1 | grep -oE 'arn:aws:elasticloadbalancing:[^"]+' || \
  aws elbv2 describe-listeners \
    --load-balancer-arn ${ALB_ARN} \
    --region ${REGION} \
    --query 'Listeners[?Port==`80`] | [0].ListenerArn' \
    --output text)

echo "Listener ARN: ${LISTENER_ARN}"

# Create ALB Listener for port 443 (HTTPS) (1x)
echo "Creating ALB Listener on port 443 (HTTPS)..."
HTTPS_LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn ${ALB_ARN} \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:us-east-1:676164205626:certificate/0a0987db-8f10-4063-a7dd-9e4264ad1648 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
  --region ${REGION} \
  --query 'Listeners[0].ListenerArn' \
  --output text 2>&1 | grep -oE 'arn:aws:elasticloadbalancing:[^"]+' || \
  aws elbv2 describe-listeners \
    --load-balancer-arn ${ALB_ARN} \
    --region ${REGION} \
    --query 'Listeners[?Port==`443`] | [0].ListenerArn' \
    --output text)

echo "HTTPS Listener ARN: ${HTTPS_LISTENER_ARN}"
echo "ALB setup complete!"

# Register ECS task definition (creates new revision each time)
CONTAINER_DEFS=$(cat <<EOF
[
  {
    "name": "frontend",
    "image": "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/product-video-generator-frontend:${FRONTEND_TAG}",
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80,
        "protocol": "tcp"
      }
    ],
    "essential": true,
    "environment": [
      {
        "name": "BACKEND_HOST",
        "value": "127.0.0.1"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/product-video-generator",
        "awslogs-region": "${REGION}",
        "awslogs-stream-prefix": "frontend"
      }
    }
  },
  {
    "name": "backend",
    "image": "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/product-video-generator-backend:${BACKEND_TAG}",
    "portMappings": [
      {
        "containerPort": 8000,
        "hostPort": 8000,
        "protocol": "tcp"
      }
    ],
    "essential": true,
    "environment": [
      {
        "name": "AWS_DEFAULT_REGION",
        "value": "us-west-2"
      },
      {
        "name": "AWS_REGION",
        "value": "us-west-2"
      }
    ],
    "mountPoints": [
      {
        "sourceVolume": "efs-storage",
        "containerPath": "/app/data",
        "readOnly": false
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/product-video-generator",
        "awslogs-region": "${REGION}",
        "awslogs-stream-prefix": "backend"
      }
    }
  }
]
EOF
)

TASK_DEF_ARN=$(aws ecs register-task-definition \
  --family product-video-generator-task \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu "512" \
  --memory "1024" \
  --execution-role-arn arn:aws:iam::676164205626:role/ecsTaskExecutionRole \
  --task-role-arn arn:aws:iam::${ACCOUNT}:role/ecsTaskExecutionRole \
  --container-definitions "$CONTAINER_DEFS" \
  --volumes "[{\"name\":\"efs-storage\",\"efsVolumeConfiguration\":{\"fileSystemId\":\"${EFS_ID}\",\"transitEncryption\":\"ENABLED\"}}]" \
  --region ${REGION} \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

# Create a new ECS service with ALB integration (1x)
echo "Creating ECS service with ALB integration..."
aws ecs create-service \
  --cluster product-video-generator-cluster \
  --service-name product-video-generator-service \
  --task-definition product-video-generator-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$(echo ${SUBNETS} | tr ' ' ',')],securityGroups=[${ECS_SG}],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=${TG_ARN},containerName=frontend,containerPort=80" \
  --health-check-grace-period-seconds 60 \
  --region ${REGION} 2>&1 | grep -v "ServiceAlreadyExistsException" || echo "Service may already exist"

# Update service to use new task definition with ALB configuration (redeploys each time)
echo "Updating ECS service with new task definition..."
aws ecs update-service \
  --cluster product-video-generator-cluster \
  --service product-video-generator-service \
  --task-definition ${TASK_DEF_ARN} \
  --force-new-deployment \
  --health-check-grace-period-seconds 60 \
  --region ${REGION}

echo "Waiting for service to stabilize..."
aws ecs wait services-stable \
  --cluster product-video-generator-cluster \
  --services product-video-generator-service \
  --region ${REGION} || echo "Service stabilization timed out, check manually"

# ========================================
# Deployment Complete
# ========================================
echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Application Load Balancer DNS: ${ALB_DNS}"
echo ""
echo "Access your application at:"
echo "  HTTP:  http://${ALB_DNS}"
echo "  HTTPS: https://${ALB_DNS}"
echo ""
echo "Note: It may take a few minutes for the ALB to start routing traffic"
echo "to the healthy ECS tasks. Check the target group health status:"
echo ""
echo "aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${REGION}"
echo ""
echo "========================================"