#!/usr/bin/env python3
"""Summarize a run: coverage, errors, latest-row view per model/case."""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
run = sys.argv[1] if len(sys.argv) > 1 else "full-20260813"
path = os.path.join(ROOT, "results", f"run-{run}", "results.json")
results = json.load(open(path))

latest = {}
for x in results:
    latest[(x["model"], x["case"])] = x

models = list(dict.fromkeys(r["model"] for r in results))
cases = list(dict.fromkeys(r["case"] for r in results))

print(f"run {run}: {len(results)} rows, {len(latest)} unique pairs, "
      f"{len([x for x in latest.values() if x.get('error')])} errors\n")
print(f"{'model':<24}{'':<2}{' '.join(c[:10].ljust(10) for c in cases)}")
for m in models:
    cells = []
    for c in cases:
        x = latest.get((m, c))
        if x is None:
            cells.append("-".ljust(10))
        elif x.get("error"):
            cells.append("ERR".ljust(10))
        else:
            cells.append(f"{x.get('elapsed_s','?'):>3}s".ljust(10))
    print(f"{m:<24}{' '.join(cells)}")

print("\nerrors:")
for (m, c), x in sorted(latest.items()):
    if x.get("error"):
        print(f"  {m} {c}: {x['error'][:80]}")
