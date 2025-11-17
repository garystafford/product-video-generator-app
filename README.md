# Product Video Generator - Web UI

A professional web interface for generating product videos using AWS Bedrock and Luma AI, built with CloudScape Design System and FastAPI.

## Features

- **Keyframe Upload**: Upload and preview start and end keyframes for your product videos
- **Video Generation**: Generate videos with customizable settings (aspect ratio, duration, resolution)
- **Real-time Monitoring**: Track video generation progress with live updates
- **Video Gallery**: Browse, preview, and download all generated videos
- **Responsive Design**: Professional AWS CloudScape UI that works on all devices

## Architecture

```text
Frontend (React + CloudScape)  <-->  Backend (FastAPI)  <-->  AWS Bedrock + S3
         Port 3000                        Port 8000              Luma AI
```

## Prerequisites

- Python 3.8+
- Node.js 16+
- AWS credentials configured (`aws configure`)
- FFmpeg installed on your system
- Access to AWS Bedrock with Luma AI models

## Installation

### 1. Install Backend Dependencies

```bash
python -m pip install virtualenv --break-system-packages -Uq
python -m venv .venv
source .venv/bin/activate

python -m pip install pip -Uq
python -m pip install -r requirements.txt -Uq
```

### 2. Install Frontend Dependencies

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
3. Enter your S3 bucket name
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

## Directory Structure

```text
product-videos/
├── api_server.py              # FastAPI backend server
├── frontend/                  # React frontend
│   ├── public/
│   │   └── index.html
│   ├── src/
│   │   ├── components/
│   │   │   ├── VideoGenerator.js
│   │   │   ├── JobMonitor.js
│   │   │   └── VideoGallery.js
│   │   ├── App.js
│   │   ├── index.js
│   │   └── index.css
│   └── package.json
├── keyframes/                 # Uploaded keyframe images
├── videos/                    # Generated and processed videos
├── uploads/                   # Temporary upload storage
├── requirements.txt           # Python dependencies
├── start_ui.sh               # Startup script
└── UI_README.md              # This file
```

## Environment Variables

You can optionally configure these via environment variables:

- `AWS_REGION` - AWS region (default: us-west-2)
- `S3_BUCKET` - Default S3 bucket name
- `API_HOST` - Backend host (default: 0.0.0.0)
- `API_PORT` - Backend port (default: 8000)

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

## Production Deployment

For production use, consider:

1. **Database**: Replace in-memory storage with PostgreSQL/MongoDB
2. **Authentication**: Add user authentication and authorization
3. **Queue System**: Use Celery or AWS SQS for job processing
4. **Static Hosting**: Deploy frontend to S3 + CloudFront
5. **API Gateway**: Deploy backend to Lambda or ECS
6. **Monitoring**: Add CloudWatch logs and metrics
7. **HTTPS**: Enable SSL/TLS for secure connections

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
