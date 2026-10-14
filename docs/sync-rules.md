# Sync rules

`sync-rules.csv` lists every stored setting. The last column is yours: write one
of these per row (now filled in with what we agreed).

- **LIVE**: every change on any Mac reaches the others, and the latest change wins.
- **SEED**: a Mac copies the iCloud value once, when it has none of its own. After
  that it keeps its own, and nothing overwrites it.
- **MERGE**: each Mac's entries are combined, and deletes are honoured (the dictionary).
- **PER-MAC**: never leaves this Mac.

"Built" is what the code does on `next-release`. SEED copies happen when you answer yes to "Already use PUSHTYPE on another Mac?" at setup, or press Copy Settings in Settings ▸ General. The learned writing itself is not synced yet.
