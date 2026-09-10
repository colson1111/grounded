#!/usr/bin/env python3
"""
Stage 2 of 2: CLIP-filter raw candidates down to clean per-category eval images.

Reads   clip_eval/data/candidates/<id>/*.jpg
Writes  clip_eval/data/images/<id>/NN.jpg        (the keepers, renumbered)
        clip_eval/data/images_manifest.jsonl     (keeper -> source/license + filter score)
        clip_eval/data/filter_report.json        (per-category kept/dropped counts + score spread)

Scoring model is ViT-B-16 / laion2b -- deliberately NOT MobileCLIP-S1 (the model under
test), so the eval set is not filtered by its own judge. For each candidate we compare
cos-sim against the category's prompts vs. a fixed background/negative prompt set; an
image is kept only if a category prompt wins AND its similarity clears --min-score,
up to --limit best per category.

Usage:
  clip_env/bin/python clip_eval/data/filter_images.py
  clip_env/bin/python clip_eval/data/filter_images.py --limit 12 --min-score 0.22
  clip_env/bin/python clip_eval/data/filter_images.py --only oven,blender
"""

import argparse
import json
from pathlib import Path

import open_clip
import torch
from PIL import Image

HERE = Path(__file__).resolve().parent
CLIP_EVAL = HERE.parent
CATEGORIES_FILE = CLIP_EVAL / "categories" / "categories_core.json"
CAND_DIR = HERE / "candidates"
OUT_DIR = HERE / "images"
CAND_MANIFEST = HERE / "candidates_manifest.jsonl"
OUT_MANIFEST = HERE / "images_manifest.jsonl"
REPORT = HERE / "filter_report.json"

FILTER_MODEL = "ViT-B-16"
FILTER_PRETRAINED = "laion2b_s34b_b88k"

# Negatives to reject non-object images. Kept deliberately narrow: broad scene
# prompts ("an empty room", "an outdoor scene", "a software UI") collide with real
# categories (bed, car, television) and over-reject them.
BACKGROUND_PROMPTS = [
    "a photo of food on a plate", "a plate of prepared food",
    "a glass of juice or smoothie", "a bowl of cut fruit",
    "a photo of a person's face", "a crowd of people",
    "a line drawing or diagram", "a cartoon or comic strip",
    "a promotional poster with large text", "a company logo",
    "a page of text from a book",
]


def load_manifest():
    m = {}
    if CAND_MANIFEST.exists():
        for line in CAND_MANIFEST.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                m[r["file"]] = r
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=12, help="max keepers per category")
    ap.add_argument("--min-score", type=float, default=0.22, help="min cos-sim to category prompt")
    ap.add_argument("--margin", type=float, default=0.015, help="min (category - background) sim gap")
    ap.add_argument("--only", default=None)
    args = ap.parse_args()

    cats = json.loads(CATEGORIES_FILE.read_text())
    if args.only:
        want = set(args.only.split(","))
        cats = [c for c in cats if c["id"] in want]

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"loading filter model {FILTER_MODEL}/{FILTER_PRETRAINED} on {device} ...")
    model, _, preprocess = open_clip.create_model_and_transforms(
        FILTER_MODEL, pretrained=FILTER_PRETRAINED)
    model = model.to(device).eval()
    tok = open_clip.get_tokenizer(FILTER_MODEL)

    with torch.no_grad():
        bg = model.encode_text(tok(BACKGROUND_PROMPTS).to(device))
        bg = bg / bg.norm(dim=-1, keepdim=True)

    cand_meta = load_manifest()
    OUT_DIR.mkdir(exist_ok=True)
    out_man = OUT_MANIFEST.open("w")
    report = {}

    for ci, cat in enumerate(cats, 1):
        cid = cat["id"]
        cdir = CAND_DIR / cid
        files = sorted(cdir.glob("*.jpg")) if cdir.exists() else []
        if not files:
            print(f"[{ci}/{len(cats)}] {cid}: no candidates")
            report[cid] = {"candidates": 0, "kept": 0}
            continue

        with torch.no_grad():
            cprompts = cat["prompts"]
            ct = model.encode_text(tok(cprompts).to(device))
            ct = ct / ct.norm(dim=-1, keepdim=True)

        scored = []
        for fp in files:
            try:
                im = preprocess(Image.open(fp).convert("RGB")).unsqueeze(0).to(device)
            except Exception:
                continue
            with torch.no_grad():
                fe = model.encode_image(im)
                fe = fe / fe.norm(dim=-1, keepdim=True)
            cat_sim = float((fe @ ct.T).max())
            bg_sim = float((fe @ bg.T).max())
            scored.append((fp, cat_sim, bg_sim))

        keepers = [s for s in scored if s[1] >= args.min_score and s[1] - s[2] >= args.margin]
        keepers.sort(key=lambda s: s[1], reverse=True)
        keepers = keepers[:args.limit]

        odir = OUT_DIR / cid
        if odir.exists():
            for old in odir.glob("*.jpg"):
                old.unlink()
        odir.mkdir(exist_ok=True)

        for n, (fp, cat_sim, bg_sim) in enumerate(keepers):
            Image.open(fp).convert("RGB").save(odir / f"{n:02d}.jpg", "JPEG", quality=90)
            meta = cand_meta.get(f"{cid}/{fp.name}", {})
            out_man.write(json.dumps({
                "id": cid, "file": f"{cid}/{n:02d}.jpg",
                "filter_score": round(cat_sim, 4), "bg_score": round(bg_sim, 4),
                "source_url": meta.get("source_url"),
                "foreign_landing_url": meta.get("foreign_landing_url"),
                "creator": meta.get("creator"), "license": meta.get("license"),
                "provider": meta.get("provider"),
            }) + "\n")

        top = round(keepers[0][1], 3) if keepers else None
        bot = round(keepers[-1][1], 3) if keepers else None
        report[cid] = {"candidates": len(scored), "kept": len(keepers),
                       "score_hi": top, "score_lo": bot}
        flag = "  <-- LOW" if len(keepers) < 5 else ""
        print(f"[{ci}/{len(cats)}] {cid}: kept {len(keepers)}/{len(scored)}  "
              f"score {bot}..{top}{flag}")

    out_man.close()
    REPORT.write_text(json.dumps(report, indent=1))
    thin = sorted(k for k, v in report.items() if v["kept"] < 5)
    print(f"\nwrote {OUT_MANIFEST.name} + {REPORT.name}")
    print(f"categories with <5 keepers ({len(thin)}): {thin}")


if __name__ == "__main__":
    main()
