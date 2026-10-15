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

Recipe: use the debug build (its settings live in the `PUSH` domain; make its
cleanup settings match the shipped defaults first, e.g. `resolveSelfCorrections`
on). Before quitting the installed PUSHTYPE, check
`defaults read com.push.voicetotext licence.offered` is 0: a relaunch re-checks
the license. Play the voice with `afplay` at volume 100 through the desk
speakers; hold the key for lead-in + speech length + 0.1 s so the release is
real; record with `screencapture -v -V <s> -R x,y,w,h`. Restore the volume, the
installed app, and the clipboard afterwards; delete the test notes.

TYPE takes: Grammarly Desktop draws pink underlines in Notes; quit it for the take and reopen it after. Plan the message so names, places and times are typed and TYPE only finishes everyday phrasing; dry-run every stop through the model (the replay harness's `suggest`) and rehearse once live, since in-app suggestions differ from the dry run.

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
