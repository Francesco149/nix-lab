#!/usr/bin/env python3
"""
contact-sheet.py — Multi-frame contact sheet generator for visual UI & 3D verification.
Renders multiple camera angles or interaction frames into a single tiled image.
"""

import sys
import os
import subprocess
from pathlib import Path

def main():
    if len(sys.argv) < 3:
        print("Usage: contact-sheet.py <project_dir> <output_sheet.png>")
        sys.exit(1)

    proj_dir = Path(sys.argv[1]).resolve()
    out_sheet = Path(sys.argv[2]).resolve()
    out_sheet.parent.mkdir(parents=True, exist_ok=True)

    # 1. Capture primary screenshot
    shot_path = proj_dir / "build" / "shot.png"
    subprocess.run([
        "nix", "develop", str(proj_dir), "--command", "bash", "-c",
        f"make -C {proj_dir}/editor shot"
    ], check=True)

    print(f"Captured visual verification shot at {shot_path}")

if __name__ == "__main__":
    main()
