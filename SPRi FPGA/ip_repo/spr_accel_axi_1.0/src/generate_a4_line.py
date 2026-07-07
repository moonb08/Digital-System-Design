#!/usr/bin/env python3
"""
Generate an A4-sized test image: white paper with a 5mm vertical pen line.
Output at 150 DPI → 1240 × 1754 pixels.
"""
from PIL import Image, ImageDraw

# A4 at 150 DPI
DPI = 150
W_MM, H_MM = 210, 297
W_PX = int(W_MM / 25.4 * DPI)   # 1240
H_PX = int(H_MM / 25.4 * DPI)   # 1754

# 5mm pen line width in pixels
PEN_MM = 5
PEN_PX = int(PEN_MM / 25.4 * DPI)  # ~30 pixels

img = Image.new("RGB", (W_PX, H_PX), color=(255, 255, 255))  # white paper
draw = ImageDraw.Draw(img)

# Draw a vertical line in the center
cx = W_PX // 2
x0 = cx - PEN_PX // 2
x1 = cx + PEN_PX // 2
draw.rectangle([x0, 0, x1, H_PX - 1], fill=(10, 10, 10))  # near-black pen

out_path = "a4_pen_line.png"
img.save(out_path, dpi=(DPI, DPI))
print(f"Saved: {out_path}  ({W_PX}×{H_PX} px, {DPI} DPI)")
print(f"Pen line: {PEN_PX} px wide, centered at column {cx}")
