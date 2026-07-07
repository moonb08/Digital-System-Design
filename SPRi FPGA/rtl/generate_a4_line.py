#!/usr/bin/env python3
"""
Generate an A4-sized test image: white paper with a pen line, as a physical
test target for the SPR pipeline (print it, photograph it, run run_fpga_pmin).

Defaults reproduce the original: 150 DPI A4 (1240x1754), 5 mm vertical
near-black line at the horizontal center. Everything is now a knob, and the
script prints the p_min the RTL should report for a straight-on photo.
"""
import argparse

from PIL import Image, ImageDraw, ImageFilter

MM_PER_IN = 25.4
A4_MM = (210, 297)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dpi", type=int, default=150)
    ap.add_argument("--pen-mm", type=float, default=5.0, help="line width, mm")
    ap.add_argument("--orient", choices=["v", "h"], default="v",
                    help="v: vertical line (dip along x), h: horizontal (dip along y)")
    ap.add_argument("--pos", type=float, default=0.5,
                    help="line center as a fraction of the perpendicular axis (0..1)")
    ap.add_argument("--ink", type=int, default=10, help="line gray level 0..255")
    ap.add_argument("--blur", type=float, default=0.0,
                    help="Gaussian blur radius in px (softens edges like a real photo)")
    ap.add_argument("--out", default="a4_pen_line.png")
    args = ap.parse_args()

    w_px = round(A4_MM[0] / MM_PER_IN * args.dpi)   # 1240 at 150 DPI
    h_px = round(A4_MM[1] / MM_PER_IN * args.dpi)   # 1754 at 150 DPI
    pen_px = max(1, round(args.pen_mm / MM_PER_IN * args.dpi))

    img = Image.new("L", (w_px, h_px), 255)          # single channel: it's B/W
    draw = ImageDraw.Draw(img)
    if args.orient == "v":
        c = round(args.pos * (w_px - 1))
        box = [c - pen_px // 2, 0, c - pen_px // 2 + pen_px - 1, h_px - 1]
    else:
        c = round(args.pos * (h_px - 1))
        box = [0, c - pen_px // 2, w_px - 1, c - pen_px // 2 + pen_px - 1]
    draw.rectangle(box, fill=args.ink)
    if args.blur > 0:
        img = img.filter(ImageFilter.GaussianBlur(args.blur))
    img.save(args.out, dpi=(args.dpi, args.dpi))

    # What the RTL should say for a straight-on, full-frame photo of this sheet
    span = w_px if args.orient == "v" else h_px
    p_expect = round(c / (span - 1) * 1279)
    axis = "x" if args.orient == "v" else "y"
    print(f"Saved: {args.out}  ({w_px}x{h_px} px, {args.dpi} DPI)")
    print(f"Pen line: {pen_px} px ({args.pen_mm} mm) wide, "
          f"{'vertical' if args.orient == 'v' else 'horizontal'}, "
          f"centered at {c}")
    print(f"Expected: run_fpga_pmin --axis {axis} -> p_min ~ {p_expect} "
          f"(1280-sample line)")


if __name__ == "__main__":
    main()
