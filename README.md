# Product Video Generator

A professional web application for generating product videos using AWS Bedrock and Luma AI, built with CloudScape Design System and FastAPI. Includes complete AWS deployment infrastructure using CloudFormation.

## Features

- **Keyframe Upload**: Upload and preview start and end keyframes for your product videos
- **Video Generation**: Generate videos with customizable settings (aspect ratio, duration, resolution)
- **Batch Automation**: Automated batch processing with pre-built product templates
- **Real-time Monitoring**: Track video generation progress with live updates
- **Video Gallery**: Browse, preview, and download all generated videos
- **Responsive Design**: Professional AWS CloudScape UI that works on all devices
- **Cloud Deployment**: Automated AWS infrastructure deployment with Docker containers
- **Multi-Region Support**: Deploy S3 storage and infrastructure to different regions

## Architecture

### Local Development Architecture

```text
Frontend (React + CloudScape)  <-->  Backend (FastAPI)  <-->  AWS Bedrock + S3
         Port 3000/80                     Port 8000              Luma AI
```

### AWS Production Deployment Architecture

```text
Internet  <-->  ALB  <-->  ECS Fargate  <-->  AWS Bedrock + S3
                           (Frontend + Backend     Luma AI
                            in containers)
```

## Prerequisites

### Local Development Prerequisites

- Python 3.12+
- Node.js v24.11.1+ (Latest LTS)
- AWS credentials configured (`aws configure`)
- FFmpeg installed on your system
- Access to AWS Bedrock with Luma AI models

### AWS Deployment Prerequisites

- AWS CLI installed and configured
- Docker Desktop (for building container images)
- AWS account with appropriate permissions for:
  - CloudFormation, ECS, ECR, S3, ALB, EFS, IAM
  - AWS Bedrock access

## Deployment Options

### Option 1: AWS Production Deployment (Recommended)

Deploy the complete application to AWS using automated CloudFormation templates:

```bash
# Deploy to AWS with default settings (S3 in us-west-2, infrastructure in us-east-1)
./deploy-modular.sh

# Or specify custom regions
S3_REGION=us-west-1 INFRA_REGION=us-west-2 ./deploy-modular.sh
```

The deployment script will:

1. Create S3 bucket for video storage
2. Set up ECR repositories for container images
3. Deploy EFS for shared storage
4. Create Application Load Balancer
5. Set up IAM roles with Bedrock permissions
6. Deploy ECS Fargate cluster with your application

### Option 2: Local Development

## Installation

### 1. Install Backend Dependencies

```bash
python -m pip install virtualenv --break-system-packages -Uq
python -m venv .venv
source .venv/bin/activate

python -m pip install pip -Uq
python -m pip install -r requirements.txt -Uq
```

### 2. Install Frontend Node.js Dependencies

```bash
cd frontend
npm install
cd ..
```

## Running the Application

### Option 1: Using the Start Script (Recommended)

```bash
chmod +x start_ui.sh
./start_ui.sh
```

This will start both the backend (port 8000) and frontend (port 3000) simultaneously.

### Option 2: Manual Start

**Terminal 1 - Start Backend:**

```bash
python api_server.py
```

**Terminal 2 - Start Frontend:**

```bash
cd frontend
npm start
```

## Usage

### 1. Generate Video

1. Navigate to **Generate Video** page
2. Enter product name (e.g., "watch", "sneaker")
3. Enter your S3 bucket name (in us-west-2 where Luma AI Ray2 is located)
4. Upload start keyframe image (required)
5. Upload end keyframe image (optional)
6. Write an animation prompt describing the video motion
7. Configure video settings:
   - Aspect Ratio: 1:1, 4:3, 3:4, 16:9, 9:16, 21:9
   - Duration: 5s or 10s
   - Resolution: 720p or 540p
   - Loop: Yes or No
8. Click **Upload Keyframes** to upload images
9. Click **Generate Video** to start the process

### 2. Monitor Jobs

1. Navigate to **Job Monitor** page
2. View real-time progress of all video generation jobs
3. See active jobs, completed jobs, and failed jobs
4. Auto-refreshes every 3 seconds

### 3. View Results

1. Navigate to **Video Gallery** page
2. Browse all generated videos
3. Click on a video to play it
4. Download final processed videos (with boomerang effect)
5. Download original videos from AWS
6. Delete videos you no longer need

## API Endpoints

### Keyframe Management

- `POST /api/keyframes/upload` - Upload start and end keyframes
- `GET /api/keyframes/{product_name}/{frame_type}` - Get keyframe image

### Video Generation

- `POST /api/videos/generate` - Start video generation
- `GET /api/videos` - List all videos
- `GET /api/videos/{product_name}` - Get video info
- `GET /api/videos/download/{product_name}` - Download video
- `DELETE /api/videos/{product_name}` - Delete video

### Job Management

- `GET /api/jobs` - List all jobs
- `GET /api/jobs/{job_id}` - Get job status

### Configuration

- `GET /api/config/options` - Get available config options
- `GET /api/config/environment` - Get environment configuration (S3 bucket name, etc.)

## CloudFormation Templates

### Template Overview

The deployment uses modular CloudFormation templates for better organization:

1. **00-s3-storage.yaml** - S3 bucket for video storage with encryption and private access
2. **01-ecr-repositories.yaml** - ECR repositories for frontend and backend container images
3. **02-efs-storage.yaml** - EFS file system for shared storage between containers
4. **03-load-balancer.yaml** - Application Load Balancer with optional HTTPS support
5. **04-iam-roles.yaml** - IAM roles and policies with Bedrock and S3 permissions
6. **05-ecs-application.yaml** - ECS Fargate cluster, task definitions, and services

### Deployment Features

- **Multi-Region Support**: Deploy S3 to one region, infrastructure to another
- **Security Groups**: Automatically creates and configures security groups
- **SSL/TLS**: Optional ACM certificate integration for HTTPS
- **Auto-scaling**: ECS services with health checks and deployment strategies
- **Monitoring**: CloudWatch logs and metrics for all services

## Video Processing Pipeline

1. **Upload**: Keyframe images are uploaded to the server
2. **Generate**: AWS Bedrock creates video using Luma AI model (3-6 minutes)
3. **Download**: Video is downloaded from S3 to local storage
4. **Process**: Boomerang effect is applied:
   - Video is reversed
   - Original + reversed are concatenated
   - Speed is increased by 1.33x
   - Audio is removed
5. **Complete**: Final video is ready for viewing and download

## Batch Automation with video_configs.json

The Product Video Generator includes powerful **batch automation capabilities** through the `video_configs.json` configuration file and `batch_generate_product_videos.py` script, enabling enterprise-scale video production.

### Configuration-Driven Batch Processing

The `video_configs.json` file serves as a **centralized configuration hub** for defining multiple product video generation jobs:

```json
{
  "keyframe_based": [
    {
      "product_name": "watch",
      "prompt": "A luxury wristwatch rotates clockwise around its vertical axis...",
      "aspect_ratio": "1:1",
      "duration": "5s",
      "resolution": "720p",
      "loop": false
    },
    {
      "product_name": "sneaker",
      "prompt": "A running sneaker gently rotates counterclockwise...",
      "aspect_ratio": "4:3",
      "duration": "5s",
      "resolution": "720p",
      "loop": false
    }
  ]
}
```

### Automated Batch Generation Workflow

The `batch_generate_product_videos.py` script automates the entire pipeline:

**Preparation Phase:**

- Validates all keyframe images exist (`{product_name}_start_frame.jpg`, `{product_name}_end_frame.jpg`)
- Checks configuration completeness and reports missing files
- Provides detailed pre-flight validation

**Processing Phase:**

- Processes each product configuration sequentially
- Configurable delays between jobs (default: 30 seconds) for API rate limiting
- Intelligent error handling continues processing if individual videos fail

**Post-Processing Phase:**

- Downloads generated videos from S3 automatically
- Applies boomerang effect processing
- Creates final processed videos ready for distribution

### Usage Examples

**Basic Batch Generation:**

```bash
# Generate all configured products
python batch_generate_product_videos.py my-product-videos-bucket
```

**Custom Configuration:**

```bash
# Use custom config file
python batch_generate_product_videos.py my-bucket --config seasonal_products.json
```

**Production Environment:**

```bash
# Set environment variables for production
export AWS_REGION=us-east-1
export DELAY_BETWEEN_JOBS=60
python batch_generate_product_videos.py production-video-bucket
```

### Enterprise Features

**Intelligent Error Handling:**

- Continues processing if individual videos fail
- Provides detailed success/failure reporting
- Exits with proper error codes for CI/CD integration

**Customizable Processing:**

- Environment variable configuration (`AWS_REGION`, `DELAY_BETWEEN_JOBS`)
- Custom config file support (`--config custom_configs.json`)
- Flexible S3 bucket targeting

**Production-Ready Logging:**

```bash
=== BATCH GENERATION SUMMARY ===
Total: 6 videos
Successful: 5
Failed: 1

✓ watch → s3://bucket/videos/watch/output.mp4
✓ sneaker → s3://bucket/videos/sneaker/output.mp4
✗ coat → Configuration error: Start frame not found
```

### Key Benefits

**Time Savings:**

- Generate multiple product videos in a single command
- No manual intervention required after initial setup
- Automated post-processing pipeline

**Consistency:**

- Standardized prompt engineering across products
- Consistent video settings and quality
- Professional-grade outputs

**Scalability:**

- Easy addition of new product configurations
- CI/CD pipeline integration ready
- Cloud-native AWS architecture for enterprise scale

**Cost Efficiency:**

- Batch processing reduces management overhead
- Configurable delays prevent API throttling
- Automated cleanup of intermediate files

This automation capability transforms the application from a single-video tool into a **production-ready video generation platform** capable of processing entire product catalogs automatically.

## Directory Structure

```text
product-video-generator/
├── api_server.py                    # FastAPI backend server
├── batch_generate_product_videos.py # Batch processing script
├── generate_video_with_keyframes.py # Core video generation logic
├── process_video.py                 # Video post-processing (boomerang effect)
├── download_from_s3.py             # S3 download utilities
├── video_configs.json              # Video configuration templates
├── requirements.txt                # Python dependencies
│
├── frontend/                       # React frontend application
│   ├── public/
│   │   └── index.html
│   ├── src/
│   │   ├── components/
│   │   │   ├── VideoGenerator.js   # Video generation interface
│   │   │   ├── JobMonitor.js       # Job monitoring dashboard
│   │   │   └── VideoGallery.js     # Video library browser
│   │   ├── App.js                  # Main React application
│   │   ├── index.js               # React entry point
│   │   └── index.css              # Application styling
│   └── package.json               # Frontend dependencies
│
├── templates/                      # CloudFormation templates
│   ├── 00-s3-storage.yaml        # S3 bucket for video storage
│   ├── 01-ecr-repositories.yaml  # Container image repositories
│   ├── 02-efs-storage.yaml       # Shared file system
│   ├── 03-load-balancer.yaml     # Application Load Balancer
│   ├── 04-iam-roles.yaml         # IAM roles and policies
│   └── 05-ecs-application.yaml   # ECS Fargate cluster and services
│
├── deploy-modular.sh              # Main deployment script
├── start_ui.sh                    # Local development startup script
├── docker-compose.yml             # Local Docker development
├── Dockerfile.backend             # Backend container image
├── Dockerfile.frontend            # Frontend container image
├── nginx.conf                     # Nginx configuration for frontend
├── ecr_ecs_deployment.sh          # Legacy deployment script
├── refresh-credentials.sh         # AWS credential refresh utility
│
├── app/data/                      # Application data storage
│   ├── database.json             # Local job/video database
│   ├── keyframes/                # Uploaded keyframe images
│   ├── uploads/                  # Temporary file uploads
│   └── videos/                   # Generated and processed videos
│
├── keyframes/                     # Additional keyframe storage
├── uploads/                       # Additional upload storage
├── videos/                        # Additional video storage
│
├── CLI_README.md                  # Command-line interface documentation
├── DOCKER_QUICKSTART.md          # Docker development guide
└── README.md                     # This file
```

## Environment Variables

### AWS Deployment Configuration

Configure deployment regions and settings:

- `S3_REGION` - Region for S3 bucket (default: us-west-2)
- `INFRA_REGION` - Region for infrastructure (default: us-east-1)
- `PROJECT_NAME` - Project name (default: product-video-generator)
- `ENVIRONMENT` - Environment (default: prod)
- `VPC_ID` - VPC ID for deployment
- `SUBNET_IDS` - Space-separated subnet IDs
- `SECURITY_GROUP_ID` - Security group for ECS tasks
- `CERTIFICATE_ARN` - ACM certificate ARN (optional for HTTPS)
- `FRONTEND_TAG` - Frontend Docker image tag
- `BACKEND_TAG` - Backend Docker image tag

### Local Development Configuration

Configure local development settings:

- `AWS_REGION` - AWS region (default: us-west-2)
- `S3_BUCKET_NAME` - Default S3 bucket name
- `API_HOST` - Backend host (default: 0.0.0.0)
- `API_PORT` - Backend port (default: 8000)

## AWS Deployment Commands

### Deploy Complete Infrastructure

```bash
# Deploy with default regions (S3: us-west-2, Infrastructure: us-east-1)
./deploy-modular.sh

# Deploy with custom regions
S3_REGION=us-west-1 INFRA_REGION=us-west-2 ./deploy-modular.sh

# Deploy with specific image tags
FRONTEND_TAG=1.0.5 BACKEND_TAG=1.0.5 ./deploy-modular.sh
```

### Check Deployment Status

```bash
./deploy-modular.sh status
```

### Clean Up Resources

```bash
./deploy-modular.sh cleanup
```

### Manual Stack Operations

```bash
# Deploy individual templates
aws cloudformation deploy \
    --template-file templates/00-s3-storage.yaml \
    --stack-name product-video-generator-s3-prod \
    --parameter-overrides ProjectName=product-video-generator Environment=prod UniqueId=$(date +%s) \
    --region us-west-2

# List all stacks
aws cloudformation list-stacks --region us-east-1 --query 'StackSummaries[?contains(StackName, `product-video-generator`)].[StackName,StackStatus]' --output table
```

## Troubleshooting

### Backend Issues

**Port 8000 already in use:**

```bash
lsof -ti:8000 | xargs kill -9
```

**AWS credentials not configured:**

```bash
aws configure
```

**AWS credentials expired (SSO/temporary credentials):**

If using AWS SSO or temporary credentials that expire, use the refresh utility:

```bash
# Refresh AWS credentials and update Docker environment
./refresh-credentials.sh

# Then retry your deployment
./deploy-modular.sh
```

The refresh script will:

- Refresh your AWS SSO session if needed
- Update environment variables for Docker builds
- Re-authenticate with ECR for container pushes

**FFmpeg not found:**

```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
sudo apt-get install ffmpeg

# Windows
# Download from https://ffmpeg.org/download.html
```

### Frontend Issues

**Port 3000 already in use:**

```bash
# Kill the process
lsof -ti:3000 | xargs kill -9

# Or use a different port
PORT=3001 npm start
```

**Proxy connection refused:**

- Make sure the backend is running on port 8000
- Check the `proxy` setting in `frontend/package.json`

### Video Generation Issues

**Generation takes too long:**

- Normal processing time is 3-6 minutes per video
- Check AWS Bedrock service status
- Verify your AWS credentials and permissions

**Upload fails:**

- Check file size (images should be < 10MB)
- Verify file format (JPG, PNG, or WebP)
- Ensure keyframes directory exists

### AWS Deployment Troubleshooting

**CloudFormation stack fails:**

```bash
# Check stack events for errors
aws cloudformation describe-stack-events --stack-name product-video-generator-s3-prod --region us-west-2

# Delete failed stack and retry
aws cloudformation delete-stack --stack-name product-video-generator-s3-prod --region us-west-2
```

**S3 bucket name conflicts:**

- Bucket names are globally unique and include timestamp to avoid conflicts
- If deployment fails, the script will generate a new timestamp on retry

**AWS credentials expired during deployment:**

```bash
# If deployment fails with credential errors
./refresh-credentials.sh

# Then continue deployment (will skip completed stacks)
./deploy-modular.sh
```

**ECR authentication failures:**

```bash
# Manual ECR login if automated login fails
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 890966919088.dkr.ecr.us-east-1.amazonaws.com

# Or use the refresh script which handles this automatically
./refresh-credentials.sh
```

**ECS service deployment issues:**

```bash
# Check ECS service status
aws ecs describe-services --cluster product-video-generator-cluster-prod --services product-video-generator-service-prod --region us-east-1

# View container logs
aws logs describe-log-groups --log-group-name-prefix /ecs/product-video-generator --region us-east-1
```

**Docker image build failures:**

```bash
# Test Docker builds locally
docker build -f Dockerfile.frontend -t test-frontend .
docker build -f Dockerfile.backend -t test-backend .

# Check ECR repository permissions
aws ecr describe-repositories --region us-east-1
```

## Production Considerations

The AWS deployment includes production-ready features:

1. **High Availability**: ALB with multiple AZs and ECS service auto-recovery
2. **Security**: IAM roles with least-privilege permissions, private subnets, security groups
3. **Monitoring**: CloudWatch logs and metrics for all services
4. **Scalability**: ECS Fargate with configurable CPU/memory limits
5. **Storage**: EFS for shared data, S3 for video storage with encryption
6. **HTTPS**: Optional SSL/TLS with ACM certificates

### Additional Production Enhancements

Consider these improvements for enterprise use:

1. **Database**: Replace in-memory storage with RDS PostgreSQL
2. **Authentication**: Add AWS Cognito or Auth0 integration
3. **Queue System**: Use AWS SQS/SNS for asynchronous job processing
4. **CDN**: Add CloudFront for global video delivery
5. **Monitoring**: Implement AWS X-Ray tracing and custom CloudWatch dashboards
6. **Backup**: Set up automated EFS and RDS backups
7. **Multi-Environment**: Separate dev/staging/prod deployments

## Cost Considerations

- AWS Bedrock charges per video generation (~$0.50-1.00 per video)
- S3 storage costs for videos
- Data transfer costs for downloads
- Consider implementing usage limits and quotas

## Support

For issues or questions:

- Check the main project documentation
- Review AWS Bedrock documentation
- Verify your AWS IAM permissions include Bedrock and S3 access

## License

Same as the main project.
