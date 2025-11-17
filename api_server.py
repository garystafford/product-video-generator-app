"""
FastAPI server for product video generation UI
Provides REST API endpoints for keyframe upload, video generation, progress tracking, and results
"""

import sys
import os
from fastapi import FastAPI, File, UploadFile, BackgroundTasks, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional
import uuid
from datetime import datetime
from pathlib import Path
import asyncio
from enum import Enum
import json

# Import existing video processing functions
from generate_video_with_keyframes import generate_video_with_keyframes
from download_from_s3 import download_from_s3, upload_to_s3
from process_video import process_video

app = FastAPI(title="Product Video Generator API")

# CORS middleware for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Directory setup - use /app/data as base (EFS mount point in ECS) unless "local" arg is given
BASE_DIR = Path("/app/data")

if len(sys.argv) > 1:
    if sys.argv[1] == "local":
        print("Running in local mode, using ./app/data as base directory")
        BASE_DIR = Path("./app/data")
else:
    print("No arguments provided!")

KEYFRAMES_DIR = BASE_DIR / "keyframes"
VIDEOS_DIR = BASE_DIR / "videos"
DATA_DIR = BASE_DIR
KEYFRAMES_DIR.mkdir(exist_ok=True, parents=True)
VIDEOS_DIR.mkdir(exist_ok=True, parents=True)

# Database file path
DB_FILE = DATA_DIR / "database.json"

# In-memory job store (persisted to JSON)
jobs_db = {}
videos_db = {}
keyframes_db = {}  # Maps product_name -> {start_frame: path, end_frame: path}


def save_database():
    """Save jobs, videos, and keyframes databases to JSON file."""
    try:
        data = {
            "jobs": jobs_db,
            "videos": videos_db,
            "keyframes": keyframes_db,
            "last_updated": datetime.now().isoformat(),
        }
        with open(DB_FILE, "w") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print(f"Error saving database: {e}")


def load_database():
    """Load jobs, videos, and keyframes databases from JSON file."""
    global jobs_db, videos_db, keyframes_db
    try:
        if DB_FILE.exists():
            with open(DB_FILE, "r") as f:
                data = json.load(f)
                jobs_db = data.get("jobs", {})
                videos_db = data.get("videos", {})
                keyframes_db = data.get("keyframes", {})
                print(
                    f"Loaded {len(jobs_db)} jobs, {len(videos_db)} videos, and {len(keyframes_db)} keyframe mappings from database"
                )
        else:
            print("No existing database found, starting fresh")
    except Exception as e:
        print(f"Error loading database: {e}")
        jobs_db = {}
        videos_db = {}
        keyframes_db = {}


class JobStatus(str, Enum):
    PENDING = "pending"
    UPLOADING = "uploading"
    GENERATING = "generating"
    DOWNLOADING = "downloading"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class VideoSettings(BaseModel):
    aspect_ratio: str = "16:9"
    duration: str = "5s"
    resolution: str = "720p"
    loop: bool = False
    region: str = "us-west-2"


class VideoGenerationRequest(BaseModel):
    product_name: str
    prompt: str
    s3_bucket: str
    settings: VideoSettings


class Job(BaseModel):
    job_id: str
    product_name: str
    status: JobStatus
    progress: int
    message: str
    created_at: str
    updated_at: str
    video_url: Optional[str] = None
    error: Optional[str] = None


class VideoInfo(BaseModel):
    video_id: str
    product_name: str
    prompt: str
    status: str
    created_at: str
    final_video_path: Optional[str] = None
    original_video_path: Optional[str] = None
    start_keyframe: Optional[str] = None
    end_keyframe: Optional[str] = None
    s3_uri: Optional[str] = None


# Startup event to load database
@app.on_event("startup")
async def startup_event():
    """Load database on application startup"""
    load_database()


def create_job(product_name: str) -> str:
    """Create a new job and return job ID"""
    job_id = str(uuid.uuid4())
    timestamp = datetime.now().isoformat()

    jobs_db[job_id] = {
        "job_id": job_id,
        "product_name": product_name,
        "status": JobStatus.PENDING,
        "progress": 0,
        "message": "Job created",
        "created_at": timestamp,
        "updated_at": timestamp,
        "video_url": None,
        "error": None,
    }

    save_database()
    return job_id


def update_job(
    job_id: str,
    status: JobStatus,
    progress: int,
    message: str,
    error: Optional[str] = None,
):
    """Update job status and progress"""
    if job_id in jobs_db:
        jobs_db[job_id]["status"] = status
        jobs_db[job_id]["progress"] = progress
        jobs_db[job_id]["message"] = message
        jobs_db[job_id]["updated_at"] = datetime.now().isoformat()
        if error:
            jobs_db[job_id]["error"] = error
        save_database()


async def process_video_generation(
    job_id: str,
    product_name: str,
    prompt: str,
    s3_bucket: str,
    start_frame_path: str,
    end_frame_path: Optional[str],
    settings: VideoSettings,
):
    """Background task to generate and process video"""
    try:
        # Update status: Generating
        update_job(
            job_id, JobStatus.GENERATING, 10, "Generating video with AWS Bedrock..."
        )

        # Generate video using existing function
        s3_uri = await asyncio.to_thread(
            generate_video_with_keyframes,
            product_name=product_name,
            prompt=prompt,
            s3_bucket=s3_bucket,
            start_frame_path=start_frame_path,
            end_frame_path=end_frame_path,
            aspect_ratio=settings.aspect_ratio,
            duration=settings.duration,
            resolution=settings.resolution,
            loop=settings.loop,
            region=settings.region,
        )

        if not s3_uri:
            raise Exception("Video generation failed - no S3 URI returned")

        update_job(
            job_id,
            JobStatus.DOWNLOADING,
            50,
            "Video generated! Downloading from S3...",
        )

        # Download video from S3 - use job_id for unique naming
        job_id_short = job_id[:8]
        video_base_name = f"{product_name}_{job_id_short}"
        output_path = str(VIDEOS_DIR / f"{video_base_name}.mp4")
        await asyncio.to_thread(download_from_s3, s3_uri, output_path)

        update_job(job_id, JobStatus.PROCESSING, 70, "Applying boomerang effect...")

        # Apply boomerang effect
        await asyncio.to_thread(
            process_video, video_base_name, base_dir=str(VIDEOS_DIR)
        )

        final_video_path = str(VIDEOS_DIR / f"{video_base_name}_final.mp4")

        # Upload final video to S3
        update_job(job_id, JobStatus.PROCESSING, 90, "Uploading final video to S3...")
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        final_s3_key = (
            f"product-videos/{product_name}/{timestamp}/{video_base_name}_final.mp4"
        )
        final_s3_uri = f"s3://{s3_bucket}/{final_s3_key}"

        uploaded_s3_uri = await asyncio.to_thread(
            upload_to_s3, final_video_path, final_s3_uri, settings.region
        )

        # Update job as completed
        jobs_db[job_id]["video_url"] = f"/api/videos/download/{job_id}"
        update_job(job_id, JobStatus.COMPLETED, 100, "Video processing completed!")

        # Store video info - use job_id as unique key
        videos_db[job_id] = {
            "video_id": job_id,
            "product_name": product_name,
            "prompt": prompt,
            "status": "completed",
            "created_at": jobs_db[job_id]["created_at"],
            "final_video_path": final_video_path,
            "original_video_path": output_path,
            "start_keyframe": start_frame_path,
            "end_keyframe": end_frame_path,
            "job_id": job_id,
            "s3_uri": uploaded_s3_uri,
        }
        save_database()

    except Exception as e:
        error_msg = str(e)
        print(f"ERROR in job {job_id}: {error_msg}")
        import traceback

        traceback.print_exc()
        update_job(job_id, JobStatus.FAILED, 0, f"Error: {error_msg}", error_msg)


@app.get("/")
async def root():
    """Root endpoint"""
    return {"message": "Product Video Generator API", "version": "1.0.0"}


@app.post("/api/keyframes/upload")
async def upload_keyframes(
    product_name: str = Form(...),
    start_frame: UploadFile = File(...),
    end_frame: Optional[UploadFile] = File(None),
):
    """Upload start and end keyframe images and associate them with a product name"""
    try:
        # Validate file types
        allowed_types = ["image/jpeg", "image/png", "image/webp"]

        if start_frame.content_type not in allowed_types:
            raise HTTPException(
                400, f"Invalid start frame type: {start_frame.content_type}"
            )

        if end_frame and end_frame.content_type not in allowed_types:
            raise HTTPException(
                400, f"Invalid end frame type: {end_frame.content_type}"
            )

        # Generate unique filenames to avoid collisions
        start_ext = (
            start_frame.filename.split(".")[-1]
            if "." in start_frame.filename
            else "jpg"
        )
        start_filename = f"{uuid.uuid4()}.{start_ext}"
        start_path = KEYFRAMES_DIR / start_filename

        with open(start_path, "wb") as f:
            content = await start_frame.read()
            f.write(content)

        # Save end frame if provided
        end_path = None
        if end_frame:
            end_ext = (
                end_frame.filename.split(".")[-1]
                if "." in end_frame.filename
                else "jpg"
            )
            end_filename = f"{uuid.uuid4()}.{end_ext}"
            end_path = KEYFRAMES_DIR / end_filename

            with open(end_path, "wb") as f:
                content = await end_frame.read()
                f.write(content)

        # Store mapping in database
        keyframes_db[product_name] = {
            "start_frame": str(start_path),
            "end_frame": str(end_path) if end_path else None,
            "uploaded_at": datetime.now().isoformat(),
        }
        save_database()

        return {
            "success": True,
            "product_name": product_name,
            "start_frame": str(start_path),
            "end_frame": str(end_path) if end_path else None,
        }

    except Exception as e:
        raise HTTPException(500, f"Upload failed: {str(e)}")


@app.get("/api/keyframes/list")
async def list_keyframes():
    """List all available keyframes grouped by product"""
    try:
        # Read from keyframes database
        products = []
        for product_name, data in keyframes_db.items():
            products.append(
                {
                    "product_name": product_name,
                    "start_frame": data.get("start_frame"),
                    "end_frame": data.get("end_frame"),
                    "uploaded_at": data.get("uploaded_at"),
                }
            )

        return {"success": True, "products": products, "count": len(products)}

    except Exception as e:
        raise HTTPException(500, f"Failed to list keyframes: {str(e)}")


@app.post("/api/videos/generate")
async def generate_video(
    background_tasks: BackgroundTasks, request: VideoGenerationRequest
):
    """Start video generation process"""
    try:
        product_name = request.product_name

        # Look up keyframes from database
        if product_name not in keyframes_db:
            # Get list of available products for helpful error message
            available_list = (
                ", ".join(sorted(keyframes_db.keys())) if keyframes_db else "none"
            )
            raise HTTPException(
                400,
                f"No keyframes found for product: {product_name}. "
                f"Please upload keyframes with this product name first. "
                f"Available products: {available_list}",
            )

        keyframe_data = keyframes_db[product_name]
        start_frame_path = keyframe_data.get("start_frame")
        end_frame_path = keyframe_data.get("end_frame")

        if not start_frame_path:
            raise HTTPException(
                400,
                f"No start frame found for product: {product_name}. "
                f"Please upload keyframes.",
            )

        # Create job
        job_id = create_job(product_name)

        # Add background task
        background_tasks.add_task(
            process_video_generation,
            job_id=job_id,
            product_name=product_name,
            prompt=request.prompt,
            s3_bucket=request.s3_bucket,
            start_frame_path=start_frame_path,
            end_frame_path=end_frame_path,
            settings=request.settings,
        )

        return {
            "success": True,
            "job_id": job_id,
            "message": "Video generation started",
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to start generation: {str(e)}")


@app.get("/api/jobs/{job_id}")
async def get_job_status(job_id: str):
    """Get job status and progress"""
    if job_id not in jobs_db:
        raise HTTPException(404, "Job not found")

    return jobs_db[job_id]


@app.get("/api/jobs")
async def list_jobs():
    """List all jobs"""
    return {"jobs": list(jobs_db.values())}


@app.get("/api/videos")
async def list_videos():
    """List all generated videos"""
    return {"videos": list(videos_db.values())}


@app.get("/api/videos/{video_id}")
async def get_video_info(video_id: str):
    """Get video information by video_id (job_id)"""
    if video_id not in videos_db:
        raise HTTPException(404, "Video not found")

    return videos_db[video_id]


@app.get("/api/videos/download/{video_id}")
async def download_final_video(video_id: str, original: bool = False):
    """Download the final processed video or original by video_id (job_id)"""
    if video_id not in videos_db:
        raise HTTPException(404, "Video not found")

    video_info = videos_db[video_id]

    if original:
        video_path = Path(video_info["original_video_path"])
    else:
        video_path = Path(video_info["final_video_path"])

    if not video_path.exists():
        raise HTTPException(404, "Video file not found")

    # Use product name in filename for download
    product_name = video_info["product_name"]
    download_filename = (
        f"{product_name}_final.mp4" if not original else f"{product_name}.mp4"
    )

    return FileResponse(
        path=video_path, media_type="video/mp4", filename=download_filename
    )


@app.get("/api/keyframes/{product_name}/{frame_type}")
async def get_keyframe(product_name: str, frame_type: str):
    """Get keyframe image (start or end)"""
    if frame_type not in ["start", "end"]:
        raise HTTPException(400, "Invalid frame type. Use 'start' or 'end'")

    # Look up keyframe from database
    if product_name not in keyframes_db:
        raise HTTPException(404, f"No keyframes found for product: {product_name}")

    keyframe_data = keyframes_db[product_name]
    keyframe_path_str = keyframe_data.get(f"{frame_type}_frame")

    if not keyframe_path_str:
        raise HTTPException(
            404, f"No {frame_type} frame found for product: {product_name}"
        )

    keyframe_path = Path(keyframe_path_str)

    if not keyframe_path.exists():
        raise HTTPException(404, f"Keyframe file not found: {keyframe_path}")

    return FileResponse(
        path=keyframe_path, media_type=f"image/{keyframe_path.suffix[1:]}"
    )


@app.delete("/api/videos/{video_id}")
async def delete_video(video_id: str):
    """Delete video and associated files by video_id (job_id)"""
    try:
        # Get video info before deleting
        if video_id not in videos_db:
            raise HTTPException(404, "Video not found")

        video_info = videos_db[video_id]
        product_name = video_info["product_name"]

        # Remove from database
        del videos_db[video_id]
        save_database()

        # Remove video files
        for path_str in [
            video_info["original_video_path"],
            video_info["final_video_path"],
        ]:
            video_path = Path(path_str)
            if video_path.exists():
                video_path.unlink()

        return {"success": True, "message": f"Video {product_name} deleted"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Delete failed: {str(e)}")


@app.get("/api/config/options")
async def get_config_options():
    """Get available configuration options"""
    return {
        "aspect_ratios": ["1:1", "4:3", "3:4", "16:9", "9:16", "21:9"],
        "durations": ["5s", "10s"],
        "resolutions": ["720p", "540p"],
        "regions": ["us-west-2", "us-east-1", "eu-west-1"],
    }


@app.get("/api/config/environment")
async def get_environment_config():
    """Get environment configuration"""
    s3_bucket = os.getenv("S3_BUCKET_NAME", "")
    print(f"DEBUG: S3_BUCKET_NAME environment variable = '{s3_bucket}'")
    return {"s3_bucket_name": s3_bucket}


@app.get("/api/keyframes/available")
async def get_available_keyframes():
    """List all available keyframe sets"""
    try:
        # Find all start frame files
        start_frames = list(KEYFRAMES_DIR.glob("*_start_frame.*"))

        keyframe_sets = []
        seen_prefixes = set()

        for start_frame in start_frames:
            # Extract prefix (everything before _start_frame)
            filename = start_frame.stem  # e.g., "watch_02_start_frame"
            prefix = filename.replace("_start_frame", "")  # e.g., "watch_02"

            if prefix in seen_prefixes:
                continue
            seen_prefixes.add(prefix)

            # Look for matching end frame
            end_frame_candidates = list(KEYFRAMES_DIR.glob(f"{prefix}_end_frame.*"))
            has_end_frame = len(end_frame_candidates) > 0

            # Extract base product name (first part before underscore)
            parts = prefix.split("_")
            base_product = parts[0] if parts else prefix

            keyframe_sets.append(
                {
                    "prefix": prefix,
                    "product_name": base_product,
                    "display_name": prefix.replace("_", " ").title(),
                    "has_start_frame": True,
                    "has_end_frame": has_end_frame,
                    "start_frame_path": str(start_frame),
                    "end_frame_path": (
                        str(end_frame_candidates[0]) if has_end_frame else None
                    ),
                }
            )

        # Sort by prefix
        keyframe_sets.sort(key=lambda x: x["prefix"])

        return {"keyframe_sets": keyframe_sets}

    except Exception as e:
        raise HTTPException(500, f"Failed to list keyframes: {str(e)}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
