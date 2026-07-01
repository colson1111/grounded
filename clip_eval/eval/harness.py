#!/Users/craigolson/grounded/clip_env/bin/python3.14
"""
CLIP zero-shot eval harness for Grounded unlock-object classifier.
Usage: python harness.py [--model MobileCLIP-S1] [--pretrained datacompdr] [--top-k 5] [--min-sim 0.0]
"""

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import open_clip
import torch
from PIL import Image

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
CATEGORIES_FILE = REPO_ROOT / "categories" / "categories_50.json"
IMAGES_DIR = REPO_ROOT / "data" / "images"
DECOYS_DIR = REPO_ROOT / "data" / "decoys"
STATE_DIR = REPO_ROOT / "state"
CONFIG_FILE = STATE_DIR / "config.json"
STATUS_FILE = STATE_DIR / "status.json"
RESULTS_LOG = STATE_DIR / "results_log.jsonl"

RECALL_TARGET = 0.95
FALSE_ACCEPT_TARGET = 0.02
LATENCY_TARGET_MS = 200.0


def load_config(args: argparse.Namespace) -> dict:
    with open(CONFIG_FILE) as f:
        config = json.load(f)
    if args.model:
        config["model"] = args.model
    if args.pretrained:
        config["pretrained"] = args.pretrained
    if args.top_k is not None:
        config["top_k"] = args.top_k
    if args.min_sim is not None:
        config["min_sim"] = args.min_sim
    return config


def embed_texts(model, tokenizer, texts: list[str], device: str) -> torch.Tensor:
    tokens = tokenizer(texts).to(device)
    with torch.no_grad():
        features = model.encode_text(tokens)
    features = features / features.norm(dim=-1, keepdim=True)
    return features


def embed_image(model, preprocess, image_path: Path, device: str) -> torch.Tensor:
    img = preprocess(Image.open(image_path).convert("RGB")).unsqueeze(0).to(device)
    with torch.no_grad():
        features = model.encode_image(img)
    features = features / features.norm(dim=-1, keepdim=True)
    return features


def cosine_sim(img_feat: torch.Tensor, text_feats: torch.Tensor) -> torch.Tensor:
    # img_feat: (1, D), text_feats: (N, D) -> (N,)
    return (img_feat @ text_feats.T).squeeze(0)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=None)
    parser.add_argument("--pretrained", default=None)
    parser.add_argument("--top-k", type=int, default=None, dest="top_k")
    parser.add_argument("--min-sim", type=float, default=None, dest="min_sim")
    args = parser.parse_args()

    config = load_config(args)
    model_name = config["model"]
    pretrained = config["pretrained"]
    top_k = config["top_k"]
    min_sim = config["min_sim"]
    prompt_strategy = config.get("prompt_strategy", "multi")

    print(f"Model: {model_name}  pretrained: {pretrained}  top_k: {top_k}  min_sim: {min_sim}  prompts: {prompt_strategy}")

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")

    print("Loading model...")
    model, _, preprocess = open_clip.create_model_and_transforms(model_name, pretrained=pretrained)
    model = model.to(device)
    model.eval()
    tokenizer = open_clip.get_tokenizer(model_name)

    with open(CATEGORIES_FILE) as f:
        categories = json.load(f)

    # Embed category prompts
    print("Embedding category prompts...")
    cat_embeddings: dict[str, torch.Tensor] = {}
    for cat in categories:
        cid = cat["id"]
        if prompt_strategy == "multi":
            prompts = cat["prompts"]
        else:
            # single: use first prompt only
            prompts = [cat["prompts"][0]]
        feats = embed_texts(model, tokenizer, prompts, device)
        # Average and re-normalize
        avg = feats.mean(dim=0)
        avg = avg / avg.norm()
        cat_embeddings[cid] = avg

    cat_ids = list(cat_embeddings.keys())
    # Stack into matrix: (N_cats, D)
    text_matrix = torch.stack([cat_embeddings[cid] for cid in cat_ids])  # (N, D)

    # Eval per category
    per_category_results: dict[str, dict] = {}
    latencies_ms: list[float] = []
    total_hits = 0
    total_images = 0

    print("Evaluating category images...")
    for cat in categories:
        cid = cat["id"]
        cat_dir = IMAGES_DIR / cid
        if not cat_dir.exists():
            continue
        image_files = [p for p in cat_dir.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png")]
        if not image_files:
            continue

        hits = 0
        for img_path in image_files:
            t0 = time.perf_counter()
            try:
                img_feat = embed_image(model, preprocess, img_path, device)
            except Exception as e:
                print(f"  Error loading {img_path}: {e}")
                continue
            elapsed_ms = (time.perf_counter() - t0) * 1000
            latencies_ms.append(elapsed_ms)

            sims = cosine_sim(img_feat, text_matrix)  # (N_cats,)
            top_k_indices = sims.topk(min(top_k, len(cat_ids))).indices.tolist()
            top_k_ids = [cat_ids[i] for i in top_k_indices]
            top_sim = sims[top_k_indices[0]].item() if top_k_indices else 0.0

            hit = (cid in top_k_ids) and (top_sim >= min_sim if min_sim > 0.0 else True)
            if hit:
                hits += 1
            total_images += 1

        total_hits += hits
        recall = hits / len(image_files)
        per_category_results[cid] = {
            "id": cid,
            "display_name": cat["display_name"],
            "total": len(image_files),
            "hits": hits,
            "recall": recall,
        }

    overall_recall = total_hits / total_images if total_images > 0 else 0.0

    # Eval decoys
    print("Evaluating decoy images...")
    decoy_files = [p for p in DECOYS_DIR.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png")] if DECOYS_DIR.exists() else []
    false_accepts = 0
    total_decoys = 0

    for img_path in decoy_files:
        t0 = time.perf_counter()
        try:
            img_feat = embed_image(model, preprocess, img_path, device)
        except Exception as e:
            print(f"  Error loading decoy {img_path}: {e}")
            continue
        elapsed_ms = (time.perf_counter() - t0) * 1000
        latencies_ms.append(elapsed_ms)

        sims = cosine_sim(img_feat, text_matrix)
        top_sim = sims.max().item()
        if top_sim >= min_sim and min_sim > 0.0:
            false_accepts += 1
        elif min_sim == 0.0:
            # Without a threshold, any top-1 is a "false accept" — use 0.5 as baseline
            if top_sim >= 0.5:
                false_accepts += 1
        total_decoys += 1

    false_accept_rate = false_accepts / total_decoys if total_decoys > 0 else 0.0

    # Sort by recall ascending
    sorted_cats = sorted(per_category_results.values(), key=lambda x: x["recall"])
    worst_10 = [{"id": c["id"], "recall": round(c["recall"], 3)} for c in sorted_cats[:10]]

    import statistics
    median_latency_ms = statistics.median(latencies_ms) if latencies_ms else 0.0

    # Load current iteration
    if STATUS_FILE.exists():
        with open(STATUS_FILE) as f:
            status = json.load(f)
        iteration = status.get("iteration", 0) + 1
    else:
        iteration = 1

    targets_met = (
        overall_recall >= RECALL_TARGET
        and false_accept_rate <= FALSE_ACCEPT_TARGET
        and median_latency_ms <= LATENCY_TARGET_MS
    )

    # Build next suggestion
    suggestions = []
    if overall_recall < RECALL_TARGET:
        suggestions.append(f"Recall {overall_recall:.2%} below target {RECALL_TARGET:.0%} — try increasing top_k or adding more descriptive prompts for worst categories.")
    if false_accept_rate > FALSE_ACCEPT_TARGET:
        suggestions.append(f"False accept rate {false_accept_rate:.2%} above target {FALSE_ACCEPT_TARGET:.0%} — try raising min_sim threshold.")
    if median_latency_ms > LATENCY_TARGET_MS:
        suggestions.append(f"Latency {median_latency_ms:.0f}ms above target {LATENCY_TARGET_MS:.0f}ms — try a smaller model variant.")
    if targets_met:
        suggestions.append("All targets met. Ready for on-device integration.")
    next_suggestion = " ".join(suggestions) if suggestions else "Run next iteration."

    # Write results log
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    log_entry = {
        "iteration": iteration,
        "model": model_name,
        "pretrained": pretrained,
        "top_k": top_k,
        "min_sim": min_sim,
        "recall": round(overall_recall, 4),
        "false_accept_rate": round(false_accept_rate, 4),
        "median_latency_ms": round(median_latency_ms, 2),
        "worst_categories": worst_10,
        "total_images": total_images,
        "total_decoys": total_decoys,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    with open(RESULTS_LOG, "a") as f:
        f.write(json.dumps(log_entry) + "\n")

    # Update status
    new_status = {
        "iteration": iteration,
        "targets_met": targets_met,
        "next_suggestion": next_suggestion,
    }
    with open(STATUS_FILE, "w") as f:
        json.dump(new_status, f, indent=2)

    # Print summary
    print(f"\n{'='*60}")
    print(f"Iteration {iteration} results")
    print(f"{'='*60}")
    print(f"Overall recall:     {overall_recall:.2%}  (target >= {RECALL_TARGET:.0%})  {'PASS' if overall_recall >= RECALL_TARGET else 'FAIL'}")
    print(f"False accept rate:  {false_accept_rate:.2%}  (target <= {FALSE_ACCEPT_TARGET:.0%})  {'PASS' if false_accept_rate <= FALSE_ACCEPT_TARGET else 'FAIL'}")
    print(f"Median latency:     {median_latency_ms:.1f}ms  (target <= {LATENCY_TARGET_MS:.0f}ms)  {'PASS' if median_latency_ms <= LATENCY_TARGET_MS else 'FAIL'}")
    print(f"Total images:       {total_images}")
    print(f"Total decoys:       {total_decoys}")
    print(f"\nWorst 10 categories by recall:")
    for c in worst_10:
        print(f"  {c['id']:30s}  {c['recall']:.2%}")
    print(f"\nTargets met: {'YES' if targets_met else 'NO'}")
    print(f"Next: {next_suggestion}")


if __name__ == "__main__":
    main()
