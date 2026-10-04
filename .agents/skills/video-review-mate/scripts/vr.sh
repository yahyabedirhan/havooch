#!/bin/bash
# Finds the Video Review command line inside the installed app and runs it.
#
#   vr.sh which             print the command line this session uses, and why
#   vr.sh listen [options]  `wait [options]`, then acknowledge the batch at once and print it;
#                           while the app isn't running, it waits for the app to start
#   vr.sh <command> ...     any other `video-review` command, with its own output and exit code
#
# The command line is looked for in this order, never on PATH:
#   1. VIDEO_REVIEW_CLI, an absolute path
#   2. /Applications/Video Review.app
#   3. the only "Video Review*.app" in /Applications
#   4. among several, the only one whose app runs; the session keeps that choice,
#      so another app that starts later changes nothing
# VIDEO_REVIEW_APPS_DIR moves /Applications, for a test.
set -u

apps="${VIDEO_REVIEW_APPS_DIR:-/Applications}"
helper="Contents/Helpers/video-review"
folder="${TMPDIR:-/tmp}/video-review-mate"
session="${CLAUDE_CODE_SESSION_ID:-}"
cli=""
why=""

refuse() {
    echo "video-review-mate: $1" >&2
    exit 1
}

runs() {
    "$1" app status --json 2>/dev/null | grep -Eq '"running" *: *true'
}

find_cli() {
    if [ -n "${VIDEO_REVIEW_CLI:-}" ]; then
        [ -x "$VIDEO_REVIEW_CLI" ] || refuse "VIDEO_REVIEW_CLI names \`$VIDEO_REVIEW_CLI\`, which isn't an executable file"
        cli="$VIDEO_REVIEW_CLI"
        why="VIDEO_REVIEW_CLI names it"
        return
    fi
    if [ -x "$apps/Video Review.app/$helper" ]; then
        cli="$apps/Video Review.app/$helper"
        why="the installed app"
        return
    fi

    local candidate count=0 only="" running=0 live="" kept=""
    for candidate in "$apps"/Video\ Review*.app/"$helper"; do
        [ -x "$candidate" ] || continue
        count=$((count + 1))
        only="$candidate"
    done
    [ "$count" -gt 0 ] || refuse "no Video Review app in $apps; install it, or set VIDEO_REVIEW_CLI to its Contents/Helpers/video-review"
    if [ "$count" -eq 1 ]; then
        cli="$only"
        why="the only Video Review app in $apps"
        return
    fi

    [ -z "$session" ] || [ ! -f "$folder/cli-$session" ] || kept="$(cat "$folder/cli-$session")"
    if [ -n "$kept" ] && [ -x "$kept" ]; then
        cli="$kept"
        why="the one of $count Video Review apps this session chose when it alone ran"
        return
    fi
    for candidate in "$apps"/Video\ Review*.app/"$helper"; do
        [ -x "$candidate" ] || continue
        if runs "$candidate"; then
            running=$((running + 1))
            live="$candidate"
        fi
    done
    if [ "$running" -eq 1 ]; then
        cli="$live"
        why="the only one of $count Video Review apps that runs"
        [ -z "$session" ] || { mkdir -p "$folder" && echo "$cli" >"$folder/cli-$session"; }
        return
    fi
    echo "video-review-mate: $count Video Review apps in $apps, and $running of them run:" >&2
    for candidate in "$apps"/Video\ Review*.app/"$helper"; do
        [ -x "$candidate" ] && echo "  $candidate" >&2
    done
    refuse "set VIDEO_REVIEW_CLI to the one to listen to"
}

listen() {
    local payload code id
    mkdir -p "$folder" || refuse "can't make $folder"
    payload="$(mktemp "$folder/batch.XXXXXX")" || refuse "can't write in $folder"

    while :; do
        "$cli" wait "$@" >"$payload"
        code=$?
        # Refused while the app runs is an answer; refused with no app is a wait for the app.
        if [ "$code" -ne 1 ] || runs "$cli"; then break; fi
        echo "video-review-mate: waiting for the Video Review app to start" >&2
        until runs "$cli"; do sleep 5; done
    done
    if [ "$code" -ne 0 ]; then
        rm -f "$payload"
        exit "$code"
    fi

    id="$(plutil -extract batch.id raw -o - "$payload" 2>/dev/null)"
    if [ -n "$id" ] && "$cli" ack "$id" >/dev/null; then
        mv "$payload" "$folder/$id.json" && payload="$folder/$id.json"
        echo "video-review-mate: acknowledged $id; the batch is also in $payload" >&2
    else
        echo "video-review-mate: NOT acknowledged; run \`ack <batch id>\` now. The batch is also in $payload" >&2
    fi
    cat "$payload"
}

find_cli
case "${1:-}" in
which)
    echo "$cli"
    echo "video-review-mate: $why" >&2
    ;;
listen)
    shift
    listen "$@"
    ;;
*)
    exec "$cli" "$@"
    ;;
esac
