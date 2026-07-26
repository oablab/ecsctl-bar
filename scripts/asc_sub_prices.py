#!/usr/bin/env python3
"""Set equalized prices for a subscription in all territories from a base
(USA) price point. Stdlib only.

Usage: asc_sub_prices.py <subscription-id> <base-price-point-id>
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    return subprocess.run(
        ["python3", os.path.expanduser("~/repo/foldic/scripts/asc_jwt.py")],
        capture_output=True, text=True, check=True).stdout.strip()


def req(method, url, tok, body=None):
    r = urllib.request.Request(url, method=method)
    r.add_header("Authorization", f"Bearer {tok}")
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, data=data) as resp:
        text = resp.read()
        return json.loads(text) if text else None


def main():
    sub_id, base_pp = sys.argv[1], sys.argv[2]
    tok = token()

    # Collect equalized price points across all territories (paginated).
    pps = []
    url = (f"{API}/subscriptionPricePoints/{urllib.parse.quote(base_pp)}"
           f"/equalizations?limit=200&include=territory")
    while url:
        page = req("GET", url, tok)
        pps.extend(page["data"])
        url = page.get("links", {}).get("next")
    print(f"equalized price points: {len(pps)}")

    ok = fail = skip = 0
    for pp in pps:
        try:
            req("POST", f"{API}/subscriptionPrices", tok, body={
                "data": {
                    "type": "subscriptionPrices",
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                        "subscriptionPricePoint": {
                            "data": {"type": "subscriptionPricePoints", "id": pp["id"]}},
                    }}})
            ok += 1
        except urllib.error.HTTPError as e:
            if e.code == 409:
                skip += 1  # already priced (e.g. USA)
            else:
                fail += 1
                print("  fail:", pp["id"][:24], e.code)
        time.sleep(0.1)
    print(f"done: created={ok} skipped={skip} failed={fail}")


if __name__ == "__main__":
    main()
