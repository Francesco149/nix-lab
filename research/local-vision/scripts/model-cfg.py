#!/usr/bin/env python3
"""Emit shell `export` lines for one model entry from models.yaml."""
import sys, yaml
sys.path.insert(0, __import__("os").path.dirname(__file__))
cfg = yaml.safe_load(open(__import__("os").path.join(__import__("os").path.dirname(__file__), "..", "models.yaml")))
mid = sys.argv[1]
for m in cfg["models"]:
    if m["id"] == mid:
        print(f'GGUF="{m["gguf"]}"')
        print(f'MMPROJ="{m["mmproj"]}"')
        print(f'FAMILY="{m["family"]}"')
        print(f'LABEL="{m["label"]}"')
        sys.exit(0)
print(f"unknown model {mid}", file=sys.stderr); sys.exit(1)
