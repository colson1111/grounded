#!/Users/craigolson/grounded/clip_env/bin/python3.14
"""
Download eval images from COCO 2017 validation set.
Usage: python fetch_images.py
"""

import json
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

ANNOTATIONS_URL = "http://images.cocodataset.org/annotations/annotations_trainval2017.zip"
COCO_VAL_IMG_BASE = "http://images.cocodataset.org/val2017/"
IMAGES_PER_CATEGORY = 10
DECOY_COUNT = 20
MIN_CATEGORIES_FOR_DECOY = 5

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
CATEGORIES_FILE = REPO_ROOT / "categories" / "categories_50.json"
DATA_DIR = SCRIPT_DIR
ANNOTATIONS_DIR = DATA_DIR / "annotations"
ANNOTATIONS_ZIP = DATA_DIR / "annotations_trainval2017.zip"
ANNOTATIONS_JSON = ANNOTATIONS_DIR / "instances_val2017.json"
IMAGES_DIR = DATA_DIR / "images"
DECOYS_DIR = DATA_DIR / "decoys"


def download_file(url: str, dest: Path) -> None:
    print(f"Downloading {url} -> {dest} ...")
    dest.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, dest)
    print(f"  Done ({dest.stat().st_size // 1024} KB)")


def ensure_annotations() -> dict:
    if not ANNOTATIONS_JSON.exists():
        if not ANNOTATIONS_ZIP.exists():
            download_file(ANNOTATIONS_URL, ANNOTATIONS_ZIP)
        print(f"Extracting {ANNOTATIONS_ZIP} ...")
        with zipfile.ZipFile(ANNOTATIONS_ZIP, "r") as zf:
            zf.extractall(DATA_DIR)
        print("  Extracted.")
    with open(ANNOTATIONS_JSON) as f:
        return json.load(f)


COCO_ALIASES = {
    "television": "tv",
    "sofa": "couch",
    "exercise_bike": "bicycle",
    "kayak": "boat",
    # everything else with no good COCO match → None (skip, no proxy)
    "trash_can": None,
    "bathtub": None,
    "piano": None,
    "washing_machine": None,
    "treadmill": None,
    "guitar": None,
    "dishwasher": None,
    "desk": None,
    "barbecue_grill": None,
    "drum_kit": None,
    "weight_rack": None,
    "ladder": None,
    "lawnmower": None,
    "power_drill": None,
    "toolbox": None,
    "filing_cabinet": None,
    "printer": None,
    "whiteboard": None,
    "coat_rack": None,
    "garden_hose": None,
    "mailbox": None,
    "stroller": None,
    "vending_machine": None,
    "safe": None,
    "aquarium": None,
    "ironing_board": None,
    "tent": None,
}


def fuzzy_match_coco(our_id: str, coco_categories: list[dict]) -> dict | None:
    """Match our category id to a COCO category using aliases then substring logic."""
    if our_id in COCO_ALIASES:
        alias = COCO_ALIASES[our_id]
        if alias is None:
            return None
        for c in coco_categories:
            if c["name"].lower() == alias.lower():
                return c
        return None
    normalized = our_id.replace("_", " ").lower()
    # Exact match first
    for c in coco_categories:
        if c["name"].lower() == normalized:
            return c
    # Substring match: our name in coco name or vice versa
    for c in coco_categories:
        coco_name = c["name"].lower()
        if normalized in coco_name or coco_name in normalized:
            return c
    # Word overlap match
    our_words = set(normalized.split())
    for c in coco_categories:
        coco_words = set(c["name"].lower().split())
        if our_words & coco_words:
            return c
    return None


def download_image(filename: str, dest: Path) -> bool:
    if dest.exists():
        return True
    url = COCO_VAL_IMG_BASE + filename
    try:
        urllib.request.urlretrieve(url, dest)
        return True
    except Exception as e:
        print(f"  Failed to download {url}: {e}", file=sys.stderr)
        return False


def main() -> None:
    with open(CATEGORIES_FILE) as f:
        our_categories = json.load(f)

    coco = ensure_annotations()
    coco_cats = coco["categories"]
    coco_anns = coco["annotations"]
    coco_imgs = {img["id"]: img for img in coco["images"]}

    # Build mapping: coco_cat_id -> list of image_ids
    cat_to_img_ids: dict[int, list[int]] = {}
    for ann in coco_anns:
        cid = ann["category_id"]
        cat_to_img_ids.setdefault(cid, [])
        if ann["image_id"] not in cat_to_img_ids[cid]:
            cat_to_img_ids[cid].append(ann["image_id"])

    # Build mapping: image_id -> set of coco_cat_ids (for decoy selection)
    img_to_cats: dict[int, set[int]] = {}
    for ann in coco_anns:
        img_to_cats.setdefault(ann["image_id"], set()).add(ann["category_id"])

    matched_categories = 0
    unmatched_categories = []
    total_images = 0

    for cat in our_categories:
        our_id = cat["id"]
        coco_match = fuzzy_match_coco(our_id, coco_cats)

        if coco_match is None:
            unmatched_categories.append(our_id)
            continue

        coco_cat_id = coco_match["id"]
        image_ids = cat_to_img_ids.get(coco_cat_id, [])[:IMAGES_PER_CATEGORY]

        if not image_ids:
            unmatched_categories.append(our_id)
            continue

        dest_dir = IMAGES_DIR / our_id
        dest_dir.mkdir(parents=True, exist_ok=True)
        downloaded = 0

        for img_id in image_ids:
            img_info = coco_imgs.get(img_id)
            if img_info is None:
                continue
            filename = img_info["file_name"]
            dest = dest_dir / filename
            if download_image(filename, dest):
                downloaded += 1

        if downloaded > 0:
            matched_categories += 1
            total_images += downloaded
            print(f"  [{our_id}] matched COCO '{coco_match['name']}' -> {downloaded} images")
        else:
            unmatched_categories.append(our_id)

    # Decoy images: COCO images with 5+ distinct category labels
    print("\nSelecting decoy images...")
    DECOYS_DIR.mkdir(parents=True, exist_ok=True)
    decoy_candidates = [
        (img_id, cats)
        for img_id, cats in img_to_cats.items()
        if len(cats) >= MIN_CATEGORIES_FOR_DECOY
    ]
    # Sort by descending category count for most ambiguous first
    decoy_candidates.sort(key=lambda x: -len(x[1]))
    decoy_count = 0

    for img_id, _ in decoy_candidates:
        if decoy_count >= DECOY_COUNT:
            break
        img_info = coco_imgs.get(img_id)
        if img_info is None:
            continue
        filename = img_info["file_name"]
        dest = DECOYS_DIR / filename
        if download_image(filename, dest):
            decoy_count += 1

    print(f"\n=== Summary ===")
    print(f"Categories with images:   {matched_categories} / {len(our_categories)}")
    print(f"Total category images:    {total_images}")
    print(f"Decoy images downloaded:  {decoy_count}")
    if unmatched_categories:
        print(f"No COCO match ({len(unmatched_categories)}): {', '.join(unmatched_categories)}")


if __name__ == "__main__":
    main()
