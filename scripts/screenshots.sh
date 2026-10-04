#!/bin/bash
# Makes the pictures in assets/screenshots/v1-acceptance/: a review in
# progress on the fixture video, in light and dark, through the `video-review`
# CLI only, against the installed app in demo mode.
#
#   make install && scripts/screenshots.sh [<folder for the PNG files>]
#
# The scene: two batches, with comments that are done, failed, working and
# acknowledged, a question with its answer, an open question, a queued comment
# and two region comments. The last pair keeps the lease banner in
# (`screenshot --with-banner`, an addition of this build to the spec's
# contract, which is why this is not part of scripts/acceptance.sh).
#
# Like the acceptance script, it stops at once when `app status --json` does
# not say "demo": true. The replies and their commit ids are scene text.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
variant="$(sed -n 's/.*static let variant = "\(.*\)".*/\1/p' "$root/Sources/ReviewWire/AppIdentity.swift" 2>/dev/null)"
cli="${VIDEO_REVIEW_CLI:-/Applications/Video Review${variant:+ ($variant)}.app/Contents/Helpers/video-review}"
video="$root/fixtures/sample/sample.mp4"

case "${1:-}" in
    "") shots="$root/assets/screenshots/v1-acceptance" ;;
    /*) shots="$1" ;;
    *) shots="$PWD/$1" ;;
esac

run_id="$(date +%Y%m%d-%H%M%S)-$$"
demo="$root/.scratch/screenshots/$run_id/demo"
operator_key="screenshots-operator-$run_id"
listener_key="screenshots-listener-$run_id"
on_demo=0

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

clean_up() {
    if [ "$on_demo" -eq 1 ]; then
        VIDEO_REVIEW_CONTROL_KEY="$operator_key" "$cli" app quit >/dev/null 2>&1
    fi
}
trap clean_up EXIT

# id <payload> <index>: the id of a comment in a batch, in time order.
id() { printf '%s' "$1" | jq -r ".comments[$2].id"; }

# pair <name> [--with-banner]: one view in both appearances.
pair() {
    local name="$1"
    shift
    operator screenshot "$shots/$name-light.png" --appearance light "$@" >/dev/null
    operator screenshot "$shots/$name-dark.png" --appearance dark "$@" >/dev/null
    echo "$shots/$name-light.png"
    echo "$shots/$name-dark.png"
}

command -v jq >/dev/null 2>&1 || fail "jq is needed and was not found"
[ -x "$cli" ] || fail "no video-review command at $cli; run make install, or set VIDEO_REVIEW_CLI"
mkdir -p "$shots"

operator app open --demo "$demo" >/dev/null
VIDEO_REVIEW_CONTROL_KEY="$operator_key" "$cli" app status --json | jq -e '.demo == true' >/dev/null 2>&1 \
    || fail 'app status --json does not say "demo": true; nothing more was sent to the app'
on_demo=1
operator control take >/dev/null
operator player open "$video" >/dev/null

# The first batch, finished: one comment done, one failed.
operator comment add "The intro goes by too fast. Hold this frame a second longer." --at 0:03 >/dev/null
operator comment add "Name the repo here, so a viewer can find the skill." --at 0:17 >/dev/null
operator batch send >/dev/null
first="$(listener wait --timeout 20)"
first_batch="$(printf '%s' "$first" | jq -r '.batch.id')"
listener ack "$first_batch" "Got your 2 comments, starting." >/dev/null
listener status "$(id "$first" 0)" working >/dev/null
listener reply "$(id "$first" 0)" "The first scene now holds for 1 s more: paddingSeconds is 1.4 in voiceover.json. Commit 4f2a91c." >/dev/null
listener status "$(id "$first" 0)" "done" >/dev/null
listener status "$(id "$first" 1)" working >/dev/null
listener reply "$(id "$first" 1)" "I can't change this one: the scene's source is in the explainer studio, not in this repo. Send it from there, or tell me where the studio's checkout is." >/dev/null
listener status "$(id "$first" 1)" failed >/dev/null
listener reply "$first_batch" "1 of 2 done. The comment at 0:17 needs the studio's repo." >/dev/null

# The second batch, in progress. The region comment is added last, so it is
# the selected one: its rectangle is on the frame and its thread is open.
operator comment add "\"Too fast here\" is my own note from above. Use another example." --at 0:07.5 >/dev/null
operator comment add "Show the three ways the agent can answer, not only the reply." --at 0:19.5 >/dev/null
operator comment add "Show the keys as the menu names them." --at 0:12.5 --region 0.47,0.27,0.29,0.15 >/dev/null
operator batch send >/dev/null
second="$(listener wait --timeout 20)"
second_batch="$(printf '%s' "$second" | jq -r '.batch.id')"
example="$(id "$second" 0)"
keys="$(id "$second" 1)"
listener ack "$second_batch" "Got your 3 comments. Starting with the keys." >/dev/null
listener status "$keys" working >/dev/null
VIDEO_REVIEW_CONTROL_KEY="$listener_key" "$cli" ask "$keys" "Which name do you want: Cmd+Return, as the menu says, or Cmd+Enter, as the narration says?" --wait 60 >/dev/null &
ask_pid=$!
sleep 2
operator thread answer "$keys" "Cmd+Return on the keys. Leave the narration as it is." >/dev/null
wait "$ask_pid" || fail "the ask was not answered"
listener reply "$keys" "The keys now read Cmd and Return. The narration is unchanged. Commit 9c03e7b." >/dev/null
listener status "$keys" "done" >/dev/null
listener status "$example" working >/dev/null

# The notices of the last messages go after 5 s.
sleep 6
echo "the thread, the region and the markers:"
pair review

# A question that waits for the person, and a new region comment in the queue.
# `ask --wait 0` leaves the question and exits 2 at once.
VIDEO_REVIEW_CONTROL_KEY="$listener_key" "$cli" ask "$example" "Which example do you want in its place: \"Zoom in on the diff.\", or one of your own?" --wait 0 >/dev/null
[ $? -eq 2 ] || fail "the open question was refused"
operator comment add "Add \"Send.\" as a third word, so the line tells the whole loop." --at 0:04 --region 0.63,0.64,0.3,0.21 >/dev/null
echo "an open question and a queued region comment:"
pair queue-and-question
echo "the same, with the lease banner:"
pair lease-banner --with-banner

operator control release >/dev/null
echo "done"
