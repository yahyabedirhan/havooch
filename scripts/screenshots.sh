#!/bin/bash
# Makes the 0.1.0 gallery for the pull request, through the `video-review`
# CLI only, against the installed app in demo mode with the fixture video:
#
#   states/<state>-<light|dark>.png   the main states, in both appearances
#   themes/<slug>.png                 every built-in theme on one scene
#
# in assets/screenshots/0.1.0/, or in the folder given.
#
#   make install && scripts/screenshots.sh [<gallery folder>]
#
# The states:
#
#   empty           the empty screen: the drop target, "Open a video" and "Try the demo"
#   threads         a review with threads in every state (done, failed, working,
#                   sent, queued) and their pins on the player bar, at a region
#                   thread's frame
#   sidebar         a thread view, with an agent reply and a question
#   thread-popover  a thread's popover on the video
#   agent-control   the header with the agent-control icon, and the footer with
#                   the listener's presence, the queued count and Send
#   dimmed          the Dimmed theme
#   comment-popover the comment popover on a region (`comment open --region`)
#
# The themes: every built-in theme of `theme list`, pinned in turn, on the
# threads scene with thread #3 shown in the sidebar. A pinned theme looks
# the same in both appearances, so each has one picture, named after the
# theme in lowercase with hyphens (`Atom One Light` is atom-one-light.png).
#
# A state whose view or command is not built yet is a PENDING step: the script
# says what it waits on and makes no picture for it. Each one is marked
# "PENDING" below, with the command to put in its place.
#
# Every picture but agent-control leaves the agent-control indicator out
# (`screenshot --hide-agent-indicator`). Like the acceptance script, it stops
# at once when `app status --json` does not say "demo": true. The operator is
# VIDEO_REVIEW_CONTROL_KEY when it is set; the listener has a key of its own.
# The replies and their commit ids are scene text.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cli="${VIDEO_REVIEW_CLI:-/Applications/Video Review.app/Contents/Helpers/video-review}"
video="$root/fixtures/sample/sample.mp4"

case "${1:-}" in
    "") gallery="$root/assets/screenshots/0.1.0" ;;
    /*) gallery="$1" ;;
    *) gallery="$PWD/$1" ;;
esac
shots="$gallery/states"
theme_shots="$gallery/themes"

run_id="$(date +%Y%m%d-%H%M%S)-$$"
demo="$root/.scratch/screenshots/$run_id"
operator_key="${VIDEO_REVIEW_CONTROL_KEY:-screenshots-operator-$run_id}"
listener_key="${VIDEO_REVIEW_LISTENER_KEY:-screenshots-listener-$run_id}"
holds_lease=0
listener_pid=""
taken=()
pending_states=()

fail() {
    echo "screenshots: $1" >&2
    exit 1
}

# Every command must succeed: a scene with a step missing is the wrong picture.
operator() {
    VIDEO_REVIEW_CONTROL_KEY="$operator_key" "$cli" "$@" || fail "refused: video-review $*"
}
listener() {
    VIDEO_REVIEW_CONTROL_KEY="$listener_key" "$cli" "$@" || fail "refused: video-review $*"
}

# The background `wait` ends and the lease is free. The demo app keeps
# running: other agents may be in line for it.
clean_up() {
    [ -n "$listener_pid" ] && kill "$listener_pid" 2>/dev/null
    [ "$holds_lease" -eq 1 ] && VIDEO_REVIEW_CONTROL_KEY="$operator_key" "$cli" control release >/dev/null 2>&1
}
trap clean_up EXIT

require_demo() {
    VIDEO_REVIEW_CONTROL_KEY="$operator_key" "$cli" app status --json | jq -e '.demo == true' >/dev/null 2>&1 \
        || fail 'app status --json does not say "demo": true; nothing more was sent to the app'
}

# pair <state> [--hide-agent-indicator]: one state in both appearances.
pair() {
    local name="$1"
    shift
    operator screenshot "$shots/$name-light.png" --appearance light "$@" >/dev/null
    operator screenshot "$shots/$name-dark.png" --appearance dark "$@" >/dev/null
    echo "  $shots/$name-light.png"
    echo "  $shots/$name-dark.png"
    taken+=("$name")
}

# pending <state> <ticket> <what is missing>: a state the CLI can't reach yet.
pending() {
    echo "PENDING  $1: waits on $2: $3"
    pending_states+=("$1 [$2]")
}

# message <json>: the id of the message a `comment add --json` queued.
message() { printf '%s' "$1" | jq -r '.message.id'; }
thread() { printf '%s' "$1" | jq -r '.thread.id'; }

command -v jq >/dev/null 2>&1 || fail "jq is needed and was not found"
[ -x "$cli" ] || fail "no video-review command at $cli; run make install, or set VIDEO_REVIEW_CLI"
mkdir -p "$shots" "$theme_shots"

# --- the empty screen --------------------------------------------------------

# A running app answers only to the lease holder: take it first. With no app
# running, the open launches one and the lease is taken from it.
if VIDEO_REVIEW_CONTROL_KEY="$operator_key" "$cli" app status --json 2>/dev/null | jq -e '.running == true' >/dev/null 2>&1; then
    operator control take --wait 1800 >/dev/null
    holds_lease=1
    operator app open --demo "$demo/empty" >/dev/null
    require_demo
else
    operator app open --demo "$demo/empty" >/dev/null
    require_demo
    operator control take --wait 1800 >/dev/null
    holds_lease=1
fi
operator theme set system >/dev/null
echo "the empty screen:"
pair empty --hide-agent-indicator

# --- a review with a thread in every state -----------------------------------

# Another demo folder: the app relaunches on it and hands the lease over.
operator app open --demo "$demo/review" >/dev/null
require_demo
operator theme set system >/dev/null
operator player open "$video" >/dev/null

# The first send: #1 done, #2 failed, #3 working with an open question.
operator player seek 3 >/dev/null
intro="$(operator comment add "The intro goes by too fast. Hold this frame a second longer." --json)"
operator player seek 7.5 >/dev/null
words="$(operator comment add "\"Too fast here\" is my own note from above. Use another example." --region 0.1,0.55,0.5,0.2 --json)"
operator player seek 12.5 >/dev/null
keys="$(operator comment add "Show the keys as the menu names them." --region 0.47,0.27,0.29,0.15 --json)"
# A refusal inside $( ) ends only the subshell: check that each message is there.
for added in "$intro" "$words" "$keys"; do
    [ "$(message "$added")" != "null" ] && [ -n "$(message "$added")" ] || fail "a message of the first send was refused"
done
operator send >/dev/null
first="$(listener wait --timeout 20)"
listener ack "$(printf '%s' "$first" | jq -r '.send.id')" "Got your 3 messages on 3 threads, starting." >/dev/null
listener status "$(message "$intro")" working >/dev/null
listener reply "$(thread "$intro")" "The first scene now holds for 1 s more: paddingSeconds is 1.4 in voiceover.json. Commit 4f2a91c." >/dev/null
listener status "$(message "$intro")" "done" >/dev/null
listener status "$(message "$words")" working >/dev/null
listener reply "$(thread "$words")" "I can't change this one: the scene's source is in the explainer studio, not in this repo." >/dev/null
listener status "$(message "$words")" failed >/dev/null
listener status "$(message "$keys")" working >/dev/null
listener reply "$(thread "$keys")" "Both names are in the video. I'll ask before I change one." >/dev/null
# `ask --wait 0` leaves the question open and exits 2 at once.
VIDEO_REVIEW_CONTROL_KEY="$listener_key" "$cli" ask "$(thread "$keys")" \
    "Which name do you want: Cmd+Return, as the menu says, or Cmd+Enter, as the narration says?" --wait 0 >/dev/null
[ $? -eq 2 ] || fail "the open question was refused"

# The second send, taken and not acknowledged yet: #4 sent.
operator player seek 17 >/dev/null
operator comment add "Name the repo here, so a viewer can find the skill." >/dev/null
operator send >/dev/null
listener wait --timeout 20 >/dev/null

# A message still in the queue: #5 queued.
operator player seek 19.5 >/dev/null
operator comment add "Show the three ways the agent can answer, not only the reply." --region 0.55,0.6,0.4,0.3 >/dev/null

# The listener waits again, so the footer shows it present.
VIDEO_REVIEW_CONTROL_KEY="$listener_key" "$cli" wait --timeout 900 >/dev/null 2>&1 &
listener_pid=$!

# Thread #3's frame: its region and its badge are on the video. The notices
# of the last messages go after 5 s.
operator player seek 12.5 >/dev/null
sleep 6
echo "threads in every state, with their pins:"
pair threads --hide-agent-indicator

# Thread #3 shown, with its reply, its open question and its region's
# crop.
operator thread show "$(thread "$keys")" >/dev/null
sleep 1
echo "a thread view in the sidebar:"
pair sidebar --hide-agent-indicator

# Thread #3's popover, as a click on its pin opens it: its conversation with
# the agent's open question above the field, beside its region.
operator thread open "$(thread "$keys")" >/dev/null
sleep 1
echo "a thread's popover on the video:"
pair thread-popover --hide-agent-indicator
# A seek closes the empty popover, as a change of the moment does.
operator player seek 12.5 >/dev/null

# The header and the footer of #32: the agent-control icon shows while this
# script holds the lease; the footer shows the listener and the queued count.
echo "the agent-control indicator, the header and the footer:"
pair agent-control

# --- the Dimmed theme --------------------------------------------------------

operator theme set Dimmed >/dev/null
sleep 1
echo "the Dimmed theme:"
pair dimmed --hide-agent-indicator
operator theme set system >/dev/null

# --- every built-in theme ----------------------------------------------------

# The threads scene, with thread #3 shown and no popover open.
operator thread show "$(thread "$keys")" >/dev/null
echo "every built-in theme:"
themes="$(operator theme list --json | jq -r '.themes[] | select(.source == "built-in") | .name')"
[ -n "$themes" ] || fail "theme list --json names no built-in theme"
while IFS= read -r name; do
    slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
    operator theme set "$name" >/dev/null
    sleep 1
    operator screenshot "$theme_shots/$slug.png" --hide-agent-indicator >/dev/null
    echo "  $theme_shots/$slug.png"
    taken+=("theme:$slug")
done <<< "$themes"
operator theme set system >/dev/null

# --- the comment popover on a region -----------------------------------------

# Last: a seek would queue the popover's text. A frame with no thread, so
# the popover starts thread #6, and still: 1.5 s is in the first scene,
# not in a cross-fade. The region is the scene's title.
operator player seek 1.5 >/dev/null
operator comment open "The title and the subtitle overlap here." --region 0.62,0.6,0.32,0.27 >/dev/null
sleep 1
echo "the comment popover on a region:"
pair comment-popover --hide-agent-indicator

kill "$listener_pid" 2>/dev/null; wait "$listener_pid" 2>/dev/null
listener_pid=""
operator control release >/dev/null
holds_lease=0

echo
echo "taken:   ${taken[*]}"
if [ "${#pending_states[@]}" -gt 0 ]; then
    echo "pending: ${pending_states[*]}"
fi
echo "done"
