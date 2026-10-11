# Type — compatibility

An app counts as supported only when it is in this table as passing. Re-run
before each release. "Inline" = blue text at the caret; "card" = a small card
under the caret or field (Cotypist's mirroring). Tested on a Mac mini M4,
macOS 27.2, Developer-ID-signed build, Qwen3.5 2B, unless noted.

## 2026-10-10 (Phase 4, first pass)

| App | Field | Reads text | Caret | Shows | Accept (Tab / →) | Notes |
|---|---|---|---|---|---|---|
| TextEdit | document | AX value | char before caret | inline | ✅ | On a line where macOS **text replacement** fired ("Thanks" → "Thank you"), TextEdit's AX bounds come back ~8 pt short, so the suggestion overlaps the last letters. TextEdit's bug; not worked around. |
| Notes | note body | AX value | ✅ | inline | ✅ | Type size follows the caret (bold title, body). |
| Mail | compose body | **text markers** (body is an AXWebArea with no value) | text markers | inline | ✅ | |
| Safari | textarea | AX value | ✅ | inline | ✅ | |
| Chrome | textarea | AX value | ✅ | inline | ✅ | |
| Chrome | contenteditable | AX value | **text markers** (no range bounds) | inline | ✅ | |
| Claude.app (Electron) | composer | AX value | ✅ | inline | ✅ | Slack stand-in. |
| Discord (Electron) | quick switcher | — | — | none (correct) | — | Focus is reported on the highlighted *result* (AXMenuItem), not the box; Type only suggests in text roles. Message box **not tested**: typing there shows "is typing…" to others. |
| Antigravity IDE (VS Code fork) | Monaco editor | AX value | ⚠️ off when the line is scrolled sideways | card | ✅ | **Tab conflicts** with the editor's own completion popup / AI completions. Open question: exclude code editors by default? |
| Terminal | agent prompt (rule + `>`) | AX value → `TerminalLine` | ✅ | inline | ✅ (→) | Starts on the block cursor (cosmetic). Plain shell prompts: off by design. Tested with a fake prompt, not a live Claude Code session. |

Not yet tested: Slack, VS Code, Gmail compose (Chrome contenteditable passes),
Messages, WhatsApp, Notion, Arc, Firefox, iTerm2, Ghostty, Warp, Claude Code in
iTerm2, VS Code's integrated terminal, a second display.

## Known interactions

- **macOS inline predictive text** (on by default) also offers gray completions
  and also takes Tab. While a blue suggestion is up, PUSH gets the Tab; the two
  can still show at once. Recommend turning it off (System Settings ▸ Keyboard ▸
  Text Input ▸ "Show inline predictive text") when Type is on — Cotypist asks
  the same.
- **Grammarly** and other overlays drew alongside without interfering.
