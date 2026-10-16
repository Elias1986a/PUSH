#!/bin/zsh
# Check a composition the way people will see it: stills at the size it is
# shown (website hero column, phone screen, ...), tiled into one sheet at
# out/check/<Id>.png, safe-zone guides on vertical frames, and the loudness of
# its render in out/<group>/ if there is one. Needs the full ffmpeg (Homebrew).
#   ./scripts/check.sh SocialPromo9x16            8 stills, evenly spaced
#   ./scripts/check.sh WebHero16x9 22.5 24 35     stills at these seconds
set -euo pipefail
cd "${0:A:h}/.."
(( $# )) || { echo "usage: $0 <CompositionId> [seconds...]" >&2; exit 64; }
id=$1; shift

line=$(npx remotion compositions 2>/dev/null | awk -v id="$id" '$1 == id { print $3, $4 }')
[[ -n $line ]] || { echo "$id: no such composition (see src/Root.tsx)" >&2; exit 64; }
size=${line%% *} frames=${line##* }
w=${size%x*} h=${size#*x}
fps=30
dur=$(( frames / 30.0 ))

times=("$@")
if (( ! ${#times} )); then
  for i in {0..7}; do times+=$(( dur * (i + 0.5) / 8 )); done
fi

# Width it is seen at, in CSS pixels: the site's hero column (laptop 16:9,
# phone 4:5), a phone screen for vertical social, a small player for 16:9.
case $id in
  Web*16x9) show=496 ;;
  Web*) show=327 ;;
  *16x9) show=640 ;;
  *) show=390 ;;
esac

# Safe zones (promo/PROMO-PLAYBOOK.md §1): text and key visuals inside the
# red box; on 9:16 the 4:5 crop is the white box and TikTok/Reels UI covers
# the gray strips.
guides=""
if (( h == 1920 )); then
  guides="drawbox=x=0:y=285:w=1080:h=1350:color=white@0.5:t=3,drawbox=x=0:y=1500:w=1080:h=420:color=gray@0.35:t=fill,drawbox=x=960:y=0:w=120:h=1500:color=gray@0.35:t=fill,drawbox=x=60:y=340:w=900:h=1160:color=red@0.8:t=3,"
elif (( h == 1350 )) && [[ $id == Social* ]]; then
  guides="drawbox=x=60:y=55:w=900:h=1160:color=red@0.8:t=3,"
fi

dir=out/check/$id
rm -rf $dir && mkdir -p $dir
i=0
for t in $times; do
  frame=$(printf "%.0f" $(( t * fps )))
  (( frame < frames )) || frame=$(( frames - 1 ))
  npx remotion still "$id" "$dir/full-$i.png" --frame=$frame --log=error
  ffmpeg -loglevel error -y -i "$dir/full-$i.png" -vf "${guides}scale=$show:-1:flags=lanczos" "$dir/$(printf %02d $i).png"
  printf "  %2d  %6.2f s  (frame %d)\n" $i $t $frame
  i=$(( i + 1 ))
done
cols=$(( i < 4 ? i : 4 )) rows=$(( (i + 3) / 4 ))
ffmpeg -loglevel error -y -framerate 1 -i "$dir/%02d.png" -vf "tile=${cols}x${rows}:padding=8:margin=8:color=0x808080" -frames:v 1 "out/check/$id.png"
echo "→ out/check/$id.png (${show} px wide each; full-size frames in $dir/)"

case $id in Web*) group=website ;; Social*) group=social ;; *) group=archive ;; esac
render=out/$group/$id.mp4
if [[ -f $render ]]; then
  ffmpeg -hide_banner -nostats -i "$render" -af ebur128=peak=true -f null - 2>&1 |
    awk '/Integrated loudness/ { s = 1 } s && /I:|Peak:/ { gsub(/^ +/, ""); printf "  %s\n", $0 }' | sed -n '1,2p'
  echo "  (target -14 LUFS, true peak ≤ -1 dBFS; render.sh normalizes)"
fi
