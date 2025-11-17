#!/usr/bin/env python3
"""
Video Processing Script
Creates a boomerang effect (forward + reverse) and speeds it up
Usage: python process_video.py <video_name_without_extension>
Example: python process_video.py watch_01
"""

import sys
import os
import ffmpeg


def process_video(video_name, base_dir="videos"):
    """Process video: reverse, concatenate, and speed up."""

    video_directory = base_dir
    input_file = os.path.join(video_directory, f"{video_name}.mp4")
    reversed_file = os.path.join(video_directory, f"{video_name}_reversed.mp4")
    combined_file = os.path.join(video_directory, f"{video_name}_combined.mp4")
    final_file = os.path.join(video_directory, f"{video_name}_final.mp4")
    list_file = "list.txt"

    # Check if input file exists
    if not os.path.exists(input_file):
        error_msg = f"Error: {input_file} not found"
        print(error_msg)
        raise FileNotFoundError(error_msg)

    print(f"Processing {input_file}...")

    try:
        # Step 1: Create reversed version
        print("Step 1/4: Creating reversed version...")
        (
            ffmpeg.input(input_file)
            .filter("reverse")
            .output(reversed_file, y=None)
            .run(quiet=True, overwrite_output=True)
        )

        # Step 2: Create concat list file
        print("Step 2/4: Creating concat list...")
        with open(list_file, "w") as f:
            f.write(f"file '{input_file}'\n")
            f.write(f"file '{reversed_file}'\n")

        # Step 3: Concatenate original and reversed
        print("Step 3/4: Concatenating videos...")
        (
            ffmpeg.input(list_file, format="concat", safe=0)
            .output(combined_file, c="copy")
            .run(quiet=True, overwrite_output=True)
        )

        # Step 4: Speed up to 75% (1.33x speed)
        print("Step 4/4: Applying speed adjustment...")
        (
            ffmpeg.input(combined_file)
            .filter("setpts", "0.75*PTS")
            .output(final_file, an=None)
            .run(quiet=True, overwrite_output=True)
        )

        # Clean up intermediate files
        print("Cleaning up intermediate files...")
        if os.path.exists(reversed_file):
            os.remove(reversed_file)
        if os.path.exists(combined_file):
            os.remove(combined_file)
        if os.path.exists(list_file):
            os.remove(list_file)

        print(f"Done! Output saved as {final_file}")

    except ffmpeg.Error as e:
        print(f"Error processing video: {e.stderr.decode() if e.stderr else str(e)}")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        sys.exit(1)


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Error: No video name provided")
        print(f"Usage: {sys.argv[0]} <video_name_without_extension>")
        print(f"Example: {sys.argv[0]} laptop")
        sys.exit(1)

    video_names = sys.argv[1:]
    for video_name in video_names:
        video_name = video_name.strip()
        process_video(video_name)


if __name__ == "__main__":
    main()
