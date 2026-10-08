#!/bin/bash
# The 0.2.0 acceptance scenario (`Spec: Havooch 0.2.0`, #36): the 10
# steps of 0.1.0's scenario, rewritten for the 0.2.0 sidebar, through the
# `havooch` CLI only, against the installed app in demo mode with the
# fixture video. Step 11 adds `havooch open` (#82): the person's open,
# run by the listener with no lease. Step 12 adds the windows (#86): any
# number of windows, each with one video, and `--window`. Step 13 adds a
# listener per window: two agents wait on two videos, each gets only
# its own window's sends, and a third agent takes one window over. Step 14
# adds the Connect view (#89): a send with no agent opens it with the outbox
# banner, an agent's wait delivers it, a harness is picked, and Disconnect
# lets the agent go. Step 15 adds the setup tour (#91): it shows, moves on,
# closes at its step and is skipped, and "Finish setup" is gone once an
# agent has connected.
# Step 16 adds projects (#92): an agent makes the first video a project, its
# threads move in as v1, the second video becomes v2, and `wait --project`
# gets the project's send with its project block.
# Step 17 adds the first-run window (#90): its steps go on and back, the
# Connect step shows the demo prompt in the picked harness's form, and
# skip closes it.
# Step 18 adds the thread list by version (#94): with four versions the list
# shows the last three, v4 on screen; All versions searches and an older
# version picked from it gets its section, until --remove takes it out.
# Step 19 adds the version switcher (#93): `version show` moves the project
# from v4 to v1 with the playhead at the same time, the field names v1 and
# the thread list marks its section, the picker searches, and a plain video
# has no switcher.
# Step 20 adds Compare (#95): the popover opens on v3 and v4, a side's
# picker searches, the other side's version swaps the sides, the window
# compares on one playhead, a message goes to the side made active, the
# layouts change, and compare exit returns to the right side's version.
#
#   make install && make acceptance        (or: scripts/acceptance.sh)
#
# Beside the 0.1.0 checks (threads, the send, the listener's payload, the
# question and answer, the follow-up, the themes, persistence, screenshots),
# each step checks the sidebar:
#
#   - which view it shows: `sidebar.thread` of `state --json`, the shown
#     thread's id or null for the thread list, and `thread show <thread>` and
#     `thread list` to change it;
#   - the group each thread is in on the thread list (Needs you, With agent,
#     Queued, Done), worked out from the threads of `state --json` by the
#     rule of the spec (`group` below);
#   - what the composer at the foot of the sidebar says it writes to:
#     "New thread at 0:10", "Reply on #1", "Follow up on #1", "Answer #1 ·
#     goes at once", `sidebar.composer.target` of `state --json` (#42). A
#     build that doesn't report it makes each of these checks PENDING, not
#     failed, and the run ends with exit 4.
#
# It uses only the CLI contract, so it runs against another build by naming
# that build's command:
#
#   HAVOOCH_CLI=/path/to/havooch scripts/acceptance.sh
#
# Two agents take part. The operator drives the app under the lease, with
# HAVOOCH_CONTROL_KEY when it is set (else a key of this run). The
# listener is a second process with its own key (HAVOOCH_LISTENER_KEY,
# else a key of this run): it runs `wait` in the background, as "a second
# shell", and never holds the lease.
#
# Each run has its own folder, .scratch/acceptance/<run>/ (ACCEPTANCE_DIR
# moves it): the demo data in demo/, the two sends in send-1.json and
# send-2.json, and every command's output in logs/. Step 10's screenshots
# (the thread list and a thread view, in light and dark) go to
# assets/screenshots/0.2.0/acceptance/ (ACCEPTANCE_SHOTS moves them).
#
# The script never touches the person's data: it stops at once, with exit 3,
# when `app status --json` does not say "demo": true. It leaves the demo app
# running and gives the lease up when it ends.
#
# Exit codes: 0 all 20 steps passed, 1 a step failed, 3 the app is not on
# demo data, 4 every step passed but a composer check is pending, 69
# something the script needs is missing.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"

# The one place that names the command: HAVOOCH_CLI, else the installed
# app's.
cli="${HAVOOCH_CLI:-/Applications/Havooch.app/Contents/Helpers/havooch}"

# The fixture, and what its README says about it.
video="$root/fixtures/sample/sample.mp4"
# A second video, with other content, for a second window.
other_video="$root/fixtures/launch/havooch-demo.mp4"
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
shots="${ACCEPTANCE_SHOTS:-$root/assets/screenshots/0.2.0/acceptance}"

operator_key="${HAVOOCH_CONTROL_KEY:-acceptance-operator-$run_id}"
listener_key="${HAVOOCH_LISTENER_KEY:-acceptance-listener-$run_id}"
operator() { HAVOOCH_CONTROL_KEY="$operator_key" "$cli" "$@"; }
listener() { HAVOOCH_CONTROL_KEY="$listener_key" "$cli" "$@"; }
# Step 13's agents, each named by its harness's session variable, so the
# window can say which agent took over from which.
claude_listener() {
    env -u CODEX_THREAD_ID -u PI_SESSION_ID CLAUDE_CODE_SESSION_ID="acceptance-$run_id" \
        HAVOOCH_CONTROL_KEY="acceptance-claude-$run_id" "$cli" "$@"
}
codex_listener() {
    env -u CLAUDE_CODE_SESSION_ID -u PI_SESSION_ID CODEX_THREAD_ID="acceptance-$run_id" \
        HAVOOCH_CONTROL_KEY="acceptance-codex-$run_id" "$cli" "$@"
}
# The settings commands read config.toml themselves, with no app: on the
# demo's support folder, so they read its config/config.toml and never the
# person's ~/.config/havooch.
settings() { HAVOOCH_SUPPORT_DIR="$demo" "$cli" "$@"; }

# The thread list's rule (spec 0.2.0, L38), over a thread of `state --json`:
# Needs you (the last question has no answer after it), With agent (a
# person's message sent, acknowledged or working), Queued (a queued one),
# Done (the rest). `list` is the thread list: each group that has a thread,
# in the groups' order, with its threads' numbers in the order of `state`
# (General first, then time order).
jq_defs='
def open_question:
    . as $t
    | ([$t.messages | to_entries[] | select(.value.kind == "question") | .key] | last) as $i
    | $i != null and ([$t.messages[$i:][] | select(.kind == "answer")] == []);
def group:
    if open_question then "needs you"
    else [.messages[] | select(.author == "person" and .kind == "message") | .state] as $s
        | if any($s[]; . == "sent" or . == "acknowledged" or . == "working") then "with agent"
          elif any($s[]; . == "queued") then "queued"
          else "done" end
    end;
def list:
    .threads as $threads
    | ["needs you", "with agent", "queued", "done"]
    | map(. as $g | [$threads[] | select(group == $g) | .number] | select(. != []) | [$g, .]);
'

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
window_pids=()
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
# app is not on demo data. Only `app open --demo` makes a demo run (it marks
# the launch with HAVOOCH_DEMO_RUN=1); a HAVOOCH_SUPPORT_DIR alone is not one.
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

# stop <pid>: ends a background command. Its pid is the subshell's that
# runs the agent's function, and the havooch command is that subshell's
# child: killing the subshell alone would leave the command running, a
# `wait` that takes a later step's send.
stop() {
    pkill -TERM -P "$1" 2>/dev/null
    kill "$1" 2>/dev/null
    wait "$1" 2>/dev/null
}

# Leaves nothing behind: the background commands end and the lease is free.
# The demo app keeps running: other agents may be in line for it.
clean_up() {
    [ -n "$listener_pid" ] && stop "$listener_pid"
    [ -n "$ask_pid" ] && stop "$ask_pid"
    # Bash 3.2 calls an empty array unbound under set -u.
    for pid in ${window_pids[@]+"${window_pids[@]}"}; do stop "$pid"; done
    [ "$holds_lease" -eq 1 ] && operator control release >/dev/null 2>&1
}
trap clean_up EXIT


# --- the sidebar -------------------------------------------------------------

# on_list <state file>: the sidebar shows the thread list.
on_list() {
    holds "the sidebar shows the thread list (sidebar.thread is null)" "$1" \
        '(.sidebar | type) == "object" and .sidebar.thread == null'
}

# on_thread <state file> <thread id> <what>: the sidebar shows that thread's view.
on_thread() {
    holds "the sidebar shows the thread view of $3" "$1" '.sidebar.thread == $id' --arg id "$2"
}

# grouped <what> <state file> <list as JSON>: the thread list's groups, each
# with its threads' numbers, in order.
grouped() {
    local what="$1" file="$2" expected="$3"
    if jq -e --argjson expected "$expected" "$jq_defs list == \$expected" "$file" >/dev/null 2>&1; then
        ok "$what"
    else
        bad "$what: the list is $(jq -c "$jq_defs list" "$file" 2>/dev/null), not $expected"
    fi
}

# composer_says <target>: what the composer at the foot of the sidebar says
# it writes to: `sidebar.composer.target` of `state --json` (#42). With a
# build that doesn't report it, the check is PENDING: it is listed at the
# end and the run exits 4, never 0.
composer_pending=()
composer_says() {
    local file="$logs/composer-$commands.json"
    operator state --json >"$file" 2>/dev/null
    if ! jq -e '.sidebar.composer.target? != null' "$file" >/dev/null 2>&1; then
        printf '  PEND  the composer says "%s" (state --json has no sidebar.composer.target)\n' "$1"
        composer_pending+=("step $step: \"$1\"")
        return
    fi
    holds "the composer says \"$1\"" "$file" '.sidebar.composer.target == $target' --arg target "$1"
}
# --- before the first step ---------------------------------------------------

for tool in jq sips xxd awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "acceptance: $tool is needed and was not found" >&2
        exit 69
    fi
done
if [ ! -x "$cli" ]; then
    echo "acceptance: no havooch command at $cli; run make install, or set HAVOOCH_CLI" >&2
    exit 69
fi
if [ ! -f "$video" ] || [ ! -f "$context_file" ]; then
    echo "acceptance: the fixture is missing in $root/fixtures/sample" >&2
    exit 69
fi
mkdir -p "$logs" "$shots"

echo "Havooch 0.2.0 acceptance scenario"
echo "cli:   $cli ($("$cli" --version 2>/dev/null))"
echo "video: $video"
echo "run:   $out"

# --- step 1 --------------------------------------------------------------------

begin 1 "Run app open --demo <folder> with the fixture. Check that the sidebar shows the thread list"
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
on_list "$stdout"
grouped "the thread list holds General alone, in Done" "$stdout" '[["done", [0]]]'
finish

# --- step 2 --------------------------------------------------------------------

begin 2 "Seek to a frame. Add a message, then a message with a region at the same frame. Check that both are in one thread, in Queued, and the sidebar stays on the list"
run operator player seek "$first_time"
exits 0 "player seek $first_time"
composer_says "New thread at 0:$first_time"
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
on_list "$stdout"
grouped "the thread list: #1 in Queued, General in Done" "$stdout" '[["queued", [1]], ["done", [0]]]'
composer_says "Reply on #1"
finish

# --- step 3 --------------------------------------------------------------------

begin 3 "Seek to another frame. Add a message with a region. Check that it starts a second thread, after #1 in Queued"
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
on_list "$stdout"
grouped "the thread list: #1 and #2 in Queued, in time order" "$stdout" '[["queued", [1, 2]], ["done", [0]]]'
finish

# --- step 4 --------------------------------------------------------------------

begin 4 "Show thread #1's view, then the thread list again. Run send. Check that both threads move to With agent"
run operator player seek "$second_time"
exits 0 "player seek $second_time (away from #1's frame)"
run operator thread show 1 --json
exits 0 "thread show 1"
holds "thread show answers with the shown thread" "$stdout" '.sidebar.thread == $id' --arg id "$first_thread"
state
on_thread "$stdout" "$first_thread" "#1"
holds "the player is paused on #1's frame, at $first_time s" "$stdout" \
    '.player.playing == false and ((.player.time - $time) | fabs) < 0.05' --argjson time "$first_time"
composer_says "Follow up on #1"
run operator thread list --json
exits 0 "thread list"
holds "thread list answers with no shown thread" "$stdout" '.sidebar.thread == null'
state
on_list "$stdout"
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
grouped "the thread list: #1 and #2 in With agent" "$stdout" '[["with agent", [1, 2]], ["done", [0]]]'
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

begin 6 "Run ack. Then ask on the first thread: check it moves to Needs you, answer it in its thread view, reply on both threads and set every message to done"
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
state
grouped "the thread list: #1 in Needs you, #2 in With agent" "$stdout" '[["needs you", [1]], ["with agent", [2]], ["done", [0]]]'

run operator thread show "$first_thread" --json
exits 0 "thread show $first_thread"
state
on_thread "$stdout" "$first_thread" "#1"
composer_says "Answer #1 · goes at once"
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
state
grouped "the answer takes #1 out of Needs you, back to With agent" "$stdout" '[["with agent", [1, 2]], ["done", [0]]]'
composer_says "Follow up on #1"

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
grouped "the thread list: every thread in Done" "$stdout" '[["done", [0, 1, 2]]]'
on_thread "$stdout" "$first_thread" "#1, still: the agent's messages leave the view as it is"
earlier="$(value "$stdout" '[.threads[] | select(.id == $id) | .messages[].id]' --arg id "$first_thread" -c)"
finish

# --- step 7 --------------------------------------------------------------------

begin 7 "Follow up on the first thread from its view with comment add --thread. Send it. Check that wait returns it with the earlier messages in history[] and no context"
run operator comment add "$follow_up" --thread "$first_thread" --json
exits 0 "comment add --thread $first_thread"
follow_up_message="$(value "$stdout" '.message.id')"
holds "the follow-up goes on thread #1" "$stdout" '.thread.id == $id and .thread.number == 1' --arg id "$first_thread"
state
holds "thread #1 is active again: queued" "$stdout" '[.threads[] | select(.id == $id) | .state] == ["queued"]' --arg id "$first_thread"
grouped "the thread list: #1 in Queued again" "$stdout" '[["queued", [1]], ["done", [0, 2]]]'
on_thread "$stdout" "$first_thread" "#1, still: a written message leaves the view as it is"
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
state
grouped "the thread list: every thread in Done again" "$stdout" '[["done", [0, 1, 2]]]'
finish

# --- step 8 --------------------------------------------------------------------

begin 8 "Run theme set with Dimmed, then with Default Dark. Check state --json and config check"
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
holds "filled buttons use Default Dark's accentFill, which white text reads on" "$stdout" '.theme.accentFill == "#48689d"'
holds "the pin is in the demo's config.toml, which the app accepted" "$stdout" \
    '.config.path == $path and .config.accepted == true' --arg path "$demo/config/config.toml"
run settings config check --json
exits 0 "config check"
holds "config check reads the demo's config.toml and accepts it" "$stdout" \
    '.config == $path and .accepted == true' --arg path "$demo/config/config.toml"
if grep -q '^theme = "Default Dark"$' "$demo/config/config.toml" 2>/dev/null; then
    ok "config.toml has the line theme = \"Default Dark\""
else
    bad "config.toml has the line theme = \"Default Dark\""
fi
finish

# --- step 9 --------------------------------------------------------------------

begin 9 "Quit and open the app again. Check that it shows home with the video first in recents, then open the video again and check that state --json shows the threads, messages, states and theme, and the sidebar opens on the thread list"
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
# A launch opens no video by itself (spec 0.3.0, #65): one window on home,
# with the fixture first in recents.
state
holds "the launch shows home in one window, with no video" "$stdout" \
    '.screen == "home" and .video.path == null and (.windows | length) == 1'
holds "the fixture is first in recents" "$stdout" '.recents[0].path == $path' --arg path "$video"
run operator player open "$video"
exits 0 "player open (the fixture, again)"
state
after="$stdout"
# The lease, the listener's presence, the player and the sidebar's view are
# of one run; everything the person and the agent wrote must be the same.
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
on_list "$after"
finish

# --- step 10 -------------------------------------------------------------------

begin 10 "Take screenshots of the thread list and of thread #1's view in light and dark"
# The theme follows the appearance again, so the pictures are of Default
# Light and Default Dark.
run operator theme set system
exits 0 "theme set system"
run operator player seek "$first_time"
exits 0 "player seek $first_time (thread #1's frame)"
# The notices of the last replies go after 5 s.
sleep 6
for view in list thread; do
    if [ "$view" = thread ]; then
        run operator thread show "$first_thread"
        exits 0 "thread show $first_thread"
        sleep 1
    fi
    for appearance in light dark; do
        run operator screenshot "$shots/$view-$appearance.png" --appearance "$appearance" --hide-agent-indicator
        exits 0 "screenshot of the $view view --appearance $appearance"
        png "the $view view in $appearance" "$shots/$view-$appearance.png"
    done
    if [ -f "$shots/$view-light.png" ] && [ -f "$shots/$view-dark.png" ] && ! cmp -s "$shots/$view-light.png" "$shots/$view-dark.png"; then
        ok "the $view view's two appearances are two pictures"
    else
        bad "the $view view's two appearances are two pictures"
    fi
done
if ! cmp -s "$shots/list-light.png" "$shots/thread-light.png"; then
    ok "the thread list and the thread view are two pictures"
else
    bad "the thread list and the thread view are two pictures"
fi
run operator thread list
exits 0 "thread list"
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 11 -------------------------------------------------------------------

begin 11 "Run havooch open as the listener, with no lease. Check that the video plays in front, no lease is taken, and a file that doesn't play is refused"
mkdir -p "$out/open"
cut="$out/open/cut2.mp4"
cp "$video" "$cut"
printf 'These are notes, not a video.\n' >"$out/open/notes.mp4"
run listener open "$cut"
exits 0 "open $cut (the listener, no lease)"
# The app asks macOS to bring it in front, and macOS does it a moment later.
for _ in $(seq 1 20); do
    state
    jq -e '.app.active == true' "$stdout" >/dev/null 2>&1 && break
    sleep 0.1
done
# A copy is the same video: the window that holds it comes forward (#86).
holds "the copy's video plays in its one window, and the app is in front" "$stdout" \
    '.video.path == $path and .player.playing == true and .app.active == true and (.windows | length) == 1' --arg path "$video"
holds "no lease is held: the agent-control icon doesn't show" "$stdout" '.lease == null'
run listener open "$out/open/notes.mp4"
exits 1 "open of a file that doesn't play"
state
holds "the video is still open, in one window" "$stdout" '.video.path == $path and (.windows | length) == 1' --arg path "$video"
holds "still no lease is held" "$stdout" '.lease == null'
finish

# --- step 12 -------------------------------------------------------------------

begin 12 "Open a second window and a second video. Check that each window holds its own video, open brings the holder forward, and --window picks a window"
take
run operator window new --json
exits 0 "window new"
holds "window new names the new window, w2, showing home" "$stdout" '.window == "w2" and ([.windows[] | .id] == ["w1", "w2"])'
state
holds "state lists two windows, the new one key and home" "$stdout" \
    '.window == "w2" and .screen == "home" and ([.windows[] | select(.key) | .id] == ["w2"])'
run listener open "$other_video"
exits 0 "open $other_video (the listener, no lease)"
holds "the empty key window, w2, takes it" "$stdout" 'test(" in w2, playing$")' -R
run operator state --window w2 --json
holds "w2 holds the second video" "$stdout" '.video.path == $path' --arg path "$other_video"
run listener open "$video"
exits 0 "open $video again"
state
holds "the first video's window, w1, comes forward: still two windows" "$stdout" \
    '.window == "w1" and .video.path == $path and (.windows | length) == 2' --arg path "$video"
run operator player pause --window w2
exits 0 "player pause --window w2"
run operator state --window w2 --json
holds "w2 is paused, and still holds its video" "$stdout" '.player.playing == false and .video.path == $path' --arg path "$other_video"
run operator player open "$video" --window w2
exits 1 "player open of w1's video in w2 is refused"
run operator window close w2
exits 0 "window close w2"
run operator window list --json
holds "one window is left, w1, with the first video" "$stdout" \
    '[.windows[] | .id] == ["w1"] and .windows[0].video.path == $path' --arg path "$video"
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 13 -------------------------------------------------------------------

begin 13 "Open the second video in a second window. Two agents wait, one on each video. Check that a send reaches only its window's listener, and that a third agent takes a window over"
take
run operator window new --json
exits 0 "window new"
# Window ids are not reused, so the new window is not w2 after step 12.
second_window="$(jq -r .window "$stdout")"
run listener open "$other_video"
exits 0 "open $other_video in the new window, w2"
first_wait="$out/window-wait-1.json"
second_wait="$out/window-wait-2.json"
listener wait --video "$video" --timeout 60 >"$first_wait" 2>"$first_wait.err" &
first_pid=$!
claude_listener wait --video "$other_video" --timeout 60 >"$second_wait" 2>"$second_wait.err" &
second_pid=$!
window_pids=("$first_pid" "$second_pid")
# Each window shows its own listener once both waits are open.
for _ in $(seq 1 50); do
    operator window list --json >"$logs/window-listeners.json" 2>/dev/null
    jq -e '[.windows[] | .listener.presence] == ["listening", "listening"]' "$logs/window-listeners.json" >/dev/null 2>&1 && break
    sleep 0.2
done
holds "w1 and w2 each show a listening agent, w2's is Claude Code" "$logs/window-listeners.json" \
    '[.windows[] | .listener.presence] == ["listening", "listening"] and .windows[1].listener.session == "Claude Code"'
run operator comment add "Brighter logo here." --window "$second_window"
exits 0 "comment add --window w2"
run operator send --window "$second_window"
exits 0 "send --window w2"
wait "$second_pid"
code=$?
stderr="$second_wait.err"
exits 0 "w2's listener's wait"
holds "w2's listener gets the send of the second video" "$second_wait" '.video.path == $path' --arg path "$other_video"
if kill -0 "$first_pid" 2>/dev/null; then
    ok "w1's listener still waits: the send was not its"
else
    bad "w1's listener's wait ended with w2's send"
fi
# Claude Code took the send and hadn't acknowledged it: Codex gets it again.
run codex_listener wait --video "$other_video" --timeout 0
exits 0 "a third agent's wait on the second video (Codex)"
holds "Codex gets the send Claude Code didn't finish" "$stdout" '.video.path == $path' --arg path "$other_video"
run operator state --window "$second_window" --json
holds "w2 says Codex took over from Claude Code" "$stdout" \
    '.listener.session == "Codex" and .listener.tookOverFrom == "Claude Code"'
run operator state --window w1 --json
holds "w1's listener is untouched" "$stdout" '.listener.tookOverFrom == null and .listener.waitOpen == true'
stop "$first_pid"
window_pids=()
run operator window close "$second_window"
exits 0 "window close w2"
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 14 -------------------------------------------------------------------

begin 14 "Send with no agent. Check that the Connect view opens with the outbox banner, that an agent's wait delivers the send, that a harness shows its prompt, and that Disconnect lets the agent go"
take
# w1's listener of step 13 went: let its grace run out, so nobody is there.
sleep 6
run operator comment add "Connect check." --at 3
exits 0 "comment add (no agent listens)"
run operator send
exits 0 "send with no agent"
state
holds "the sidebar shows the Connect view, opened by the send" "$stdout" '.sidebar.mode == "connect" and .sidebar.connect.reason == "send"'
holds "the banner says 1 message waits for an agent" "$stdout" \
    '.sidebar.connect.banner.kind == "waiting" and .sidebar.connect.banner.messages == 1'
run listener wait --timeout 0
exits 0 "wait (an agent connects)"
state
holds "the banner says the message was delivered to the agent" "$stdout" \
    '.sidebar.connect.banner.kind == "delivered" and .sidebar.connect.banner.messages == 1'
holds "the listener card shows the agent" "$stdout" '.sidebar.connect.phase == "connected" and .sidebar.connect.listener.agent != null'
holds "an agent connected once: setup needs nothing more" "$stdout" '.setup.agentConnectedOnce == true and .setup.needsFinishing == false'
run operator connect pick codex --json
exits 0 "connect pick codex"
holds "Codex's prompt is in its own form" "$stdout" '.sidebar.connect.harness == "codex" and (.sidebar.connect.prompt | startswith("$havooch-mate listen for my feedback on "))'
run operator connect disconnect
exits 0 "connect disconnect"
state
holds "nobody listens after Disconnect" "$stdout" '.sidebar.connect.phase == "none" and .sidebar.connect.listener == null'
run operator connect disconnect
exits 1 "connect disconnect again (nobody is connected)"
run operator thread list
exits 0 "thread list (Back)"
state
holds "the sidebar shows the threads again" "$stdout" '.sidebar.mode == "threads" and .sidebar.connect == null'
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 15 -------------------------------------------------------------------

begin 15 "Take the setup tour. Check that it shows its steps with their rings, that close keeps the step and skip starts over, and that Finish setup is gone after step 14's agent"
take
run operator tour show --json
exits 0 "tour show"
holds "the tour shows step 1 of 5 and rings the setup steps" "$stdout" \
    '.tour.open == true and .tour.step == "tools" and .tour.stepNumber == 1 and .tour.steps == 5 and .tour.rings == ["setupSteps"]'
holds "Finish setup shows while the tour does, and counts no first connection: step 14's agent connected" "$stdout" \
    '.tour.finishSetup == true and .tour.setupItemsLeft <= 2'
state
holds "the tools step shows the Connect view" "$stdout" '.sidebar.mode == "connect"'
run operator tour next --json
exits 0 "tour next"
holds "the connect step rings the agent step" "$stdout" '.tour.step == "connect" and .tour.rings == ["agentStep"]'
run operator tour next --json
exits 0 "tour next"
holds "the write step rings the stage and the composer" "$stdout" '.tour.step == "write" and .tour.rings == ["stage", "composer"]'
run operator tour close --json
exits 0 "tour close"
holds "close keeps the step" "$stdout" '.tour.open == false and .tour.step == "write" and .tour.rings == []'
state
holds "with the tour closed and an agent connected once, Finish setup is gone" "$stdout" '.tour.finishSetup == false'
run operator tour show --json
exits 0 "tour show (again)"
holds "the tour opens at the step it was left on" "$stdout" '.tour.open == true and .tour.step == "write"'
run operator tour skip --json
exits 0 "tour skip"
holds "skip starts the next tour from the first step" "$stdout" '.tour.open == false and .tour.step == "tools"'
run operator tour next
exits 1 "tour next (the tour isn't showing)"
run operator thread list
exits 0 "thread list"
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 16 -------------------------------------------------------------------

begin 16 "Make the first video a project, with its threads as v1. Add the second video as v2. Check that wait --project gets the project's send with its project block"
slug="launch-video"
run claude_listener project new "$slug" --from "$video" --title "Launch video"
exits 0 "project new $slug --from the first video, with no lease"
run operator state --window w1 --json
holds "w1 holds the project, v1, and every thread on a frame is tagged v1" "$stdout" \
    '.project.slug == $slug and .project.version == 1 and .windows[0].video.project == $slug
     and ([.threads[] | select(.number > 0) | .version.number] | length > 0 and all(. == 1))' --arg slug "$slug"
run settings project list --json
holds "project list reads config.toml with no app: one project, v1 the first video" "$stdout" \
    '.projects == [{slug: $slug, title: "Launch video", versions: [{number: 1, path: $path, label: null}]}]' \
    --arg slug "$slug" --arg path "$video"
run claude_listener project add "$slug" "$other_video" --label "second cut"
exits 0 "project add $slug, the second video as v2"
run operator state --window w1 --json
holds "w1 shows v2, the second video, and v1's threads stay" "$stdout" \
    '.project.version == 2 and .video.path == $path and ([.threads[] | select(.version.number == 1)] | length > 0)' \
    --arg path "$other_video"
take
run operator comment add "The logo is too small in v2." --at 2 --window w1
exits 0 "comment add on v2"
run operator send --window w1
exits 0 "send on v2"
run operator control release
exits 0 "control release"
holds_lease=0
# A send an earlier step left unfinished may come first: wait once more for v2's.
run claude_listener wait --project "$slug" --timeout 10
if [ "$code" -eq 0 ] && ! jq -e '.project.onScreen == 2' "$stdout" >/dev/null 2>&1; then
    run claude_listener wait --project "$slug" --timeout 10
fi
exits 0 "wait --project $slug"
holds "the send carries the project, v2 on screen, and its thread's version" "$stdout" \
    '.project.slug == $slug and .project.onScreen == 2 and (.project.versions | length) == 2
     and .video.path == $path and ([.threads[] | select(.number > 0) | .version.number] | index(2) != null)' \
    --arg slug "$slug" --arg path "$other_video"
finish

# --- step 17 -------------------------------------------------------------------

begin 17 "Show the first-run window. Check that its steps go on and back, that the Connect step shows the demo prompt in the picked harness's form, and that Skip Setup closes it"
take
# A demo run never shows it by itself: it shows only on a person's first launch.
state
holds "the first-run window doesn't show by itself on demo data" "$stdout" '.firstRun.showing == false'
run operator first-run show --json
exits 0 "first-run show"
holds "it shows Welcome" "$stdout" '.firstRun.showing == true and .firstRun.step == "welcome"'
run operator first-run next
exits 0 "first-run next (Get Started)"
run operator first-run next
exits 0 "first-run next (Continue)"
run operator first-run pick codex --json
exits 0 "first-run pick codex"
holds "the Connect step shows Codex's demo prompt" "$stdout" \
    '.firstRun.step == "connect" and .firstRun.harness == "codex" and .firstRun.prompt == "$havooch-mate use Havooch to open the demo video and listen for my feedback"'
run operator screenshot "$out/first-run-connect.png" --window first-run --hide-agent-indicator
exits 0 "screenshot of the first-run window"
run operator first-run back
exits 0 "first-run back"
run operator first-run skip
exits 0 "first-run skip (Skip Setup)"
state
holds "the first-run window is closed and done" "$stdout" '.firstRun.showing == false and .firstRun.done == true'
run operator first-run next
exits 1 "first-run next with the window closed"
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 18 -------------------------------------------------------------------

begin 18 "Add v3 and v4 to the project. Check that the thread list shows v2 to v4 with v4 on screen, that All versions searches, and that picking v1 adds its section until it is removed"
# Two copies of the first video, so the project has four versions.
mkdir -p "$out/versions"
for number in 3 4; do
    cp "$video" "$out/versions/cut$number.mp4"
    run claude_listener project add "$slug" "$out/versions/cut$number.mp4"
    exits 0 "project add $slug, a copy of the first video as v$number"
done
take
run operator thread list --window w1
exits 0 "thread list"
run operator state --window w1 --json
holds "the list shows the last three versions, v4 on screen, and v1 under All versions" "$stdout" \
    '.sidebar.versions.sections == [4, 3, 2] and .sidebar.versions.onScreen == 4 and .sidebar.versions.older == [1]
     and .sidebar.versions.showing == "Showing v2 to v4" and .sidebar.versions.menu == null'
run operator thread versions --search v1 --window w1 --json
exits 0 "thread versions --search v1"
holds "All versions is open with the search, and finds v1" "$stdout" \
    '.sidebar.versions.menu.search == "v1" and .sidebar.versions.menu.older == [1] and .sidebar.versions.menu.inList == []'
run operator screenshot "$out/thread-list-all-versions.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of All versions"
run operator thread version 1 --window w1 --json
exits 0 "thread version 1"
holds "v1 joins the list under the last three, picked, and the menu closes" "$stdout" \
    '.sidebar.versions.sections == [4, 3, 2, 1] and .sidebar.versions.picked == [1] and .sidebar.versions.menu == null
     and .sidebar.versions.older == []'
run operator screenshot "$out/thread-list-v1-picked.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of the list with v1"
run operator thread version 3 --remove --window w1
exits 1 "thread version 3 --remove (v3 is one of the last three)"
run operator thread version 1 --remove --window w1 --json
exits 0 "thread version 1 --remove"
holds "v1 leaves the list" "$stdout" '.sidebar.versions.sections == [4, 3, 2] and .sidebar.versions.picked == []'
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 19 -------------------------------------------------------------------

begin 19 "Switch the project from v4 to v1 in the header's switcher. Check that the playhead keeps its time, that the field names v1 and the thread list marks its section, that the picker searches, and that a plain video has no switcher"
take
run operator player pause --window w1
exits 0 "player pause"
run operator player seek 1.5 --window w1
exits 0 "player seek 1.5 on v4"
run operator state --window w1 --json
holds "w1 shows v4: the segments are v2 to v4, and the field says All 4" "$stdout" \
    '.project.version == 4 and .project.switcher.segments == [2, 3, 4] and .project.switcher.selected == 4
     and .project.switcher.field == "All 4" and .project.switcher.picker == null'
run operator version pick v1 --window w1 --json
exits 0 "version pick v1"
holds "the picker is open with the search, and finds v1" "$stdout" \
    '.project.switcher.picker.query == "v1" and .project.switcher.picker.matches == [1] and .project.switcher.picker.highlighted == 1'
run operator screenshot "$out/version-picker.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of the version picker"
run operator version show 1 --window w1
exits 0 "version show 1"
run operator state --window w1 --json
holds "w1 shows v1 at the same time, the field names it, the picker closed, and the thread list marks v1 on screen" "$stdout" \
    '.project.version == 1 and .video.path == $path and (.player.time - 1.5 | fabs) < 0.05
     and .project.switcher.selected == 1 and .project.switcher.field == "v1" and .project.switcher.picker == null
     and .sidebar.versions.onScreen == 1 and (.sidebar.versions.sections | index(1) != null)' \
    --arg path "$video"
run operator screenshot "$out/version-switcher-v1.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of the header with v1 in the field"
run operator version show v4 --window w1
exits 0 "version show v4"
run operator window new --json
exits 0 "window new"
plain_window=$(value "$stdout" '.window')
run operator player open "$root/fixtures/showcase/halcyon-teaser.mp4" --window "$plain_window"
exits 0 "player open a plain video in $plain_window"
run operator state --window "$plain_window" --json
holds "a plain video has no project, so no switcher" "$stdout" '.project == null'
run operator version show 1 --window "$plain_window"
exits 1 "version show on a plain video"
run operator window close "$plain_window"
exits 0 "window close $plain_window"
run operator control release
exits 0 "control release"
holds_lease=0
finish

# --- step 20 -------------------------------------------------------------------

begin 20 "Compare v3 and v4 of the project. Check that the popover opens on the previous version and the one on screen, that the other side's version swaps the sides, that both play on one playhead, that a message goes to the side made active, and that compare exit returns to the right side's version"
take
run operator player pause --window w1
exits 0 "player pause"
run operator player seek 1 --window w1
exits 0 "player seek 1 on v4"
run operator compare open --window w1 --json
exits 0 "compare open"
holds "the popover opens on v3 and v4, side by side" "$stdout" \
    '.project.compare.phase == "choosing" and .project.compare.left == 3 and .project.compare.right == 4
     and .project.compare.layout == "side-by-side" and .project.compare.active == null'
run operator compare pick left v1 --window w1 --json
exits 0 "compare pick left v1"
holds "the left side's picker finds v1" "$stdout" \
    '.project.compare.picker.side == "left" and .project.compare.picker.matches == [1] and .project.compare.picker.highlighted == 1'
run operator screenshot "$out/compare-popover.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of the compare popover"
run operator compare set --right 3 --window w1 --json
exits 0 "compare set --right 3"
holds "v3 on the right swaps the sides, and the picker closes" "$stdout" \
    '.project.compare.left == 4 and .project.compare.right == 3 and .project.compare.picker == null'
run operator compare swap --window w1 --json
exits 0 "compare swap"
holds "the swap button puts v3 back on the left" "$stdout" '.project.compare.left == 3 and .project.compare.right == 4'
run operator compare start --window w1 --json
exits 0 "compare start"
holds "the window compares v3 and v4 at the same time; messages go to v4 on the right" "$stdout" \
    '.project.compare.phase == "comparing" and .project.compare.active == "right" and .project.version == 4
     and (.player.time - 1 | fabs) < 0.05'
run operator screenshot "$out/compare-side-by-side.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of side by side"
run operator compare set --side left --window w1 --json
exits 0 "compare set --side left"
holds "the left side is active: v3 is the version on screen" "$stdout" \
    '.project.compare.active == "left" and .project.version == 3'
compare_text="The title is cut off on this cut"
run operator comment add "$compare_text" --window w1 --json
exits 0 "comment add on the left side"
run operator state --window w1 --json
holds "the message is on v3, the left side's version" "$stdout" \
    '[.threads[] | select(any(.messages[]; .text == $text))][0].version.number == 3' --arg text "$compare_text"
run operator compare set --layout flip --window w1 --json
exits 0 "compare set --layout flip"
holds "Flip shows the active side" "$stdout" '.project.compare.layout == "flip" and .project.compare.showing == "left"'
run operator screenshot "$out/compare-flip.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of flip"
run operator compare set --layout slider --slider 0.3 --window w1 --json
exits 0 "compare set --layout slider --slider 0.3"
holds "Slider shows the left side on 30% of the picture" "$stdout" \
    '.project.compare.layout == "slider" and .project.compare.slider == 0.3 and .project.compare.showing == null'
run operator screenshot "$out/compare-slider.png" --window w1 --hide-agent-indicator
exits 0 "screenshot of slider"
run operator compare exit --window w1 --json
exits 0 "compare exit"
holds "one version again: v4, the right side's" "$stdout" '.project.compare == null and .project.version == 4'
run operator compare exit --window w1
exits 0 "compare exit with Compare closed"
run operator control release
exits 0 "control release"
holds_lease=0
finish

if [ "${#composer_pending[@]}" -gt 0 ]; then
    printf '\nPASS: all 20 steps, with %s composer checks PENDING (the composer of #42):\n' "${#composer_pending[@]}"
    printf '  %s\n' "${composer_pending[@]}"
    printf 'Screenshots: %s\n' "$shots"
    exit 4
fi
printf '\nPASS: all 20 steps. Screenshots: %s\n' "$shots"
exit 0
