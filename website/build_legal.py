#!/usr/bin/env python3
"""Render legal/*.md into website/legal/*.html.

Run from the repo root after editing any file in legal/:
    python3 website/build_legal.py
Standard library only, and only the Markdown those files use: headings,
paragraphs, lists, tables, blockquotes, bold, inline code and links.
"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGES = {
    "privacy": ("legal/PRIVACY.md", "Privacy Policy"),
    "terms": ("legal/TERMS_OF_SALE.md", "Terms of Sale"),
    "eula": ("legal/EULA.md", "End User License Agreement"),
    "notices": ("legal/THIRD_PARTY_NOTICES.md", "Third-party notices"),
}


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', text)
    return text


def render(md):
    out, para, lines = [], [], md.splitlines()

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()

    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if not line.strip():
            flush(); i += 1; continue
        m = re.match(r"^(#{1,3})\s+(.*)", line)
        if m:
            flush()
            level = len(m.group(1))
            out.append(f"<h{level}>{inline(m.group(2))}</h{level}>")
            i += 1; continue
        if line.startswith(">"):
            flush()
            block = []
            while i < len(lines) and lines[i].startswith(">"):
                block.append(lines[i].lstrip(">").strip()); i += 1
            out.append("<blockquote><p>" + inline(" ".join(block)) + "</p></blockquote>")
            continue
        if line.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")]); i += 1
            head, body = rows[0], [r for r in rows[1:] if not all(set(c) <= set("-: ") for c in r)]
            t = ['<div class="table-wrap"><table><thead><tr>']
            t += [f"<th>{inline(c)}</th>" for c in head]
            t.append("</tr></thead><tbody>")
            for r in body:
                t.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            out.append("".join(t))
            continue
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", line)
        if m:
            flush()
            tag = "ol" if m.group(2)[0].isdigit() else "ul"
            items = []
            while i < len(lines):
                m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", lines[i])
                if m:
                    items.append(m.group(3).strip())
                elif lines[i].startswith("  ") and lines[i].strip() and items:
                    items[-1] += " " + lines[i].strip()
                else:
                    break
                i += 1
            out.append(f"<{tag}>" + "".join(f"<li>{inline(x)}</li>" for x in items) + f"</{tag}>")
            continue
        para.append(line.strip()); i += 1
    flush()
    return "\n".join(out)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · PUSH</title>
<meta name="robots" content="noindex">
<link rel="icon" href="../assets/icon.png">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@100..125,400..900&amp;family=Instrument+Sans:wght@400..700&amp;family=JetBrains+Mono:wght@400;700&amp;display=swap">
<link rel="stylesheet" href="../assets/tokens.css">
<link rel="stylesheet" href="../assets/components.css">
<link rel="stylesheet" href="../assets/site.css">
</head>
<body>
<header class="wrap nav">
<a class="brand" href="../"><span class="disp">PUSH</span><span class="dot"></span></a>
<span style="flex-grow: 1;"></span>
<a href="../" style="text-decoration: none; font-size: 15px; font-weight: 500;">← Back to PUSH</a>
</header>
<main class="wrap doc">
{body}
</main>
<footer class="footer">
<div class="wrap">
<div class="row" style="gap: 28px;">
<a href="privacy.html">Privacy</a>
<a href="terms.html">Terms of sale</a>
<a href="eula.html">Licence (EULA)</a>
<a href="notices.html">Third-party notices</a>
</div>
<p>© 2026 Elias Atalah.</p>
</div>
</footer>
</body>
</html>
"""

if __name__ == "__main__":
    out_dir = ROOT / "website" / "legal"
    out_dir.mkdir(parents=True, exist_ok=True)
    for slug, (src, title) in PAGES.items():
        body = render((ROOT / src).read_text(encoding="utf-8"))
        if not body.lstrip().startswith("<h1"):
            body = f'<h1 class="disp">{html.escape(title)}</h1>\n' + body
        body = body.replace("<h1>", '<h1 class="disp">', 1)
        (out_dir / f"{slug}.html").write_text(TEMPLATE.format(title=html.escape(title), body=body), encoding="utf-8")
        print(f"wrote website/legal/{slug}.html")
