#!/bin/bash
# $1 = Original MP4 Path
# $2 = Date Value (YYYYMMDD)

ORIGINAL_MP4="$1"
DATE_VAL="$2"
TRANSCODE_720P="${ORIGINAL_MP4%.mp4}_720p.mp4"
DETECTIONS_JSON="/root/MetDetPy/detections/detections.json"
LOG_FILE="/export/media/skycam/pipeline.log"
CLIP_DIR="/export/media/meteors/$DATE_VAL"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to calculate and log duration
log_duration() {
    local start=$1
    local end=$(date +%s)
    local diff=$((end - start))
    echo " (Took ${diff}s)" >> "$LOG_FILE"
}

log_msg "START: AUTO-DETECT-METEORS for $ORIGINAL_MP4"
TOTAL_START=$(date +%s)

# 1. Timelapse and Transcode
echo -n "$(date '+%Y-%m-%d %H:%M:%S') - STEP 1: Timelapse and 720p Transcode..." >> "$LOG_FILE"
STEP_START=$(date +%s)
# Run timelapse in background, transcode in foreground
/bin/bash /app/timelapse.sh "$ORIGINAL_MP4" > /dev/null 2>&1 &
/bin/bash /app/transcode_720p.sh "$ORIGINAL_MP4" > /dev/null 2>&1
wait 
log_duration $STEP_START

# 2. MetDetPy Analysis
echo -n "$(date '+%Y-%m-%d %H:%M:%S') - STEP 2: MetDetPy analysis..." >> "$LOG_FILE"
STEP_START=$(date +%s)

# Extract just the base filename of the video (e.g., capture_000937_720p) for a unique log name
VIDEO_BASE=$(basename "${TRANSCODE_720P%.mp4}")

# Define a unique, permanent log file path for this specific video file
METDET_LOG="/export/media/skycam/${DATE_VAL}_${VIDEO_BASE}_metdetpy.log"

# Run with double quotes so variables expand properly, saving full output permanently
/bin/bash -l -c "/root/MetDetPy/run_p600.sh \"$TRANSCODE_720P\"" > "$METDET_LOG" 2>&1

if [ $? -eq 0 ]; then
    log_duration $STEP_START
    # Ensure the successful log file gets picked up by the permission cleanup in Step 5
    chown 1000:1000 "$METDET_LOG"
else
    # Append the last 3 lines of the actual crash to your main pipeline.log
    echo -n " FAILED. Recent output: " >> "$LOG_FILE"
    tail -n 3 "$METDET_LOG" | tr '\n' ' ' >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    chown 1000:1000 "$METDET_LOG"
fi

# 3. Path Swap in JSON
# This ensures ClipToolkit cuts from the 4K original, not the 720p version
echo -n "$(date '+%Y-%m-%d %H:%M:%S') - STEP 3: Swapping JSON paths..." >> "$LOG_FILE"
STEP_START=$(date +%s)
if [ -f "$DETECTIONS_JSON" ]; then
    sed -i "s|$TRANSCODE_720P|$ORIGINAL_MP4|g" "$DETECTIONS_JSON"
    log_duration $STEP_START
else
    echo " FAILED (File not found)" >> "$LOG_FILE"
fi

# 4. Clip Generation and MP4 Conversion
echo -n "$(date '+%Y-%m-%d %H:%M:%S') - STEP 4: ClipToolkit generation & MP4 conversion..." >> "$LOG_FILE"
STEP_START=$(date +%s)
mkdir -p "$CLIP_DIR"
cd /root/MetDetPy || exit

# Run the python toolkit
/root/MetDetPy/.venv/bin/python ClipToolkit.py --mode video --enable-filter-rules \
--save-path "$CLIP_DIR" \
"$DETECTIONS_JSON" --padding-before 2 --padding-after 2 --suffix mp4 > /dev/null 2>&1

if [ $? -eq 0 ]; then
    # REMUX: Convert AVI to MP4 for web compatibility without re-encoding
    for avi_file in "$CLIP_DIR"/*.avi; do
        if [ -f "$avi_file" ]; then
            ffmpeg -y -hide_banner -loglevel error -i "$avi_file" -c copy "${avi_file%.avi}.mp4" && rm "$avi_file"
        fi
    done
    log_duration $STEP_START
else
    echo " FAILED" >> "$LOG_FILE"
fi

# 5. Permissions
echo -n "$(date '+%Y-%m-%d %H:%M:%S') - STEP 5: Finalizing permissions..." >> "$LOG_FILE"
STEP_START=$(date +%s)
# Ensure both storage paths and the log are owned by UID 1000
chown -R 1000:1000 /export/media/meteors
chown -R 1000:1000 /export/media/skycam
chown 1000:1000 "$LOG_FILE"
log_duration $STEP_START

FINAL_END=$(date +%s)
TOTAL_DIFF=$((FINAL_END - TOTAL_START))
log_msg "FINISH: AUTO-DETECT-METEORS complete for $ORIGINAL_MP4 (Total Time: ${TOTAL_DIFF}s)"
echo "----------------------------------------------------------------" >> "$LOG_FILE"
