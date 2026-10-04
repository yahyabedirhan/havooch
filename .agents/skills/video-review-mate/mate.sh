#!/bin/sh
# The video-review CLI under one listener key.
#
#   mate.sh <key> listen        wait for the next batch, print its payload, acknowledge it
#   mate.sh <key> <arguments>   video-review <arguments>, with its output and exit code
#
# The CLI is $VIDEO_REVIEW_CLI when set, else the installed app's helper.

if [ $# -lt 2 ]; then
    echo "usage: mate.sh <key> listen | mate.sh <key> <video-review arguments>" >&2
    exit 2
fi

VIDEO_REVIEW_CONTROL_KEY=$1
export VIDEO_REVIEW_CONTROL_KEY
shift
cli=${VIDEO_REVIEW_CLI:-/Applications/Video Review.app/Contents/Helpers/video-review}

if [ "$1" != listen ]; then
    exec "$cli" "$@"
fi

payload=$("$cli" wait) || exit
printf '%s\n' "$payload"
batch=$(printf '%s' "$payload" | /usr/bin/plutil -extract batch.id raw -o - -) || exit 1
"$cli" ack "$batch" >&2
