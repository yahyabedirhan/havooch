#!/bin/bash
# The v1 acceptance scenario of the spec, through the `video-review` CLI only,
# against the installed app in demo mode.
#
#   make install && make acceptance        (or: scripts/acceptance.sh)
#
# It uses only the spec's CLI contract, so it runs against another build of
# the spec by naming that build's command:
#
#   VIDEO_REVIEW_CLI="/Applications/Video Review.app/Contents/Helpers/video-review" scripts/acceptance.sh
#
# Each run has its own folder, .scratch/acceptance/<run>/ (ACCEPTANCE_DIR moves
# it): the demo data in demo/, the batch in payload.json, the screenshots in
# screenshots/ and every command's output in logs/.
#
# The script never touches the person's data: it stops at once, with exit 3,
# when `app status --json` does not say "demo": true.
#
# Exit codes: 0 all eight steps passed, 1 a step failed, 3 the app is not on
# demo data, 69 something the script needs is missing.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"

# The one place that names the command: VIDEO_REVIEW_CLI, else the installed
# app of this checkout's identity (the same constant the Makefile reads).
variant="$(sed -n 's/.*static let variant = "\(.*\)".*/\1/p' "$root/Sources/ReviewWire/AppIdentity.swift" 2>/dev/null)"
cli="${VIDEO_REVIEW_CLI:-/Applications/Video Review${variant:+ ($variant)}.app/Contents/Helpers/video-review}"

# The fixture, and what its README says about it.
video="$root/fixtures/sample/sample.mp4"
context_file="$root/fixtures/sample/sample.context.md"
frame_width=1920
frame_height=1080
duration=21.233
narration="Press command enter"          # spoken from 6.067 s to 14.333 s

# What the scenario writes.
first_time=10
first_text="The three notes on this frame are too small to read."
second_time=12.5
second_region="0.47,0.27,0.29,0.15"       # the Cmd + Enter keys on that frame
second_text="Show the keys as the menu names them."
ack_text="Got your 2 comments, starting."
question="Which name: Cmd+Return or Cmd+Enter?"
answer="Cmd+Return, as the Send Comments menu item says."
first_reply="Made the three notes larger."
second_reply="The keys now read Cmd+Return."
batch_reply="Both comments are done."

run_id="$(date +%Y%m%d-%H%M%S)-$$"
out="${ACCEPTANCE_DIR:-$root/.scratch/acceptance}/$run_id"
demo="$out/demo"
logs="$out/logs"
shots="$out/screenshots"
payload="$out/payload.json"

# Two agents: the operator drives the app under the lease, the listener takes
# the batch from "a second shell" and never holds the lease.
operator_key="acceptance-operator-$run_id"
listener_key="acceptance-listener-$run_id"
operator() { VIDEO_REVIEW_CONTROL_KEY="$operator_key" "$cli" "$@"; }
listener() { VIDEO_REVIEW_CONTROL_KEY="$listener_key" "$cli" "$@"; }

# --- reporting ---------------------------------------------------------------

step=0
step_title=""
step_failed=0
commands=0
code=0
stdout=""
stderr=""
ask_pid=""
on_demo=0

ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; step_failed=1; }

begin() {
    step="$1"
    step_title="$2"
    step_failed=0
    printf '\nstep %s: %s\n' "$step" "$step_title"
}

# Ends a step with its one line. A failed step ends the run: every later step
# builds on it.
finish() {
    if [ "$step_failed" -eq 0 ]; then
        printf 'PASS  step %s: %s\n' "$step" "$step_title"
    else
        printf 'FAIL  step %s: %s\n' "$step" "$step_title"
        printf '\nFAIL: step %s failed. Logs: %s\n' "$step" "$logs"
        exit 1
    fi
}

# run <operator|listener> <arguments…>: runs one command, keeps its output in
# the logs, and leaves its exit code in $code and the files in $stdout, $stderr.
run() {
    local who="$1"
    shift
    commands=$((commands + 1))
    stdout="$logs/$(printf '%02d' "$commands")-$who.out"
    stderr="$logs/$(printf '%02d' "$commands")-$who.err"
    "$who" "$@" >"$stdout" 2>"$stderr"
    code=$?
}

# exits <code> <what>: the last command's exit code.
exits() {
    if [ "$code" -eq "$1" ]; then
        ok "$2 exits $1"
    else
        bad "$2 exits $code, not $1: $(head -n 3 "$stderr" | tr '\n' ' ')"
    fi
}

# holds <what> <json file> <jq filter> [jq options…]: the filter is true.
holds() {
    local what="$1" file="$2" filter="$3"
    shift 3
    if jq -e "$@" "$filter" "$file" >/dev/null 2>&1; then
        ok "$what"
    else
        bad "$what    [jq: $filter]"
    fi
}

# state: the app's state, as a file in the logs, named in $stdout.
state() {
    run operator state --json
    if [ "$code" -ne 0 ]; then
        bad "state --json exits $code: $(head -n 3 "$stderr" | tr '\n' ' ')"
    fi
}

# png <what> <file> [<width> <height>]: a PNG file, of that size within a pixel.
png() {
    local what="$1" file="$2" magic width height
    if [ ! -f "$file" ]; then
        bad "$what is a file ($file)"
        return
    fi
    magic="$(head -c 8 "$file" | xxd -p)"
    if [ "$magic" != "89504e470d0a1a0a" ]; then
        bad "$what is a PNG file ($file)"
        return
    fi
    width="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    if [ -z "$width" ] || [ -z "$height" ] || [ "$width" -le 0 ] || [ "$height" -le 0 ]; then
        bad "$what has a size ($file)"
        return
    fi
    if [ $# -ge 4 ]; then
        if [ $((width - $3)) -ge -1 ] && [ $((width - $3)) -le 1 ] && [ $((height - $4)) -ge -1 ] && [ $((height - $4)) -le 1 ]; then
            ok "$what is a PNG of ${width}x${height}"
        else
            bad "$what is ${width}x${height}, not ${3}x${4}"
        fi
    else
        ok "$what is a PNG of ${width}x${height}"
    fi
}

# The rule that keeps the person's data safe. Nothing else may run when the
# app is not on demo data, the clean-up's `app quit` included.
require_demo() {
    run operator app status --json
    if [ "$code" -eq 0 ] && jq -e '.demo == true' "$stdout" >/dev/null 2>&1; then
        on_demo=1
        ok 'app status --json says "demo": true'
    else
        on_demo=0
        printf '  FAIL  app status --json does not say "demo": true\n'
        cat "$stdout" "$stderr"
        printf '\nSTOP: the app is not on demo data. Nothing more was sent to it.\n'
        exit 3
    fi
}

# Leaves nothing behind: the held `ask` ends, and the demo app quits.
clean_up() {
    if [ -n "$ask_pid" ]; then
        kill "$ask_pid" 2>/dev/null
    fi
    if [ "$on_demo" -eq 1 ]; then
        operator app quit >/dev/null 2>&1
    fi
}
trap clean_up EXIT

# --- before the first step ---------------------------------------------------

for tool in jq sips xxd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "acceptance: $tool is needed and was not found" >&2
        exit 69
    fi
done
if [ ! -x "$cli" ]; then
    echo "acceptance: no video-review command at $cli; run make install, or set VIDEO_REVIEW_CLI" >&2
    exit 69
fi
if [ ! -f "$video" ] || [ ! -f "$context_file" ]; then
    echo "acceptance: the fixture is missing in $root/fixtures/sample" >&2
    exit 69
fi
mkdir -p "$logs" "$shots"

echo "Video Review v1 acceptance scenario"
echo "cli:   $cli"
echo "video: $video"
echo "run:   $out"

# --- step 1 --------------------------------------------------------------------

begin 1 "Run app open --demo <folder> with the fixture"
run operator app open --demo "$demo"
exits 0 "app open --demo"
require_demo
run operator control take
exits 0 "control take (the operator's lease)"
finish

# --- step 2 --------------------------------------------------------------------

begin 2 "Open the fixture video. Seek, pause and add a comment"
run operator player open "$video"
exits 0 "player open"
run operator player play
exits 0 "player play"
run operator player pause
exits 0 "player pause"
run operator player seek 0:10
exits 0 "player seek 0:10"
run operator comment add "$first_text"
exits 0 "comment add"
state
holds "the video is the fixture" "$stdout" '.video.path == $path' --arg path "$video"
holds "the player is paused" "$stdout" '.player.playing == false'
holds "one comment, queued, at 10 s, with its text" "$stdout" \
    '(.comments | length) == 1 and .comments[0].state == "queued" and .comments[0].time == $time and .comments[0].text == $text' \
    --argjson time "$first_time" --arg text "$first_text"
finish

# --- step 3 --------------------------------------------------------------------

begin 3 "Add a second comment with a region"
run operator comment add "$second_text" --at 0:12.5 --region "$second_region"
exits 0 "comment add --at 0:12.5 --region $second_region"
state
holds "two comments, both queued" "$stdout" '(.comments | length) == 2 and all(.comments[]; .state == "queued")'
holds "the second comment is at 12.5 s and has a region" "$stdout" \
    '.comments[1].time == $time and .comments[1].text == $text and .comments[1].region != null' \
    --argjson time "$second_time" --arg text "$second_text"
finish

# --- step 4 --------------------------------------------------------------------

begin 4 "Run batch send"
run operator batch send
exits 0 "batch send"
state
holds "both comments are sent" "$stdout" '(.comments | length) == 2 and all(.comments[]; .state == "sent")'
finish

# --- step 5 --------------------------------------------------------------------

begin 5 "In a second shell, wait returns the batch. Check the keyframe, the crop, the transcript window and context"
commands=$((commands + 1))
listener wait --timeout 20 >"$payload" 2>"$logs/$(printf '%02d' "$commands")-listener.err"
code=$?
stderr="$logs/$(printf '%02d' "$commands")-listener.err"
exits 0 "wait (as the listener)"

holds "batch has id and sentAt" "$payload" '(.batch.id | type) == "string" and (.batch.id | length) > 0 and (.batch.sentAt | type) == "string"'
holds "video has path, contentHash, duration and title" "$payload" \
    '.video.path == $path and (.video.contentHash | length) > 0 and ((.video.duration - $duration) | fabs) < 0.1 and (.video.title | length) > 0' \
    --arg path "$video" --argjson duration "$duration"
holds "context is the text of the fixture's context file" "$payload" \
    'def trimmed: sub("^\\s+"; "") | sub("\\s+$"; ""); (.context | type) == "string" and (.context | trimmed) == ($text | trimmed)' \
    --rawfile text "$context_file"
holds "two comments, in time order" "$payload" '(.comments | length) == 2 and .comments[0].time == $a and .comments[1].time == $b' \
    --argjson a "$first_time" --argjson b "$second_time"
holds "the first comment has its text, no region and no crop" "$payload" \
    '.comments[0].text == $text and .comments[0].region == null and .comments[0].cropPath == null' --arg text "$first_text"
holds "the second comment has its text and its region $second_region" "$payload" \
    '.comments[1].text == $text and ([.comments[1].region | .x, .y, .w, .h] | map(tostring) | join(",")) == $region' \
    --arg text "$second_text" --arg region "$second_region"

batch_id="$(jq -r '.batch.id' "$payload" 2>/dev/null)"
first_id="$(jq -r '.comments[0].id' "$payload" 2>/dev/null)"
second_id="$(jq -r '.comments[1].id' "$payload" 2>/dev/null)"
holds "each comment has its own id" "$payload" '.comments[0].id != .comments[1].id and all(.comments[]; (.id | length) > 0)'

png "the first keyframe" "$(jq -r '.comments[0].keyframePath' "$payload")" "$frame_width" "$frame_height"
png "the second keyframe" "$(jq -r '.comments[1].keyframePath' "$payload")" "$frame_width" "$frame_height"
# The crop is the region's part of the frame: its size is the region's size in
# the frame's pixels.
crop_width="$(jq -r --argjson width "$frame_width" '.comments[1].region.w * $width | round' "$payload" 2>/dev/null)"
crop_height="$(jq -r --argjson height "$frame_height" '.comments[1].region.h * $height | round' "$payload" 2>/dev/null)"
png "the crop (the region's part of the frame)" "$(jq -r '.comments[1].cropPath' "$payload")" "$crop_width" "$crop_height"
holds "the image paths are absolute" "$payload" \
    'all(.comments[]; (.keyframePath | startswith("/"))) and (.comments[1].cropPath | startswith("/"))'

holds "each transcript is timed lines inside 15 s before to 15 s after the comment" "$payload" \
    'all(.comments[]; . as $c | (.transcript | length) > 0 and all(.transcript[]; (.text | length) > 0 and .start < .end and .end > ($c.time - 15) and .start < ($c.time + 15)))'
holds "each transcript holds the narration at the comment's time (\"$narration\")" "$payload" \
    'all(.comments[]; . as $c | any(.transcript[]; .start <= $c.time and $c.time <= .end and (.text | contains($words))))' \
    --arg words "$narration"
finish

# --- step 6 --------------------------------------------------------------------

begin 6 "Run ack, then ask on one comment. Answer it with thread answer. Then set both comments to done with a reply"
run listener ack "$batch_id" "$ack_text"
exits 0 "ack"
state
holds "both comments are acknowledged" "$stdout" 'all(.comments[]; .state == "acknowledged")'

answer_file="$out/answer.txt"
listener ask "$second_id" "$question" --wait 60 >"$answer_file" 2>"$logs/ask.err" &
ask_pid=$!
# The question is in the thread before the person can answer it.
asked=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if operator state --json 2>/dev/null | jq -e --arg id "$second_id" --arg text "$question" \
        'any(.comments[] | select(.id == $id) | .thread[]; .author == "agent" and .kind == "question" and .text == $text)' >/dev/null 2>&1; then
        asked=1
        break
    fi
    sleep 0.5
done
if [ "$asked" -eq 1 ]; then ok "ask puts the agent's question in the comment's thread"; else bad "ask puts the agent's question in the comment's thread"; fi

run operator thread answer "$second_id" "$answer"
exits 0 "thread answer"
wait "$ask_pid"
code=$?
ask_pid=""
stderr="$logs/ask.err"
exits 0 "ask"
if [ "$(cat "$answer_file")" = "$answer" ]; then
    ok "ask prints the person's answer"
else
    bad "ask prints \"$(cat "$answer_file")\", not the person's answer"
fi

run listener status "$first_id" working
exits 0 "status working (first comment)"
run listener reply "$first_id" "$first_reply"
exits 0 "reply (first comment)"
run listener status "$first_id" "done"
exits 0 "status done (first comment)"
run listener status "$second_id" working
exits 0 "status working (second comment)"
run listener reply "$second_id" "$second_reply"
exits 0 "reply (second comment)"
run listener status "$second_id" "done"
exits 0 "status done (second comment)"
run listener reply "$batch_id" "$batch_reply"
exits 0 "reply (the batch)"

state
before="$stdout"
holds "both comments are done" "$before" '(.comments | length) == 2 and all(.comments[]; .state == "done")'
holds "the first thread has the agent's reply" "$before" \
    'any(.comments[] | select(.id == $id) | .thread[]; .author == "agent" and .kind == "message" and .text == $text)' \
    --arg id "$first_id" --arg text "$first_reply"
holds "the second thread has the question, the person's answer and the reply, in that order" "$before" \
    '[.comments[] | select(.id == $id) | .thread[] | [.author, .kind, .text]] == [["agent", "question", $q], ["person", "answer", $a], ["agent", "message", $r]]' \
    --arg id "$second_id" --arg q "$question" --arg a "$answer" --arg r "$second_reply"
holds "the batch has the acknowledgement and its own reply" "$before" \
    '[.batches[] | select(.id == $id) | .messages[] | select(.author == "agent") | .text] == [$ack, $reply]' \
    --arg id "$batch_id" --arg ack "$ack_text" --arg reply "$batch_reply"
finish

# --- step 7 --------------------------------------------------------------------

begin 7 "Quit and open the app again. Check that state --json shows the comments, threads and statuses"
run operator app quit
exits 0 "app quit"
run operator app status --json
holds "the app is not running" "$stdout" '.running == false'
on_demo=0
run operator app open --demo "$demo"
exits 0 "app open --demo, the same folder"
require_demo
state
after="$stdout"
# The lease, the listener's presence and the player's time are of one run;
# everything the person and the agent wrote must be the same.
kept='{comments, queue, batches, video}'
jq -S "$kept" "$before" >"$out/state-before-quit.json" 2>/dev/null
jq -S "$kept" "$after" >"$out/state-after-open.json" 2>/dev/null
if [ -s "$out/state-before-quit.json" ] && cmp -s "$out/state-before-quit.json" "$out/state-after-open.json"; then
    ok "comments, queue, batches and video are the same as before the quit"
else
    bad "comments, queue, batches and video are the same as before the quit: $(diff "$out/state-before-quit.json" "$out/state-after-open.json" | head -n 6 | tr '\n' ' ')"
fi
holds "the video is open again, with both comments done" "$after" \
    '.video.path == $path and (.comments | length) == 2 and all(.comments[]; .state == "done")' --arg path "$video"
holds "the threads are there: 1 message and 3 messages" "$after" '[.comments[].thread | length] == [1, 3]'
holds "the answer is still the person's" "$after" \
    'any(.comments[] | select(.id == $id) | .thread[]; .author == "person" and .kind == "answer" and .text == $text)' \
    --arg id "$second_id" --arg text "$answer"
finish

# --- step 8 --------------------------------------------------------------------

begin 8 "Take screenshots in light and dark appearance"
run operator screenshot "$shots/light.png" --appearance light
exits 0 "screenshot --appearance light"
png "the light screenshot" "$shots/light.png"
run operator screenshot "$shots/dark.png" --appearance dark
exits 0 "screenshot --appearance dark"
png "the dark screenshot" "$shots/dark.png"
if [ -f "$shots/light.png" ] && [ -f "$shots/dark.png" ] && ! cmp -s "$shots/light.png" "$shots/dark.png"; then
    ok "the two appearances are two pictures"
else
    bad "the two appearances are two pictures"
fi
run operator control release
exits 0 "control release"
state
holds "the lease is free" "$stdout" '.lease == null'
finish

printf '\nPASS: all 8 steps. Screenshots: %s\n' "$shots"
exit 0
