# Recording promo clips

Small tools used to record and cut the live preview clips in `promo/`
(2026-10-14). Build any of them with `swiftc -O <name>.swift -o <name>`
(output outside the repo, e.g. a temp folder).

## Recording

| Tool | Does |
|---|---|
| `backdrop.swift` | A plain full-screen dark backdrop, so no desktop or other windows show in the frame. Quit with `pkill backdrop`. |
| `freshnote.applescript`, `freshnote-small.applescript` | Closes Notes windows, makes a new empty note in its own window, sizes, places, and zooms it (wide frame / tight frame). Notes ignores a scripted Delete or Cut, so every take gets a fresh note. |
| `holdoption.swift <s>` | Holds Left Option (the PUSH-to-talk key) for N seconds. Flags must be `0x80120` (the left-side bit) down and `[]` up, from a `.hidSystemState` source, or Option stays stuck. |
| `typekeys.swift "<steps>"` | Types like a person, checking Notes is in front before every key. Steps: `t:text`, `tab`, `all` (`), `w:1.5`. |
| `movemouse.swift` | Moves the pointer out of the frame. |
| `unstick.swift` | Releases a stuck Option and, only if Notes is in front, presses Esc. |
| `notes-spelling.applescript get\|off\|on` | Notes' spelling/grammar-while-typing switches. Its menu checkmarks read unreliably: confirm with `defaults read com.apple.Notes ShouldCorrectSpellingAutomatically`. |
| `miclevel.swift <s>` | Prints the microphone level per second, to check the speakers reach the mic. |
| `pilltake.swift` | Records a dictation take as its own element: a screen region at full Retina resolution in ProRes, holding Left Option and playing the voice in the same process, and prints when the key went down, the voice started and the key came up (seconds into the movie). `--probe` prints where PUSH's pill window is. |

Recipe: use the debug build (its settings live in the `PUSH` domain; make its
cleanup settings match the shipped defaults first, e.g. `resolveSelfCorrections`
on). Before quitting the installed PUSHTYPE, check
`defaults read com.push.voicetotext licence.offered` is 0: a relaunch re-checks
the license. Play the voice with `afplay` at volume 100 through the desk
speakers; hold the key for lead-in + speech length + 0.1 s so the release is
real; record with `screencapture -v -V <s> -R x,y,w,h`. Restore the volume, the
installed app, and the clipboard afterwards; delete the test notes.

TYPE takes: Grammarly Desktop draws pink underlines in Notes; quit it for the take and reopen it after. Plan the message so names, places and times are typed and TYPE only finishes everyday phrasing; dry-run every stop through the model (the replay harness's `suggest`) and rehearse once live, since in-app suggestions differ from the dry run.

Element takes (`pilltake`, 2026-10-15; made `promo/pill-large.mp4`): dev build
with `showLivePreview` on, `previewSize large`, `pillPosition bottom`; a fresh
note in front so the release pastes there; region from `--probe` with margin
(the Large pill was 731,1260, 841 pt wide; recorded 700,1200 910×96). Measure
the mic with `miclevel` while the voice plays first: at ~0.01 RMS Silero hears
no speech and the pill only says "Listening" (take 1); input volume 100 gave
~0.05 and worked. Hold `--after 2.5`: the live words run ~2.85 s behind the
voice, so a 0.1 s hold cuts off the last sentence. Restore input volume, the
dev build's three settings, the clipboard and the installed app afterwards.

Never send Esc or other keys while the terminal is in front: they reach Claude
Code and cancel the running command.

## Cutting

| Tool | Does |
|---|---|
| `frames.swift <movie> <prefix> <t>…` | Saves frames at given times, to check a take. |
| `pillstart.swift <movie> <from> <to>` | Brightness of the pill strip over time: when the pill appears and when it closes (the key release). |
| `textland.swift <movie> <from> <to>` | When the text lands in the note. |
| `speechedges.swift <audio>` | Where speech starts and ends in the voice file. |
| `mux.swift` | Lays the voice under a take at an offset, with an optional trim. |
| `mux2.swift` | The same, plus playing one stretch slower (used for `promo/live-preview.mp4`). |
| `trimexport.swift <in> <out> <start> <end> [web]` | Cuts a silent clip (the TYPE video); `web` = 1280×720. |
| `webexport.swift <in> <out>` | 1280×720 H.264/AAC for the website. |
