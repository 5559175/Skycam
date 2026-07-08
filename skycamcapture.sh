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
ln -s "$TEMP_FILE" "$OUTPUT_FILE"

# 0 = Run Pipeline, 1 = Skip Pipeline
SKIP_PIPELINE=0

finalize_video() {
    # If called via SIGUSR1 (Stop All), skip the pipeline
    if [ "$1" == "HARD_STOP" ]; then
        SKIP_PIPELINE=1
    fi

    # Kill FFmpeg immediately
    if [ ! -z "$FFMPEG_PID" ]; then
        kill -TERM "$FFMPEG_PID" 2>/dev/null
        wait "$FFMPEG_PID" 2>/dev/null
    fi

    # Only convert if the file actually has data (> 0 bytes)
    if [ -s "$TEMP_FILE" ]; then
        rm -f "$OUTPUT_FILE"
        ffmpeg -hide_banner -y -loglevel error \
        -i "$TEMP_FILE" -c copy \
        -video_track_timescale 25 \
        -fflags +genpts+igndts \
        -avoid_negative_ts make_zero \
        -movflags +faststart \
        "$OUTPUT_FILE"
    fi

    # CLEANUP: Always remove the .ts and the broken symlink if conversion failed
    rm -f "$TEMP_FILE"
    [ ! -s "$OUTPUT_FILE" ] && rm -f "$OUTPUT_FILE"
    
    chown -R 1000 /export/media/skycam

    # Trigger pipeline only if NOT skipping
    if [ "$MODE" == "auto-detect-meteors" ] && [ "$SKIP_PIPELINE" -eq 0 ]; then
        /bin/bash /app/pipeline.sh "$OUTPUT_FILE" "$DATE_VAL" &
    fi

    exit 0
}

# --- SIGNAL HANDLING ---
# SIGTERM (Stop) -> Runs pipeline
trap 'finalize_video' SIGTERM 
# SIGUSR1 (Stop All) -> Skips pipeline
trap 'finalize_video HARD_STOP' SIGUSR1
# SIGINT (Ctrl+C) -> Runs pipeline
trap 'finalize_video' SIGINT

START_EPOCH=$(date +%s)
END_EPOCH=$(( START_EPOCH + SECONDS ))

while [ $(date +%s) -lt $END_EPOCH ]; do
    REMAINING=$(( END_EPOCH - $(date +%s) ))
    [ $REMAINING -le 0 ] && break

    # Append output to survive network drops without wiping file
    ffmpeg -hide_banner -loglevel error \
    -rtsp_transport tcp \
    -timeout 30000000 \
    -use_wallclock_as_timestamps 1 \
    -i "rtsp://admin:password@camera.ip:554/h265Preview_01_main" \
    -t "$REMAINING" \
    -vcodec copy -an \
    -f mpegts - >> "$TEMP_FILE" &

    FFMPEG_PID=$!
    wait $FFMPEG_PID
    
    # Check if we should reconnect (if more than 10s left)
    if [ $(date +%s) -lt $(( END_EPOCH - 10 )) ]; then
        echo "$(date): Connection lost. Reconnecting..." >> "$FINAL_DIR/reconnect.log"
        sleep 5
    else
        break
    fi
done

finalize_video
