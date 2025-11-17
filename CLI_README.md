# Product Motion Videos

Product motion videos produced with Luma AI AI Ray2 and FFmpeg.

## TL;DR - Local Quick Start

Generate product videos with keyframes in 3 steps:

1. **Place your keyframe images** in the `keyframes/` directory:

   - `{product_name}_start_frame.jpg`
   - `{product_name}_end_frame.jpg`

2. **Configure your videos** in `video_configs.json`:

   ```json
   {
     "keyframe_based": [
       {
         "product_name": "watch",
         "prompt": "The watch rotates 30 degrees clockwise then returns",
         "aspect_ratio": "16:9",
         "duration": "5s",
         "resolution": "720p"
       }
     ]
   }
   ```

3. **Run the batch generation script**:
   ```bash
   python batch_generate_product_videos.py my-s3-bucket
   ```

The script will generate videos, download them to `videos/`, and apply the boomerang effect automatically.

## Table of Contents

1. [Setup](#setup)
2. [Python Scripts Overview](#python-scripts-overview)
3. [AWS Bedrock Video Generation](#aws-bedrock-video-generation)
4. [Video Post-Processing](#video-post-processing)
5. [Project Structure](#project-structure)

## Setup

Mac:

```bash
python -m pip install virtualenv --break-system-packages -Uq
python -m venv .venv
source .venv/bin/activate

python -m pip install pip -Uq
python -m pip install -r requirements.txt -Uq
```

Windows:

```bat
python -m venv .venv
.venv\Scripts\activate

python -m pip install pip -Uq
python -m pip install -r requirements.txt -Uq
```

## Python Scripts Overview

The project contains the following Python scripts:

- `batch_generate_product_videos.py` - Main script for batch video generation with keyframes
- `generate_video_with_keyframes.py` - Generate single videos using start/end frame images
- `download_from_s3.py` - Download generated videos from S3 bucket
- `process_video.py` - Apply boomerang effect to videos

The recommended workflow uses the keyframe-based approach with `batch_generate_product_videos.py` for the best results.

### AWS Configuration

To use the Bedrock video generation scripts, configure AWS credentials:

```bash
# Option 1: AWS CLI
aws configure
# Enter your Access Key ID, Secret Access Key, and default region

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

## AWS Bedrock Video Generation

Generate product videos using Luma AI Ray2 via AWS Bedrock.

### Download Generated Videos

**List all videos in your S3 bucket:**

```bash
python download_from_s3.py --list my-s3-bucket product-videos/
```

**Download a specific video:**

```bash
python download_from_s3.py "s3://my-bucket/product-videos/watch/20241107_123456/video.mp4"

# Or specify local filename
python download_from_s3.py "s3://my-bucket/path/video.mp4" watch.mp4
```

**Using AWS CLI:**

```bash
aws s3 cp s3://my-bucket/product-videos/watch/20241107_123456/video.mp4 .
```

### Generate Videos with Keyframes (Recommended)

Use start and end frame images to control video generation precisely:

**Generate video with both start and end frames:**

```bash
python generate_video_with_keyframes.py watch my-bucket \
  watch_start_frame.jpg watch_end_frame.jpg \
  "The watch rotates 30 degrees clockwise then returns to start"
```

**Generate with only start frame:**

```bash
python generate_video_with_keyframes.py watch my-bucket \
  watch_start_frame.jpg - \
  "Camera slowly orbits around the watch"
```

**Batch generate with keyframes:**

```bash
# Edit VIDEO_CONFIGS in batch_generate_product_videos.py first
python batch_generate_product_videos.py my-bucket
```

**Benefits of using keyframes:**

- More control over start/end positions
- Consistent product placement across videos
- Better results for specific product angles
- Easier to create variations from same base images

### Prompt Writing Tips

For best results with Luma Ray:

**Product Rotation:**

- "A [product] rotating [degrees] clockwise, pausing, then returning to start"
- "A [product] spinning smoothly in a complete 360-degree rotation"

**Camera Movement:**

- "Camera orbits around a [product] on a [surface]"
- "Slow zoom into [product] revealing intricate details"

**Lighting & Environment:**

- "Dark velvet surface with dramatic studio lighting"
- "Soft gradient background with professional lighting"
- "Stars and celestial objects moving in the background"

**Example prompts:**

```text
A luxury watch rotating 30 degrees clockwise then back. Dark velvet surface with rim lighting.

Designer sunglasses slowly rotating on a marble pedestal. Soft shadows and golden hour lighting.

High-end sneaker floating and rotating. Cosmic background with particles.
```

### Troubleshooting

#### Error: 'BedrockRuntime' object has no attribute 'invoke_model_async'

- This has been fixed in the latest scripts
- The correct method is `start_async_invoke` (not `invoke_model_async`)
- Uses `bedrock-runtime` client with proper parameter structure
- Make sure you're using the updated scripts

#### Error: Access Denied / Authorization

- Check AWS credentials are configured: `aws configure`
- Ensure your IAM user/role has `bedrock:InvokeModel` permission
- Verify the Luma AI Ray2 model is available in your region

#### Keyframe images not found

- Use absolute paths or ensure images are in the `keyframes/` directory
- Supported formats: JPG, JPEG, PNG, WebP
- Ensure filenames follow the pattern: `{product_name}_start_frame.jpg` and `{product_name}_end_frame.jpg`

## Video Post-Processing

Two scripts are provided to automate the boomerang video processing:

### Bash Script

**Usage:**

```bash
./process_video.sh watch
```

**Features:**

- No dependencies beyond ffmpeg
- Fast execution
- Automatic cleanup of intermediate files

### Python Script

**Installation:**

```bash
python -m pip install virtualenv --break-system-packages -Uq
python -m venv .venv
source .venv/bin/activate

python -m pip install pip -Uq
python -m pip install -r requirements.txt -Uq
```

**Usage:**

```bash
python process_video.py watch
# or
./process_video.py watch
```

**Features:**

- Cross-platform compatibility
- Enhanced error handling
- Uses ffmpeg-python package

### What the Scripts Do

Both scripts automate the boomerang effect process:

1. **Reverse** - Creates backward version of video
2. **Concatenate** - Combines original + reversed
3. **Speed Up** - Applies 1.33x speed (0.75 PTS)
4. **Clean Up** - Removes intermediate files

**Input:** `video_name.mp4`
**Output:** `video_name_final.mp4`

### Batch Processing

Process multiple videos at once:

```bash
# Bash
for video in watch sunglasses sneaker; do
    ./process_video.sh $video
done

# Python
for video in watch sunglasses sneaker; do
    python process_video.py $video
done
```

### Customization

**Adjust speed** by modifying the `setpts` filter:

- `0.5*PTS` = 2x speed (faster)
- `0.75*PTS` = 1.33x speed (current default)
- `1.0*PTS` = original speed
- `2.0*PTS` = 0.5x speed (slower)

**Keep audio** by removing the `-an`/`an=None` parameter in the scripts.

## Complete Workflow Example

1. **Generate video with AWS Bedrock:**

```bash
python generate_video_with_keyframes.py watch my-bucket \
  watch_start_frame.jpg watch_end_frame.jpg \
  "Luxury watch rotating 30 degrees clockwise then back"
```

2. **Download from S3:**

```bash
python download_from_s3.py "s3://my-bucket/product-videos/watch/.../video.mp4" watch.mp4
```

3. **Add boomerang effect:**

```bash
./process_video.sh watch
# Output: watch_final.mp4
```

## Manual FFmpeg Commands

For reference, here are the manual ffmpeg commands:

```bash
# Simple boomerang effect
ffmpeg -i watch.mp4 -vf reverse watch_reversed.mp4 -y
(echo file 'watch.mp4' & echo file 'watch_reversed.mp4')>list.txt
ffmpeg -safe 0 -f concat -i list.txt -c copy watch_combined.mp4 -y
ffmpeg -i watch_combined.mp4 -filter:v "setpts=0.75*PTS" -an watch_final.mp4

# With pause on last frame
ffmpeg -sseof -1 -i watch.mp4 -update 1 -q:v 1 watch.jpg
ffmpeg -loop 1 -i watch.jpg -t 1 -r 30 -c:v libx264 -pix_fmt yuv420p watch_last_frame_1s.mp4
(echo file 'watch.mp4' & echo file 'watch_last_frame_1s.mp4' & echo file 'watch_reversed.mp4')>list.txt
ffmpeg -safe 0 -f concat -i list.txt -c copy watch_combined.mp4
```

## Project Structure

```text
product-videos/
├── batch_generate_product_videos.py     # Main batch keyframe-based generation
├── download_from_s3.py                  # Download videos from S3
├── generate_video_with_keyframes.py     # Video generation with keyframes (recommended)
├── process_video.py                     # Python boomerang effect script
├── process_video.sh                     # Bash boomerang effect script
├── requirements.txt                     # Python dependencies
├── video_configs.json                   # Video configuration file
└── README.md                            # This file
```
