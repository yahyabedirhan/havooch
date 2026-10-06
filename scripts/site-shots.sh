#!/bin/bash
# Makes the landing page's screenshots in site/assets/shots/ from the app's
# screenshot gallery, as WebP files the page loads.
#
#   scripts/site-shots.sh [<gallery folder>]     (default: assets/screenshots/showcase,
#                                                 made by scripts/showcase.sh)
#
# The page refers to each image by its name on the left of SHOTS, never by its
# gallery path. To show a newer gallery, change the paths on the right (or pass
# the folder) and run this script again; the page needs no edit.
#
# Each line: <name on the page> <path in the gallery> <width> [<crop w:h:x:y>]
# Needs ffmpeg and cwebp (brew install ffmpeg webp).
set -euo pipefail

cd "$(dirname "$0")/.."
gallery="${1:-assets/screenshots/showcase}"
out="site/assets/shots"
mkdir -p "$out"

SHOTS="
hero-light      hero-light.png          2400
hero-dark       hero-dark.png           2400
list-light      list-light.png          1800
list-dark       list-dark.png           1800
question-light  question-light.png      1800
question-dark   question-dark.png       1800
chat-light      hero-light.png          680  676:1150:2346:325
chat-dark       hero-dark.png           680  676:1150:2346:325
theme-tokyo     tokyo-night-list.png    1800
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
