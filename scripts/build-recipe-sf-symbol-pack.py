#!/usr/bin/env python3
"""Build custom SF Symbol sets from web SVG icons (recipe-scaler-web).

Output: RecipeScalerNative/Assets.xcassets/rs.<name>.symbolset/
SVG follows SF Symbols 3 layout (Guides + Regular-S/M/L) for Xcode Symbol Image Set.

See: https://developer.apple.com/documentation/uikit/creating-custom-symbol-images-for-your-app

Web Lucide icons use strokes; SF Symbol assets need filled paths. Run `npm install` in
`scripts/` once, then this script outlines strokes via `svg-outline-stroke` before export.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = Path(__file__).resolve().parent
OUTLINE_NODE = SCRIPTS / "outline-svg.cjs"
SRC = ROOT.parent / "recipe-scaler-web" / "recipe-scaler" / "src" / "assets" / "icons"
OUT = ROOT / "RecipeScalerNative" / "Assets.xcassets"
SOURCE_VIEWBOX = 24

# Capline / baseline (y) and left-right margin (x) per scale in 100×100 canvas.
SCALES = {
    "S": {"cap": 28.5, "base": 71.5, "margin_left": 12.0, "margin_right": 88.0},
    "M": {"cap": 25.0, "base": 75.0, "margin_left": 10.0, "margin_right": 90.0},
    "L": {"cap": 22.0, "base": 78.0, "margin_left": 8.0, "margin_right": 92.0},
}


def pascal_to_camel(name: str) -> str:
    return name[0].lower() + name[1:] if name else name


def outline_strokes(svg: str) -> str:
    if not OUTLINE_NODE.is_file():
        raise FileNotFoundError(f"Missing {OUTLINE_NODE}")
    node_modules = SCRIPTS / "node_modules" / "svg-outline-stroke"
    if not node_modules.is_dir():
        raise FileNotFoundError(
            f"Run `npm install` in {SCRIPTS} before building symbol sets (need svg-outline-stroke)."
        )
    result = subprocess.run(
        ["node", str(OUTLINE_NODE)],
        input=svg,
        capture_output=True,
        text=True,
        cwd=SCRIPTS,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "outline-svg failed")
    return result.stdout


def extract_svg_body(svg: str) -> str:
    svg = svg.strip()
    svg = re.sub(r"<\?xml[^>]*\?>", "", svg, flags=re.I)
    svg = re.sub(r"<!DOCTYPE[^>]*>", "", svg, flags=re.I)
    svg = re.sub(r"<svg[^>]*>", "", svg, count=1, flags=re.I)
    svg = re.sub(r"</svg>\s*$", "", svg, flags=re.I)
    return svg.strip()


def normalize_paths(body: str) -> str:
    body = re.sub(r'fill="currentColor"', 'fill="#000000"', body, flags=re.I)
    body = re.sub(r'fill="black"', 'fill="#000000"', body, flags=re.I)
    # Outlined glyphs must be fill-only (no stroke) for SF Symbol rendering.
    body = re.sub(r'\sstroke="[^"]*"', "", body, flags=re.I)
    body = re.sub(r'\sstroke-width="[^"]*"', "", body, flags=re.I)
    body = re.sub(r'\sstroke-linecap="[^"]*"', "", body, flags=re.I)
    body = re.sub(r'\sstroke-linejoin="[^"]*"', "", body, flags=re.I)
    if 'fill="' not in body:
        body = re.sub(r"<path ", '<path fill="#000000" ', body, flags=re.I)
    lines = [line for line in body.splitlines() if line.strip()]
    return "\n".join(f"          {line}" for line in lines)


def guides_xml() -> str:
    lines: list[str] = ['  <g id="Guides">']
    for key, m in SCALES.items():
        lines.append(
            f'    <line id="Baseline-{key}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" '
            f'x1="0" x2="100" y1="{m["base"]}" y2="{m["base"]}"/>'
        )
        lines.append(
            f'    <line id="Capline-{key}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" '
            f'x1="0" x2="100" y1="{m["cap"]}" y2="{m["cap"]}"/>'
        )
        lines.append(
            f'    <line id="left-margin-Regular-{key}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" '
            f'x1="{m["margin_left"]}" x2="{m["margin_left"]}" y1="18" y2="82"/>'
        )
        lines.append(
            f'    <line id="right-margin-Regular-{key}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" '
            f'x1="{m["margin_right"]}" x2="{m["margin_right"]}" y1="18" y2="82"/>'
        )
    lines.append("  </g>")
    return "\n".join(lines)


def symbol_glyph(body: str, scale_key: str) -> str:
    m = SCALES[scale_key]
    glyph_scale = (m["base"] - m["cap"]) / SOURCE_VIEWBOX
    tx = (100 - SOURCE_VIEWBOX * glyph_scale) / 2
    inner = normalize_paths(body)
    return (
        f'    <g id="Regular-{scale_key}">\n'
        f'      <g transform="translate({tx:g},{m["cap"]:g}) scale({glyph_scale:g})">\n'
        f"{inner}\n"
        f"      </g>\n"
        f"    </g>"
    )


def wrap_as_symbol_svg(body: str) -> str:
    glyphs = "\n".join(symbol_glyph(body, key) for key in ("S", "M", "L"))
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="none">\n'
        f"{guides_xml()}\n"
        "  <g id=\"Symbols\">\n"
        f"{glyphs}\n"
        "  </g>\n"
        "</svg>\n"
    )


def main() -> int:
    if not SRC.is_dir():
        print(f"Missing icon source: {SRC}", file=sys.stderr)
        return 1

    contents_template = {
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "template",
        },
        "symbols": [{"idiom": "universal"}],
    }

    manifest: list[dict[str, str]] = []
    for path in sorted(SRC.glob("*.svg")):
        asset = f"rs.{pascal_to_camel(path.stem)}"
        symbol_dir = OUT / f"{asset}.symbolset"
        symbol_dir.mkdir(parents=True, exist_ok=True)
        svg_name = f"{asset}.svg"
        raw = path.read_text(encoding="utf-8")
        body = extract_svg_body(outline_strokes(raw))
        (symbol_dir / svg_name).write_text(wrap_as_symbol_svg(body), encoding="utf-8")
        contents = json.loads(json.dumps(contents_template))
        contents["symbols"][0]["filename"] = svg_name
        (symbol_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
        manifest.append({"web": path.stem, "asset": asset})

    (OUT / "RecipeSymbols.manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {len(manifest)} symbol sets to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())