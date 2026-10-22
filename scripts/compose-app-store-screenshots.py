#!/usr/bin/env python3
"""
Compose the App Store iPhone slides as designed in Figma (recipe-scaler-files, frames
"en/1. Recipes" … "ru/6. iOS"): caption over a raw capture in the iPhone Air frame, white or black
background. Slides, texts and captures: store/screenshots/compose/slides.json; layout: style.css.

Raw frames come from scripts/capture-app-store-screenshots.sh. Rendering uses headless Google Chrome
(override with $CHROME).

Usage:
  python3 scripts/compose-app-store-screenshots.py
  python3 scripts/compose-app-store-screenshots.py --locale en --slide 2-cooking
  # raw frames from another checkout (PNGs are not in git)
  python3 scripts/compose-app-store-screenshots.py --raw-root ../recipe-scaler-native/store/screenshots

Output: store/screenshots/final/iphone-6.5/{ru,en}/<slide-id>.png, 1284×2778 (the Figma 3× export).
"""

from __future__ import annotations

import argparse
import html
import json
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
COMPOSE_DIR = ROOT / "store" / "screenshots" / "compose"
DEFAULT_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
RENDER_TIMEOUT_S = 45
RENDER_ATTEMPTS = 3
# style.css takes the caption font from the system (local()); Chrome would silently fall back without it.
FONT_FILE = "MartianGrotesk-StdBd.otf"
FONT_DIRS = (Path.home() / "Library" / "Fonts", Path("/Library/Fonts"))
# Not in git either (Apple's bezel licence): 1380×2880 with the screen cut out at (60, 72).
BEZEL = COMPOSE_DIR / "iphone-air.png"


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def png_info(path: Path) -> tuple[int, int, bool]:
    """Width, height and whether the IHDR color type carries alpha (4 gray+alpha, 6 RGBA)."""
    with path.open("rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        die(f"not a PNG: {path}")
    width, height = struct.unpack(">II", head[16:24])
    return width, height, head[25] in (4, 6)


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def capture_path(raw_root: Path, screens: str, capture: str) -> Path:
    path = raw_root / "iphone-6.9" / screens / f"{capture}.png"
    if not path.is_file():
        die(f"missing raw frame {path}; run scripts/capture-app-store-screenshots.sh")
    return path


def slide_html(slide: dict[str, Any], locale: str, raw_root: Path, screens: str) -> str:
    body = [f'<p class="caption">{esc(slide["title"][locale])}</p>']
    if slide.get("layout") == "ios":
        for key, capture in slide["captures"].items():
            src = capture_path(raw_root, screens, capture).as_uri()
            body.append(f'<div class="tile {key}"><img src="{src}"></div>')
        for key, label in slide["labels"].items():
            body.append(f'<p class="label {key}">{esc(label[locale])}</p>')
    else:
        src = capture_path(raw_root, screens, slide["capture"]).as_uri()
        bezel = BEZEL.as_uri()
        body.append(f'<img class="screen" src="{src}"><img class="bezel" src="{bezel}">')
    css = (COMPOSE_DIR / "style.css").as_uri()
    return (
        "<!doctype html><html><head><meta charset=\"utf-8\">"
        f'<link rel="stylesheet" href="{css}"></head>'
        f'<body class="{esc(slide["theme"])}">{"".join(body)}</body></html>'
    )


def render(chrome: str, page: Path, out: Path, canvas: dict[str, int]) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        chrome,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--allow-file-access-from-files",
        f"--force-device-scale-factor={canvas['scale']}",
        f"--window-size={canvas['width']},{canvas['height']}",
        "--virtual-time-budget=5000",
        f"--screenshot={out}",
        page.as_uri(),
    ]
    out.unlink(missing_ok=True)
    # Headless Chrome now and then never exits after writing the screenshot; kill it and try again.
    for attempt in range(1, RENDER_ATTEMPTS + 1):
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=RENDER_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            if attempt == RENDER_ATTEMPTS:
                die(f"chrome hung on {page.name} {RENDER_ATTEMPTS} times")
            out.unlink(missing_ok=True)
            continue
        if proc.returncode != 0 or not out.is_file():
            die(f"chrome failed for {page.name}: {proc.stderr.strip()[-800:]}")
        break
    width, height = canvas["width"] * canvas["scale"], canvas["height"] * canvas["scale"]
    got_width, got_height, has_alpha = png_info(out)
    if (got_width, got_height) != (width, height):
        die(f"{out} is {got_width}×{got_height}, expected {width}×{height}")
    # App Store Connect rejects screenshots with an alpha channel.
    if has_alpha:
        die(f"{out} has an alpha channel")


def main() -> None:
    parser = argparse.ArgumentParser(description="Compose App Store iPhone slides from raw captures")
    parser.add_argument("--raw-root", type=Path, default=ROOT / "store" / "screenshots")
    parser.add_argument("--out", type=Path, default=ROOT / "store" / "screenshots" / "final")
    parser.add_argument("--locale", action="append", choices=("ru", "en"), help="repeatable; default ru and en")
    parser.add_argument("--slide", action="append", help="slide id from slides.json (repeatable)")
    parser.add_argument("--keep-html", action="store_true", help="leave the generated HTML next to the PNG")
    args = parser.parse_args()

    config = json.loads((COMPOSE_DIR / "slides.json").read_text(encoding="utf-8"))
    canvas = config["canvas"]
    slides = config["slides"]
    if args.slide:
        unknown = set(args.slide) - {s["id"] for s in slides}
        if unknown:
            die(f"unknown slide id(s): {', '.join(sorted(unknown))}")
        slides = [s for s in slides if s["id"] in args.slide]
    chrome = os.environ.get("CHROME", DEFAULT_CHROME)
    if not Path(chrome).is_file():
        die(f"Chrome not found at {chrome}; set $CHROME")
    if not any((d / FONT_FILE).is_file() for d in FONT_DIRS):
        die(f"{FONT_FILE} (Martian Grotesk Std Bold) is not installed in {' or '.join(map(str, FONT_DIRS))}")
    if not BEZEL.is_file():
        die(f"missing {BEZEL}: iPhone Air, Cloud White, portrait PNG from Apple Design Resources (product bezels)")
    raw_root = args.raw_root.resolve()

    with tempfile.TemporaryDirectory(prefix="store-compose-") as tmp:
        for locale in args.locale or ["ru", "en"]:
            # Which capture locale the slides of this store locale show (slides.json "screens").
            screens = config["screens"][locale]
            for slide in slides:
                out = args.out.resolve() / "iphone-6.5" / locale / f"{slide['id']}.png"
                page_dir = out.parent if args.keep_html else Path(tmp)
                page_dir.mkdir(parents=True, exist_ok=True)
                page = page_dir / f"{locale}-{slide['id']}.html"
                page.write_text(slide_html(slide, locale, raw_root, screens), encoding="utf-8")
                render(chrome, page, out, canvas)
                print(out.relative_to(ROOT) if out.is_relative_to(ROOT) else out)


if __name__ == "__main__":
    main()
