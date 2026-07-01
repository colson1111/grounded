# Focus App: Object-Based Unlock — Model Replacement Plan

## Background

The app blocks distracting apps during a scheduled or manually-activated focus profile (e.g. a 9am–5pm work profile). To unlock, the user either scans a QR code or points the camera at a real-world object they pre-selected from a curated list during setup. The object should typically be something physically inconvenient to reach (e.g. a refrigerator instead of the monitor sitting in front of them), so retrieving it adds friction and a moment of reconsideration before unlocking.

Apple's built-in Vision classifier (`VNClassifyImageRequest`) is not accurate enough for this use case and is being replaced.

## Key Decisions Made

- **Classification, not instance-matching.** The unlock target is a *category* (e.g. "any refrigerator"), not one specific user-owned object. No per-object enrollment photos are needed — the user just picks a category from a curated list at setup.
- **Curated category list (~1000 items), not free text.** Open-ended user-typed categories were considered and rejected for v1 — too easy to pick something trivially easy to match, undermining the friction goal.
- **Top-5 matching, not top-1.** If the user's chosen category appears anywhere in the model's top 5 predictions for the live camera frame, the unlock succeeds. This tolerates near-miss confusions (e.g. oven vs. refrigerator) without weakening the friction goal, since both objects are still equally inconvenient to reach.
- **Model approach: CLIP zero-shot**, specifically Apple's **MobileCLIP** (CoreML-ready, built for on-device phone inference). Each of the ~1000 categories is embedded once via text prompts (e.g. "a photo of a refrigerator"); at unlock time, the live camera frame is embedded and compared via cosine similarity against all category embeddings, taking the top 5.
- **Why zero-shot over fine-tuning:** no training pipeline or labeled dataset required to ship; categories can be added/removed by just adding text prompts, not retraining. Fine-tuning a dedicated 1000-class classifier remains a fallback if zero-shot accuracy proves insufficient for specific categories.
- **QR code remains as a fallback unlock method** for cases where the user can't access a matching object (e.g. traveling).
- **Primary failure mode to guard against: false accepts**, not false rejects. The friction goal fails if the unlock is trivially gameable (e.g. a photo of the object on a screen, or an object that's coincidentally always nearby).

## Open Items / Things to Decide During Build

- Final curated category list — needs vetting so visually-near-duplicate categories don't make top-5 *too* easy (e.g. avoid having "couch" and "armchair" both trivially satisfy each other if that undermines the friction goal — or decide this is acceptable since both still require leaving the desk).
- Exact prompt template(s) per category (CLIP zero-shot accuracy is sensitive to phrasing).
- Confidence threshold, if any, beyond just "in top 5" (e.g. do you also want a minimum similarity score, so a very low-confidence top-5 placement doesn't count?).
- Decoy testing policy: should photo-of-a-photo or screen-displayed images be explicitly tested and penalized?

---

## Implementation Plan: Autonomous Build & Eval Loop in Claude Code

### Goal statement for the agent

Give Claude Code an explicit, measurable goal — this is what makes the "run on its own until successful" loop work. Something like:

> Build an on-device MobileCLIP zero-shot classifier for a curated list of ~1000 household/world object categories. Using top-5 matching, achieve ≥95% recall on held-out test images per category, ≤2% false-accept rate against decoy images, and <200ms on-device inference time. Compare results against Apple's VNClassifyImageRequest baseline on the same test set.
>
> Validate and tune on a 20-50 category subset first, capped at 10 iterations, before running once at full scale. Each iteration: read current state from `state/config.json` and `state/status.json`, run one experiment, append a compact result to `state/results_log.jsonl`, update state, stop. Do not re-read the full result history each iteration — only the most recent entries. Report final results and stop early if targets are met before the cap.

### Step 1: Build the category list

- Start from an existing taxonomy (e.g. a relevant subset of ImageNet-1k classes, Open Images categories, or COCO) rather than inventing 1000 labels from scratch.
- Filter down to things plausible as household/world "unlock objects" — exclude rare/abstract/non-physical classes.
- Output as a simple JSON/CSV: `category_id, display_name, clip_prompt_template(s)`.

### Step 2: Build the eval dataset

This is the part that determines whether the agent loop's self-testing is trustworthy — garbage eval data means false confidence in the results.

- **Per-category test images:** several real photos per category, varied angle/lighting/background. Pull from existing labeled datasets (Open Images, ImageNet val set) rather than hand-collecting where possible, since you need broad coverage across ~1000 categories.
- **Decoy/negative set:** images designed to probe false accepts — near-duplicate categories, photos-of-photos or screens, ambiguous/cluttered scenes.
- Keep this dataset separate from anything used to tune prompts, so the agent can't "cheat" by overfitting prompt wording to the test set without it showing up as a real generalization gap later.

### Step 3: Build the harness

A script (Python, run outside Xcode is fine for the iteration loop, then port the final config into the iOS app) that:
1. Loads MobileCLIP (or whichever variant being tested) and embeds all category prompts.
2. For each test image, embeds it and computes top-5 categories by cosine similarity.
3. Computes recall (is true category in top 5?) and false-accept rate (does a decoy image land in top 5 for a category it shouldn't?).
4. Logs per-category breakdown, not just an aggregate number — aggregate accuracy can hide categories that are completely broken.
5. Times inference to check the latency budget.

### Step 4: Build the Apple Vision baseline comparison

Same harness, swapped model: run the same test images through `VNClassifyImageRequest`, apply the same top-5 logic, log the same metrics. This gives you a like-for-like comparison rather than an anecdotal "it feels better" judgment.

### Step 5: Set the agent loose — with cost controls

An open-ended "run until successful" loop against ~1000 categories risks burning a large token budget without converging, because most of the cost isn't model inference (that's free local compute) — it's Claude re-reading large eval outputs into context on every iteration. Build in guardrails:

- **Subset-first.** Build and debug the harness against a small slice (20–50 categories), not all 1000. Fix bugs and validate the pipeline logic here. Only scale to the full category list for a final validation run or two, once the harness itself is no longer changing.
- **Summary-only logging.** The harness should output an aggregate score plus a short "worst N categories" list, not a full per-category dump every iteration. Claude only needs to see what's broken, not what's already working — re-reading 1000 lines of mostly-fine results every loop is pure token waste.
- **Hard iteration cap.** Cap at 5–10 tuning iterations on the subset, not "loop until targets are met." Most of the achievable gain typically shows up in the first couple of passes; an unbounded instruction has no natural stopping point.
- **Separate build from tune.** Writing the harness, dataset loader, and comparison script is a normal bounded coding task — do it once as regular Claude Code work. Only the prompt/threshold/model-variant tuning needs to be iterative, and that search space is narrow (a handful of prompt variants, 2-3 model sizes, a threshold sweep) — not open-ended.

**Stateless loop via disk-persisted state.** Rather than one long-running conversation that accumulates every iteration's output in context, structure each loop iteration as a fresh, short invocation that reads/writes state to files:

- `state/config.json` — current best-known config (prompt templates, model variant, threshold), updated each iteration.
- `state/results_log.jsonl` — one compact line per iteration (iteration number, config used, aggregate recall/false-accept/latency, worst-N categories) — append-only, so history is preserved on disk without being re-read into context wholesale.
- `state/status.json` — current iteration count, whether targets are met, and a short "next thing to try" note the prior iteration left for the next one.

Each invocation: read `status.json` and `config.json` (small, cheap), read only the *last* entry (or last few) of `results_log.jsonl` rather than the whole history, run one experiment, append a new result line, update `config.json` and `status.json`, then stop. This keeps each iteration's context small and bounded regardless of how many iterations have run, and gives you a durable, inspectable record of what was tried without needing to scroll back through a giant conversation. Claude Code's scheduled triggers (or just re-invoking it manually) work well for this — each run is independent and self-orienting from the state files rather than depending on conversation memory.

### Step 6: Review output

The agent should produce: final metrics (CLIP vs. Apple Vision baseline, per-category breakdown), the final prompt templates and model config, and a short report on any categories that remain weak or were removed.

### Step 7: Port into the app

Once the harness validates the config, integrate MobileCLIP CoreML model + finalized prompt embeddings into the iOS app, replacing the `VNClassifyImageRequest` call with the embedding/cosine-similarity top-5 logic.

---

## Summary of the Comparison You'll End Up With

| | Apple Vision (`VNClassifyImageRequest`) | MobileCLIP zero-shot |
|---|---|---|
| Setup cost | None (built-in) | Build category list + prompts |
| Per-category recall | Baseline (currently unsatisfactory) | Tuned via agent loop |
| Adding new categories | Fixed taxonomy, can't customize | Just add a text prompt |
| False-accept risk | Unknown — needs same eval | Explicitly tested against decoys |
| On-device latency | Fast (native) | Needs measurement, expect comparable on MobileCLIP S0 |