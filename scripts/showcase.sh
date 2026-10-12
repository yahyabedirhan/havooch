#!/bin/bash
# Plays a believable review of the showcase video (fixtures/showcase/, the
# Lantern teaser) through the `havooch` CLI only, against the installed
# app in demo mode, and takes the pictures of it:
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
#   #1 0:01.5  pacing: the request line types too fast to read      done
#   #2 0:09.5  typography: the wordmark is heavy (region); the agent
#              asks about the tagline, gets an answer and finishes;
#              a follow-up on the mark's unfold waits in the queue   done + queued
#   #3 0:26    a label: three times on the trace (region); the
#              agent asks which one should lead                     needs you (open question)
#   #4 0:18.5  the Postgres logo (region): the agent can't add the
#              project's trademark without the approved file        failed
#   #5 0:19.3  a transition: the map cuts to the trace too fast      with agent (working)
#   #6 0:33    colour: the fix panel pulls the eye (region)          queued
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

# An agent's check plays no sound on the person's Mac: `app open --demo`
# passes HAVOOCH_MUTED=1 on to the app it launches.
export HAVOOCH_MUTED=1
cli="${HAVOOCH_CLI:-/Applications/Havooch.app/Contents/Helpers/havooch}"
video="$root/fixtures/showcase/lantern-teaser.mp4"

case "${1:-}" in
    "") gallery="$root/assets/screenshots/showcase" ;;
    /*) gallery="$1" ;;
    *) gallery="$PWD/$1" ;;
esac

run_id="$(date +%Y%m%d-%H%M%S)-$$"
demo="$root/.scratch/showcase/$run_id/demo"
operator_key="${HAVOOCH_CONTROL_KEY:-showcase-operator-$run_id}"
listener_key="${HAVOOCH_LISTENER_KEY:-showcase-listener-$run_id}"
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

request="$(operator comment add "The request line types too fast to read the path. Slow the typing a little, it's the hook." --at 1.5 --json)"
wordmark="$(operator comment add "The wordmark feels heavy next to the folded mark. Try a lighter weight and open the tracking a little." --at 9.5 --region 0.37,0.35,0.4,0.18 --json)"
label="$(operator comment add "The label says 1.12 s, the Payments bar says 1.31 s, and the voice says more than a second. Three times in two seconds is a lot. Pick one to lead." --at 26 --region 0.46,0.74,0.33,0.1 --json)"
logo="$(operator comment add "Put the Postgres elephant on the Postgres node, so the map reads at a glance." --at 18.5 --region 0.8,0.29,0.15,0.15 --json)"
for added in "$request" "$wordmark" "$label" "$logo"; do check "$added"; done
operator send >/dev/null

first="$(listener wait --timeout 20)"
listener ack "$(printf '%s' "$first" | jq -r '.send.id')" "Got your 4 notes on 4 threads. Starting with the cold open." >/dev/null

listener status "$(message "$request")" working >/dev/null
listener reply "$(thread "$request")" "The path now types 40 percent slower and the time counts up only after it lands. The cold open runs 0.8 s longer. Commit 3c1e7a2." >/dev/null
listener status "$(message "$request")" done >/dev/null

listener status "$(message "$wordmark")" working >/dev/null
listener reply "$(thread "$wordmark")" "Took Lantern from 600 down to 500 and opened the tracking to 0.01 em. It balances the mark much better now." >/dev/null
ask "$(thread "$wordmark")" "Should the tagline go lighter with it, or stay at 400 so it still reads at small sizes?"
operator thread answer "$(thread "$wordmark")" "Keep it at 400, it has to read." >/dev/null
listener reply "$(thread "$wordmark")" "Kept the tagline at 400 and moved it 8 px closer to the wordmark. Commit 9b4d1e0." >/dev/null
listener status "$(message "$wordmark")" done >/dev/null

listener status "$(message "$label")" working >/dev/null
listener reply "$(thread "$label")" "All three are right: the query takes 1.12 s inside the 1.31 s Payments call. Before I touch the label, one question." >/dev/null
ask "$(thread "$label")" "Should the label lead with the query's 1.12 s, or with Payments' 1.31 s to match the bar the voice points at?"

listener status "$(message "$logo")" working >/dev/null
listener reply "$(thread "$logo")" "I left this one out. The elephant is the PostgreSQL project's trademark, used under their rules, and there's no copy in the repo. Drop their official SVG into assets/ and I'll place it." >/dev/null
listener status "$(message "$logo")" failed >/dev/null

listener reply 0 "#1 and #2 are done. #4 failed: it needs the Postgres logo file. #3 waits on your answer." >/dev/null

# --- the second send: a transition, with the agent ------------------------------

cut="$(operator comment add "The map cuts to the trace too fast. Let the Payments node slide down into its row in the trace." --at 19.3 --json)"
check "$cut"
operator send >/dev/null
second="$(listener wait --timeout 20)"
listener ack "$(printf '%s' "$second" | jq -r '.send.id')" "Got it, looking at the cut into the trace." >/dev/null
listener status "$(message "$cut")" working >/dev/null

# --- in the queue: a follow-up, a new note and a word on the whole cut ----------

check "$(operator comment add "Lovely. Can the mark unfold a touch slower?" --thread "$(thread "$wordmark")" --json)"
panel="$(operator comment add "The fix panel is so bright it pulls the eye off the drop. Tone the white down a touch, or let the chart land first." --at 33 --region 0.64,0.3,0.31,0.42 --json)"
check "$panel"
check "$(operator comment add "Overall this is so close. The voice and the folds are lovely, please don't touch them." --thread 0 --json)"

# The listener waits again, so the footer shows it with the agent.
HAVOOCH_CONTROL_KEY="$listener_key" "$cli" wait --timeout 900 >/dev/null 2>&1 &
listener_pid=$!

# --- the pictures ----------------------------------------------------------------

# The notices of the last messages go after 5 s.
operator player seek 33 >/dev/null
operator thread list >/dev/null
sleep 6
echo "the thread list, at the fix panel:"
shot list

operator thread show "$(thread "$wordmark")" >/dev/null
sleep 1
echo "thread #2: reply, question, answer, done, and a follow-up in the queue:"
shot hero

operator thread show "$(thread "$label")" >/dev/null
sleep 1
echo "thread #3: the open question:"
shot question

operator thread show "$(thread "$logo")" >/dev/null
sleep 1
echo "thread #4: failed, with its reason:"
shot failed

operator thread show "$(thread "$cut")" >/dev/null
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
operator player seek 9.5 >/dev/null

kill "$listener_pid" 2>/dev/null; wait "$listener_pid" 2>/dev/null
listener_pid=""
operator control release >/dev/null
holds_lease=0
echo "done; the app stays on $demo"
