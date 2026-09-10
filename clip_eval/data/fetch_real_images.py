#!/usr/bin/env python3
"""
Stage 1 of 2: download raw candidate photos for each unlock category from Openverse.

Candidates  -> clip_eval/data/candidates/<category_id>/NN.jpg
Manifest    -> clip_eval/data/candidates_manifest.jsonl  (source + license per image)

Openverse text relevance is weak, so this over-fetches; stage 2 (filter_images.py)
CLIP-ranks candidates down to the clean keepers used by the harness.

Auth: clip_eval/.openverse_creds.json -> cached token in clip_eval/.openverse_token.json.
Unverified Openverse account = 200 requests/day; verified = 10k/day (click the email link).

Usage:
  clip_env/bin/python clip_eval/data/fetch_real_images.py                    # all categories
  clip_env/bin/python clip_eval/data/fetch_real_images.py --max-categories 8 # pilot
  clip_env/bin/python clip_eval/data/fetch_real_images.py --only oven,blender
"""

import argparse
import io
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
CLIP_EVAL = HERE.parent
CATEGORIES_FILE = CLIP_EVAL / "categories" / "categories_core.json"
CAND_DIR = HERE / "candidates"
MANIFEST = HERE / "candidates_manifest.jsonl"
CREDS_FILE = CLIP_EVAL / ".openverse_creds.json"
TOKEN_FILE = CLIP_EVAL / ".openverse_token.json"

API = "https://api.openverse.org/v1"
UA = "GroundedUnlockEval/0.1 (colson1111@gmail.com)"
SEARCH_SLEEP = 1.5          # verified tier: 100/min
DOWNLOAD_SLEEP = 0.1
CANDIDATES_PER_CAT = 40
MIN_SIDE = 200
MAX_SIDE = 512

# Search-term overrides for category ids whose display name is an ambiguous word
# (software, brand, verb, ...). Everything else searches on its display_name.
# Openverse 500s on many multi-word queries, so overrides stay to ONE token that
# is less of a homograph than the display name. Bad matches are pruned by the
# CLIP filter (stage 2) and the manual contact-sheet review.
SEARCH_OVERRIDES = {
    "blender": "blender",
    "oven": "oven",
}


def _req(url, headers, data=None, timeout=45, retries=2):
    last = None
    for attempt in range(retries + 1):
        try:
            r = urllib.request.Request(url, data=data, headers=headers)
            with urllib.request.urlopen(r, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.HTTPError:
            raise
        except Exception as e:  # timeout, connection reset, DNS blip
            last = e
            time.sleep(2 + 3 * attempt)
    raise last


def get_token(force=False):
    if not force and TOKEN_FILE.exists():
        t = json.loads(TOKEN_FILE.read_text())
        if t.get("expires_at", 0) > time.time() + 120:
            return t["access_token"]
    creds = json.loads(CREDS_FILE.read_text())
    body = urllib.parse.urlencode({
        "client_id": creds["client_id"],
        "client_secret": creds["client_secret"],
        "grant_type": "client_credentials",
    }).encode()
    tok = json.loads(_req(f"{API}/auth_tokens/token/",
                          {"User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded"},
                          data=body))
    tok["expires_at"] = time.time() + tok.get("expires_in", 43200)
    TOKEN_FILE.write_text(json.dumps(tok))
    print(f"  [token refreshed, {tok.get('expires_in', 0)//3600}h]")
    return tok["access_token"]


def search(query, token):
    qs = urllib.parse.urlencode({
        "q": query, "page_size": CANDIDATES_PER_CAT,
        "category": "photograph", "mature": "false", "license_type": "all",
    })
    url = f"{API}/images/?{qs}"
    for attempt in range(4):
        try:
            return json.loads(_req(url, {"User-Agent": UA, "Authorization": f"Bearer {token}"})).get("results", [])
        except urllib.error.HTTPError as e:
            if e.code == 401 and attempt == 0:
                token = get_token(force=True)
            elif e.code == 429:
                print("  [429] sleep 60s"); time.sleep(60)
            elif e.code in (500, 502, 503, 504) and attempt < 3:
                print(f"  [{e.code}] retry in 10s"); time.sleep(10)
            else:
                raise
        except Exception as e:
            if attempt < 3:
                print(f"  [{type(e).__name__}] retry in 10s"); time.sleep(10)
            else:
                raise
    return []


def fetch_image(url):
    try:
        raw = _req(url, {"User-Agent": UA}, timeout=20)
        img = Image.open(io.BytesIO(raw)); img.load()
    except Exception:
        return None
    if min(img.size) < MIN_SIDE:
        return None
    img = img.convert("RGB")
    if max(img.size) > MAX_SIDE:
        s = MAX_SIDE / max(img.size)
        img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-categories", type=int, default=None)
    ap.add_argument("--only", default=None)
    args = ap.parse_args()

    cats = json.loads(CATEGORIES_FILE.read_text())
    if args.only:
        want = set(args.only.split(","))
        cats = [c for c in cats if c["id"] in want]
    if args.max_categories:
        cats = cats[:args.max_categories]

    CAND_DIR.mkdir(exist_ok=True)
    token = get_token()
    man = MANIFEST.open("a")
    searches = 0

    for ci, cat in enumerate(cats, 1):
        cid, name = cat["id"], cat["display_name"]
        cdir = CAND_DIR / cid
        cdir.mkdir(exist_ok=True)
        if len(list(cdir.glob("*.jpg"))) >= CANDIDATES_PER_CAT * 0.6:
            print(f"[{ci}/{len(cats)}] {cid}: candidates present, skip")
            continue

        query = SEARCH_OVERRIDES.get(cid, name)
        print(f"[{ci}/{len(cats)}] {cid}  \"{query}\" ...", end=" ", flush=True)
        results = search(query, token)
        searches += 1
        time.sleep(SEARCH_SLEEP)

        n = 0
        for res in results:
            src = res.get("url") or res.get("thumbnail")
            if not src:
                continue
            img = fetch_image(src)
            time.sleep(DOWNLOAD_SLEEP)
            if img is None:
                continue
            img.save(cdir / f"{n:02d}.jpg", "JPEG", quality=90)
            man.write(json.dumps({
                "id": cid, "file": f"{cid}/{n:02d}.jpg", "source_url": src,
                "foreign_landing_url": res.get("foreign_landing_url"),
                "creator": res.get("creator"),
                "license": f"{res.get('license')}-{res.get('license_version')}",
                "provider": res.get("provider"), "openverse_id": res.get("id"),
            }) + "\n")
            man.flush()
            n += 1
        print(f"{n} candidates")

    man.close()
    print(f"\ndone. {searches} search requests used.")


if __name__ == "__main__":
    main()
