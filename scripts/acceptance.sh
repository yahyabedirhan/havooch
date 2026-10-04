#!/bin/bash
# The v1 acceptance scenario of the spec, through the `video-review` command
# line alone, against an installed app in demo mode.
#
#   scripts/acceptance.sh <path to Contents/Helpers/video-review>
#   VIDEO_REVIEW_CLI=<that path> scripts/acceptance.sh
#   make acceptance                 this build's installed app
#
# The command line's path is the one setting: the script knows nothing else of
# the build it tests, so it runs against any build that keeps the spec's CLI
# contract. Each run uses a new demo folder and never the person's data.
#
#   ACCEPTANCE_SCREENSHOTS   where the screenshots go (default: in the run's folder)
#
# It prints one PASS or FAIL line per check and exits 1 when any check failed.
# The app is quit at the end, passed or not; the run's folder is kept.
#
# What it leans on: exit codes, the batch payload's fields and the item states,
# all fixed by the spec. Two things the spec leaves open are each kept in one
# place below: the shape of `state --json`, and the names of a region's and a
# transcript line's fields. It needs bash, jq, sips and xxd, which
# macOS ships, and says so first when one is missing.
set -u

# --- The one setting ---------------------------------------------------------

cli="${1:-${VIDEO_REVIEW_CLI:-}}"
if [ -z "$cli" ] || [ ! -x "$cli" ]; then
    echo "usage: scripts/acceptance.sh <path to an installed app's Contents/Helpers/video-review>" >&2
    echo "       (or VIDEO_REVIEW_CLI); \`make install\` first" >&2
    exit 2
fi
for tool in jq sips xxd; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "scripts/acceptance.sh needs \`$tool\`, which isn't on PATH" >&2
        exit 2
    fi
done

# --- The fixture (fixtures/sample/README.md) ----------------------------------

repo="$(cd "$(dirname "$0")/.." && pwd)"
video="$repo/fixtures/sample/sample.mp4"
sidecar="$repo/fixtures/sample/sample.context.md"
frame_width=1920
frame_height=1080

moment_time="0:10"                  # in the scene `send`
moment_seconds=10
moment_text="The keys go by too fast here. Hold this scene a little longer."
moment_narration="Press command enter"

region_seconds=4                    # in the scene `pause`; the region is the card on its frame
region="0.275,0.375,0.275,0.225"
region_text="This card is hard to read against the background."
region_narration="Pause any video"

ack_text="Got both notes."
question="A lighter card, or a darker background?"
answer="A lighter card."
region_reply="The card is lighter now, and its label has more contrast."
moment_reply="The scene now holds a second and a half longer."
batch_reply="Both notes are done."

# --- What the spec leaves open, in one place ----------------------------------

# `state --json`. The spec names the command, not its shape; a build with
# another shape changes these filters and nothing else.
state_support='.app.support'
state_video='.video.path'
state_states='[.comments[].state] | sort | join(" ")'
# The review as step 7 compares it across a restart: each comment with its
# status and its thread.
state_review='[.comments[] | {id, time, text, region, state, thread: [.thread[] | {author, kind, text}]}] | sort_by(.id)'
# One comment's thread, as `author kind text` lines; $id is the comment's id.
state_thread='.comments[] | select(.id == $id) | .thread[] | "\(.author) \(.kind) \(.text)"'

# The payload. The spec names `region` and `transcript[]`, not the fields
# inside them.
payload_region='.region | [.x, .y, .w, .h]'
payload_narration='[.transcript[].text] | join(" ")'

# --- Reporting -----------------------------------------------------------------

step=0
checks=0
failures=0
failed_steps=""

begin() {
    step=$1
    echo
    echo "Step $1: $2"
}

pass() {
    checks=$((checks + 1))
    echo "  PASS  $1"
}

fail() {
    checks=$((checks + 1))
    failures=$((failures + 1))
    case " $failed_steps " in *" $step "*) ;; *) failed_steps="$failed_steps $step" ;; esac
    echo "  FAIL  $1"
    [ -z "${2:-}" ] || echo "        $2"
}

# check <what> <command...>: passes when the command exits 0.
check() {
    local what="$1" detail
    shift
    if detail="$("$@" 2>&1)"; then pass "$what"; else fail "$what" "$(echo "$detail" | head -3)"; fi
}

# equal <what> <actual> <expected>
equal() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got \`$2\`, expected \`$3\`"; fi
}

# holds <what> <text> <part>: passes when the text contains the part.
holds() {
    case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "\`$3\` isn't in \`$(echo "$2" | head -c 300)\`" ;; esac
}

# A path as the output names it: under the repository when it is there.
shown() {
    echo "${1#"$repo"/}"
}

# --- The two shells --------------------------------------------------------------

# The operator drives the app and holds the lease; the listener is another
# holder, as a second shell is.
operator() { VIDEO_REVIEW_CONTROL_KEY="acceptance-operator-$$" "$cli" "$@"; }
listener() { VIDEO_REVIEW_CONTROL_KEY="acceptance-listener-$$" "$cli" "$@"; }

state() { operator state --json | jq -r "${@:2}" "$1"; }

near() { jq -en --argjson a "$1" --argjson b "$2" --argjson by "$3" '($a - $b) | fabs <= $by' >/dev/null; }

is_png() { [ -f "$1" ] && [ "$(head -c 8 "$1" | xxd -p)" = "89504e470d0a1a0a" ]; }

png_size() { echo "$(sips -g pixelWidth "$1" | awk '/pixelWidth/ {print $2}')x$(sips -g pixelHeight "$1" | awk '/pixelHeight/ {print $2}')"; }

# shot <name> <appearance>: one screenshot, checked to be a PNG with a size.
shot() {
    local file="$shots/$1-$2.png"
    rm -f "$file"
    check "\`screenshot --appearance $2\` exits 0" operator screenshot "$file" --appearance "$2"
    if is_png "$file"; then pass "$(shown "$file") is a PNG, $(png_size "$file")"; else fail "$(shown "$file") is a PNG"; fi
}

# --- The run's folder -------------------------------------------------------------

temporary="${TMPDIR:-/tmp}"
work="$(mktemp -d "${temporary%/}/video-review-acceptance.XXXXXX")"
demo="$work/demo"
shots="${ACCEPTANCE_SCREENSHOTS:-$work/screenshots}"
mkdir -p "$shots"
shots="$(cd "$shots" && pwd)"
payload="$work/payload.json"
opened=0
second_wait=""
asking=""

finish() {
    [ -z "$second_wait" ] || kill "$second_wait" 2>/dev/null
    [ -z "$asking" ] || kill "$asking" 2>/dev/null
    [ "$opened" -eq 0 ] || operator app quit >/dev/null 2>&1
}
trap finish EXIT

echo "video-review acceptance: the v1 scenario of the spec, through the command line"
echo "command line: $cli"
echo "run's folder: $work"

# --- Step 1 -----------------------------------------------------------------------

begin 1 "open the app in demo mode"
opened=1
check "\`app open --demo <folder>\` exits 0" operator app open --demo "$demo"
check "\`state --json\` answers with JSON" state '.'
equal "the app keeps its data in the demo folder" "$(state "$state_support")" "$demo"

# --- Step 2 -----------------------------------------------------------------------

begin 2 "open the fixture video; seek, pause and add a comment"
check "\`player open\` exits 0" operator player open "$video"
equal "the state names the open video" "$(state "$state_video")" "$video"
check "\`player seek $moment_time\` exits 0" operator player seek "$moment_time"
check "\`player pause\` exits 0" operator player pause
check "\`comment add\` at the playhead exits 0" operator comment add "$moment_text"
equal "one comment, queued" "$(state "$state_states")" "queued"

# --- Step 3 -----------------------------------------------------------------------

begin 3 "add a second comment with a region"
check "\`comment add --at $region_seconds --region $region\` exits 0" \
    operator comment add "$region_text" --at "$region_seconds" --region "$region"
equal "two comments, queued" "$(state "$state_states")" "queued queued"
if operator comment add "outside the frame" --region 0.9,0.9,0.5,0.5 >/dev/null 2>&1; then
    fail "a region outside the frame is refused"
else
    pass "a region outside the frame is refused"
fi

# --- Step 4 -----------------------------------------------------------------------

begin 4 "send the batch"
check "\`batch send\` exits 0" operator batch send
equal "both comments are sent" "$(state "$state_states")" "sent sent"

# --- Step 5 -----------------------------------------------------------------------

begin 5 "a second shell's \`wait\` returns the batch"
listener wait --timeout 30 >"$payload"
equal "\`wait\` exits 0" "$?" "0"
if ! jq -e '.batch.id and (.comments | length > 0)' "$payload" >/dev/null 2>&1; then
    fail "\`wait\` prints the batch as one JSON object" "$(head -c 300 "$payload")"
    echo
    echo "FAILED: no batch to go on with (step 5)"
    exit 1
fi
pass "\`wait\` prints the batch as one JSON object"

# The listener keeps a `wait` open while it works, as the skill does, so the
# app shows it present.
listener wait --timeout 300 >/dev/null 2>&1 &
second_wait=$!

batch_id="$(jq -r '.batch.id' "$payload")"
check "batch: \`id\` and \`sentAt\`" jq -e '.batch | (.id | length > 0) and (.sentAt | length > 0)' "$payload"
equal "video: \`path\` is the fixture" "$(jq -r '.video.path' "$payload")" "$video"
check "video: \`contentHash\`, \`title\`, and a \`duration\` of 20 to 30 s" \
    jq -e '.video | (.contentHash | length > 0) and (.title | length > 0) and .duration > 20 and .duration < 30' "$payload"
equal "comments: two" "$(jq -r '.comments | length' "$payload")" "2"

context="$(jq -r '.context // ""' "$payload")"
missing=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$context" in *"$line"*) ;; *) missing="$line" ;; esac
done <"$sidecar"
if [ -n "$context" ] && [ -z "$missing" ]; then
    pass "context: every line of the fixture's sample.context.md"
else
    fail "context: every line of the fixture's sample.context.md" "missing \`$missing\`"
fi

# The two comments, told apart by their region, not by their order.
moment="$(jq -c '.comments[] | select(.region == null)' "$payload")"
pointed="$(jq -c '.comments[] | select(.region != null)' "$payload")"
moment_id="$(echo "$moment" | jq -r '.id')"
region_id="$(echo "$pointed" | jq -r '.id')"
check "each comment has an id of its own" test -n "$moment_id" -a -n "$region_id" -a "$moment_id" != "$region_id"

equal "comment at $moment_time: its text" "$(echo "$moment" | jq -r '.text')" "$moment_text"
check "comment at $moment_time: \`time\` is $moment_seconds s" near "$(echo "$moment" | jq '.time')" "$moment_seconds" 0.05
equal "comment at $moment_time: no crop" "$(echo "$moment" | jq -r '.cropPath')" "null"
keyframe="$(echo "$moment" | jq -r '.keyframePath')"
check "comment at $moment_time: the keyframe is a PNG at an absolute path" eval 'case "$keyframe" in /*) is_png "$keyframe" ;; *) false ;; esac'
equal "comment at $moment_time: the keyframe has the frame's size" "$(png_size "$keyframe")" "${frame_width}x${frame_height}"
holds "comment at $moment_time: the transcript window holds \"$moment_narration\"" \
    "$(echo "$moment" | jq -r "$payload_narration")" "$moment_narration"

equal "region comment: its text" "$(echo "$pointed" | jq -r '.text')" "$region_text"
check "region comment: \`time\` is $region_seconds s" near "$(echo "$pointed" | jq '.time')" "$region_seconds" 0.05
check "region comment: \`region\` is $region" jq -en --argjson got "$(echo "$pointed" | jq -c "$payload_region")" \
    --argjson sent "[$region]" '[range(4) | ($got[.] - $sent[.]) | fabs < 1e-6] | all'
region_keyframe="$(echo "$pointed" | jq -r '.keyframePath')"
check "region comment: the keyframe is a PNG at an absolute path" eval 'case "$region_keyframe" in /*) is_png "$region_keyframe" ;; *) false ;; esac'
equal "region comment: the keyframe has the frame's size" "$(png_size "$region_keyframe")" "${frame_width}x${frame_height}"
crop="$(echo "$pointed" | jq -r '.cropPath')"
check "region comment: the crop is a PNG at an absolute path" eval 'case "$crop" in /*) is_png "$crop" ;; *) false ;; esac'
# The region's size in the frame's pixels, a pixel either way for the rounding.
crop_size="$(png_size "$crop")"
check "region comment: the crop has the region's size ($crop_size)" jq -en --arg size "$crop_size" --argjson r "[$region]" \
    --argjson w "$frame_width" --argjson h "$frame_height" \
    '($size | split("x") | map(tonumber)) as $s | (($s[0] - $r[2] * $w) | fabs <= 1) and (($s[1] - $r[3] * $h) | fabs <= 1)'
holds "region comment: the transcript window holds \"$region_narration\"" \
    "$(echo "$pointed" | jq -r "$payload_narration")" "$region_narration"

# --- Step 6 -----------------------------------------------------------------------

begin 6 "acknowledge, ask and answer, then finish both comments with a reply"
check "\`ack\` exits 0" listener ack "$batch_id" "$ack_text"
equal "both comments are acknowledged" "$(state "$state_states")" "acknowledged acknowledged"

# The question waits in the listener's shell while the operator answers it.
# `thread answer` is refused until the question is there, so it is tried
# until the app takes it.
listener ask "$region_id" "$question" --wait 60 >"$work/answer.txt" 2>"$work/ask.err" &
asking=$!
answered=1
for _ in $(seq 1 40); do
    if operator thread answer "$region_id" "$answer" >/dev/null 2>&1; then
        answered=0
        break
    fi
    sleep 0.25
done
equal "\`thread answer\` exits 0" "$answered" "0"
wait "$asking"
equal "\`ask\` exits 0" "$?" "0"
asking=""
holds "\`ask\` prints the person's answer" "$(cat "$work/answer.txt")" "$answer"

check "\`status working\` on the region comment" listener status "$region_id" working
check "\`reply\` on the region comment" listener reply "$region_id" "$region_reply"
check "\`status done\` on the region comment" listener status "$region_id" done
# The other comment goes from acknowledged to done at once, as the spec's step does.
check "\`reply\` on the comment at $moment_time" listener reply "$moment_id" "$moment_reply"
check "\`status done\` on the comment at $moment_time, straight from acknowledged" listener status "$moment_id" done
check "\`reply\` on the batch" listener reply "$batch_id" "$batch_reply"

equal "both comments are done" "$(state "$state_states")" "done done"
region_thread="agent question $question
person answer $answer
agent message $region_reply"
equal "the region comment's thread: question, answer, reply" "$(state "$state_thread" --arg id "$region_id")" "$region_thread"
equal "the other comment's thread: reply" "$(state "$state_thread" --arg id "$moment_id")" "agent message $moment_reply"
holds "the state holds the batch's messages" "$(state 'tostring')" "$batch_reply"

# The review as the person sees it now: paused on the region comment's frame.
operator player seek "$region_seconds" >/dev/null
operator player pause >/dev/null
shot review light
shot review dark

# --- Step 7 -----------------------------------------------------------------------

begin 7 "quit and open the app again"
before="$(state "$state_review" -c)"
kill "$second_wait" 2>/dev/null
wait "$second_wait" 2>/dev/null
second_wait=""
check "\`app quit\` exits 0" operator app quit
if operator state --json >/dev/null 2>&1; then
    fail "nothing answers after the quit"
else
    pass "nothing answers after the quit"
fi
check "\`app open --demo <folder>\` exits 0 again" operator app open --demo "$demo"
check "\`player open\` on the same video exits 0" operator player open "$video"
after="$(state "$state_review" -c)"
equal "the comments, threads and statuses are the ones from before the quit" "$after" "$before"
equal "both comments are still done" "$(state "$state_states")" "done done"
equal "the region comment's thread is still question, answer, reply" "$(state "$state_thread" --arg id "$region_id")" "$region_thread"
check "the keyframes and the crop are still on disk" eval 'is_png "$keyframe" && is_png "$region_keyframe" && is_png "$crop"'

# --- Step 8 -----------------------------------------------------------------------

begin 8 "screenshots in light and dark"
operator player seek "$region_seconds" >/dev/null
operator player pause >/dev/null
shot restart light
shot restart dark
if cmp -s "$shots/restart-light.png" "$shots/restart-dark.png"; then
    fail "the light and the dark screenshot differ"
else
    pass "the light and the dark screenshot differ"
fi

check "\`app quit\` exits 0" operator app quit
opened=0

# --- The result ---------------------------------------------------------------------

echo
if [ "$failures" -eq 0 ]; then
    echo "PASSED: 8 of 8 steps, $checks checks"
    exit 0
fi
echo "FAILED: $failures of $checks checks, in step$failed_steps"
exit 1
