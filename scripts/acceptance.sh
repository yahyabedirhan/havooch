#!/bin/bash
# The 0.1.0 acceptance scenario of the spec (`Spec: Video Review 0.1.0`), in
# its 10 steps, through the `video-review` CLI only, against the installed
# app in demo mode with the fixture video.
#
#   make install && make acceptance        (or: scripts/acceptance.sh)
#
# It uses only the spec's CLI contract, so it runs against another build by
# naming that build's command:
#
#   VIDEO_REVIEW_CLI=/path/to/video-review scripts/acceptance.sh
#
# Two agents take part. The operator drives the app under the lease, with
# VIDEO_REVIEW_CONTROL_KEY when it is set (else a key of this run). The
# listener is a second process with its own key (VIDEO_REVIEW_LISTENER_KEY,
# else a key of this run): it runs `wait` in the background, as "a second
# shell", and never holds the lease.
#
# Each run has its own folder, .scratch/acceptance/<run>/ (ACCEPTANCE_DIR
# moves it): the demo data in demo/, the two sends in send-1.json and
# send-2.json, and every command's output in logs/. Step 10's screenshots go
# to assets/screenshots/0.1.0/acceptance/ (ACCEPTANCE_SHOTS moves them).
#
# The script never touches the person's data: it stops at once, with exit 3,
# when `app status --json` does not say "demo": true. It leaves the demo app
# running and gives the lease up when it ends.
#
# Exit codes: 0 all 10 steps passed, 1 a step failed, 3 the app is not on
# demo data, 69 something the script needs is missing.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"

# The one place that names the command: VIDEO_REVIEW_CLI, else the installed
# app's.
cli="${VIDEO_REVIEW_CLI:-/Applications/Video Review.app/Contents/Helpers/video-review}"

# The fixture, and what its README says about it.
video="$root/fixtures/sample/sample.mp4"
context_file="$root/fixtures/sample/sample.context.md"
frame_width=1920
frame_height=1080
duration=21.233
first_narration="Press command enter"           # spoken from 6.067 s to 14.333 s
second_narration="The agent reads your notes"   # spoken from 14.333 s to 21.233 s

# What the scenario writes.
first_time=10
first_text="The three notes on this frame are too small to read."
first_region_text="Show the keys as the menu names them."
first_region="0.47,0.27,0.29,0.15"              # the Cmd + Enter keys on that frame
second_time=17
second_text="Name the repo here, so a viewer can find the skill."
second_region="0.1,0.6,0.5,0.25"
ack_text="Got your 3 messages on 2 threads, starting."
question="Which name: Cmd+Return or Cmd+Enter?"
answer="Cmd+Return, as the Send menu item says."
first_reply="Made the three notes larger, and the keys now read Cmd+Return."
second_reply="I can't change this one: the scene's source is not in this repo."
follow_up="Larger is better. Make the notes bold as well."
follow_up_reply="The notes are bold now."
lease_wait=1800

run_id="$(date +%Y%m%d-%H%M%S)-$$"
out="${ACCEPTANCE_DIR:-$root/.scratch/acceptance}/$run_id"
demo="$out/demo"
logs="$out/logs"
shots="${ACCEPTANCE_SHOTS:-$root/assets/screenshots/0.1.0/acceptance}"

operator_key="${VIDEO_REVIEW_CONTROL_KEY:-acceptance-operator-$run_id}"
listener_key="${VIDEO_REVIEW_LISTENER_KEY:-acceptance-listener-$run_id}"
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
listener_pid=""
ask_pid=""
holds_lease=0

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

# value <json file> <jq filter> [jq options…]: one value, raw.
value() {
    local file="$1" filter="$2"
    shift 2
    jq -r "$@" "$filter" "$file" 2>/dev/null
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

# crop <what> <payload> <jq path to a message>: the message's crop is the
# region's part of the frame, so its size is the region's size in pixels.
crop() {
    local what="$1" file="$2" message="$3" width height
    width="$(value "$file" "$message.region.w * \$w | round" --argjson w "$frame_width")"
    height="$(value "$file" "$message.region.h * \$h | round" --argjson h "$frame_height")"
    png "$what" "$(value "$file" "$message.cropPath")" "$width" "$height"
}

# The rule that keeps the person's data safe. Nothing else may run when the
# app is not on demo data.
require_demo() {
    run operator app status --json
    if [ "$code" -eq 0 ] && jq -e '.demo == true' "$stdout" >/dev/null 2>&1; then
        ok 'app status --json says "demo": true'
    else
        printf '  FAIL  app status --json does not say "demo": true\n'
        cat "$stdout" "$stderr"
        printf '\nSTOP: the app is not on demo data. Nothing more was sent to it.\n'
        exit 3
    fi
}

# take: the operator's lease, waiting in line behind another agent.
take() {
    run operator control take --wait "$lease_wait"
    exits 0 "control take --wait $lease_wait (the operator's lease)"
    [ "$code" -eq 0 ] && holds_lease=1
}

# listen <payload file>: `wait`, as the listener, in the background: the
# second process. Its pid is in $listener_pid.
listen() {
    listener wait --timeout 60 >"$1" 2>"$1.err" &
    listener_pid=$!
}

# heard <payload file>: the background `wait` returned, with exit 0.
heard() {
    wait "$listener_pid"
    code=$?
    listener_pid=""
    stderr="$1.err"
    exits 0 "wait (the listener, in a second process)"
}

# Leaves nothing behind: the background commands end and the lease is free.
# The demo app keeps running: other agents may be in line for it.
clean_up() {
    [ -n "$listener_pid" ] && kill "$listener_pid" 2>/dev/null
    [ -n "$ask_pid" ] && kill "$ask_pid" 2>/dev/null
    [ "$holds_lease" -eq 1 ] && operator control release >/dev/null 2>&1
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

echo "Video Review 0.1.0 acceptance scenario"
echo "cli:   $cli ($("$cli" --version 2>/dev/null))"
echo "video: $video"
echo "run:   $out"

# --- step 1 --------------------------------------------------------------------

begin 1 "Run app open --demo <folder> with the fixture"
# A running app answers only to the lease holder: take it first. With no
# app running, the open launches one and the lease is taken from it.
if operator app status --json 2>/dev/null | jq -e '.running == true' >/dev/null 2>&1; then
    take
    run operator app open --demo "$demo"
    exits 0 "app open --demo"
    require_demo
else
    run operator app open --demo "$demo"
    exits 0 "app open --demo"
    require_demo
    take
fi
run operator player open "$video"
exits 0 "player open (the fixture)"
state
holds "the video is the fixture, of $duration s" "$stdout" \
    '.video.path == $path and ((.video.duration - $duration) | fabs) < 0.1' --arg path "$video" --argjson duration "$duration"
holds "no thread but General, and an empty queue" "$stdout" \
    '[.threads[] | select(.number != 0)] == [] and .queue == []'
finish

# --- step 2 --------------------------------------------------------------------

begin 2 "Seek to a frame. Add a message, then a message with a region at the same frame. Check that both are in one thread"
run operator player seek "$first_time"
exits 0 "player seek $first_time"
run operator comment add "$first_text" --json
exits 0 "comment add"
first_message="$(value "$stdout" '.message.id')"
first_thread="$(value "$stdout" '.thread.id')"
holds "the message starts thread #1" "$stdout" '.thread.number == 1'
run operator comment add "$first_region_text" --region "$first_region" --json
exits 0 "comment add --region $first_region"
first_region_message="$(value "$stdout" '.message.id')"
holds "the region message joins the same thread" "$stdout" '.thread.id == $id and .thread.number == 1' --arg id "$first_thread"
state
holds "thread #1 is at $first_time s, queued, with both messages in order" "$stdout" \
    '[.threads[] | select(.id == $id)] | length == 1 and (.[0] | ((.time - $time) | fabs) < 0.05 and .state == "queued"
        and [.messages[] | [.id, .author, .kind, .state, .text]] == [[$a, "person", "message", "queued", $ta], [$b, "person", "message", "queued", $tb]])' \
    --arg id "$first_thread" --argjson time "$first_time" --arg a "$first_message" --arg b "$first_region_message" \
    --arg ta "$first_text" --arg tb "$first_region_text"
holds "the first message has no region; the second has $first_region" "$stdout" \
    '[.threads[] | select(.id == $id) | .messages[] | .region | if . == null then null else ([.x, .y, .w, .h] | map(tostring) | join(",")) end] == [null, $region]' \
    --arg id "$first_thread" --arg region "$first_region"
holds "both messages are in the queue" "$stdout" '.queue == [$a, $b]' --arg a "$first_message" --arg b "$first_region_message"
finish

# --- step 3 --------------------------------------------------------------------

begin 3 "Seek to another frame. Add a message with a region. Check that it starts a second thread"
run operator player seek "$second_time"
exits 0 "player seek $second_time"
run operator comment add "$second_text" --region "$second_region" --json
exits 0 "comment add --region $second_region"
second_message="$(value "$stdout" '.message.id')"
second_thread="$(value "$stdout" '.thread.id')"
holds "the message starts thread #2" "$stdout" '.thread.number == 2 and .thread.id != $id' --arg id "$first_thread"
state
holds "two threads besides General, in time order: #1 at $first_time s and #2 at $second_time s" "$stdout" \
    '[.threads[] | select(.number != 0) | [.number, (.time | round)]] == [[1, ($a | round)], [2, ($b | round)]]' \
    --argjson a "$first_time" --argjson b "$second_time"
holds "thread #2 has the one region message, queued" "$stdout" \
    '[.threads[] | select(.id == $id) | .messages[] | [.id, .state, (.region != null)]] == [[$m, "queued", true]]' \
    --arg id "$second_thread" --arg m "$second_message"
holds "three messages in the queue" "$stdout" '(.queue | length) == 3'
finish

# --- step 4 --------------------------------------------------------------------

begin 4 "Run send"
# The listener's `wait` is open before the send, in a second process.
first_payload="$out/send-1.json"
listen "$first_payload"
run operator send --json
exits 0 "send"
send_id="$(value "$stdout" '.send.id')"
holds "the send has the three messages on the two threads" "$stdout" \
    '(.send.messageIds | length) == 3 and .send.threadIds == [$a, $b]' --arg a "$first_thread" --arg b "$second_thread"
state
holds "the queue is empty and every message is sent in that send" "$stdout" \
    '.queue == [] and ([.threads[].messages[] | select(.author == "person")] | length == 3 and all(.state == "sent" and .sendId == $send))' \
    --arg send "$send_id"
finish

# --- step 5 --------------------------------------------------------------------

begin 5 "In a second shell, wait returns the send. Check two threads, the keyframes, the crops, the transcript windows, an empty history[] and context"
heard "$first_payload"
p="$first_payload"
holds "the send is the one sent" "$p" '.send.id == $id and (.send.sentAt | type) == "string"' --arg id "$send_id"
holds "video has path, contentHash, duration and title" "$p" \
    '.video.path == $path and (.video.contentHash | length) > 0 and ((.video.duration - $duration) | fabs) < 0.1 and .video.title == "sample.mp4"' \
    --arg path "$video" --argjson duration "$duration"
holds "context is the text of the fixture's context file" "$p" \
    'def trimmed: sub("^\\s+"; "") | sub("\\s+$"; ""); (.context | type) == "string" and (.context | trimmed) == ($text | trimmed)' \
    --rawfile text "$context_file"
holds "two threads, #1 and #2, in time order" "$p" '[.threads[] | [.id, .number]] == [[$a, 1], [$b, 2]]' \
    --arg a "$first_thread" --arg b "$second_thread"
holds "every history[] is empty" "$p" 'all(.threads[]; .history == [])'
holds "thread #1 has its two messages: no region, then the region $first_region" "$p" \
    '[.threads[0].messages[] | [.id, .text, (.region | if . == null then null else ([.x, .y, .w, .h] | map(tostring) | join(",")) end), (.cropPath != null)]]
        == [[$a, $ta, null, false], [$b, $tb, $region, true]]' \
    --arg a "$first_message" --arg b "$first_region_message" --arg ta "$first_text" --arg tb "$first_region_text" --arg region "$first_region"
holds "thread #2 has its one region message" "$p" \
    '[.threads[1].messages[] | [.id, .text, (.cropPath != null)]] == [[$m, $t, true]]' --arg m "$second_message" --arg t "$second_text"
png "thread #1's keyframe" "$(value "$p" '.threads[0].keyframePath')" "$frame_width" "$frame_height"
png "thread #2's keyframe" "$(value "$p" '.threads[1].keyframePath')" "$frame_width" "$frame_height"
crop "thread #1's crop (the region's part of the frame)" "$p" '.threads[0].messages[1]'
crop "thread #2's crop (the region's part of the frame)" "$p" '.threads[1].messages[0]'
holds "the image paths are absolute" "$p" \
    'all(.threads[]; (.keyframePath | startswith("/")) and all(.messages[] | select(.cropPath != null); .cropPath | startswith("/")))'
holds "each transcript is timed lines inside 15 s before to 15 s after the thread's time" "$p" \
    'all(.threads[]; . as $t | (.transcript | length) > 0 and all(.transcript[]; (.text | length) > 0 and .start < .end and .end > ($t.time - 15) and .start < ($t.time + 15)))'
holds "each transcript holds the narration at the thread's time" "$p" \
    '[.threads[] | . as $t | any(.transcript[]; .start <= $t.time and $t.time <= .end and (.text | contains($t.number | if . == 1 then $a else $b end)))] == [true, true]' \
    --arg a "$first_narration" --arg b "$second_narration"
finish

# --- step 6 --------------------------------------------------------------------

begin 6 "Run ack. Then ask on the first thread, answer it with thread answer, reply on both threads and set every message to done"
run listener ack "$send_id" "$ack_text"
exits 0 "ack"
state
holds "every message of the send is acknowledged" "$stdout" \
    '[.threads[].messages[] | select(.author == "person")] | all(.state == "acknowledged")'
holds "the acknowledgement is on the General thread" "$stdout" \
    'any(.threads[] | select(.number == 0) | .messages[]; .author == "agent" and .text == $text)' --arg text "$ack_text"

answer_file="$out/answer.txt"
listener ask "$first_thread" "$question" --wait 60 >"$answer_file" 2>"$logs/ask.err" &
ask_pid=$!
# The question is in the thread before the person can answer it.
asked=0
for _ in $(seq 1 20); do
    if operator state --json 2>/dev/null | jq -e --arg id "$first_thread" --arg text "$question" \
        'any(.threads[] | select(.id == $id) | .messages[]; .author == "agent" and .kind == "question" and .text == $text)' >/dev/null 2>&1; then
        asked=1
        break
    fi
    sleep 0.5
done
if [ "$asked" -eq 1 ]; then ok "ask puts the agent's question on thread #1"; else bad "ask puts the agent's question on thread #1"; fi

run operator thread answer "$first_thread" "$answer"
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

run listener reply "$first_thread" "$first_reply"
exits 0 "reply on thread #1"
run listener reply "$second_thread" "$second_reply"
exits 0 "reply on thread #2"
for message in "$first_message" "$first_region_message" "$second_message"; do
    run listener status "$message" working
    exits 0 "status $message working"
    run listener status "$message" "done"
    exits 0 "status $message done"
done
state
holds "every person message is done, and both threads are done" "$stdout" \
    '([.threads[].messages[] | select(.author == "person" and .kind == "message")] | all(.state == "done"))
        and ([.threads[] | select(.number != 0) | .state] == ["done", "done"])'
holds "thread #1 reads: two messages, the question, the answer, the reply" "$stdout" \
    '[.threads[] | select(.id == $id) | .messages[] | [.author, .kind, .text]]
        == [["person", "message", $m1], ["person", "message", $m2], ["agent", "question", $q], ["person", "answer", $a], ["agent", "message", $r]]' \
    --arg id "$first_thread" --arg m1 "$first_text" --arg m2 "$first_region_text" --arg q "$question" --arg a "$answer" --arg r "$first_reply"
holds "thread #2 reads: the message, the reply" "$stdout" \
    '[.threads[] | select(.id == $id) | .messages[] | [.author, .text]] == [["person", $m], ["agent", $r]]' \
    --arg id "$second_thread" --arg m "$second_text" --arg r "$second_reply"
earlier="$(value "$stdout" '[.threads[] | select(.id == $id) | .messages[].id]' --arg id "$first_thread" -c)"
finish

# --- step 7 --------------------------------------------------------------------

begin 7 "Add a follow-up on the first thread with comment add --thread. Send it. Check that wait returns it with the earlier messages in history[] and no context"
run operator comment add "$follow_up" --thread "$first_thread" --json
exits 0 "comment add --thread $first_thread"
follow_up_message="$(value "$stdout" '.message.id')"
holds "the follow-up goes on thread #1" "$stdout" '.thread.id == $id and .thread.number == 1' --arg id "$first_thread"
state
holds "thread #1 is active again: queued" "$stdout" '[.threads[] | select(.id == $id) | .state] == ["queued"]' --arg id "$first_thread"
second_payload="$out/send-2.json"
listen "$second_payload"
run operator send --json
exits 0 "send"
second_send="$(value "$stdout" '.send.id')"
heard "$second_payload"
p="$second_payload"
holds "wait returns the second send" "$p" '.send.id == $id and $id != $first' --arg id "$second_send" --arg first "$send_id"
holds "context is null: this listener has it already" "$p" '.context == null'
holds "one thread, #1, with the follow-up alone in messages[]" "$p" \
    '[.threads[] | [.id, .number, [.messages[] | .id, .text]]] == [[$id, 1, [$m, $t]]]' \
    --arg id "$first_thread" --arg m "$follow_up_message" --arg t "$follow_up"
holds "history[] is the thread's earlier messages, in order, with their authors and kinds" "$p" \
    '[.threads[0].history[].id] == $earlier
        and [.threads[0].history[] | [.author, .kind]] == [["person", "message"], ["person", "message"], ["agent", "question"], ["person", "answer"], ["agent", "message"]]' \
    --argjson earlier "$earlier"
holds "history[] keeps the region and the crop of the region message" "$p" \
    '.threads[0].history[1].region != null and (.threads[0].history[1].cropPath | startswith("/")) and .threads[0].history[0].cropPath == null'
holds "thread #1 has its keyframe and its transcript window again" "$p" \
    '(.threads[0].keyframePath | startswith("/")) and (.threads[0].transcript | length) > 0'
# The listener finishes the follow-up too, so nothing is left open.
run listener ack "$second_send"
exits 0 "ack"
run listener reply "$first_thread" "$follow_up_reply"
exits 0 "reply on thread #1"
run listener status "$follow_up_message" "done"
exits 0 "status $follow_up_message done"
finish

# --- step 8 --------------------------------------------------------------------

begin 8 "Run theme set with Dimmed, then with Default Dark. Check state --json"
run operator theme set Dimmed
exits 0 "theme set Dimmed"
state
holds "Dimmed is active and pinned, a dark theme" "$stdout" \
    '.theme.active == "Dimmed" and .theme.pinned == "Dimmed" and .theme.kind == "dark"'
run operator theme set "Default Dark"
exits 0 "theme set \"Default Dark\""
state
holds "Default Dark is active and pinned, a dark theme" "$stdout" \
    '.theme.active == "Default Dark" and .theme.pinned == "Default Dark" and .theme.kind == "dark"'
finish

# --- step 9 --------------------------------------------------------------------

begin 9 "Quit and open the app again. Check that state --json shows the threads, messages, states and theme"
state
before="$stdout"
run operator app quit
exits 0 "app quit"
holds_lease=0
run operator app status --json
holds "the app is not running" "$stdout" '.running == false'
run operator app open --demo "$demo"
exits 0 "app open --demo, the same folder"
require_demo
take
state
after="$stdout"
# The lease, the listener's presence and the player are of one run;
# everything the person and the agent wrote must be the same.
kept='{video: (.video | {path, contentHash}), threads, queue, sends, theme: (.theme | {active, pinned})}'
jq -S "$kept" "$before" >"$out/state-before-quit.json" 2>/dev/null
jq -S "$kept" "$after" >"$out/state-after-open.json" 2>/dev/null
if [ -s "$out/state-before-quit.json" ] && cmp -s "$out/state-before-quit.json" "$out/state-after-open.json"; then
    ok "the video, threads, messages, states, sends and theme are the same as before the quit"
else
    bad "the video, threads, messages, states, sends and theme are the same as before the quit: $(diff "$out/state-before-quit.json" "$out/state-after-open.json" | head -n 6 | tr '\n' ' ')"
fi
holds "the fixture is open again, with threads #1 and #2 done" "$after" \
    '.video.path == $path and [.threads[] | select(.number != 0) | .state] == ["done", "done"]' --arg path "$video"
holds "thread #1 has its 7 messages and the person's answer" "$after" \
    '[.threads[] | select(.id == $id) | .messages | length] == [7] and any(.threads[] | select(.id == $id) | .messages[]; .author == "person" and .kind == "answer" and .text == $a)' \
    --arg id "$first_thread" --arg a "$answer"
holds "Default Dark is still the theme" "$after" '.theme.active == "Default Dark" and .theme.pinned == "Default Dark"'
finish

# --- step 10 -------------------------------------------------------------------

begin 10 "Take screenshots in light and dark"
# The theme follows the appearance again, so the two pictures are of
# Default Light and Default Dark.
run operator theme set system
exits 0 "theme set system"
run operator player seek "$first_time"
exits 0 "player seek $first_time (thread #1's frame)"
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
holds_lease=0
finish

printf '\nPASS: all 10 steps. Screenshots: %s\n' "$shots"
exit 0
