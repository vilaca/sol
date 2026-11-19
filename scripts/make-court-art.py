#!/usr/bin/env python3
"""Crops the court figures (J, Q, K) out of the CC0 English-pattern card SVGs in Art/court/
and renders PNGs into the app's asset catalog. Needs rsvg-convert (brew install librsvg).

The crop keeps the upper half of each double-ended figure (crown, face, big pip, torso) and drops
the original corner index, which is unreadable at phone card sizes; the app draws its own index.
"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Art" / "court"
CATALOG = ROOT / "App" / "Assets.xcassets"
# Crop box in the source cards' 360 x 540 coordinate space.
CROP = (51, 31, 258, 270)
WIDTH_PX = 480

RANKS = {"jack": "J", "queen": "Q", "king": "K"}
SUITS = {"spades": "S", "hearts": "H", "diamonds": "D", "clubs": "C"}


def cropped_svg(text: str) -> str:
    x, y, w, h = CROP
    def fix(tag: re.Match) -> str:
        t = re.sub(r'\s(width|height|viewBox)="[^"]*"', "", tag.group(0))
        return t[:-1] + f' width="{w}" height="{h}" viewBox="{x} {y} {w} {h}">'
    return re.sub(r"<svg\b[^>]*>", fix, text, count=1, flags=re.S)


def main() -> None:
    out_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    for rank, r in RANKS.items():
        for suit, s in SUITS.items():
            source = SOURCE / f"English_pattern_{rank}_of_{suit}.svg"
            name = f"court-{r}{s}"
            with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as tmp:
                tmp.write(cropped_svg(source.read_text()))
            if out_dir:
                png = out_dir / f"{name}.png"
            else:
                imageset = CATALOG / f"{name}.imageset"
                imageset.mkdir(parents=True, exist_ok=True)
                png = imageset / f"{name}.png"
                (imageset / "Contents.json").write_text(json.dumps({
                    "images": [{"filename": png.name, "idiom": "universal"}],
                    "info": {"author": "xcode", "version": 1},
                }, indent=2) + "\n")
            subprocess.run(["rsvg-convert", "-w", str(WIDTH_PX), tmp.name, "-o", str(png)], check=True)
            pathlib.Path(tmp.name).unlink()
            print(png.relative_to(out_dir) if out_dir else png.relative_to(ROOT))


if __name__ == "__main__":
    main()
