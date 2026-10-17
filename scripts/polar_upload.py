#!/usr/bin/env python3
"""Put a release DMG in the live store: what buyers download from the thank-you
page and Polar's portal. Both products share one File Downloads benefit.

    python3 scripts/polar_upload.py check                     # read-only
    python3 scripts/polar_upload.py upload PUSHTYPE-v10.0.1.dmg

`upload` sends the file to Polar in 10 MB parts (each SHA-256 checked), marks
it uploaded, then makes it the benefit's only file. The previous file is
replaced only after the new one is fully in, so a failure leaves buyers with
the old DMG. The token (files:read/write, benefits:read/write, made in Polar ▸
Preferences ▸ Developers) is read from the login Keychain, never printed:

    security add-generic-password -U -s "PUSHTYPE Polar release token" -a polar -w "$(pbpaste)"
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.polar.sh"
ORG = "d5c12043-0896-4c20-99a9-bbe1e2a833f1"
KEYCHAIN_SERVICE = "PUSHTYPE Polar release token"
CHUNK = 10_000_000  # as Polar's own uploader


def token():
    out = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'No token in the Keychain under "{KEYCHAIN_SERVICE}".')
    return out.stdout.strip()


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=None if body is None else json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {token()}",
                                          "Content-Type": "application/json",
                                          "Accept": "application/json",
                                          # Cloudflare in front of the API refuses Python's default.
                                          "User-Agent": "PUSHTYPE-release/1.0"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:500]}")


def b64sha(data):
    return base64.b64encode(hashlib.sha256(data).digest()).decode()


def the_benefit():
    items = call("GET", f"/v1/benefits/?organization_id={ORG}&type=downloadables&limit=100")["items"]
    if len(items) != 1:
        sys.exit(f"Expected one File Downloads benefit, found {len(items)}.")
    return items[0]


def describe(benefit):
    files = benefit["properties"].get("files", [])
    print(f'Benefit "{benefit["description"]}" ({benefit["id"]}): {len(files)} file(s)')
    for fid in files:
        f = call("GET", f"/v1/files/?organization_id={ORG}&ids={fid}")["items"]
        print("  ", f[0]["name"] if f else fid, f[0]["size_readable"] if f else "")


def upload(path):
    data = open(path, "rb").read()
    name = os.path.basename(path)
    parts = [{"number": i + 1, "chunk_start": start, "chunk_end": min(start + CHUNK, len(data)),
              "checksum_sha256_base64": b64sha(data[start:start + CHUNK])}
             for i, start in enumerate(range(0, len(data), CHUNK))]
    created = call("POST", "/v1/files/", {
        # No organization_id: an organization token implies it, and Polar refuses it.
        "name": name, "mime_type": "application/x-apple-diskimage",
        "size": len(data), "checksum_sha256_base64": b64sha(data), "service": "downloadable",
        "upload": {"parts": parts}})
    done = []
    for part in created["upload"]["parts"]:
        chunk = data[part["chunk_start"]:part["chunk_end"]]
        req = urllib.request.Request(part["url"], data=chunk, method="PUT", headers=part.get("headers") or {})
        with urllib.request.urlopen(req) as r:
            done.append({"number": part["number"], "checksum_etag": r.headers["ETag"],
                         "checksum_sha256_base64": part.get("checksum_sha256_base64")})
        print(f"  part {part['number']}/{len(parts)} sent")
    uploaded = call("POST", f"/v1/files/{created['id']}/uploaded",
                    {"id": created["upload"]["id"], "path": created["upload"]["path"], "parts": done})
    if not uploaded.get("is_uploaded"):
        sys.exit("Polar did not mark the file uploaded; the benefit is unchanged.")
    benefit = the_benefit()
    updated = call("PATCH", f"/v1/benefits/{benefit['id']}",
                   {"type": "downloadables", "properties": {"files": [created["id"]]}})
    if updated["properties"]["files"] != [created["id"]]:
        sys.exit("The benefit did not take the new file.")
    print(f"{name} is now the download for every buyer.")
    describe(updated)


if __name__ == "__main__":
    if sys.argv[1:2] == ["check"]:
        describe(the_benefit())
    elif sys.argv[1:2] == ["upload"] and len(sys.argv) == 3:
        upload(sys.argv[2])
    else:
        sys.exit(__doc__)
