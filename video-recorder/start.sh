#!/usr/bin/env bash
set -euo pipefail

VIDEO_RECORDER_ENABLED=${VIDEO_RECORDER_ENABLED:-}
VIDEO_RECORDER_VOLUME_LABEL=${VIDEO_RECORDER_VOLUME_LABEL:-}
VIDEO_RECORDER_VOLUME_FILESYSTEM_TYPE=${VIDEO_RECORDER_VOLUME_FILESYSTEM_TYPE:-}
VIDEO_RECORDER_VOLUME_MOUNTPOINT=${VIDEO_RECORDER_VOLUME_MOUNTPOINT:-/video-recorder/data}
VIDEO_RECORDER_SLEEP_SECONDS=${VIDEO_RECORDER_SLEEP_SECONDS:-2}
VIDEO_RECORDER_SEGMENT_TIME=${VIDEO_RECORDER_SEGMENT_TIME:-00:10:00}
VIDEO_RECORDER_LOG_LEVEL=${VIDEO_RECORDER_LOG_LEVEL:-error}
VIDEO_RECORDER_SOCKET_TIMEOUT_MICROSECONDS=${VIDEO_RECORDER_SOCKET_TIMEOUT_MICROSECONDS:-10000000}
VIDEO_RECORDER_LIVENESS_PING=${VIDEO_RECORDER_LIVENESS_PING:-1.1.1.1}
VIDEO_RECORDER_LIVENESS_SLEEP_SECONDS=${VIDEO_RECORDER_LIVENESS_SLEEP_SECONDS:-$VIDEO_RECORDER_SLEEP_SECONDS}

record_repeatedly() {
    echo "Recording $1 from $2..."
    OUTPUT="$VIDEO_RECORDER_VOLUME_MOUNTPOINT/${1//[^[:alnum:]]/-}-%Y%m%dT%H%M%S.mkv"
    ffmpeg \
        -hide_banner \
        -y \
        -loglevel "$VIDEO_RECORDER_LOG_LEVEL" \
        -rtsp_transport tcp \
        -use_wallclock_as_timestamps 1 \
        -i "$2" \
        -vcodec copy \
        -acodec copy \
        -f segment \
        -reset_timestamps 1 \
        -segment_time "$VIDEO_RECORDER_SEGMENT_TIME" \
        -segment_format mkv \
        -segment_atclocktime 1 \
        -timeout "$VIDEO_RECORDER_SOCKET_TIMEOUT_MICROSECONDS" \
        -strftime 1 \
        "$OUTPUT" ||
        echo "Recording failed"

    echo "Recording $1 stopped prematurely; sleeping for $VIDEO_RECORDER_SLEEP_SECONDS seconds..."
    sleep "$VIDEO_RECORDER_SLEEP_SECONDS"

    echo "Trying again"
    record_repeatedly "$@"
}

liveness_check() {
    chronic ping -q -f -c 3 -w 10 "$VIDEO_RECORDER_LIVENESS_PING" ||
        (
            echo "Liveness ping to $VIDEO_RECORDER_LIVENESS_PING failed!"
            exit 1
        )

    sleep "$VIDEO_RECORDER_LIVENESS_SLEEP_SECONDS"

    liveness_check
}

if [ -z "$VIDEO_RECORDER_ENABLED" ]; then
    echo "VIDEO_RECORDER_ENABLED is not set; skipping video recorder"
    tail -f /dev/null
else
    for REQUIRED_PARAM in VIDEO_RECORDER_VOLUME_FILESYSTEM_TYPE VIDEO_RECORDER_VOLUME_LABEL VIDEO_RECORDER_VOLUME_MOUNTPOINT; do
        if [ -z "${!REQUIRED_PARAM}" ]; then
            echo "$REQUIRED_PARAM is not set" 1>&2
            exit 1
        fi
    done

    mkdir -p "$VIDEO_RECORDER_VOLUME_MOUNTPOINT"
    chmod -w "$VIDEO_RECORDER_VOLUME_MOUNTPOINT"
    mount \
        -t "$VIDEO_RECORDER_VOLUME_FILESYSTEM_TYPE" \
        -o rw \
        -L "$VIDEO_RECORDER_VOLUME_LABEL" \
        "$VIDEO_RECORDER_VOLUME_MOUNTPOINT"

    STREAMS=$(compgen -v -X '!VIDEO_RECORDER_STREAM_*')
    if [ -z "$STREAMS" ]; then
        echo "No streams configured (Environment variables with VIDEO_RECORDER_STREAM_ prefix)"
        tail -f /dev/null
    else
        for KEY in $STREAMS; do
            STREAM_NAME=${KEY/VIDEO_RECORDER_STREAM_/}
            STREAM_URL=${!KEY}
            record_repeatedly "$STREAM_NAME" "$STREAM_URL" &
        done

        python -m http.server -d "$VIDEO_RECORDER_VOLUME_MOUNTPOINT" 9000 &

        liveness_check
    fi
fi
