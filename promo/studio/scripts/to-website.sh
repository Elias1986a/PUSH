#!/bin/zsh
# Make the website's copies of the hero from the masters in out/website/
# (run ./scripts/render.sh WebHero16x9 WebHero4x5 first): small H.264 files and
# a poster for each, written straight into website/assets/video/.
#   WebHero16x9 → hero.mp4 + hero.jpg          (laptops and up)
#   WebHero4x5  → hero-4x5.mp4 + hero-4x5.jpg  (phones)
# Posters: the 16:9 at TYPE's gray "think!" just before Tab, the 4:5 on the
# pasted paragraph (seconds into each video; move them if the cut changes).
set -euo pipefail
cd "${0:A:h}/.."
site=../../website/assets/video
for spec in WebHero16x9:hero:34.8 WebHero4x5:hero-4x5:14.5; do
  id=${spec%%:*} rest=${spec#*:} name=${rest%%:*} poster_at=${rest#*:}
  src=out/website/$id.mp4
  [[ -f $src ]] || { echo "missing $src: render it first" >&2; exit 1; }
  npx remotion ffmpeg -loglevel error -y -i "$src" \
    -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
    -c:a aac -b:a 128k -movflags +faststart "$site/$name.mp4"
  npx remotion ffmpeg -loglevel error -y -ss $poster_at -i "$src" -frames:v 1 -q:v 3 "$site/$name.jpg"
  echo "→ website/assets/video/$name.mp4 ($(du -h "$site/$name.mp4" | cut -f1)) + $name.jpg"
done
