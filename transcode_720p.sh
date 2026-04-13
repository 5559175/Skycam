#!/bin/bash
# $1 = Full path to the input file

export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/local/cuda/lib64:$LD_LIBRARY_PATH

INPUT_FILE="$1"
OUTPUT_FILE="${INPUT_FILE%.mp4}_720p.mp4"

# Your specific CUDA hardware-accelerated command
ffmpeg -y -nostdin -hide_banner \
-hwaccel cuda \
-hwaccel_output_format cuda \
-fflags +genpts \
-c:v hevc_cuvid -resize 1280x720 -i "$INPUT_FILE" \
-c:v hevc_nvenc \
-preset p1 \
-rc constqp -qp 30 \
-spatial-aq 0 \
-temporal-aq 0 \
-nonref_p 1 \
-an \
-loglevel warning \
"$OUTPUT_FILE"

chown -R 1000 /export/media/skycam
