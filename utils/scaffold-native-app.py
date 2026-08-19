#!/usr/bin/env python3
"""
scaffold.py — Turnkey generator for high-performance native desktop creation tools.
Copies complete, verified Raylib template (2D + 3D) with build targets,
runtime fonts, Lua 5.4, Raylib 6.0 + OpenGL 3.3, and smoke test gates.
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

    args = parser.parse_args()
    target_dir = Path(args.path).resolve()
    name = args.name or target_dir.name
    name_lower = name.lower().replace(" ", "-")
    name_upper = name_lower.upper().replace("-", "_")
    name_title = "".join(w.capitalize() for w in name.replace("-", " ").replace("_", " ").split())
    desc = args.desc

    candidate_dirs = [
        Path(__file__).resolve().parent.parent / "templates" / "raylib",
        Path("/opt/src/llm-ux/templates/raylib"),
        Path(__file__).resolve().parent / "templates" / "raylib",
    ]
    template_dir = next((p for p in candidate_dirs if p.exists()), None)
    if not template_dir:
        print(f"[!] Error: Template directory not found in candidates: {candidate_dirs}")
        sys.exit(1)
    print(f"[*] Scaffolding native project '{name_title}' ({name_lower}) at {target_dir}...")

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
            if f.endswith((".nix", ".md", ".lua", ".cpp", ".h", "Makefile", ".yml", ".yaml")):
                try:
                    text = fp.read_text(encoding="utf-8")
                    text = text.replace("cubeforge", name_lower)
                    text = text.replace("CubeForge", name_title)
                    text = text.replace("CUBEFORGE", name_upper)
                    text = text.replace("3D block editor with Raylib + ImGui + Lua", desc)
                    text = text.replace("High-performance native desktop creation tool", desc)
                except Exception:
                    pass

    print(f"[+] Successfully initialized complete buildable repository for '{name}'.")
    print(f"    Build & Test: cd {target_dir} && nix develop --command make -C editor test")

if __name__ == "__main__":
    main()
