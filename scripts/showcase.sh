#!/bin/bash
# Plays a believable review of the showcase video (fixtures/showcase/, the
# Halcyon teaser) through the `havooch` CLI only, against the installed
# app in demo mode, and takes the landing page's pictures of it:
#
#   scripts/showcase.sh [<gallery folder>]     (default: assets/screenshots/showcase)
#
# Run it under the shared install lock, after `make install`, as the
# screenshot scripts are run. It takes the lease itself and gives it up at
# the end, also on failure, and leaves the app running on its demo folder
# (.scratch/showcase/<run>/demo).
#
# The review, as a person and Claude Code would have it. Threads are numbered
# in the order they are made, so the first send's four notes are #1 to #4:
#
#   #1 0:01.5  pacing: the cold open's numbers go by too fast       done
#   #2 0:12    typography: the wordmark is heavy (region); the agent
#              asks about the tagline, gets an answer and finishes;
#              a follow-up on the sunrise waits in the queue         done + queued
#   #3 0:26    a caption: two times on the rain card (region); the
#              agent asks which one should lead                     needs you (open question)
#   #4 0:40.5  the App Store badge (region): the agent can't add
#              Apple's artwork without the approved file            failed
#   #5 0:20.7  a transition: the phone leaves before the rain comes  with agent (working)
#   #6 0:34.8  colour: Thursday's tile reads cold (region)           queued
#   General    the agent's lines for each send, and the person's
#              note on the whole cut                                 queued
#
# The pictures, in light and dark (`<name>-light.png`, `<name>-dark.png`):
#
#   list      the thread list at #6's frame, every group shown
#   hero      thread #2's view: reply, question, answer, done and a
#             queued follow-up; the composer follows up on #2
#   question  thread #3's view at its frame: the open question
#   failed    thread #4's view: the honest reason it failed
#   working   thread #5's view: with the agent
# and, in the Tokyo Night theme (one picture each):
#   tokyo-night-list, tokyo-night-thread (thread #2's view)
#
# The operator holds the lease (HAVOOCH_CONTROL_KEY when set, else a
# key of this run). The listener has a key of its own and runs `wait`,
# `ack`, `status`, `reply` and `ask` only. Both carry CLAUDE_CODE_SESSION_ID,
# so the player names the agent Claude Code. The commit ids in the replies
# are scene text.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cli="${HAVOOCH_CLI:-${VIDEO_REVIEW_CLI:-/Applications/Havooch.app/Contents/Helpers/havooch}}"
video="$root/fixtures/showcase/halcyon-teaser.mp4"

case "${1:-}" in
    "") gallery="$root/assets/screenshots/showcase" ;;
    /*) gallery="$1" ;;
    *) gallery="$PWD/$1" ;;
esac

run_id="$(date +%Y%m%d-%H%M%S)-$$"
demo="$root/.scratch/showcase/$run_id/demo"
operator_key="${HAVOOCH_CONTROL_KEY:-${VIDEO_REVIEW_CONTROL_KEY:-showcase-operator-$run_id}}"
listener_key="${HAVOOCH_LISTENER_KEY:-${VIDEO_REVIEW_LISTENER_KEY:-showcase-listener-$run_id}}"
export CLAUDE_CODE_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-showcase-$run_id}"
holds_lease=0
listener_pid=""

fail() {
    echo "showcase: $1" >&2
    exit 1
}

# Every command must succeed: a scene with a step missing is the wrong picture.
operator() {
    HAVOOCH_CONTROL_KEY="$operator_key" "$cli" "$@" || fail "refused: havooch $*"
}
listener() {
    HAVOOCH_CONTROL_KEY="$listener_key" "$cli" "$@" || fail "refused: havooch $*"
}
# ask <thread> <question>: leaves the question open; `--wait 0` exits 2 at once.
ask() {
    HAVOOCH_CONTROL_KEY="$listener_key" "$cli" ask "$1" "$2" --wait 0 >/dev/null
    [ $? -eq 2 ] || fail "the question on $1 was refused"
}

clean_up() {
    [ -n "$listener_pid" ] && kill "$listener_pid" 2>/dev/null
    [ "$holds_lease" -eq 1 ] && HAVOOCH_CONTROL_KEY="$operator_key" "$cli" control release >/dev/null 2>&1
}
trap clean_up EXIT

require_demo() {
    HAVOOCH_CONTROL_KEY="$operator_key" "$cli" app status --json | jq -e '.demo == true' >/dev/null 2>&1 \
        || fail 'app status --json does not say "demo": true; nothing more was sent to the app'
}

message() { printf '%s' "$1" | jq -r '.message.id'; }
thread() { printf '%s' "$1" | jq -r '.thread.id'; }
check() { [ -n "$(message "$1")" ] && [ "$(message "$1")" != "null" ] || fail "a message was refused"; }

# shot <name> [<flags>]: one picture in both appearances.
shot() {
    local name="$1"
    shift
    operator screenshot "$gallery/$name-light.png" --appearance light --hide-agent-indicator "$@" >/dev/null
    operator screenshot "$gallery/$name-dark.png" --appearance dark --hide-agent-indicator "$@" >/dev/null
    echo "  $gallery/$name-light.png"
    echo "  $gallery/$name-dark.png"
}

command -v jq >/dev/null 2>&1 || fail "jq is needed and was not found"
[ -x "$cli" ] || fail "no havooch command at $cli; run make install, or set HAVOOCH_CLI"
[ -f "$video" ] || fail "no showcase video at $video"
mkdir -p "$gallery" "$demo"

# --- the demo app, under the lease --------------------------------------------

# A running app answers only to the lease holder: take it first. Opening the
# demo folder relaunches the app on it and hands the lease over.
if HAVOOCH_CONTROL_KEY="$operator_key" "$cli" app status --json 2>/dev/null | jq -e '.running == true' >/dev/null 2>&1; then
    operator control take --wait 1800 >/dev/null
    holds_lease=1
    operator app open --demo "$demo" >/dev/null
else
    operator app open --demo "$demo" >/dev/null
    operator control take --wait 1800 >/dev/null
    holds_lease=1
fi
require_demo
operator theme set system >/dev/null
operator player open "$video" >/dev/null

# --- the first send: four notes ------------------------------------------------

numbers="$(operator comment add "The numbers flick past before I can read them. Hold each one about half a beat longer, it's the hook." --at 1.5 --json)"
wordmark="$(operator comment add "The wordmark feels heavy against the sky. Try a lighter weight and open the tracking a little." --at 12 --region 0.075,0.27,0.5,0.28 --json)"
card="$(operator comment add "The card says rain at 4:40, the voice says leave by four fifteen. Two times in two seconds is a lot. Pick one to lead." --at 26 --region 0.07,0.29,0.48,0.33 --json)"
badge="$(operator comment add "Put the App Store badge under the date, so it feels like a real launch." --at 40.5 --region 0.07,0.75,0.37,0.08 --json)"
for added in "$numbers" "$wordmark" "$card" "$badge"; do check "$added"; done
operator send >/dev/null

first="$(listener wait --timeout 20)"
listener ack "$(printf '%s' "$first" | jq -r '.send.id')" "Got your 4 notes on 4 threads. Starting with the cold open." >/dev/null

listener status "$(message "$numbers")" working >/dev/null
listener reply "$(thread "$numbers")" "Each reading now holds 18 frames longer and eases out instead of cutting. The cold open runs 1.2 s longer. Commit 3c1e7a2." >/dev/null
listener status "$(message "$numbers")" done >/dev/null

listener status "$(message "$wordmark")" working >/dev/null
listener reply "$(thread "$wordmark")" "Took Halcyon from 400 down to 300 and opened the tracking to 0.01 em. It sits on the sky much more quietly now." >/dev/null
ask "$(thread "$wordmark")" "Should the tagline go lighter with it, or stay at 500 so it still reads over the bright part of the sky?"
operator thread answer "$(thread "$wordmark")" "Keep it at 500, it has to read." >/dev/null
listener reply "$(thread "$wordmark")" "Kept the tagline at 500 and moved it 12 px down, so it clears the sun's glow. Commit 9b4d1e0." >/dev/null
listener status "$(message "$wordmark")" done >/dev/null

listener status "$(message "$card")" working >/dev/null
listener reply "$(thread "$card")" "Both are right: the rain starts at 4:40, and 4:15 is when to leave. Before I touch the card, one question." >/dev/null
ask "$(thread "$card")" "Should the card lead with \"Leave by 4:15\" to match the voice, or keep \"Rain at 4:40 pm\" up top and let the voice carry the leave time?"

listener status "$(message "$badge")" working >/dev/null
listener reply "$(thread "$badge")" "I left this one out. Apple's badge has to come from their marketing site, under their rules, and there's no copy in the repo. Drop the approved SVG into assets/ and I'll place it." >/dev/null
listener status "$(message "$badge")" failed >/dev/null

listener reply 0 "#1 and #2 are done. #4 failed: it needs Apple's badge file. #3 waits on your answer." >/dev/null

# --- the second send: a transition, with the agent ------------------------------

phone="$(operator comment add "The phone jumps out before the rain comes in. Let it ease out, and start the rain underneath it." --at 20.7 --json)"
check "$phone"
operator send >/dev/null
second="$(listener wait --timeout 20)"
listener ack "$(printf '%s' "$second" | jq -r '.send.id')" "Got it, looking at the cut into the rain." >/dev/null
listener status "$(message "$phone")" working >/dev/null

# --- in the queue: a follow-up, a new note and a word on the whole cut ----------

check "$(operator comment add "Lovely. Can the sun rise a touch slower behind it?" --thread "$(thread "$wordmark")" --json)"
tile="$(operator comment add "Soft rain reads a little cold next to Wednesday. Warm the blue a touch, toward lavender." --at 34.8 --region 0.44,0.33,0.13,0.53 --json)"
check "$tile"
check "$(operator comment add "Overall this is so close. The voice and the colour are lovely, please don't touch them." --thread 0 --json)"

# The listener waits again, so the footer shows it with the agent.
HAVOOCH_CONTROL_KEY="$listener_key" "$cli" wait --timeout 900 >/dev/null 2>&1 &
listener_pid=$!

# --- the pictures ----------------------------------------------------------------

# The notices of the last messages go after 5 s.
operator player seek 34.8 >/dev/null
operator thread list >/dev/null
sleep 6
echo "the thread list, at Thursday's tile:"
shot list

operator thread show "$(thread "$wordmark")" >/dev/null
sleep 1
echo "thread #2: reply, question, answer, done, and a follow-up in the queue:"
shot hero

operator thread show "$(thread "$card")" >/dev/null
sleep 1
echo "thread #3: the open question:"
shot question

operator thread show "$(thread "$badge")" >/dev/null
sleep 1
echo "thread #4: failed, with its reason:"
shot failed

operator thread show "$(thread "$phone")" >/dev/null
sleep 1
echo "thread #5: with the agent:"
shot working

operator theme set "Tokyo Night" >/dev/null
operator thread list >/dev/null
operator player seek 26 >/dev/null
sleep 1
operator screenshot "$gallery/tokyo-night-list.png" --hide-agent-indicator >/dev/null
operator thread show "$(thread "$wordmark")" >/dev/null
sleep 1
operator screenshot "$gallery/tokyo-night-thread.png" --hide-agent-indicator >/dev/null
echo "Tokyo Night:"
echo "  $gallery/tokyo-night-list.png"
echo "  $gallery/tokyo-night-thread.png"

operator theme set system >/dev/null
operator thread list >/dev/null
operator player seek 12 >/dev/null

kill "$listener_pid" 2>/dev/null; wait "$listener_pid" 2>/dev/null
listener_pid=""
operator control release >/dev/null
holds_lease=0
echo "done; the app stays on $demo"
