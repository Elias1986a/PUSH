#!/usr/bin/env python3
"""How many checkouts were opened, and how many were paid: cart abandonment.

    POLAR_REPORT_TOKEN="$(pbpaste)" python3 scripts/polar_checkouts.py
    POLAR_REPORT_TOKEN="$(pbpaste)" python3 scripts/polar_checkouts.py --days 7
    python3 scripts/polar_checkouts.py --sandbox

A Polar checkout is made when someone presses Buy and the checkout page
opens. It ends "succeeded" when they pay, "expired" when they leave and it
times out, "failed" when the payment is declined; "open" is someone still on
the page. So opened minus paid is the abandonment, by product. Umami's "Buy"
event counts the clicks before that; together they show where people drop.

The token needs only checkouts:read (Polar ▸ Settings ▸ Developers). It is
read from the environment, never printed or stored. Nothing about a buyer
(name, email) is printed: counts only.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timedelta, timezone

SERVERS = {
    "production": {"api": "https://api.polar.sh", "org": "d5c12043-0896-4c20-99a9-bbe1e2a833f1"},
    "sandbox": {"api": "https://sandbox-api.polar.sh", "org": "0673c8e8-a8e6-4c1b-9cc1-5ff5d0c33037"},
}
PRODUCT_NAMES = {
    "e05a47f1-acab-4221-af17-41dcb56a94e4": "PUSHTYPE ($35)",
    "b764aace-6737-4932-9028-75b890ac4c11": "Extra Mac ($12)",
    "68857672-cc5b-45d4-8b10-abf40f523a11": "PUSHTYPE ($35, sandbox)",
    "9deeaf9c-0f19-4e76-aad4-48826f58e2c2": "Extra Mac ($12, sandbox)",
}


def get(api, path, token):
    request = urllib.request.Request(api + path, headers={
        "authorization": f"Bearer {token}", "user-agent": "pushtype-polar-report/1"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        sys.exit(f"Polar answered {error.code} for {path.split('?')[0]} (does the token have checkouts:read?)")


def checkouts_since(server, token, since):
    """Every checkout made after `since`. Reads every page and filters by
    date itself, so it does not depend on the order Polar lists them in."""
    found, page = [], 1
    while True:
        body = get(server["api"], f"/v1/checkouts/?organization_id={server['org']}&limit=100&page={page}", token)
        items = body.get("items", [])
        found += [c for c in items if parse(c["created_at"]) >= since]
        if not items or page >= body.get("pagination", {}).get("max_page", 1):
            return found
        page += 1


def parse(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def summarize(checkouts):
    """{product name: Counter of statuses}, plus an "All products" row."""
    rows = {}
    for c in checkouts:
        name = PRODUCT_NAMES.get(c.get("product_id"), "Other product")
        rows.setdefault(name, Counter())[c.get("status", "unknown")] += 1
    rows["All products"] = sum(rows.values(), Counter())
    return rows


def report(rows):
    lines = [f"{'':24}{'opened':>8}{'paid':>8}{'left':>8}{'declined':>10}{'still open':>12}{'paid %':>8}"]
    for name, n in rows.items():
        opened = sum(n.values())
        paid = n["succeeded"]
        rate = f"{100 * paid / opened:.0f}%" if opened else "-"
        lines.append(f"{name:24}{opened:>8}{paid:>8}{n['expired']:>8}{n['failed']:>10}{n['open'] + n['confirmed']:>12}{rate:>8}")
    return "\n".join(lines)


def main():
    flags = sys.argv[1:]
    server = SERVERS["sandbox" if "--sandbox" in flags else "production"]
    days = int(flags[flags.index("--days") + 1]) if "--days" in flags else 30
    token = os.environ.get("POLAR_REPORT_TOKEN")
    if not token:
        sys.exit("Set POLAR_REPORT_TOKEN (scope checkouts:read).")
    since = datetime.now(timezone.utc) - timedelta(days=days)
    checkouts = checkouts_since(server, token, since)
    print(f"Checkouts in the last {days} days: {len(checkouts)}\n")
    print(report(summarize(checkouts)))


if __name__ == "__main__":
    main()
