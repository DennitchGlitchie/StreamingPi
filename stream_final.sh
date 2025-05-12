#!/bin/bash

# Easily editable configuration variables
AUDIO_DIR="/home/garges/audio"
VISUALS_DIR="/home/garges/visual"
STREAM_KEY="STREAMKEY"
LOG_FILE="/home/garges/stream_log.txt"
ERROR_LOG="/home/garges/stream_error.log"
AUDIO_LIST_FILE="/tmp/audio_list.txt"
RESTART_INTERVAL=46800  # 13 hours in seconds

# Default flags
USE_AUDIO=true
USE_VISUALS=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-audio)
      USE_AUDIO=false
      shift
      ;;
    --no-visuals)
      USE_VISUALS=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Available options: --no-audio, --no-visuals"
      exit 1
      ;;
  esac
done

# Function to log messages with timestamps
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to handle clean exit
cleanup() {
    log_message "Received termination signal. Cleaning up and exiting..."
    if [ ! -z "$FFMPEG_PID" ]; then
        kill $FFMPEG_PID 2>/dev/null
    fi
    exit 0
}

# Set up signal trap for clean exit
trap cleanup SIGINT SIGTERM

# Find the visuals file in the directory
find_visuals_file() {
    # Count regular files (not directories) in visuals directory, excluding hidden files and the backup folder
    local file_count=$(find "$VISUALS_DIR" -maxdepth 1 -type f -not -path "*/\.*" | wc -l)
    
    if [ "$file_count" -eq 0 ]; then
        log_message "ERROR: No files found in visuals directory $VISUALS_DIR"
        return 1
    elif [ "$file_count" -gt 1 ]; then
        log_message "ERROR: Multiple files found in visuals directory $VISUALS_DIR. Only one file is allowed."
        log_message "Files found:"
        find "$VISUALS_DIR" -maxdepth 1 -type f -not -path "*/\.*" | tee -a "$LOG_FILE"
        return 1
    else
        VISUALS_FILE=$(find "$VISUALS_DIR" -maxdepth 1 -type f -not -path "*/\.*" | head -n 1)
        log_message "Using visuals file: $VISUALS_FILE"
        return 0
    fi
}

# Create concatenated audio file list for ffmpeg
create_audio_list() {
    # Remove existing file if it exists
    rm -f "$AUDIO_LIST_FILE"
    
    # Create new file with proper entries
    for audio_file in "$AUDIO_DIR"/*.mp3; do
        echo "file '$audio_file'" >> "$AUDIO_LIST_FILE"
    done
    
    log_message "Created audio list at $AUDIO_LIST_FILE with $(wc -l < "$AUDIO_LIST_FILE") entries"
    log_message "Audio list contents:"
    cat "$AUDIO_LIST_FILE" | tee -a "$LOG_FILE"
}

# Start the streaming process
start_stream() {
    log_message "Starting stream with configuration: audio=${USE_AUDIO}, visuals=${USE_VISUALS}"
    
    # Check for visuals if needed
    if $USE_VISUALS; then
        find_visuals_file
        if [ $? -ne 0 ]; then
            log_message "Failed to find appropriate visuals file"
            return 1
        fi
    fi
    
    # Create the audio list file if audio is enabled
    if $USE_AUDIO; then
        create_audio_list
        # Make sure file exists before continuing
        if [ ! -f "$AUDIO_LIST_FILE" ]; then
            log_message "ERROR: Failed to create audio list file"
            return 1
        fi
    fi
    
    # Construct FFMPEG command based on flags
    cmd="ffmpeg"
    
    # Add webcam input
    cmd+=" -f v4l2 -thread_queue_size 1024 -framerate 30 -video_size 1280x720 -input_format mjpeg -i /dev/video0"
    
    # Add visuals if enabled
    if $USE_VISUALS; then
        cmd+=" -stream_loop -1 -i \"$VISUALS_FILE\""
    fi
    
    # Add audio if enabled
    if $USE_AUDIO; then
        cmd+=" -stream_loop -1 -f concat -safe 0 -i \"$AUDIO_LIST_FILE\""
    fi
    
    # Set up video filter complex based on flags
    if $USE_VISUALS; then
        cmd+=" -filter_complex \"[1:v]scale=1280:720,format=yuv420p[scaled];[0:v][scaled]blend=all_mode=overlay:all_opacity=0.5[outv]\" -map \"[outv]\""
    else
        cmd+=" -map 0:v"
    fi
    
    # Map audio if enabled
    if $USE_AUDIO; then
        if $USE_VISUALS; then
            cmd+=" -map 2:a:0"
        else
            cmd+=" -map 1:a:0"
        fi
    fi
    
    # Add encoding parameters
    cmd+=" -c:v libx264 -preset veryfast -tune zerolatency -maxrate 1500k -bufsize 3000k"
    cmd+=" -g 60 -crf 28 -profile:v high -level 4.0"
    
    # Add audio encoding if enabled
    if $USE_AUDIO; then
        cmd+=" -c:a aac -b:a 128k -ar 44100 -ac 2"
    else
        cmd+=" -an"  # No audio
    fi
    
    # Output format and destination
    cmd+=" -f flv -movflags +faststart \"rtmp://live.twitch.tv/app/$STREAM_KEY\" >> \"$LOG_FILE\" 2>> \"$ERROR_LOG\" &"
    
    # Execute the command
    log_message "Executing command: $cmd"
    eval "$cmd"
    
    FFMPEG_PID=$!
    log_message "FFmpeg process started with PID: $FFMPEG_PID"
    
    return 0
}

# Function for fallback stream if webcam fails
start_fallback_stream() {
    log_message "Starting fallback stream without webcam..."
    
    # Check for visuals if needed
    if $USE_VISUALS; then
        find_visuals_file
        if [ $? -ne 0 ]; then
            log_message "Failed to find appropriate visuals file for fallback stream"
            return 1
        fi
    else
        log_message "ERROR: Cannot run fallback stream without visuals"
        return 1
    fi
    
    # Construct fallback command
    cmd="ffmpeg"
    
    # Add visuals
    cmd+=" -stream_loop -1 -i \"$VISUALS_FILE\""
    
    # Add audio if enabled
    if $USE_AUDIO; then
        cmd+=" -stream_loop -1 -f concat -safe 0 -i \"$AUDIO_LIST_FILE\""
        cmd+=" -map 0:v -map 1:a:0"
    else
        cmd+=" -map 0:v -an"
    fi
    
    # Add encoding parameters
    cmd+=" -c:v libx264 -preset veryfast -tune zerolatency -maxrate 1500k -bufsize 3000k"
    cmd+=" -g 60 -crf 28 -profile:v high -level 4.0"
    
    # Add audio encoding if enabled
    if $USE_AUDIO; then
        cmd+=" -c:a aac -b:a 128k -ar 44100 -ac 2"
    fi
    
    # Output format and destination
    cmd+=" -f flv -movflags +faststart \"rtmp://live.twitch.tv/app/$STREAM_KEY\" >> \"$LOG_FILE\" 2>> \"$ERROR_LOG\" &"
    
    # Execute the command
    log_message "Executing fallback command: $cmd"
    eval "$cmd"
    
    FFMPEG_PID=$!
    log_message "Fallback FFmpeg process started with PID: $FFMPEG_PID"
    
    return 0
}

# Monitor and manage the stream with periodic restarts
monitor_and_restart() {
    log_message "Starting monitor with 13-hour periodic restart"
    
    while true; do
        # Start the primary stream
        start_stream
        
        if [ $? -ne 0 ]; then
            log_message "Primary stream failed to start. Trying fallback..."
            start_fallback_stream
            
            if [ $? -ne 0 ]; then
                log_message "Both primary and fallback streams failed. Restarting in 10 seconds..."
                sleep 10
                continue
            fi
        fi
        
        # Set the time when we started this stream instance
        STREAM_START_TIME=$(date +%s)
        
        # Monitor the stream until restart interval or failure
        while true; do
            # Check if FFmpeg is still running
            if ! ps -p $FFMPEG_PID > /dev/null; then
                log_message "FFmpeg process (PID: $FFMPEG_PID) is no longer running. Starting fallback..."
                # Try fallback stream
                start_fallback_stream
                if [ $? -ne 0 ]; then
                    log_message "Both primary and fallback streams failed. Restarting in 10 seconds..."
                    sleep 10
                    break
                fi
            fi
            
            # Check if we've reached the restart interval
            CURRENT_TIME=$(date +%s)
            ELAPSED_TIME=$((CURRENT_TIME - STREAM_START_TIME))
            
            if [ $ELAPSED_TIME -ge $RESTART_INTERVAL ]; then
                log_message "Reached scheduled 13-hour restart interval. Restarting stream..."
                # Terminate the current FFmpeg process cleanly
                kill $FFMPEG_PID 2>/dev/null
                # Wait a moment for resources to be released
                sleep 5
                break
            fi
            
            # Sleep for a while before checking again (every 60 seconds)
            sleep 60
        done
    done
}

# Main script execution
log_message "=== Starting 24/7 stream script with 13-hour restarts ($(date)) ==="
log_message "Configuration: USE_AUDIO=$USE_AUDIO, USE_VISUALS=$USE_VISUALS"

# Run the stream with monitoring and automatic restart
monitor_and_restart

log_message "Script terminated."
