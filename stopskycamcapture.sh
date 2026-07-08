#!/bin/bash

DATE_STR=$(date +%Y%m%d)
PID_FILE="/export/media/skycam/$DATE_STR/latest_capture.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    
    if ps -p "$PID" > /dev/null; then
        echo "Stopping capture (PID $PID)..."
        
        # We send SIGTERM (default). 
        # The 'wait' in start.sh will catch this and trigger finalization.
        kill "$PID"
        
        echo "Signal sent. The file is now being finalized."
        echo "Please wait ~30 seconds before refreshing your CIFS share."
    else
        echo "Process $PID not found. Cleaning up stale PID file."
        rm "$PID_FILE"
    fi
else
    echo "No active capture found for today."
fi
chown -R 1000 /export/media/skycam
