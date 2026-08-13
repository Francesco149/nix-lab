#!/usr/bin/env python3
"""Render results/run-<name>/report.html from results.json (run ON lame).

Standalone page: embeds images as data URLs (videos as <video> pointing at a
copied asset). Column per model, row per case, cell = output text + timing.
"""
import base64, json, mimetypes, os, shutil, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else max(
        (os.path.join(ROOT, "results", d) for d in os.listdir(os.path.join(ROOT, "results"))),
        key=os.path.getmtime,
    )
    results = json.load(open(os.path.join(outdir, "results.json")))
    cases = yaml_load(os.path.join(ROOT, "testcases.yaml"))["cases"]
    models = yaml_load(os.path.join(ROOT, "models.yaml"))["models"]
    model_ids = list(dict.fromkeys(r["model"] for r in results))
    case_ids = [c["id"] for c in cases if any(r["case"] == c["id"] for r in results)]

    asset_dir = os.path.join(outdir, "assets")
    os.makedirs(asset_dir, exist_ok=True)
    embeds = {}
    for c in cases:
        if c["id"] not in case_ids:
            continue
        src = os.path.join(ROOT, c["path"])
        ext = os.path.splitext(src)[1]
        dst = os.path.join(asset_dir, c["id"] + ext)
        shutil.copy(src, dst)
        if c["kind"] == "image":
            with open(dst, "rb") as f:
                embeds[c["id"]] = ("data:" + (mimetypes.guess_type(dst)[0] or "image/png") + ";base64,"
                                   + base64.b64encode(f.read()).decode())
        else:
            embeds[c["id"]] = f"assets/{c['id']}{ext}"

    by = {(r["model"], r["case"]): r for r in results}
    esc = lambda s: (s or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    rows = []
    for cid in case_ids:
        c = next(c for c in cases if c["id"] == cid)
        if c["kind"] == "image":
            media = f'<img src="{embeds[cid]}" style="max-width:420px;border:1px solid #444">'
        else:
            media = f'<video src="{embeds[cid]}" controls style="max-width:420px;border:1px solid #444"></video>'
        cells = []
        for mid in model_ids:
            r = by.get((mid, cid))
            if r is None:
                cells.append("<td class=miss>—</td>"); continue
            if r.get("error"):
                cells.append(f'<td class=err><b>ERR</b> {esc(r["error"])}</td>'); continue
            meta = f'<div class=meta>{r["elapsed_s"]}s · {r.get("prompt_tokens")}pp · {r.get("completion_tokens")}tg</div>'
            cells.append(f'<td><pre class=out>{esc(r["output"])}</pre>{meta}</td>')
        rows.append(
            f'<tr><td class=casename>{esc(c["id"])}<br>{media}</td>{"".join(cells)}</tr>'
        )

    headers = "".join(f'<th>{esc(next(m["label"] for m in models if m["id"] == mid))}</th>' for mid in model_ids)
    html = f"""<!doctype html><html><head><meta charset=utf-8>
<title>Local vision eval — {os.path.basename(outdir)}</title>
<style>
 body{{background:#111;color:#ddd;font-family:system-ui,sans-serif;margin:0;padding:16px}}
 h1{{font-size:18px}} h2{{font-size:14px;color:#888}}
 table{{border-collapse:collapse;width:100%}}
 th,td{{border:1px solid #333;padding:8px;vertical-align:top;text-align:left}}
 th{{background:#1d1d1d;position:sticky;top:0;font-size:12px}}
 td.casename{{min-width:200px;font-weight:bold;font-size:12px;background:#171717}}
 pre.out{{white-space:pre-wrap;font-size:12px;max-height:340px;overflow:auto;margin:0}}
 .meta{{color:#777;font-size:11px;margin-top:4px}}
 td.err{{color:#f88}} td.miss{{color:#555;text-align:center}}
</style></head><body>
<h1>Local vision model eval — {os.path.basename(outdir)}</h1>
<h2>generated {time.strftime('%Y-%m-%d %H:%M')} · 7800XT Vulkan · temp 0.2 · llama.cpp 6e9007a</h2>
<table><tr><th>case</th>{headers}</tr>{''.join(rows)}</table>
</body></html>"""
    open(os.path.join(outdir, "report.html"), "w").write(html)
    print("report →", os.path.join(outdir, "report.html"))


def yaml_load(p):
    import yaml
    return yaml.safe_load(open(p))


if __name__ == "__main__":
    main()
