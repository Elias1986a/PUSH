#!/usr/bin/env python3
"""Release to text on screen, summarized: median, fastest, slowest and p90 per
app and speech model, from the compare app's endtoend.jsonl.

    python3 scripts/speedtest_summary.py [--from LINE] [FILE]

--from skips the lines before LINE (1-based), so a study run by
scripts/speedtest.sh is summarized on its own.
"""
import argparse
import json
import math
import os
from collections import OrderedDict

DEFAULT = os.path.expanduser("~/Library/Application Support/PUSHCompare/endtoend.jsonl")
MODELS = {"parakeet-streaming": "Streaming", "parakeet-ultra": "Ultra"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file", nargs="?", default=DEFAULT)
    ap.add_argument("--from", dest="start", type=int, default=1)
    args = ap.parse_args()

    with open(args.file) as f:
        runs = [json.loads(line) for line in f.read().splitlines()[args.start - 1:] if line.strip()]

    groups = OrderedDict()
    for r in runs:
        name = r["target"]
        if r.get("model"):
            name += " " + MODELS.get(r["model"], r["model"])
        if r.get("appVersion"):
            name += f" ({r['appVersion']})"
        groups.setdefault(name, []).append(r)

    if not groups:
        print("No runs.")
        return
    print(f"{'':34}{'n':>4}{'median':>9}{'fastest':>9}{'slowest':>9}{'p90':>8}  empty")
    for name, rs in groups.items():
        good = sorted(r["releaseToTextMs"] for r in rs if r.get("releaseToTextMs") is not None and not r.get("interrupted"))
        empty = sum(1 for r in rs if r.get("releaseToTextMs") is None)
        if not good:
            print(f"{name:34}{0:>4}{'':>35}  {empty}")
            continue
        n = len(good)
        median = good[n // 2] if n % 2 else (good[n // 2 - 1] + good[n // 2]) / 2
        i = 0.9 * (n - 1)  # linear, as numpy's default
        p90 = good[math.floor(i)] + (good[math.ceil(i)] - good[math.floor(i)]) * (i - math.floor(i))
        print(f"{name:34}{n:>4}{median:>7.0f}ms{good[0]:>7.0f}ms{good[-1]:>7.0f}ms{p90:>6.0f}ms  {empty}")


if __name__ == "__main__":
    main()
