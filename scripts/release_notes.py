#!/usr/bin/env python3
"""Build the HTML release notes Sparkle shows in its update window.

    python3 scripts/release_notes.py 8.2.2

Prints one page: the given version's notes first, then every older version in
release-notes/, newest first — so someone who skipped a few updates sees what
they missed. Each release-notes/<version>.md is also the GitHub release text,
so the notes are written once. Only the Markdown those files use is handled:
"## " headings, "- " bullets, paragraphs, **bold**, `code` and [links](url).
"""
import html, re, sys
from pathlib import Path

NOTES = Path(__file__).resolve().parent.parent / "release-notes"

STYLE = """<meta charset="utf-8">
<style>
:root { color-scheme: light dark; }
body { font: 13px -apple-system, sans-serif; line-height: 1.45; margin: 12px 16px; }
h2 { font-size: 15px; margin: 0 0 6px; }
.older { margin-top: 16px; padding-top: 12px; border-top: 1px solid rgba(128,128,128,.3); }
h2 .tag { font-size: 11px; font-weight: 600; color: #fff; background: #0a84ff;
          border-radius: 4px; padding: 1px 6px; margin-left: 6px; vertical-align: 2px; }
h3 { font-size: 11px; text-transform: uppercase; letter-spacing: .05em; opacity: .6; margin: 10px 0 4px; }
ul { margin: 0; padding-left: 18px; }
li { margin: 3px 0; }
code { font: 12px ui-monospace, monospace; background: rgba(128,128,128,.15); border-radius: 3px; padding: 0 3px; }
.older { opacity: .75; }
</style>"""


def version_key(v):
    return tuple(int(p) for p in v.split("."))


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)


def to_html(markdown):
    out, in_list = [], False
    for line in markdown.splitlines():
        line = line.rstrip()
        if line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(line[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if line.startswith("## "):
            out.append(f"<h3>{inline(line[3:])}</h3>")
        elif line:
            out.append(f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main(version):
    if not (NOTES / f"{version}.md").exists():
        sys.exit(f"release-notes/{version}.md is missing — write the notes before releasing.")
    versions = sorted((p.stem for p in NOTES.glob("*.md")), key=version_key, reverse=True)
    versions = [v for v in versions if version_key(v) <= version_key(version)]
    parts = [STYLE]
    for v in versions:
        latest = v == version
        tag = ' <span class="tag">New</span>' if latest else ""
        body = to_html((NOTES / f"{v}.md").read_text())
        parts.append(f'<div class="{"latest" if latest else "older"}"><h2>Version {v}{tag}</h2>\n{body}</div>')
    page = "\n".join(parts)
    assert "]]>" not in page  # it is embedded in a CDATA section
    print(page)


if __name__ == "__main__":
    main(sys.argv[1])
