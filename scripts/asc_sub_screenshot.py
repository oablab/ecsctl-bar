#!/usr/bin/env python3
"""Upload the subscription review screenshot to ASC. Stdlib only.

Usage: asc_sub_screenshot.py <png-path> <subscription-id> [old-screenshot-id-to-delete]
"""
import hashlib
import json
import subprocess
import sys
import time
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    import os
    return subprocess.run(
        ["python3", os.path.expanduser("~/repo/foldic/scripts/asc_jwt.py")],
        capture_output=True, text=True, check=True).stdout.strip()


def req(method: str, url: str, body=None, tok=None, headers=None, raw=False):
    r = urllib.request.Request(url, method=method)
    if tok:
        r.add_header("Authorization", f"Bearer {tok}")
    for k, v in (headers or {}).items():
        r.add_header(k, v)
    data = None
    if body is not None:
        if raw:
            data = body
        else:
            data = json.dumps(body).encode()
            r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, data=data) as resp:
        text = resp.read()
        return json.loads(text) if text and not raw else None


def main():
    png, sub_id = sys.argv[1], sys.argv[2]
    old = sys.argv[3] if len(sys.argv) > 3 else None
    tok = token()

    if old:
        try:
            req("DELETE", f"{API}/subscriptionAppStoreReviewScreenshots/{old}", tok=tok)
            print("deleted old screenshot", old)
        except Exception as e:
            print("delete failed (continuing):", e)

    blob = open(png, "rb").read()
    md5 = hashlib.md5(blob).hexdigest()
    print(f"file: {len(blob)} bytes md5={md5}")

    created = req("POST", f"{API}/subscriptionAppStoreReviewScreenshots", tok=tok, body={
        "data": {
            "type": "subscriptionAppStoreReviewScreenshots",
            "attributes": {"fileName": "demo-fleet.png", "fileSize": len(blob)},
            "relationships": {"subscription": {
                "data": {"type": "subscriptions", "id": sub_id}}},
        }})
    shot = created["data"]
    print("screenshot id:", shot["id"])

    for op in shot["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"]:op["offset"] + op["length"]]
        hdrs = {h["name"]: h["value"] for h in op["requestHeaders"]}
        req(op["method"], op["url"], body=chunk, headers=hdrs, raw=True)
        print(f"uploaded chunk offset={op['offset']} len={op['length']}")

    req("PATCH", f"{API}/subscriptionAppStoreReviewScreenshots/{shot['id']}", tok=tok, body={
        "data": {
            "type": "subscriptionAppStoreReviewScreenshots",
            "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": md5},
        }})
    print("committed; polling processing state...")

    for _ in range(30):
        time.sleep(10)
        cur = req("GET", f"{API}/subscriptionAppStoreReviewScreenshots/{shot['id']}", tok=tok)
        state = cur["data"]["attributes"]["assetDeliveryState"]["state"]
        print("  state:", state)
        if state in ("COMPLETE", "FAILED"):
            if state == "FAILED":
                print(json.dumps(cur["data"]["attributes"]["assetDeliveryState"], indent=1))
            break


if __name__ == "__main__":
    main()
