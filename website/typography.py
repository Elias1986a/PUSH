#!/usr/bin/env python3
"""House style for the website's text: two spaces after every sentence.

    python3 website/typography.py          # every page under website/

HTML collapses typed spaces, so the second space is a no-break space before an
ordinary one (".&nbsp; Next"): it shows as two and the line can still wrap.
Only visible text changes, never tags, attributes, <head>, scripts or code,
and running it again changes nothing. Strings the thank-you page writes from
JavaScript get "\\u00a0 " the same way. build_legal.py runs this on the legal
pages it writes; run it by hand after editing any other page.
"""
import re
import sys
from pathlib import Path

NBSP = "&nbsp;"
# Words whose full stop is not the end of a sentence.
ABBREVIATIONS = {"e.g", "i.e", "vs", "etc", "Mr", "Mrs", "Ms", "Dr", "St", "No", "approx", "Inc", "Ltd", "U.S"}

# A sentence end: a word, digit or closing quote, then . ? or ! (maybe a closing
# quote or bracket), then exactly one space, then what starts a sentence.
END = re.compile(r"(?P<word>(?:[\w.’'\-]*[\w)\]”’\"%])?)(?P<mark>[.?!])(?P<close>[”’\")\]]?) (?=[A-Z0-9“\"(‘¿¡$€£]|$)")
TOKEN = re.compile(r"<!--.*?-->|<(script|style|pre|code|head|textarea)\b[^>]*>.*?</\1\s*>|<[^>]+>", re.S | re.I)


def _sentences(text, next_is_opening_tag):
    def repl(m):
        word = m.group("word")
        # No word before the mark: only a sentence end when it opens the text
        # right after a tag ("<a>…</a>. Next"), never mid-text (". . .").
        if not word and m.start() != 0:
            return m.group(0)
        if word and (word.rstrip(".") in ABBREVIATIONS or word in ABBREVIATIONS):
            return m.group(0)
        at_end = m.end() == len(text)
        if at_end and not next_is_opening_tag:
            return m.group(0)
        return f"{word}{m.group('mark')}{m.group('close')}{NBSP} "
    return END.sub(repl, text)


def typeset(page: str) -> str:
    out, pos = [], 0
    tokens = list(TOKEN.finditer(page))
    for i, tok in enumerate(tokens):
        text = page[pos:tok.start()]
        opening = not tok.group(0).startswith(("</", "<!--")) and tok.group(1) is None
        out.append(_sentences(text, opening))
        out.append(tok.group(0))
        pos = tok.end()
    out.append(_sentences(page[pos:], False))
    return "".join(out)


def typeset_script_strings(page: str) -> str:
    """'…talking. Polar…' in inline JavaScript strings."""
    def fix_script(m):
        body = re.sub(r"(?<=[a-z0-9)’'])([.?!]) (?=[A-Z])", lambda s: s.group(1) + "\\u00a0 ", m.group(2))
        return m.group(1) + body + m.group(3)
    return re.sub(r"(<script>)(.*?)(</script>)", fix_script, page, flags=re.S)


def main(paths):
    root = Path(__file__).resolve().parent
    files = [Path(p) for p in paths] or sorted(root.rglob("*.html"))
    for path in files:
        old = path.read_text(encoding="utf-8")
        new = typeset_script_strings(typeset(old))
        if new != old:
            path.write_text(new, encoding="utf-8")
            print(f"typeset {path.relative_to(root.parent) if path.is_absolute() else path}")


if __name__ == "__main__":
    main(sys.argv[1:])
