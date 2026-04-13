#!/bin/bash
# $1 = Duration in decimal hours
# $2 = Mode (optional, "auto-detect-meteors" triggers pipeline)

MODE="$2"
SECONDS=$(echo "$1 * 3600 / 1" | bc)

DATE_VAL=$(date +%Y%m%d)
TIME_VAL=$(date +%H%M%S)
FINAL_DIR="/export/media/skycam/$DATE_VAL"
TEMP_FILE="$FINAL_DIR/capture_${TIME_VAL}.ts"
OUTPUT_FILE="$FINAL_DIR/capture_${TIME_VAL}.mp4"

mkdir -p "$FINAL_DIR"

# Web App Fix: Create symlink
ln -s "$TEMP_FILE" "$OUTPUT_FILE"

finalize_video() {
    if [ ! -z "$FFMPEG_PID" ]; then
        kill -TERM "$FFMPEG_PID" 2>/dev/null
        wait "$FFMPEG_PID" 2>/dev/null
    fi

    if [ -f "$TEMP_FILE" ]; then
        rm -f "$OUTPUT_FILE"
        ffmpeg -hide_banner -y -loglevel error \
        -i "$TEMP_FILE" -c copy \
        -video_track_timescale 25 \
        -fflags +genpts+igndts \
        -avoid_negative_ts make_zero \
        -movflags +faststart \
        "$OUTPUT_FILE" && rm "$TEMP_FILE"
    fi

    chown -R 1000 /export/media/skycam

    # Conditional Pipeline Trigge
    if [ "$MODE" == "auto-detect-meteors" ]; then
        /bin/bash /app/pipeline.sh "$OUTPUT_FILE" "$DATE_VAL" &
    fi

    exit 0
}

trap finalize_video SIGTERM SIGINT

ffmpeg -hide_banner -y -loglevel error \
-rtsp_transport tcp \
-timeout 30000000 \
-use_wallclock_as_timestamps 1 \
-i "rtsp://user:pass@ip.of.camera:554/h265Preview_01_main" \
-t "$SECONDS" \
-vcodec copy -an \
-f mpegts \
"$TEMP_FILE" &

FFMPEG_PID=$!
wait $FFMPEG_PID
finalize_video
