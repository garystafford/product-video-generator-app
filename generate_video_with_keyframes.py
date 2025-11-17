#!/usr/bin/env python3
"""
Generate product videos with keyframes using AWS Bedrock + Luma Ray
Uses start and end frame images to control video generation
"""

import boto3
import time
import sys
import base64
import os
from datetime import datetime


def encode_image_to_base64(image_path):
    """
    Encode an image file to base64 string.

    Args:
        image_path: Path to image file

    Returns:
        Base64 encoded string
    """
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")


def get_image_media_type(image_path):
    """
    Determine media type from file extension.

    Args:
        image_path: Path to image file

    Returns:
        Media type string (e.g., 'image/jpeg', 'image/png')
    """
    ext = os.path.splitext(image_path)[1].lower()
    media_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }
    return media_types.get(ext, "image/jpeg")


def generate_video_with_keyframes(
    product_name,
    prompt,
    s3_bucket,
    start_frame_path,
    end_frame_path=None,
    aspect_ratio="16:9",
    duration="5s",
    resolution="720p",
    loop=False,
    region="us-west-2",
):
    """
    Generate a product video using keyframes (start and optionally end frame).

    Args:
        product_name: Name of the product
        prompt: Text description of desired video motion
        s3_bucket: S3 bucket for output
        start_frame_path: Path to start keyframe image
        end_frame_path: Path to end keyframe image (optional)
        aspect_ratio: Video aspect ratio
        duration: Video duration (5s or 10s)
        resolution: Video resolution (720p or 540p)
        loop: Whether to create a looping video
        region: AWS region

    Returns:
        S3 URI of generated video or None if failed
    """

    try:
        # print(f"Start time: {datetime.now().isoformat()}")
        # Validate files exist
        if not os.path.exists(start_frame_path):
            print(f"Error: Start frame not found: {start_frame_path}")
            return None

        if end_frame_path and not os.path.exists(end_frame_path):
            print(f"Error: End frame not found: {end_frame_path}")
            return None

        # Initialize Bedrock Runtime client
        bedrock = boto3.client("bedrock-runtime", region_name=region)

        # Encode images to base64
        print("Encoding keyframe images...")
        start_frame_data = encode_image_to_base64(start_frame_path)
        start_media_type = get_image_media_type(start_frame_path)

        # Build keyframes object
        keyframes = {
            "frame0": {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": start_media_type,
                    "data": start_frame_data,
                },
            }
        }

        # Add end frame if provided
        if end_frame_path:
            end_frame_data = encode_image_to_base64(end_frame_path)
            end_media_type = get_image_media_type(end_frame_path)
            keyframes["frame1"] = {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": end_media_type,
                    "data": end_frame_data,
                },
            }

        # Prepare output path
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_prefix = f"product-videos/{product_name}/{timestamp}/"

        # Build request body
        model_input = {
            "prompt": prompt,
            "keyframes": keyframes,
            "loop": loop,
            "aspect_ratio": aspect_ratio,
        }

        # Add optional parameters
        if duration:
            model_input["duration"] = duration
        if resolution:
            model_input["resolution"] = resolution

        request_body = {
            "modelInput": model_input,
            "outputDataConfig": {
                "s3OutputDataConfig": {"s3Uri": f"s3://{s3_bucket}/{output_prefix}"}
            },
        }

        print("=" * 70)
        print("LUMA RAY VIDEO GENERATION WITH KEYFRAMES")
        print("=" * 70)
        print(f"Product: {product_name}")
        print(f"Prompt: {prompt}")
        print(f"Start frame: {start_frame_path}")
        if end_frame_path:
            print(f"End frame: {end_frame_path}")
        print(f"Settings: {aspect_ratio}, {duration}, {resolution}")
        print(f"Output bucket: s3://{s3_bucket}/{output_prefix}")
        print("=" * 70)

        # Start async generation
        print("\nStarting video generation...")
        response = bedrock.start_async_invoke(
            modelId="luma.ray-v2:0",
            modelInput=request_body["modelInput"],
            outputDataConfig=request_body["outputDataConfig"],
        )

        invocation_arn = response["invocationArn"]
        print(f"Invocation ARN: {invocation_arn}")
        print("\nMonitoring progress (this may take several minutes)...\n")

        # Monitor progress
        start_time = time.time()
        last_status = None

        while True:
            status_response = bedrock.get_async_invoke(invocationArn=invocation_arn)

            current_status = status_response["status"]
            elapsed = int(time.time() - start_time)

            if current_status != last_status:
                print(f"[{elapsed}s] Status: {current_status}")
                last_status = current_status

            if current_status == "Completed":
                output_uri = status_response["outputDataConfig"]["s3OutputDataConfig"][
                    "s3Uri"
                ]
                print("\n" + "=" * 70)
                print("✓ SUCCESS!")
                print("=" * 70)
                print(f"Video generated in {elapsed} seconds")
                print(f"Output location: {output_uri}")
                print("=" * 70)
                # print(f"End time: {datetime.now().isoformat()}")
                return output_uri

            elif current_status == "Failed":
                error = status_response.get("failureMessage", "Unknown error")
                print("\n" + "=" * 70)
                print("✗ FAILED")
                print("=" * 70)
                print(f"Error: {error}")
                print("=" * 70)
                return None

            time.sleep(15)

    except Exception as e:
        print(f"\n✗ Error: {str(e)}")
        return None


def main():
    """Main entry point."""

    if len(sys.argv) < 5:
        print(
            "Usage: python generate_video_with_keyframes.py <product_name> <s3_bucket> \\"
        )
        print("         <start_frame_path> <end_frame_path> <prompt>")
        print("\nOr with single frame:")
        print(
            "       python generate_video_with_keyframes.py <product_name> <s3_bucket> \\"
        )
        print("         <start_frame_path> - <prompt>")
        print("\nExamples:")
        print("  # With start and end frames")
        print("  python generate_video_with_keyframes.py watch_01 my-bucket \\")
        print("    watch_01_start.jpg watch_01_end.jpg \\")
        print('    "Smooth rotation from start to end position"')
        print()
        print("  # With only start frame")
        print("  python generate_video_with_keyframes.py watch_01 my-bucket \\")
        print("    watch_01_start.jpg - \\")
        print('    "Camera slowly orbits around the watch"')
        print("\nOptional environment variables:")
        print("  AWS_REGION (default: us-west-2)")
        print("  ASPECT_RATIO (default: 16:9)")
        print("  DURATION (default: 5s)")
        print("  RESOLUTION (default: 720p)")
        print("  LOOP (default: false)")
        sys.exit(1)

    product_name = sys.argv[1]
    s3_bucket = sys.argv[2]
    start_frame = sys.argv[3]
    end_frame = sys.argv[4] if sys.argv[4] != "-" else None
    prompt = sys.argv[5] if len(sys.argv) > 5 else sys.argv[4]

    # If end_frame was "-", shift prompt
    if end_frame is None and len(sys.argv) > 5:
        prompt = sys.argv[5]
    elif end_frame is None:
        prompt = sys.argv[4]

    # Get optional parameters from environment
    import os

    aspect_ratio = os.getenv("ASPECT_RATIO", "16:9")
    duration = os.getenv("DURATION", "5s")
    resolution = os.getenv("RESOLUTION", "720p")
    loop = os.getenv("LOOP", "false").lower() == "true"
    region = os.getenv("AWS_REGION", "us-west-2")

    # Generate video
    output_uri = generate_video_with_keyframes(
        product_name=product_name,
        prompt=prompt,
        s3_bucket=s3_bucket,
        start_frame_path=start_frame,
        end_frame_path=end_frame,
        aspect_ratio=aspect_ratio,
        duration=duration,
        resolution=resolution,
        loop=loop,
        region=region,
    )

    if output_uri:
        print(
            f'\nTo download: python download_from_s3.py "{output_uri}" {product_name}.mp4'
        )
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
