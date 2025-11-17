#!/usr/bin/env python3
"""
Download generated videos from S3
"""

import boto3
import os
import sys
from urllib.parse import urlparse


def download_from_s3(s3_uri, local_path=None, region="us-west-2"):
    """
    Download a file from S3.

    Args:
        s3_uri: S3 URI (e.g., s3://bucket/path/to/file.mp4 or s3://bucket/path/to/directory/)
        local_path: Local destination path (optional, uses filename if not specified)
        region: AWS region

    Returns:
        Local file path if successful, None otherwise
    """

    try:
        # Parse S3 URI
        parsed = urlparse(s3_uri)
        bucket = parsed.netloc
        key = parsed.path.lstrip("/")

        # Initialize S3 client
        s3 = boto3.client("s3", region_name=region)

        # If the key doesn't end with .mp4, it might be a prefix/directory
        # List objects with that prefix and find the video file
        if not key.endswith(".mp4"):
            print("URI appears to be a directory, looking for video file...")
            print(f"  Bucket: {bucket}")
            print(f"  Prefix: {key}")

            # Ensure prefix ends with /
            prefix = key if key.endswith("/") else key + "/"

            # List objects with this prefix
            response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)

            if "Contents" not in response:
                raise Exception(f"No files found at prefix: {prefix}")

            # Find the .mp4 file
            video_file = None
            for obj in response["Contents"]:
                if obj["Key"].endswith(".mp4"):
                    video_file = obj["Key"]
                    break

            if not video_file:
                raise Exception(f"No .mp4 file found at prefix: {prefix}")

            key = video_file
            print(f"  Found video: {key}")

        # Determine local filename
        if local_path is None:
            local_path = os.path.basename(key)

        print("\nDownloading from S3...")
        print(f"  Bucket: {bucket}")
        print(f"  Key: {key}")
        print(f"  Local: {local_path}")

        # Download file
        s3.download_file(bucket, key, local_path)

        file_size = os.path.getsize(local_path)
        print("\n✓ Downloaded successfully!")
        print(f"  Size: {file_size:,} bytes")
        print(f"  Path: {local_path}")

        return local_path

    except Exception as e:
        print(f"\n✗ Error downloading: {str(e)}")
        return None


def upload_to_s3(local_path, s3_uri, region="us-west-2"):
    """
    Upload a file to S3.

    Args:
        local_path: Local file path to upload
        s3_uri: Destination S3 URI (e.g., s3://bucket/path/to/file.mp4)
        region: AWS region

    Returns:
        S3 URI if successful, None otherwise
    """

    try:
        # Check if local file exists
        if not os.path.exists(local_path):
            print(f"Error: Local file not found: {local_path}")
            return None

        # Parse S3 URI
        parsed = urlparse(s3_uri)
        bucket = parsed.netloc
        key = parsed.path.lstrip("/")

        # Initialize S3 client
        s3 = boto3.client("s3", region_name=region)

        file_size = os.path.getsize(local_path)
        print("Uploading to S3...")
        print(f"  Local: {local_path}")
        print(f"  Size: {file_size:,} bytes")
        print(f"  Bucket: {bucket}")
        print(f"  Key: {key}")

        # Upload file
        s3.upload_file(local_path, bucket, key)

        print("\n✓ Uploaded successfully!")
        print(f"  S3 URI: {s3_uri}")

        return s3_uri

    except Exception as e:
        print(f"\n✗ Error uploading: {str(e)}")
        return None


def list_videos_in_bucket(s3_bucket, prefix="product-videos/", region="us-west-2"):
    """
    List all videos in an S3 bucket with a given prefix.

    Args:
        s3_bucket: S3 bucket name
        prefix: S3 key prefix
        region: AWS region

    Returns:
        List of S3 URIs
    """

    try:
        s3 = boto3.client("s3", region_name=region)

        print(f"Listing videos in s3://{s3_bucket}/{prefix}")
        print("-" * 70)

        paginator = s3.get_paginator("list_objects_v2")
        videos = []

        for page in paginator.paginate(Bucket=s3_bucket, Prefix=prefix):
            if "Contents" not in page:
                continue

            for obj in page["Contents"]:
                key = obj["Key"]
                if key.endswith(".mp4"):
                    s3_uri = f"s3://{s3_bucket}/{key}"
                    videos.append(
                        {
                            "uri": s3_uri,
                            "key": key,
                            "size": obj["Size"],
                            "modified": obj["LastModified"],
                        }
                    )

        # Sort by modified date (newest first)
        videos.sort(key=lambda x: x["modified"], reverse=True)

        if not videos:
            print("No videos found.")
            return []

        print(f"Found {len(videos)} video(s):\n")
        for i, video in enumerate(videos, 1):
            size_mb = video["size"] / (1024 * 1024)
            print(f"{i}. {video['key']}")
            print(f"   Size: {size_mb:.2f} MB")
            print(f"   Modified: {video['modified']}")
            print(f"   URI: {video['uri']}")
            print()

        return videos

    except Exception as e:
        print(f"✗ Error listing videos: {str(e)}")
        return []


def main():
    """Main entry point."""

    if len(sys.argv) < 2:
        print("Usage:")
        print("  # Download a specific video")
        print("  python download_from_s3.py <s3_uri> [local_path]")
        print()
        print("  # List all videos in bucket")
        print("  python download_from_s3.py --list <s3_bucket> [prefix]")
        print()
        print("Examples:")
        print(
            '  python download_from_s3.py "s3://my-bucket/product-videos/watch_01/video.mp4"'
        )
        print(
            '  python download_from_s3.py "s3://my-bucket/path/video.mp4" my_video.mp4'
        )
        print("  python download_from_s3.py --list my-bucket product-videos/")
        sys.exit(1)

    if sys.argv[1] == "--list":
        # List mode
        if len(sys.argv) < 3:
            print("Error: Bucket name required for --list")
            sys.exit(1)

        bucket = sys.argv[2]
        prefix = sys.argv[3] if len(sys.argv) > 3 else "product-videos/"

        videos = list_videos_in_bucket(bucket, prefix)

        if videos:
            print("\nTo download a video, use:")
            print('  python download_from_s3.py "s3://..." [local_path]')

    else:
        # Download mode
        s3_uri = sys.argv[1]
        local_path = sys.argv[2] if len(sys.argv) > 2 else None

        result = download_from_s3(s3_uri, local_path)

        if result:
            sys.exit(0)
        else:
            sys.exit(1)


if __name__ == "__main__":
    main()
