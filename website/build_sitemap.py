#!/usr/bin/env python3
"""Write website/sitemap.xml with each page's real last-changed date.

Run from anywhere after editing a page, and before committing:
    python3 website/build_sitemap.py
A page's lastmod is the date of the last commit that touched its file, or
today if the file has uncommitted changes.  Add new public pages to PAGES;
leave out the noindex ones (404, thanks, support/sent).
"""
import datetime
import subprocess
from pathlib import Path

SITE = Path(__file__).resolve().parent
ORIGIN = "https://pushtype.app"
PAGES = {
    "/": "index.html",
    "/benchmark/": "benchmark/index.html",
    "/support/": "support/index.html",
    "/legal/privacy.html": "legal/privacy.html",
    "/legal/terms.html": "legal/terms.html",
    "/legal/eula.html": "legal/eula.html",
    "/legal/notices.html": "legal/notices.html",
}


def git(*args):
    return subprocess.run(["git", *args], cwd=SITE, capture_output=True, text=True, check=True).stdout.strip()


def lastmod(path):
    if git("status", "--porcelain", "--", path):
        return datetime.date.today().isoformat()
    return git("log", "-1", "--format=%cs", "--", path) or datetime.date.today().isoformat()


if __name__ == "__main__":
    rows = "".join(f"  <url><loc>{ORIGIN}{url}</loc><lastmod>{lastmod(path)}</lastmod></url>\n"
                   for url, path in PAGES.items())
    (SITE / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{rows}</urlset>\n", encoding="utf-8")
    print("wrote website/sitemap.xml")
