#!/bin/zsh
# The website's speed numbers, measured again in one command: release to text
# on screen for the installed PUSHTYPE (each speech model) and Wispr Flow,
# through the compare app's end-to-end mode (compare/Sources/compare/EndToEnd.swift).
#
#   scripts/speedtest.sh [RUNS]          # default 25 per app and model
#   MODELS="parakeet-ultra" WISPR=0 scripts/speedtest.sh 5
#
# Takes over the Mac for ~45 minutes at 25 runs: the recording plays through
# the speakers at full volume and the compare window must stay in front.
# Rewriting and audio ducking are switched off for the runs; every setting it
# touches, the volume, and whether Wispr Flow was open are put back at the end.
set -u
RUNS=${1:-25}
MODELS=(${=MODELS:-parakeet-streaming parakeet-ultra})
WISPR=${WISPR:-1}
REPO=${0:A:h:h}
DOMAIN=com.push.voicetotext
LOG="$HOME/Library/Application Support/PUSH/push_debug.log"
RESULTS="$HOME/Library/Application Support/PUSHCompare/endtoend.jsonl"
COMPARE="$REPO/compare/.build/debug/compare"

(cd "$REPO/compare" && swift build -q) || { echo "compare didn't build"; exit 1; }

saved_model=$(defaults read $DOMAIN selectedWhisperModel 2>/dev/null)
saved_media=$(defaults read $DOMAIN mediaBehavior 2>/dev/null)
saved_rewrite=$(defaults read $DOMAIN talkAutocorrectModel 2>/dev/null)
saved_volume=$(osascript -e 'output volume of (get volume settings)')
pgrep -qf "Wispr Flow.app/Contents/MacOS/Wispr Flow" && wispr_was_open=1 || wispr_was_open=0

quit_wispr() { pkill -f "Wispr Flow.app/Contents/MacOS/Wispr Flow"; sleep 2; }  # it ignores AppleScript's quit

# Quits PUSHTYPE, applies $1 as its model, relaunches it and waits for that
# model to finish warming up (a model not on disk fails here).
relaunch_push() {
  osascript -e 'quit app "PUSH"'
  while pgrep -qx PUSH; do sleep 0.5; done
  [ -n "${1:-}" ] && defaults write $DOMAIN selectedWhisperModel "$1"
  local mark=$(wc -l < "$LOG")
  open -a /Applications/PUSH.app
  for _ in {1..90}; do
    sleep 1
    tail -n +$((mark + 1)) "$LOG" | grep -q "warm-up complete" || continue
    [ -z "${1:-}" ] || tail -n +$((mark + 1)) "$LOG" | grep -q "Activating $1" && return 0
    echo "PUSHTYPE didn't load $1 (is it downloaded?)"; return 1
  done
  echo "PUSHTYPE didn't finish warming up in 90 s"; return 1
}

restore() {
  trap - EXIT INT TERM
  pkill -f "$COMPARE"
  osascript -e 'tell application "System Events" to key up {option, control}' 2>/dev/null
  [ $wispr_was_open = 0 ] && quit_wispr
  [ $wispr_was_open = 1 ] && ! pgrep -qf "Wispr Flow.app/Contents/MacOS/Wispr Flow" && open -a "Wispr Flow"
  osascript -e 'quit app "PUSH"'; while pgrep -qx PUSH; do sleep 0.5; done
  [ -n "$saved_model" ] && defaults write $DOMAIN selectedWhisperModel "$saved_model"
  [ -n "$saved_media" ] && defaults write $DOMAIN mediaBehavior "$saved_media" || defaults delete $DOMAIN mediaBehavior 2>/dev/null
  [ -n "$saved_rewrite" ] && defaults write $DOMAIN talkAutocorrectModel -bool "$saved_rewrite" || defaults delete $DOMAIN talkAutocorrectModel 2>/dev/null
  osascript -e "set volume output volume $saved_volume"
  open -a /Applications/PUSH.app
  echo "Settings restored."
}
trap restore EXIT
trap 'exit 130' INT TERM

defaults write $DOMAIN mediaBehavior off           # ducking would lower the recording it has to hear
defaults write $DOMAIN talkAutocorrectModel -bool false
osascript -e 'set volume output volume 100'
start=$(( $( [ -f "$RESULTS" ] && wc -l < "$RESULTS" || echo 0 ) + 1 ))

quit_wispr
for model in $MODELS; do
  echo "PUSHTYPE, $model: $RUNS runs…"
  relaunch_push "$model" || exit 1
  sleep 3
  COMPARE_E2E="pushtype:$RUNS" "$COMPARE" || exit 1
done

if [ "$WISPR" = 1 ] && [ -d "/Applications/Wispr Flow.app" ]; then
  echo "Wispr Flow: $RUNS runs, 10 s apart…"
  open -a "Wispr Flow"; sleep 10
  COMPARE_E2E="wispr:$RUNS" "$COMPARE" || exit 1
fi

echo
python3 "$REPO/scripts/speedtest_summary.py" --from $start "$RESULTS"
