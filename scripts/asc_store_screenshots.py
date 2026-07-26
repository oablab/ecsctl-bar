#!/usr/bin/env python3
"""Create an APP_DESKTOP screenshot set on a version localization and upload
PNGs into it. Stdlib only.

Usage: asc_store_screenshots.py <localization-id> <png> [<png> ...]
"""
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    return subprocess.run(
        ["python3", os.path.expanduser("~/repo/foldic/scripts/asc_jwt.py")],
        capture_output=True, text=True, check=True).stdout.strip()


def req(method, url, tok=None, body=None, headers=None, raw=False):
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
    loc_id, files = sys.argv[1], sys.argv[2:]
    tok = token()

    # Find or create the APP_DESKTOP set.
    sets = req("GET", f"{API}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", tok)
    set_id = next((s["id"] for s in sets["data"]
                   if s["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"), None)
    if not set_id:
        created = req("POST", f"{API}/appScreenshotSets", tok, body={
            "data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": "APP_DESKTOP"},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
        set_id = created["data"]["id"]
    print("screenshot set:", set_id)

    for path in files:
        blob = open(path, "rb").read()
        md5 = hashlib.md5(blob).hexdigest()
        name = os.path.basename(path)
        shot = req("POST", f"{API}/appScreenshots", tok, body={
            "data": {"type": "appScreenshots",
                     "attributes": {"fileName": name, "fileSize": len(blob)},
                     "relationships": {"appScreenshotSet": {
                         "data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"]:op["offset"] + op["length"]]
            hdrs = {h["name"]: h["value"] for h in op["requestHeaders"]}
            req(op["method"], op["url"], body=chunk, headers=hdrs, raw=True)
        req("PATCH", f"{API}/appScreenshots/{shot['id']}", tok, body={
            "data": {"type": "appScreenshots", "id": shot["id"],
                     "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
        print(f"{name}: uploaded, waiting for processing...")
        for _ in range(30):
            time.sleep(8)
            cur = req("GET", f"{API}/appScreenshots/{shot['id']}", tok)
            state = cur["data"]["attributes"]["assetDeliveryState"]["state"]
            if state in ("COMPLETE", "FAILED"):
                print(f"  {name}: {state}")
                break


if __name__ == "__main__":
    main()
