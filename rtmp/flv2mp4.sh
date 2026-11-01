#!/bin/sh
# Called by nginx-rtmp when a recording is finished: exec_record_done <script> $path
# Re-encodes to a smaller H.264 file and rotates the picture by 180 degrees,
# because the camera is mounted upside down on the ceiling.
# Runs with the lowest priority, so a running stream is not affected.
# The .flv is only removed after a successful conversion.
set -eu

input="$1"
output="${input%.flv}.mp4"
partial="$output.part"

if nice -n 19 ffmpeg -nostdin -loglevel error -y \
    -display_rotation 180 -i "$input" \
    -c:v libx264 -preset medium -crf 28 -pix_fmt yuv420p \
    -c:a copy -movflags +faststart -f mp4 "$partial"; then
    mv "$partial" "$output"
    rm "$input"
else
    rm -f "$partial"
    exit 1
fi
