#!/usr/bin/env python3
"""
Render clip_eval/state/last_run_detail.json (written by eval/harness.py) into a
self-contained HTML evaluation report.

  clip_env/bin/python clip_eval/build_report.py
  -> clip_eval/report/unlock-eval.html   (images inlined as base64, no assets)
"""

import base64
import io
import json
from datetime import datetime
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
DETAIL = HERE / "state" / "last_run_detail.json"
IMAGES_DIR = HERE / "data" / "images"
OUT = HERE / "report" / "unlock-eval.html"

GRID_SAMPLES = 18
THUMB_W = 150
EXAMPLE_W = 300

# Categories to surface as worked-example tabs (kept if present in the run).
# A deliberate cross-domain spread, not one room.
TAB_CATEGORIES = [
    "refrigerator", "sofa", "office_chair", "bicycle", "guitar",
    "treadmill", "grandfather_clock", "aquarium", "wheelchair", "bathtub",
]


def thumb(rel_path: str, width: int) -> str | None:
    p = IMAGES_DIR / rel_path
    if not p.exists():
        return None
    try:
        im = Image.open(p).convert("RGB")
    except Exception:
        return None
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=78)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def pct(x: float) -> str:
    return f"{x * 100:.1f}%"


def judge(metric: str, v: float) -> str:
    t = {
        "recall": (0.90, 0.75, True), "precision": (0.70, 0.40, True),
        "steal": (0.10, 0.25, False), "far": (0.05, 0.15, False),
        "latency": (200, 350, False),
    }[metric]
    good, ok, higher_better = t
    if higher_better:
        return "pass" if v >= good else "warn" if v >= ok else "fail"
    return "pass" if v <= good else "warn" if v <= ok else "fail"


def bar(frac: float, cls: str) -> str:
    w = max(0.0, min(1.0, frac)) * 100
    return f'<span class="bar"><span class="bar-fill {cls}" style="width:{w:.1f}%"></span></span>'


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def top5_bars(top5: list[dict], true_id: str, true_sim: float, in_top5: bool) -> str:
    smax = max((r["sim"] for r in top5), default=1.0) or 1.0
    rows = []
    for r in top5:
        is_true = r["id"] == true_id
        rows.append(
            f'<div class="t5-row{" is-true" if is_true else ""}">'
            f'<span class="t5-name">{esc(r["display_name"])}</span>'
            f'{bar(r["sim"] / smax, "accent" if is_true else "muted")}'
            f'<span class="t5-sim">{r["sim"]:.3f}</span></div>'
        )
    if not in_top5:
        rows.append(
            f'<div class="t5-row is-miss">'
            f'<span class="t5-name">{esc(true_id)} (true)</span>'
            f'{bar(true_sim / smax, "fail")}'
            f'<span class="t5-sim">{true_sim:.3f}</span></div>'
        )
    return '<div class="t5">' + "".join(rows) + "</div>"


def main() -> None:
    d = json.loads(DETAIL.read_text())
    m, agg = d["meta"], d["aggregate"]
    cats = d["per_category"]
    samples = d["samples"]

    run_date = datetime.fromisoformat(m["timestamp"]).strftime("%Y-%m-%d %H:%M UTC")

    # filter_score per image (how clearly it depicts its category) — used to keep
    # worked-example misses to real photos the model genuinely got wrong, not junk.
    fscore: dict[str, float] = {}
    man_path = IMAGES_DIR.parent / "images_manifest.jsonl"
    if man_path.exists():
        for line in man_path.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                fscore[r["file"]] = r.get("filter_score", 0.0)

    # Precision @1, computed from the samples: of the frames where the model's single
    # best guess was X, the share that really were X. (The harness's top-k "precision"
    # is structurally near-zero because top-k always names k categories per frame.)
    pred1_tot: dict[str, int] = {}
    pred1_ok: dict[str, int] = {}
    for s in samples:
        p = s["top5"][0]["id"] if s["top5"] else None
        if p is None:
            continue
        pred1_tot[p] = pred1_tot.get(p, 0) + 1
        if p == s["true_id"]:
            pred1_ok[p] = pred1_ok.get(p, 0) + 1
    prec1 = {k: pred1_ok.get(k, 0) / v for k, v in pred1_tot.items() if v}
    for c in cats:
        c["precision1"] = prec1.get(c["id"], 1.0 if c.get("recall_at_1", 0) else 0.0)
    tested_ids = {c["id"] for c in cats}
    macro_prec1 = sum(prec1.get(cid, 0.0) for cid in tested_ids) / len(tested_ids) if tested_ids else 0.0

    # --- metric readouts ---
    metrics = [
        ("Recall @k", agg["recall_at_k"], "recall", pct,
         f'true anchor appears in the top {m["top_k"]}'),
        ("Recall @1", agg["recall_at_1"], "recall", pct, "true anchor is the single best match"),
        ("Precision @1", macro_prec1, "precision", pct,
         "when the top guess is an anchor, share that really are it"),
        ("Mean steal rate", agg["mean_steal_rate"], "steal", pct,
         "chance a non-anchor object unlocks a given anchor"),
        ("Decoy false-accept", agg["decoy_false_accept_rate"], "far", pct,
         "non-category objects that still cross the unlock bar"),
        ("Median latency", agg["median_latency_ms"], "latency",
         lambda v: f"{v:.0f} ms", "per-frame embed + match, this machine"),
    ]
    metric_html = "".join(
        f'<div class="metric">'
        f'<div class="metric-val {judge(k, v)}">{fmt(v)}</div>'
        f'<div class="metric-label">{esc(lab)}</div>'
        f'<div class="metric-note">{esc(note)}</div></div>'
        for lab, v, k, fmt, note in metrics
    )

    # --- worked examples: one tab per selected category ---
    def wrong_gap(s):
        return s["top5"][0]["sim"] - s["true_sim"] if s["top5"] else 0.0

    def worked_card(s, cap):
        if not s:
            return ""
        img = thumb(s["file"], EXAMPLE_W)
        return (
            f'<figure class="worked">'
            f'{f"<img src=\"{img}\" alt=\"\">" if img else ""}'
            f'<div class="wk-body">'
            f'<figcaption><span class="wk-cap">{esc(cap)}</span>'
            f'<span class="wk-true">true: <b>{esc(s["true_display"])}</b> &middot; '
            f'model: <b>{esc(s["top5"][0]["display_name"]) if s["top5"] else "?"}</b></span></figcaption>'
            f'{top5_bars(s["top5"], s["true_id"], s["true_sim"], s["in_topk"])}'
            f'</div></figure>'
        )

    by_cat: dict[str, list] = {}
    for s in samples:
        by_cat.setdefault(s["true_id"], []).append(s)

    tab_ids = [c for c in TAB_CATEGORIES if c in by_cat]
    if len(tab_ids) < 2:
        tab_ids = [c["id"] for c in cats if c["id"] in by_cat][:6]

    tabs, panels = [], []
    for i, cid in enumerate(tab_ids):
        pool = by_cat[cid]
        hit = max((s for s in pool if s["at_1"]), key=lambda s: s["true_sim"], default=None)
        # Prefer a miss on a clearly-depicting photo (filter_score >= 0.27) so the
        # example shows a real model confusion, not an ambiguous / junk image.
        SOLID = 0.27
        wrong = [s for s in pool if not s["at_1"]]
        good_wrong = [s for s in wrong if fscore.get(s["file"], 0.0) >= SOLID]
        pick_from = good_wrong or wrong
        # among those, the widest-confidence miss (true category not in top-k first)
        miss = (sorted((s for s in pick_from if not s["in_topk"]), key=wrong_gap, reverse=True)
                or sorted(pick_from, key=wrong_gap, reverse=True)
                or [None])[0]
        disp = pool[0]["true_display"]
        cat_row = next((c for c in cats if c["id"] == cid), {})
        rc = cat_row.get("recall")
        meta = f'recall@k {pct(rc)}' if rc is not None else ""
        tabs.append(
            f'<button class="tab mono" role="tab" data-panel="wp{i}" '
            f'id="wt{i}" aria-controls="wp{i}" aria-selected="{"true" if i == 0 else "false"}" '
            f'tabindex="{"0" if i == 0 else "-1"}">{esc(cid)}</button>'
        )
        cards = worked_card(hit, "Correct — top match")
        if miss and (not hit or miss["file"] != hit["file"]):
            cards += worked_card(miss, "Missed — anchor not in top match" if not miss["in_topk"]
                                 else "Confused — wrong top match")
        if not cards:
            cards = '<p class="empty">No sample predictions for this category.</p>'
        panels.append(
            f'<div class="tabpanel" id="wp{i}" role="tabpanel" aria-labelledby="wt{i}"{"" if i == 0 else " hidden"}>'
            f'<p class="panel-meta"><b>{esc(disp)}</b>{f" &middot; {meta}" if meta else ""}</p>'
            f'{cards}</div>'
        )
    tabs_html = "".join(tabs)
    panels_html = "".join(panels)

    # --- per-category table ---
    rows = []
    for c in cats:
        rc, rc1 = c["recall"], c.get("recall_at_1", 0.0)
        pr, st = c.get("precision1", 0.0), c.get("steal_rate", 0.0)
        conf = ", ".join(f'{x["display_name"]}&times;{x["count"]}' for x in c.get("top_confusers", [])[:3]) or "&mdash;"
        rows.append(
            f'<tr>'
            f'<td class="mono id">{esc(c["id"])}</td>'
            f'<td class="mono num" data-v="{c["total"]}">{c["total"]}</td>'
            f'<td class="mono num" data-v="{rc:.4f}"><span class="v {judge("recall", rc)}">{pct(rc)}</span>{bar(rc, judge("recall", rc))}</td>'
            f'<td class="mono num" data-v="{rc1:.4f}"><span class="v">{pct(rc1)}</span>{bar(rc1, "muted")}</td>'
            f'<td class="mono num" data-v="{pr:.4f}"><span class="v {judge("precision", pr)}">{pct(pr)}</span>{bar(pr, judge("precision", pr))}</td>'
            f'<td class="mono num" data-v="{st:.4f}"><span class="v {judge("steal", st)}">{pct(st)}</span>{bar(st, judge("steal", st))}</td>'
            f'<td class="conf">{conf}</td>'
            f'</tr>'
        )
    table_html = "".join(rows)

    # --- confusion pairs ---
    cp = d.get("confusion_pairs", [])
    cpmax = max((p["count"] for p in cp), default=1)
    conf_html = "".join(
        f'<div class="cp-row">'
        f'<span class="cp-a mono">{esc(p["shown_id"])}</span>'
        f'<span class="cp-arrow">read as</span>'
        f'<span class="cp-b mono">{esc(p["predicted_id"])}</span>'
        f'{bar(p["count"] / cpmax, "fail")}'
        f'<span class="cp-n mono">{p["count"]}</span></div>'
        for p in cp
    )

    # --- examples grid: spread of hits and misses ---
    hits = [s for s in samples if s["at_1"]]
    partial = [s for s in samples if s["in_topk"] and not s["at_1"]]
    misses = [s for s in samples if not s["in_topk"]]
    pick = (misses[:7] + partial[:5] + hits[:GRID_SAMPLES])[:GRID_SAMPLES]
    seen, grid = set(), []
    for s in pick:
        if s["file"] in seen:
            continue
        seen.add(s["file"])
        img = thumb(s["file"], THUMB_W)
        if not img:
            continue
        status = "@1" if s["at_1"] else ("top-k" if s["in_topk"] else "miss")
        scls = "pass" if s["at_1"] else ("warn" if s["in_topk"] else "fail")
        chips = "".join(
            f'<span class="chip{" is-true" if r["id"] == s["true_id"] else ""}">{esc(r["display_name"])}</span>'
            for r in s["top5"][:4]
        )
        grid.append(
            f'<figure class="ex">'
            f'<img src="{img}" alt="">'
            f'<figcaption>'
            f'<div class="ex-head"><span class="ex-true">{esc(s["true_display"])}</span>'
            f'<span class="ex-status {scls}">{status}</span></div>'
            f'<div class="ex-chips">{chips}</div>'
            f'</figcaption></figure>'
        )
    grid_html = "".join(grid)

    html = TEMPLATE.format(
        title="Unlock Classifier Evaluation",
        model=esc(m["model"]), pretrained=esc(m["pretrained"]),
        top_k=m["top_k"], min_sim=m["min_sim"],
        n_cat=m["n_categories"], n_img=m["n_images"], n_decoy=m["n_decoys"],
        run_date=run_date, prompt_strategy=esc(m["prompt_strategy"]),
        metric_html=metric_html, tabs_html=tabs_html, panels_html=panels_html,
        table_html=table_html, conf_html=conf_html or "<p class='empty'>No misclassifications recorded.</p>",
        grid_html=grid_html,
    )
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(html)
    kb = len(html.encode()) / 1024
    print(f"wrote {OUT}  ({kb:.0f} KB, {m['n_categories']} categories, {len(grid)} examples)")


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
:root {{
  --ground:#f5f6f8; --surface:#ffffff; --ink:#1a1f28; --muted:#5c6675;
  --line:#e0e3e9; --accent:#0e7c86; --accent-soft:#0e7c8622;
  --pass:#1f7a4d; --warn:#b3701a; --fail:#c0453f;
  --pass-bar:#1f7a4d; --warn-bar:#b3701a; --fail-bar:#c0453f; --muted-bar:#9aa4b2;
}}
@media (prefers-color-scheme:dark) {{
  :root:not([data-theme=light]) {{
    --ground:#101317; --surface:#181c22; --ink:#e7eaef; --muted:#98a2b3;
    --line:#2b313b; --accent:#3bb6c2; --accent-soft:#3bb6c233;
    --pass:#4bbd7e; --warn:#d59b52; --fail:#e0685f;
    --pass-bar:#3f9e6a; --warn-bar:#b3803f; --fail-bar:#c1564f; --muted-bar:#4a5361;
  }}
}}
:root[data-theme=dark] {{
  --ground:#101317; --surface:#181c22; --ink:#e7eaef; --muted:#98a2b3;
  --line:#2b313b; --accent:#3bb6c2; --accent-soft:#3bb6c233;
  --pass:#4bbd7e; --warn:#d59b52; --fail:#e0685f;
  --pass-bar:#3f9e6a; --warn-bar:#b3803f; --fail-bar:#c1564f; --muted-bar:#4a5361;
}}
* {{ box-sizing:border-box; }}
body {{
  margin:0; background:var(--ground); color:var(--ink);
  font:400 15px/1.6 "IBM Plex Sans", system-ui, sans-serif;
}}
.wrap {{ max-width:920px; margin:0 auto; padding:56px 20px 96px; }}
.mono {{ font-family:"IBM Plex Mono", ui-monospace, monospace; font-variant-numeric:tabular-nums; }}
h1 {{ font-weight:600; font-size:30px; letter-spacing:-.01em; margin:0 0 8px; text-wrap:balance; }}
h2 {{ font-weight:600; font-size:18px; margin:52px 0 14px; padding-bottom:8px; border-bottom:1px solid var(--line); }}
p {{ max-width:66ch; color:var(--ink); }}
.sub {{ color:var(--muted); font-size:13px; margin:0; }}
.sub b {{ color:var(--ink); font-weight:500; }}

.metrics {{ display:grid; grid-template-columns:repeat(3,1fr); gap:1px; background:var(--line);
  border:1px solid var(--line); border-radius:8px; overflow:hidden; margin-top:28px; }}
.metric {{ background:var(--surface); padding:16px 16px 14px; }}
.metric-val {{ font-family:"IBM Plex Mono",monospace; font-size:23px; font-weight:600; font-variant-numeric:tabular-nums; }}
.metric-val.pass {{ color:var(--pass); }} .metric-val.warn {{ color:var(--warn); }} .metric-val.fail {{ color:var(--fail); }}
.metric-label {{ font-size:12px; font-weight:600; text-transform:uppercase; letter-spacing:.06em; margin-top:4px; }}
.metric-note {{ font-size:12px; color:var(--muted); margin-top:3px; line-height:1.45; }}

.bar {{ display:inline-block; width:64px; height:4px; background:var(--line); border-radius:2px; vertical-align:middle; overflow:hidden; }}
.bar-fill {{ display:block; height:100%; }}
.bar-fill.accent {{ background:var(--accent); }} .bar-fill.muted {{ background:var(--muted-bar); }}
.bar-fill.pass {{ background:var(--pass-bar); }} .bar-fill.warn {{ background:var(--warn-bar); }} .bar-fill.fail {{ background:var(--fail-bar); }}

.tabs {{ display:flex; flex-wrap:wrap; gap:4px; margin:14px 0 0; border-bottom:1px solid var(--line); }}
.tab {{ appearance:none; background:none; border:1px solid transparent; border-bottom:none;
  color:var(--muted); font-size:12px; padding:7px 12px; border-radius:6px 6px 0 0; cursor:pointer;
  margin-bottom:-1px; }}
.tab:hover {{ color:var(--ink); }}
.tab[aria-selected=true] {{ color:var(--ink); border-color:var(--line); background:var(--surface);
  font-weight:500; }}
.tab:focus-visible {{ outline:2px solid var(--accent); outline-offset:1px; }}
.panels {{ border:1px solid var(--line); border-top:none; border-radius:0 0 8px 8px;
  background:var(--surface); padding:16px; }}
.panel-meta {{ margin:0 0 12px; font-size:13px; color:var(--muted); }}
.panel-meta b {{ color:var(--ink); }}
.worked {{ display:grid; grid-template-columns:{ew}px 1fr; gap:18px; margin:0 0 14px;
  border:1px solid var(--line); border-radius:8px; padding:14px; align-items:start; }}
.worked:last-child {{ margin-bottom:0; }}
.worked img {{ width:100%; border-radius:4px; display:block; }}
.wk-body {{ min-width:0; }}
.worked figcaption {{ display:flex; flex-direction:column; gap:2px; margin-bottom:12px; }}
.wk-cap {{ font-weight:600; }} .wk-true {{ font-size:13px; color:var(--muted); }}
.t5 {{ display:flex; flex-direction:column; gap:5px; }}
.t5-row {{ display:grid; grid-template-columns:1fr 90px 46px; gap:8px; align-items:center; font-size:13px; }}
.t5-row .bar {{ width:100%; }}
.t5-name {{ font-family:"IBM Plex Mono",monospace; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}
.t5-sim {{ font-family:"IBM Plex Mono",monospace; text-align:right; color:var(--muted); }}
.t5-row.is-true .t5-name {{ color:var(--accent); font-weight:500; }}
.t5-row.is-miss .t5-name {{ color:var(--fail); }}

.tbl-scroll {{ overflow-x:auto; border:1px solid var(--line); border-radius:8px; }}
table {{ border-collapse:collapse; width:100%; font-size:13px; background:var(--surface); }}
th, td {{ text-align:left; padding:8px 12px; border-bottom:1px solid var(--line); white-space:nowrap; }}
th {{ position:sticky; top:0; background:var(--surface); font-weight:600; font-size:11px;
  text-transform:uppercase; letter-spacing:.05em; cursor:pointer; user-select:none; }}
th[aria-sort=ascending]::after {{ content:" \\2191"; }} th[aria-sort=descending]::after {{ content:" \\2193"; }}
tr:last-child td {{ border-bottom:0; }}
td.num {{ text-align:right; }}
td.num .v {{ display:inline-block; min-width:44px; }}
td.num .bar {{ width:40px; margin-left:8px; }}
td.id {{ color:var(--ink); }}
.v.pass {{ color:var(--pass); }} .v.warn {{ color:var(--warn); }} .v.fail {{ color:var(--fail); }}
td.conf {{ color:var(--muted); white-space:normal; min-width:240px; font-size:12px; }}
th:last-child, td.conf {{ position:relative; }}

.cp {{ display:flex; flex-direction:column; gap:6px; }}
.cp-row {{ display:grid; grid-template-columns:minmax(90px,1fr) auto minmax(90px,1fr) 90px 30px; gap:10px;
  align-items:center; font-size:13px; padding:6px 0; border-bottom:1px solid var(--line); }}
.cp-row:last-child {{ border-bottom:0; }}
.cp-arrow {{ font-size:11px; color:var(--muted); text-transform:uppercase; letter-spacing:.05em; }}
.cp-b {{ color:var(--fail); }}
.cp-row .bar {{ width:100%; }}
.cp-n {{ text-align:right; color:var(--muted); }}

.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(150px,1fr)); gap:12px; }}
.ex {{ margin:0; border:1px solid var(--line); border-radius:8px; overflow:hidden; background:var(--surface); }}
.ex img {{ width:100%; aspect-ratio:1/1; object-fit:cover; display:block; }}
.ex figcaption {{ padding:8px 9px 9px; }}
.ex-head {{ display:flex; justify-content:space-between; align-items:baseline; gap:6px; }}
.ex-true {{ font-family:"IBM Plex Mono",monospace; font-size:12px; font-weight:500; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}
.ex-status {{ font-size:10px; font-weight:600; text-transform:uppercase; letter-spacing:.04em; padding:1px 5px; border-radius:3px; flex:none; }}
.ex-status.pass {{ color:var(--pass); background:color-mix(in srgb, var(--pass) 14%, transparent); }}
.ex-status.warn {{ color:var(--warn); background:color-mix(in srgb, var(--warn) 14%, transparent); }}
.ex-status.fail {{ color:var(--fail); background:color-mix(in srgb, var(--fail) 14%, transparent); }}
.ex-chips {{ display:flex; flex-wrap:wrap; gap:3px; margin-top:6px; }}
.chip {{ font-size:10.5px; padding:1px 5px; border:1px solid var(--line); border-radius:3px; color:var(--muted); }}
.chip.is-true {{ color:var(--accent); border-color:var(--accent); }}

.empty {{ color:var(--muted); font-style:italic; }}
.method dt {{ font-weight:600; margin-top:12px; font-size:13px; }}
.method dd {{ margin:2px 0 0; color:var(--muted); font-size:13px; max-width:66ch; }}
.defs {{ margin:14px 0 0; display:grid; grid-template-columns:auto 1fr; gap:6px 16px; max-width:70ch; }}
.defs dt {{ font-weight:600; }}
.defs dd {{ margin:0; color:var(--muted); }}
@media (max-width:520px) {{ .defs {{ grid-template-columns:1fr; gap:2px; }} .defs dd {{ margin-bottom:8px; }} }}
.caveat {{ border-left:3px solid var(--warn); padding:4px 0 4px 14px; margin:8px 0; color:var(--ink); font-size:13px; max-width:64ch; }}
footer {{ margin-top:56px; padding-top:16px; border-top:1px solid var(--line); color:var(--muted); font-size:12px; }}
@media (max-width:640px) {{
  .metrics {{ grid-template-columns:repeat(2,1fr); }}
  .worked {{ grid-template-columns:1fr; }}
}}
</style>
</head>
<body>
<div class="wrap">
  <h1>{title}</h1>
  <p class="sub mono"><b>{model}</b> / {pretrained} &nbsp;&middot;&nbsp; top-k <b>{top_k}</b> &nbsp;&middot;&nbsp; min-sim <b>{min_sim}</b> &nbsp;&middot;&nbsp; prompts <b>{prompt_strategy}</b><br>
  {n_cat} categories &nbsp;&middot;&nbsp; {n_img} images &nbsp;&middot;&nbsp; {n_decoy} decoys &nbsp;&middot;&nbsp; {run_date}</p>

  <div class="metrics">{metric_html}</div>

  <h2>Reading this report</h2>
  <p>A user picks one <b>anchor</b> object per profile. To unlock, they point the camera at it; the on-device
  MobileCLIP encoder embeds the frame and ranks all category prompts by cosine similarity. The unlock fires if
  the anchor is anywhere in the <b>top {top_k}</b> &mdash; there is no minimum-score gate, by design.</p>
  <dl class="defs">
    <dt>Recall @k</dt><dd>Of all the frames where the anchor really was in view, the share where the model put it
      in the top {top_k}. High recall &rarr; the legit user gets in. <span class="mono">TP / (TP + FN)</span>.</dd>
    <dt>Recall @1</dt><dd>The stricter version: the anchor was the single best match, not just somewhere in the
      top {top_k}.</dd>
    <dt>Precision @1</dt><dd>Of all the frames where the model's <i>single best</i> guess was a given anchor,
      the share that really were that object. <span class="mono">TP / (TP + FP)</span>, at rank 1.</dd>
    <dt>Steal rate</dt><dd>The false-unlock risk stated directly: for anchor X, the share of <i>non-X</i> images
      that still carry X into the top {top_k} &mdash; a wrong object unlocking the profile. This, not
      precision, is the number that matters for a top-{top_k} unlock with no threshold.</dd>
    <dt>Decoy</dt><dd>A handheld or off-list object (mug, bottle, phone) that matches no category and should
      never unlock anything.</dd>
  </dl>

  <h2>Worked examples</h2>
  <p class="sub">Pick a category to see a correct read and, where there is one, a real miss &mdash; with the full top-5 similarity ranking.</p>
  <div class="tabs" role="tablist" aria-label="Worked example categories">{tabs_html}</div>
  <div class="panels">{panels_html}</div>

  <h2>Per-category performance</h2>
  <div class="tbl-scroll">
  <table id="cat">
    <thead><tr>
      <th data-k="id">category</th>
      <th data-k="num">n</th>
      <th data-k="num">recall @k</th>
      <th data-k="num">recall @1</th>
      <th data-k="num">precision @1</th>
      <th data-k="num">steal rate</th>
      <th data-k="txt">top confusers</th>
    </tr></thead>
    <tbody>{table_html}</tbody>
  </table>
  </div>

  <h2>Where it confuses things</h2>
  <p class="sub">Most frequent wrong top-1 predictions: an image of the first object was read as the second.</p>
  <div class="cp">{conf_html}</div>

  <h2>Example predictions</h2>
  <div class="grid">{grid_html}</div>

  <h2>Method &amp; caveats</h2>
  <dl class="method">
    <dt>Test images</dt><dd>Openverse image search per category (Creative Commons / public-domain), licenses recorded per file in <span class="mono">images_manifest.jsonl</span>.</dd>
    <dt>Candidate filtering</dt><dd>Each category over-fetched, then ranked by an independent CLIP model (ViT-B-16 / laion2b) against the category vs. a background prompt set; only the top matches kept.</dd>
    <dt>Steal rate</dt><dd>For anchor X: share of images whose true category is not X that still put X in the top {top_k}.</dd>
  </dl>
  <div class="caveat">The eval set is CLIP-filtered, so it skews toward clear, unambiguous photos &mdash; real-world recall runs a few points lower.</div>
  <div class="caveat">{n_cat} of 770 shipped categories are tested here (the common household / office / garage / vehicle set). The long tail is unmeasured.</div>
  <div class="caveat">top-k {top_k} with no score threshold maximizes recall at the cost of steal rate; adjacent objects (oven / microwave, sofa / loveseat) trade top-k slots freely.</div>

  <footer>Generated from <span class="mono">clip_eval/state/last_run_detail.json</span> by <span class="mono">build_report.py</span>.</footer>
</div>
<script>
(function () {{
  var tabs = Array.prototype.slice.call(document.querySelectorAll('.tab'));
  function select(tab) {{
    tabs.forEach(function (t) {{
      var on = t === tab;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      t.tabIndex = on ? 0 : -1;
      var panel = document.getElementById(t.dataset.panel);
      if (panel) panel.hidden = !on;
    }});
  }}
  tabs.forEach(function (tab, i) {{
    tab.addEventListener('click', function () {{ select(tab); }});
    tab.addEventListener('keydown', function (e) {{
      var d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!d) return;
      e.preventDefault();
      var next = tabs[(i + d + tabs.length) % tabs.length];
      select(next); next.focus();
    }});
  }});
}})();
(function () {{
  var table = document.getElementById('cat');
  if (!table) return;
  var tbody = table.tBodies[0];
  table.querySelectorAll('th').forEach(function (th, idx) {{
    th.addEventListener('click', function () {{
      var kind = th.dataset.k;
      var cur = th.getAttribute('aria-sort');
      var dir = cur === 'ascending' ? -1 : 1;
      table.querySelectorAll('th').forEach(function (o) {{ o.removeAttribute('aria-sort'); }});
      th.setAttribute('aria-sort', dir === 1 ? 'ascending' : 'descending');
      var rows = Array.prototype.slice.call(tbody.rows);
      rows.sort(function (a, b) {{
        var av = a.cells[idx], bv = b.cells[idx];
        if (kind === 'num') {{
          return dir * ((+av.dataset.v || +av.textContent) - (+bv.dataset.v || +bv.textContent));
        }}
        return dir * av.textContent.trim().localeCompare(bv.textContent.trim());
      }});
      rows.forEach(function (r) {{ tbody.appendChild(r); }});
    }});
  }});
}})();
</script>
</body>
</html>
"""

TEMPLATE = TEMPLATE.replace("{ew}", str(EXAMPLE_W))

if __name__ == "__main__":
    main()
