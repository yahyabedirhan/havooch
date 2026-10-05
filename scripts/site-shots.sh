#!/bin/bash
# Makes the landing page's screenshots in site/assets/shots/ from the app's
# screenshot gallery, as WebP files the page loads.
#
#   scripts/site-shots.sh [<gallery folder>]     (default: assets/screenshots/0.2.0)
#
# The page refers to each image by its name on the left of SHOTS, never by its
# gallery path. To show a newer gallery, change the paths on the right (or pass
# the folder) and run this script again; the page needs no edit.
#
# Each line: <name on the page> <path in the gallery> <width> [<crop w:h:x:y>]
# Needs ffmpeg and cwebp (brew install ffmpeg webp).
set -euo pipefail

cd "$(dirname "$0")/.."
gallery="${1:-assets/screenshots/0.2.0}"
out="site/assets/shots"
mkdir -p "$out"

SHOTS="
hero-light      chat/default-light-answered-and-queued.png  2400
hero-dark       chat/default-dark-answered-and-queued.png   2400
list-light      sidebar/list-light.png                      1800
list-dark       sidebar/list-dark.png                       1800
question-light  chat/default-light-open-question.png        1800
question-dark   chat/default-dark-open-question.png         1800
chat-light      chat/default-light-answered-and-queued.png  680  680:830:2040:330
chat-dark       chat/default-dark-answered-and-queued.png   680  680:830:2040:330
composer-light  chat/default-light-answered-and-queued.png  660  660:262:2044:1170
composer-dark   chat/default-dark-answered-and-queued.png   660  660:262:2044:1170
theme-tokyo     sidebar/list-tokyo-night.png                1800
"

tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT

echo "$SHOTS" | while read -r name path width crop; do
  [ -z "$name" ] && continue
  filter="scale=${width}:-2:flags=lanczos"
  [ -n "${crop:-}" ] && filter="crop=${crop},${filter}"
  ffmpeg -loglevel error -y -i "$gallery/$path" -vf "$filter" "$tmp/$name.png"
  cwebp -quiet -q 84 -m 6 "$tmp/$name.png" -o "$out/$name.webp"
  echo "$out/$name.webp  <-  $gallery/$path"
done
