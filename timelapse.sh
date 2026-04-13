#!/bin/bash
# $1 = Full path to the input file

INPUT_FILE="$1"
OUTPUT_FILE="${INPUT_FILE%.mp4}_tl.mp4"

# Fast bitstream copy using only keyframes
ffmpeg -hide_banner -loglevel error -discard nokey -i "$INPUT_FILE" \
-c:v copy -bsf:v "setts=ts=N/20/TB" -an "$OUTPUT_FILE"
chown -R 1000 /export/media/skycam
