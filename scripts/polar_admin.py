#!/usr/bin/env python3
"""Make Polar's live (or sandbox) store match what the website's functions expect.

    POLAR_ADMIN_TOKEN="$(pbpaste)" python3 scripts/polar_admin.py plan
    POLAR_ADMIN_TOKEN="$(pbpaste)" python3 scripts/polar_admin.py apply
    python3 scripts/polar_admin.py --sandbox plan

What it makes true (each step is skipped when it already is):
  * the Extra Mac product carries its licence-key benefit and the download, so
    a single can be given away on its own and every order gets a key;
  * the webhook endpoint at /api/polar-webhook listens to the order and
    benefit-grant events lib/seats.mts needs.

The token is a short-lived admin token made for this, scopes products:write,
webhooks:read and webhooks:write. It is read from the environment, never
printed, never stored. Create it in Polar (Settings ▸ Developers), run this,
then delete it. The Netlify token is a different, smaller one.
"""
import json
import os
import sys
import urllib.error
import urllib.request

SERVERS = {
    "production": {
        "api": "https://api.polar.sh",
        "org": "d5c12043-0896-4c20-99a9-bbe1e2a833f1",
        "extra_product": "b764aace-6737-4932-9028-75b890ac4c11",
        "extra_benefit": "cea19ca1-e6c9-45d9-ae60-5c57f050c2c2",
    },
    "sandbox": {
        "api": "https://sandbox-api.polar.sh",
        "org": "0673c8e8-a8e6-4c1b-9cc1-5ff5d0c33037",
        "extra_product": "9deeaf9c-0f19-4e76-aad4-48826f58e2c2",
        "extra_benefit": "54dc6cec-6c2d-4a1f-8979-f3bcfc1d5de6",
    },
}
WEBHOOK_PATH = "/api/polar-webhook"
EVENTS = ["order.paid", "order.refunded", "order.updated", "benefit_grant.created", "benefit_grant.updated"]


def call(api, path, token=None, method="GET", body=None):
    request = urllib.request.Request(
        api + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"content-type": "application/json", "user-agent": "pushtype-polar-admin/1", **({"authorization": f"Bearer {token}"} if token else {})},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        try:
            detail = json.loads(error.read())
        except Exception:
            detail = {}
        return error.code, detail


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sandbox = "--sandbox" in sys.argv
    command = args[0] if args else "plan"
    if command not in ("plan", "apply"):
        sys.exit(__doc__)
    cfg = SERVERS["sandbox" if sandbox else "production"]
    api = cfg["api"]
    token = os.environ.get("POLAR_ADMIN_TOKEN", "").strip()
    if command == "apply" and not token:
        sys.exit("apply needs POLAR_ADMIN_TOKEN (see the top of this file).")
    changed = False

    # ---- Extra Mac benefits (read from Polar's public store data) ----
    status, org = call(api, "/v1/customer-portal/organizations/pushtype")
    if status != 200:
        sys.exit(f"could not read the store ({status})")
    products = {p["id"]: p for p in org["products"]}
    extra = products[cfg["extra_product"]]
    have = [b["id"] for b in extra.get("benefits", [])]
    # The download is the same benefit the main product carries.
    download = next(
        b["id"] for p in org["products"] if p["id"] != cfg["extra_product"]
        for b in p.get("benefits", []) if b["type"] == "downloadables"
    )
    want = [cfg["extra_benefit"], download]
    if sorted(have) == sorted(want):
        print("Extra Mac benefits: already right (licence key + download).")
    else:
        types = [b["type"] for b in extra.get("benefits", [])]
        print(f"Extra Mac benefits: have {types}, want ['license_keys', 'downloadables'].")
        if command == "apply":
            status, body = call(api, f"/v1/products/{cfg['extra_product']}/benefits", token, "POST", {"benefits": want})
            print(f"  update -> {status}")
            if status != 200:
                print(f"  {body.get('detail', '')}")
                sys.exit(1)
            changed = True

    # ---- Webhook events ----
    if not token:
        print("Webhook: skipped (set POLAR_ADMIN_TOKEN to check it).")
    else:
        status, body = call(api, f"/v1/webhooks/endpoints?organization_id={cfg['org']}&limit=100", token)
        if status != 200:
            sys.exit(f"could not list webhook endpoints ({status}); does the token have webhooks:read?")
        endpoint = next((e for e in body["items"] if e["url"].endswith(WEBHOOK_PATH)), None)
        if not endpoint:
            print(f"Webhook: no endpoint ending {WEBHOOK_PATH}; add it in Polar first.")
        elif sorted(endpoint["events"]) == sorted(EVENTS):
            print("Webhook events: already right.")
        else:
            missing = sorted(set(EVENTS) - set(endpoint["events"]))
            print(f"Webhook events: missing {missing}.")
            if command == "apply":
                status, _ = call(api, f"/v1/webhooks/endpoints/{endpoint['id']}", token, "PATCH", {"events": EVENTS})
                print(f"  update -> {status}")
                if status != 200:
                    sys.exit(1)
                changed = True

    if changed:
        # Check from the public side that it took.
        _, after = call(api, "/v1/customer-portal/organizations/pushtype")
        now = {p["id"]: [b["type"] for b in p.get("benefits", [])] for p in after["products"]}
        print("Extra Mac now carries:", now[cfg["extra_product"]])


if __name__ == "__main__":
    main()
