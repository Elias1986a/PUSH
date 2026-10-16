#!/bin/zsh
# Render compositions to out/<group>/<Id>.mp4 (group from the id: Web… → website,
# Social… → social, Archive… → archive), then normalize the audio for delivery
# (-14 LUFS, true peak -1 dB; promo/PROMO-PLAYBOOK.md §4) with the ffmpeg
# Remotion ships, so nothing else needs installing.
#   ./scripts/render.sh SocialPromo16x9 SocialPromo9x16    1080p
#   ./scripts/render.sh --4k SocialPromo16x9               2× scale, <Id>-4k.mp4
set -euo pipefail
cd "${0:A:h}/.."

scale=() suffix=""
if [[ ${1:-} == --4k ]]; then
  # A small Mac runs out of memory at 4K with the default concurrency.
  scale=(--scale=2 --concurrency=1) suffix="-4k"
  shift
fi
(( $# )) || { echo "usage: $0 [--4k] <CompositionId>..." >&2; exit 64; }

for id in "$@"; do
  case $id in
    Web*) dir=out/website ;;
    Social*) dir=out/social ;;
    Archive*) dir=out/archive ;;
    *) echo "$id: ids start with Web, Social or Archive (see src/Root.tsx)" >&2; exit 64 ;;
  esac
  mkdir -p $dir
  raw="$dir/.$id$suffix-raw.mp4" final="$dir/$id$suffix.mp4"
  npx remotion render "$id" "$raw" --crf=16 $scale
  npx remotion ffmpeg -loglevel error -y -i "$raw" -c:v copy \
    -af loudnorm=I=-14:TP=-1.0:LRA=7 -ar 48000 -c:a aac -b:a 256k \
    -movflags +faststart "$final"
  rm "$raw"
  echo "→ $final"
done
