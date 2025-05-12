# 24/7 Stream Script for Raspberry Pi 5 with Webcam and Optional Audio/Visuals

This project provides a robust Bash script for continuously streaming content to Twitch (or another RTMP server) using a Raspberry Pi 5, a USB webcam, and optional audio and visual overlays.

The script supports automatic restarts every 13 hours and fallback handling if the webcam becomes unavailable.

---

## Features

- Stream from a USB webcam with or without:
  - Background visuals
  - Audio loop from MP3 files
- Optional fallback to visuals + audio if webcam fails
- Auto-restart every 13 hours
- Logs activity and errors to files
- Works well for 24/7 channels or ambient livestreams

---

## Hardware

This setup has been tested using the following components:

- **Raspberry Pi 5 (4GB or 8GB)**
- **USB Webcam** (supports MJPEG and 1280x720 resolution)
- **Metal Case for Raspberry Pi 5**  
  Supports Pi 5 Active Cooler, HATs, add-on boards, NVMe HATs  
  [Link to Amazon](https://www.amazon.com/dp/B0DJS9TGHT?ref=ppx_yo2ov_dt_b_fed_asin_title)

- **Ultra-Quiet Active Cooler for Raspberry Pi 5**  
  ICE Peak Cooler with aluminum heatsink and 3510 fan  
  [Link to Amazon](https://www.amazon.com/dp/B0D946TDYX?ref=ppx_yo2ov_dt_b_fed_asin_title)

---

## Directory Structure

Before running the script, make sure the following directories exist and are populated appropriately:
/home/garges/
├── audio/ # Place your .mp3 files here
├── visual/ # Place a single visual (image or video) file here
├── stream_log.txt # Created automatically if not present
├── stream_error.log # Created automatically if not present

## Usage

Make the script executable and run it:

```bash
chmod +x stream.sh
./stream.sh [OPTIONS]
--no-audio	Disables audio playback
--no-visuals	Disables visual overlay (webcam only)

