#!/bin/zsh
# Make the website's copies of the hero from the masters in out/website/
# (run ./scripts/render.sh WebHero16x9 WebHero4x5 first): small H.264 files and
# a poster for each, written straight into website/assets/video/.
#   WebHero16x9 → hero.mp4 + hero.jpg      (laptops and up)
#   WebHero4x5  → hero-4x5.mp4 + hero-4x5.jpg   (phones)
set -euo pipefail
cd "${0:A:h}/.."
site=../../website/assets/video
poster_at=2.0 # seconds in: the pill streaming words under "Hold a key and talk."

for pair in WebHero16x9:hero WebHero4x5:hero-4x5; do
  id=${pair%%:*} name=${pair#*:}
  src=out/website/$id.mp4
  [[ -f $src ]] || { echo "missing $src: render it first" >&2; exit 1; }
  npx remotion ffmpeg -loglevel error -y -i "$src" \
    -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
    -c:a aac -b:a 128k -movflags +faststart "$site/$name.mp4"
  npx remotion ffmpeg -loglevel error -y -ss $poster_at -i "$src" -frames:v 1 -q:v 3 "$site/$name.jpg"
  echo "→ website/assets/video/$name.mp4 ($(du -h "$site/$name.mp4" | cut -f1)) + $name.jpg"
done
