#!/bin/bash
# The v1 acceptance scenario of the spec ("Spec: Video Review v1", "The v1
# acceptance scenario"), through the CLI only, against the installed app in
# demo mode. Each of the eight steps is checked; the first check that fails
# names its step on standard error and the script exits 1.
#
#   scripts/acceptance.sh        (or: make acceptance)
#
#   VIDEO_REVIEW_CLI     the CLI to drive. Default: the helper in this build's
#                        installed bundle, named by AppIdentity.variant as the
#                        Makefile names it. Set it to run the same scenario
#                        against another prototype.
#   ACCEPTANCE_SHOTS     the folder for light.png and dark.png. Default:
#                        .scratch/acceptance/ in this checkout (ignored).
#
# The demo folder is a temporary copy of fixtures/sample, so every run starts
# from an empty store and the tracked fixture is never written to. At the
# end, also after a failure, the script quits the app, releases the lease and
# removes the copy.
#
# It needs what every Mac with macOS 15 or later has: /bin/bash, /usr/bin/jq
# and /usr/bin/sips.

set -u

root=$(cd "$(dirname "$0")/.." && pwd -P)
variant=$(sed -n 's/.*static let variant = "\(.*\)".*/\1/p' "$root/Sources/VRWire/AppIdentity.swift")
if [ -n "$variant" ]; then
    app_name="Video Review ($variant)"
else
    app_name="Video Review"
fi
cli=${VIDEO_REVIEW_CLI:-/Applications/$app_name.app/Contents/Helpers/video-review}
shots=${ACCEPTANCE_SHOTS:-$root/.scratch/acceptance}
jq=/usr/bin/jq

# One holder for the operator and one for the listener, whatever shell or
# agent session runs the script.
operator_key=acceptance-operator
listener_key=acceptance-listener

# The second comment's region: the box in the fixture's frame at 16 s.
region=0.27,0.36,0.27,0.24
region_json='{"x": 0.27, "y": 0.36, "w": 0.27, "h": 0.24}'
first_text="The narration says command enter here. Show the key on the frame too."
second_text="This box is the part I mean."
ack_text="Got both comments."
question="Which part of the box matters most?"
answer="The top half."
first_reply="Added the key to the frame."
second_reply="Reworked the top half of the box."

step=0
title="setup"
work=""
ask_pid=""

say() { printf '%s\n' "$*"; }
begin() { step=$1; title=$2; say "step $step: $title"; }
ok() { say "  ok    $*"; }
fail() {
    printf 'FAIL  step %s (%s): %s\n' "$step" "$title" "$*" >&2
    exit 1
}

operator() { VIDEO_REVIEW_CONTROL_KEY=$operator_key "$cli" "$@"; }
listener() { VIDEO_REVIEW_CONTROL_KEY=$listener_key "$cli" "$@"; }

# must <operator|listener> <arguments>: the command's standard output in
# $out; a failure of the step when it doesn't exit 0.
must() {
    out=$("$@" 2>"$work/stderr")
    local status=$?
    [ $status -eq 0 ] || fail "\`video-review ${*:2}\` exited $status: $(cat "$work/stderr")"
}

# check <what it proves> <jq filter> <file> [jq arguments]: the filter must
# give true.
check() {
    local what=$1 filter=$2 file=$3
    shift 3
    [ "$("$jq" "$@" "$filter" "$file" 2>&1)" = true ] || fail "$what; got: $(cat "$file")"
    ok "$what"
}

is_png() { [ -s "$1" ] && [ "$(head -c 8 "$1" | xxd -p)" = 89504e470d0a1a0a ]; }
pixels() { /usr/bin/sips -g "pixel$2" "$1" | awk -v key="pixel$2:" '$1 == key { print $2 }'; }

# A comment of `state --json` by its id, wherever the state keeps it.
comment_in_state() {
    "$jq" -c --arg id "$1" '[.. | objects | select(.id? == $id and has("text"))] | first // empty' "$2"
}

cleanup() {
    local status=$?
    trap - EXIT
    [ -z "$ask_pid" ] || kill "$ask_pid" 2>/dev/null
    if [ -x "$cli" ]; then
        operator app quit >/dev/null 2>&1
        # Only when the quit was refused and the app still runs.
        operator control release >/dev/null 2>&1
    fi
    [ -z "$work" ] || rm -r "$work"
    exit $status
}

[ -x "$cli" ] || fail "no CLI at $cli; run \`make install\`, or set VIDEO_REVIEW_CLI"
[ -x "$jq" ] || fail "no $jq; it comes with macOS 15 and later"

temporary=${TMPDIR:-/tmp}
work=$(mktemp -d "${temporary%/}/video-review-acceptance.XXXXXX") || fail "couldn't make a temporary folder"
trap cleanup EXIT
trap 'exit 130' INT TERM

demo=$work/sample
video=$demo/sample.mp4
# The app may name the same folder with or without /private in front
# (/var is a link to /private/var), so paths are compared from here on.
demo_tail=${work##*/}/sample
cp -R "$root/fixtures/sample" "$demo" || fail "couldn't copy fixtures/sample to $demo"
mkdir -p "$shots" || fail "couldn't make $shots"

say "cli:  $cli"
say "demo: $demo"

# The app on the demo folder, held by the operator.
open_demo() {
    must operator app open --demo "$demo"
    must operator control take
    must operator app status
    case $out in
        *"$demo_tail"*) ;;
        *) fail "\`app status\` doesn't name the demo folder $demo: $out" ;;
    esac
}

begin 1 "app open --demo with the fixture"
open_demo
ok "the app runs on the demo folder and the operator holds the lease"
must operator state --json
say "$out" >"$work/state.json"
check "the store is empty: no comment yet" '[.. | objects | select(has("text"))] | length == 0' "$work/state.json"

begin 2 "open the video, seek, pause, add a comment"
must operator player open "$video"
must operator player seek 0:10
must operator player pause
must operator comment add "$first_text" --json
first=$(say "$out" | "$jq" -r '.id // empty')
[ -n "$first" ] || fail "\`comment add --json\` gave no id: $out"
must operator state --json
comment_in_state "$first" <(say "$out") >"$work/comment.json"
check "comment $first is queued at 10 s, where the player was paused" \
    '.text == $text and (.time - 10 | fabs) < 0.05 and (.state // .status) == "queued"' \
    "$work/comment.json" --arg text "$first_text"

begin 3 "add a second comment with a region"
must operator comment add "$second_text" --at 16 --region "$region" --json
second=$(say "$out" | "$jq" -r '.id // empty')
[ -n "$second" ] || fail "\`comment add --json\` gave no id: $out"
[ "$second" != "$first" ] || fail "both comments have the id $first"
must operator state --json
comment_in_state "$second" <(say "$out") >"$work/comment.json"
check "comment $second is queued at 16 s with the region $region" \
    '.text == $text and (.time - 16 | fabs) < 0.05 and (.state // .status) == "queued"
        and .region == $region' \
    "$work/comment.json" --arg text "$second_text" --argjson region "$region_json"

begin 4 "batch send"
must operator batch send --json
sent=$(say "$out" | "$jq" -r '.id // empty')
[ -n "$sent" ] || fail "\`batch send --json\` gave no id: $out"
ok "batch $sent is sent"

begin 5 "a second shell's wait returns the batch"
must listener wait --timeout 30
say "$out" >"$work/payload.json"
payload=$work/payload.json
check "the payload is batch $sent with its send time" \
    '.batch.id == $id and (.batch.sentAt | type == "string" and length > 0)' "$payload" --arg id "$sent"
check "the payload names the video: path, content hash, duration, title" \
    '(.video.path | endswith($tail)) and (.video.contentHash | type == "string" and length > 0)
        and .video.duration > 20 and .video.duration < 22 and (.video.title | type == "string" and length > 0)' \
    "$payload" --arg tail "$demo_tail/sample.mp4"
check "the payload has the two comments, with their ids, times and texts" \
    '(.comments | length == 2)
        and (.comments | map(select(.id == $first)) | first | .text == $firstText and .time == 10)
        and (.comments | map(select(.id == $second)) | first | .text == $secondText and .time == 16)' \
    "$payload" --arg first "$first" --arg second "$second" --arg firstText "$first_text" --arg secondText "$second_text"

for id in "$first" "$second"; do
    keyframe=$("$jq" -r --arg id "$id" '.comments[] | select(.id == $id) | .keyframePath // empty' "$payload")
    case $keyframe in
        /*) ;;
        *) fail "comment $id has no absolute keyframePath: \"$keyframe\"" ;;
    esac
    is_png "$keyframe" || fail "comment $id's keyframe isn't a PNG file: $keyframe"
    ok "comment $id's keyframe is a PNG, $(pixels "$keyframe" Width) x $(pixels "$keyframe" Height): $keyframe"
done

check "comment $first has no region and no crop" \
    '.comments[] | select(.id == $id) | .region == null and .cropPath == null' "$payload" --arg id "$first"
check "comment $second has its region as given" \
    '.comments[] | select(.id == $id) | .region == $region' "$payload" --arg id "$second" --argjson region "$region_json"
crop=$("$jq" -r --arg id "$second" '.comments[] | select(.id == $id) | .cropPath // empty' "$payload")
case $crop in
    /*) ;;
    *) fail "comment $second has no absolute cropPath: \"$crop\"" ;;
esac
is_png "$crop" || fail "comment $second's crop isn't a PNG file: $crop"
frame_w=$(pixels "$keyframe" Width); frame_h=$(pixels "$keyframe" Height)
crop_w=$(pixels "$crop" Width); crop_h=$(pixels "$crop" Height)
# The crop is the region's part of the frame: smaller than the frame, and in
# the region's shape.
awk -F, -v fw="$frame_w" -v fh="$frame_h" -v cw="$crop_w" -v ch="$crop_h" '{
    want = ($3 * fw) / ($4 * fh); got = cw / ch; off = got / want - 1
    exit !(cw < fw && ch < fh && off < 0.02 && off > -0.02)
}' <<<"$region" || fail "comment $second's crop is $crop_w x $crop_h, not the region's part of the $frame_w x $frame_h frame: $crop"
ok "comment $second's crop is a PNG, $crop_w x $crop_h, the region's part of the frame: $crop"

check "each comment's transcript is timed lines inside 15 s before to 15 s after it" \
    '.comments | all(. as $c | ($c.transcript | type == "array" and length > 0)
        and ($c.transcript | all((.text | type == "string" and length > 0)
            and .start < .end and .start <= $c.time + 15 and .end >= $c.time - 15)))' "$payload"
check "comment $first's transcript holds what the video says at 10 s (\"Press command enter\")" \
    '.comments[] | select(.id == $id) | .transcript
        | any(.start <= 10 and .end > 10 and (.text | contains("Press command enter")))' "$payload" --arg id "$first"
check "context is the text of the video's context.md" \
    '.context as $context | ($context | type == "string")
        and ($sidecar | split("\n") | map(select(length > 0)) | all(. as $line | $context | contains($line)))' \
    "$payload" --rawfile sidecar "$demo/sample.context.md"

begin 6 "ack, ask answered by thread answer, both comments done with a reply"
must listener ack "$sent" "$ack_text"
ok "batch $sent is acknowledged"
listener ask "$second" "$question" --wait 60 >"$work/answer" 2>"$work/ask-stderr" &
ask_pid=$!
# The ask reaches the app a moment after its process starts: until then the
# comment has no question to answer.
tries=0
until operator thread answer "$second" "$answer" >/dev/null 2>"$work/stderr"; do
    tries=$((tries + 1))
    [ $tries -lt 40 ] || fail "\`thread answer $second\` was refused for 10 s: $(cat "$work/stderr")"
    sleep 0.25
done
wait "$ask_pid"
asked=$?
ask_pid=""
[ $asked -eq 0 ] || fail "\`ask $second\` exited $asked: $(cat "$work/ask-stderr")"
case $(cat "$work/answer") in
    *"$answer"*) ok "ask on $second ended with the answer \"$answer\"" ;;
    *) fail "\`ask $second\` didn't print the answer \"$answer\": $(cat "$work/answer")" ;;
esac
must listener reply "$first" "$first_reply"
must listener status "$first" done
must listener reply "$second" "$second_reply"
must listener status "$second" done
ok "both comments have a reply and are set to done"

# What the state must show now, and again after a restart, when the app
# opens the video by itself: both comments
# done, the thread of the question, and the replies.
check_state() {
    must operator state --json
    say "$out" >"$work/state.json"
    comment_in_state "$first" "$work/state.json" >"$work/comment.json"
    check "$1: comment $first is done, with its text and the reply" \
        '.text == $text and (.state // .status) == "done" and (tostring | contains($reply))' \
        "$work/comment.json" --arg text "$first_text" --arg reply "$first_reply"
    comment_in_state "$second" "$work/state.json" >"$work/comment.json"
    check "$1: comment $second is done, with its region and its thread: question, answer, reply" \
        '.text == $text and (.state // .status) == "done" and .region == $region
            and (tostring | contains($question) and contains($answer) and contains($reply))' \
        "$work/comment.json" --arg text "$second_text" --arg question "$question" --arg answer "$answer" --arg reply "$second_reply" \
        --argjson region "$region_json"
    check "$1: batch $sent is there with its acknowledgement" \
        '[.. | objects | select(.id? == $id)] | length > 0 and (tostring | contains($ack))' \
        "$work/state.json" --arg id "$sent" --arg ack "$ack_text"
}
check_state "before the restart"

begin 7 "quit, open again, state --json shows the comments, threads and statuses"
must operator app quit
if operator app status >/dev/null 2>&1; then
    fail "the app still answers after \`app quit\`"
fi
ok "the app quit"
open_demo
ok "the app runs again"
# No `player open`: the app opens the video it had open at the quit. Step 8's
# seek is refused when no video is open.
check_state "after the restart, with no \`player open\`"

begin 8 "screenshots in light and dark"
# The region comment's moment, so its rectangle shows on the frame beside its
# marker and its thread.
must operator player seek 16
must operator player pause
for appearance in light dark; do
    shot=$shots/$appearance.png
    rm -f "$shot"
    must operator screenshot "$shot" --appearance "$appearance"
    [ ! -s "$work/stderr" ] || say "  note  $(cat "$work/stderr")"
    is_png "$shot" || fail "the $appearance screenshot isn't a PNG file: $shot"
    ok "$appearance: $(pixels "$shot" Width) x $(pixels "$shot" Height), $shot"
done
if cmp -s "$shots/light.png" "$shots/dark.png"; then
    fail "the light and the dark screenshot are the same picture"
fi
ok "the two screenshots differ"

say "PASS  all 8 steps of the v1 acceptance scenario"
