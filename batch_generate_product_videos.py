#!/usr/bin/env python3
"""
Batch generate multiple product videos with keyframes using AWS Bedrock + Luma Ray
Processes a list of products with their start/end frame images
"""

import sys
import json
import time
import os
from generate_video_with_keyframes import generate_video_with_keyframes
from download_from_s3 import download_from_s3
from process_video import process_video


KEYFRAME_DIRECTORY = "keyframes"
VIDEO_DIRECTORY = "videos"


def load_video_configs(config_file="video_configs.json") -> list:
    """
    Load video configurations from JSON file.

    Args:
        config_file: Path to JSON config file

    Returns:
        List of keyframe-based video configurations
    """
    try:
        with open(config_file, "r") as f:
            configs = json.load(f)
        return configs.get("keyframe_based", [])
    except FileNotFoundError:
        print(f"Error: Config file '{config_file}' not found")
        print("Please create video_configs.json or specify path with --config")
        return []
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in config file: {e}")
        return []


def validate_config(config) -> tuple:
    """
    Validate that a config has all required fields and files exist.

    Args:
        config: Configuration dictionary

    Returns:
        Tuple of (is_valid, error_message)
    """
    required_fields = ["product_name", "prompt"]

    # Check required fields
    for field in required_fields:
        if field not in config:
            return False, f"Missing required field: {field}"

    # Check start frame exists
    start_frame_path = os.path.join(
        KEYFRAME_DIRECTORY, f"{config.get('product_name')}_start_frame.jpg"
    )
    end_frame_path = os.path.join(
        KEYFRAME_DIRECTORY, f"{config.get('product_name')}_end_frame.jpg"
    )

    if not os.path.exists(start_frame_path):
        return False, f"Start frame not found: {start_frame_path}"

    # Check end frame if specified
    if "end_frame" in config and config["end_frame"]:
        if not os.path.exists(end_frame_path):
            return False, f"End frame not found: {end_frame_path}"

    return True, None


def batch_generate_with_keyframes(
    configs,
    s3_bucket,
    region="us-west-2",
    delay_between=10,
) -> list:
    """
    Generate multiple videos with keyframes in sequence.

    Args:
        configs: List of video configuration dictionaries
        s3_bucket: S3 bucket for outputs
        region: AWS region
        delay_between: Seconds to wait between starting jobs

    Returns:
        List of results
    """

    results = []

    print("=" * 70)
    print(f"BATCH VIDEO GENERATION WITH KEYFRAMES - {len(configs)} videos")
    print("=" * 70)

    for i, config in enumerate(configs, 1):
        print(f"\n[{i}/{len(configs)}] Processing: {config['product_name']}")
        print("-" * 70)

        # # Check videos directory, if config["product_name"] + "_final.mp4" exists, skip
        # final_video_path = os.path.join(
        #     VIDEO_DIRECTORY, f"{config['product_name']}_final.mp4"
        # )
        # results.append(
        #     {
        #         "product_name": config["product_name"],
        #         "success": True,
        #         "output_uri": final_video_path,
        #     }
        # )

        # Validate configuration
        is_valid, error_msg = validate_config(config)
        if not is_valid:
            print(f"✗ Configuration error: {error_msg}")
            results.append(
                {
                    "product_name": config["product_name"],
                    "success": False,
                    "error": error_msg,
                }
            )
            continue

        try:
            start_frame_path = str(
                os.path.join(
                    KEYFRAME_DIRECTORY, f"{config.get('product_name')}_start_frame.jpg"
                )
            )
            end_frame_path = str(
                os.path.join(
                    KEYFRAME_DIRECTORY, f"{config.get('product_name')}_end_frame.jpg"
                )
            )

            output_uri = generate_video_with_keyframes(
                product_name=config["product_name"],
                prompt=config["prompt"],
                s3_bucket=s3_bucket,
                start_frame_path=start_frame_path,
                end_frame_path=end_frame_path,
                aspect_ratio=config.get("aspect_ratio", "16:9"),
                duration=config.get("duration", "5s"),
                resolution=config.get("resolution", "720p"),
                loop=config.get("loop", False),
                region=region,
            )

            results.append(
                {
                    "product_name": config["product_name"],
                    "success": output_uri is not None,
                    "output_uri": output_uri,
                    "start_frame": start_frame_path,
                    "end_frame": end_frame_path,
                }
            )

            # Optional delay between jobs
            if i < len(configs) and delay_between > 0:
                print(f"\nWaiting {delay_between}s before next job...\n")
                time.sleep(delay_between)

        except Exception as e:
            print(f"✗ Error processing {config['product_name']}: {str(e)}")
            results.append(
                {
                    "product_name": config["product_name"],
                    "success": False,
                    "error": str(e),
                }
            )

    # Print summary
    print("\n" + "=" * 70)
    print("BATCH GENERATION SUMMARY")
    print("=" * 70)

    successful = sum(1 for r in results if r["success"])
    failed = len(results) - successful

    print(f"Total: {len(results)} videos")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    print("\nResults:")

    for result in results:
        print(result)
        status = "✓" if result["success"] else "✗"
        print(f"{status} {result['product_name']}")
        if result["success"]:
            print(f"  → {result['output_uri']}")
            print(f"  Keyframes: {result['start_frame']}", end="")
            if result.get("end_frame"):
                print(f" → {result['end_frame']}")
            else:
                print()
        else:
            print(f"  → {result.get('error', 'Unknown error')}")

    print("=" * 70)

    return results


def parse_arguments() -> tuple:
    """
    Parse command line arguments and environment variables.

    Args:
        None

    Returns:
        Tuple of (config_file, s3_bucket)
    """
    # Check for --config argument
    s3_bucket = sys.argv[1]
    config_file = "video_configs.json"
    if "--config" in sys.argv:
        config_idx = sys.argv.index("--config")
        if config_idx + 1 < len(sys.argv):
            config_file = sys.argv[config_idx + 1]

    return config_file, s3_bucket


def download_videos(region, results) -> list:
    """
    Download videos from S3 for successful results.

    Args:
        region: AWS region
        results: List of generation results

    Returns:
        List of local video file paths
    """
    downloaded_videos = []
    for result in results:
        print(f"Downloading video for {result['product_name']}")
        if result["success"]:
            s3_uri = os.path.join(result["output_uri"], "output.mp4")
            local_path = os.path.join(VIDEO_DIRECTORY, f"{result['product_name']}.mp4")
            download_from_s3(s3_uri, local_path=local_path, region=region)
            downloaded_videos.append(local_path)
            print(f"output_uri: {s3_uri}")
            print(f"local_path: {local_path}")
        else:
            print("Skipping download due to generation failure.")
    print("\n" + "=" * 70)

    return downloaded_videos


def process_videos(downloaded_videos) -> list:
    """
    Process downloaded videos.

    Args:
        downloaded_videos: List of local video file paths
    Returns:
        List of processed video names
    """
    processed_videos = []
    for video_path in downloaded_videos:
        video_name = os.path.splitext(os.path.basename(video_path))[0]
        process_video(video_name)
        processed_videos.append(video_name)
    return processed_videos


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print(
            "Usage: python batch_generate_with_keyframes.py <s3_bucket> [--config CONFIG_FILE]"
        )
        print("\nExample:")
        print("  python batch_generate_with_keyframes.py my-product-videos-bucket")
        print(
            "  python batch_generate_with_keyframes.py my-bucket --config my_configs.json"
        )
        print(
            "\nThis will generate videos for all products defined in video_configs.json"
        )
        print("Make sure keyframe images exist in the current directory!")
        print("\nOptional arguments:")
        print("  --config FILE    Path to config file (default: video_configs.json)")
        print("\nOptional environment variables:")
        print("  AWS_REGION (default: us-west-2)")
        print("  DELAY_BETWEEN_JOBS (default: 30 seconds)")
        print("\nEdit video_configs.json to customize:")
        print("  - product_name")
        print("  - start_frame (path to start keyframe image)")
        print("  - end_frame (path to end keyframe image, optional)")
        print("  - prompt (motion description)")
        print("  - aspect_ratio, duration, resolution")
        sys.exit(1)

    # Load configurations from file
    config_file, s3_bucket = parse_arguments()

    print(f"Loading configurations from: {config_file}")
    VIDEO_CONFIGS = load_video_configs(config_file)

    if not VIDEO_CONFIGS:
        print("Error: No video configurations found")
        sys.exit(1)

    region = os.getenv("AWS_REGION", "us-west-2")
    delay = int(os.getenv("DELAY_BETWEEN_JOBS", "30"))

    print(f"\nS3 Bucket: {s3_bucket}")
    print(f"Region: {region}")
    print(f"Products to generate: {len(VIDEO_CONFIGS)}")
    print("\nKeyframe files required:")
    for config in VIDEO_CONFIGS:
        start_frame_path = os.path.join(
            KEYFRAME_DIRECTORY, f"{config.get('product_name')}_start_frame.jpg"
        )
        end_frame_path = os.path.join(
            KEYFRAME_DIRECTORY, f"{config.get('product_name')}_end_frame.jpg"
        )

        print(f"  - {start_frame_path}", end="")
        if end_frame_path:
            print(f" and {end_frame_path}")
        else:
            print(" (start frame only)")

    # Check if any files are missing
    missing_files = []
    for config in VIDEO_CONFIGS:
        start_frame_path = os.path.join(
            KEYFRAME_DIRECTORY, f"{config.get('product_name')}_start_frame.jpg"
        )
        end_frame_path = os.path.join(
            KEYFRAME_DIRECTORY, f"{config.get('product_name')}_end_frame.jpg"
        )

        if not os.path.exists(start_frame_path):
            missing_files.append(start_frame_path)
        if not os.path.exists(end_frame_path):
            missing_files.append(end_frame_path)

    if missing_files:
        print("\n⚠ Warning: Missing keyframe files:")
        for f in missing_files:
            print(f"  - {f}")
        print("\nSome videos will fail to generate.")

    # Confirm before proceeding
    response = input("\nProceed with batch generation? (y/n): ")
    if response.lower() != "y":
        print("Cancelled.")
        sys.exit(0)

    # Run batch generation
    video_generation_results = batch_generate_with_keyframes(
        configs=VIDEO_CONFIGS, s3_bucket=s3_bucket, region=region, delay_between=delay
    )

    # Download and process videos
    downloaded_videos = download_videos(region, video_generation_results)
    for dv in downloaded_videos:
        print(f"Downloaded video: {dv}")

    # Process videos
    processed_videos = process_videos(downloaded_videos)
    for pv in processed_videos:
        print(f"Processed video: {pv}")

    # Exit with error code if any failed
    failed_count = sum(1 for r in video_generation_results if not r["success"])
    sys.exit(1 if failed_count > 0 else 0)


if __name__ == "__main__":
    main()
