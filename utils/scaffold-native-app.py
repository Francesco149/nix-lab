#!/usr/bin/env python3
"""
scaffold.py — Turnkey generator for high-performance native desktop creation tools.
Copies complete, verified templates (2d-canvas or 3d-viewport) with build targets,
embedded fonts, Lua 5.4, D3D11/SDL3, and smoke test gates.
"""

import os
import sys
import shutil
import argparse
from pathlib import Path

LLM_UX_ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser(description="Scaffold high-performance native desktop tool")
    parser.add_argument("path", help="Target project directory")
    parser.add_argument("--name", help="Project name (default: directory name)")
    parser.add_argument("--desc", default="High-performance native desktop creation tool", help="Project description")
    parser.add_argument("--type", choices=["2d", "3d"], default="2d", help="Application type (2d canvas or 3d viewport)")

    args = parser.parse_args()
    target_dir = Path(args.path).resolve()
    name = args.name or target_dir.name
    desc = args.desc
    app_type = args.type

    template_dir = LLM_UX_ROOT / "templates" / ("2d-canvas" if app_type == "2d" else "3d-viewport")
    if not template_dir.exists():
        print(f"[!] Error: Template directory {template_dir} not found.")
        sys.exit(1)

    print(f"[*] Scaffolding native '{app_type}' project '{name}' at {target_dir}...")

    # Copy template cleanly
    if target_dir.exists():
        shutil.rmtree(target_dir)
    shutil.copytree(template_dir, target_dir)

    # Clean intermediate build files if any
    for cleanup in ["build", "dist", ".git"]:
        p = target_dir / cleanup
        if p.exists():
            shutil.rmtree(p)

    # Token substitutions
    for root, _, files in os.walk(target_dir):
        for f in files:
            fp = Path(root) / f
            if f.endswith((".nix", ".md", ".lua", ".cpp", ".h", "Makefile")):
                try:
                    text = fp.read_text(encoding="utf-8")
                    text = text.replace("texturewrangler", name)
                    text = text.replace("lowpoly-painter", name)
                    text = text.replace("godot-blockout", name)
                    text = text.replace("Non-destructive retro texture editor", desc)
                    text = text.replace("Specialized low-poly 3D modeler and handpainted texture painter with auto UVs and procedural bake effects", desc)
                    text = text.replace("CSG 3D level blockout editor with Godot-grade viewport controls and 1-click .tscn/.glb export", desc)
                    fp.write_text(text, encoding="utf-8")
                except Exception:
                    pass

    print(f"[+] Successfully initialized complete buildable repository for '{name}'.")
    print(f"    Build & Test: cd {target_dir} && nix develop --command make -C editor test")

if __name__ == "__main__":
    main()
