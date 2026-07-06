#!/usr/bin/env python3
"""
frame_to_hex.py  --  Turn a camera frame (HAYEAR capture, or any image/video)
into $readmemh-loadable test vectors for the SPR RTL pipeline.

Pipeline facts this tool targets
--------------------------------
  * 1-D data path: IMAGE_WIDTH samples per line (default 1024; 1280 for S11661).
  * PIXEL_WIDTH = 12 bits  ->  values 0..4095  ->  3 hex nibbles per line.
  * bg_subtraction consumes BOTH ref_pixel and current_pixel every frame,
    computing dip_depth = max(ref - current, 0). So we emit two vectors.

What it does
------------
  1. Load an image, or one frame of a video.
  2. Pick a channel (grayscale luma by default; 'g' often best on a Bayer sensor).
  3. Collapse the 2-D frame to a 1-D profile along the chosen axis.
  4. Resample to exactly IMAGE_WIDTH samples if needed.
  5. Scale to 12-bit full scale (or --bits N).
  6. Write current.hex, ref.hex, a decimal/plot .txt for eyeballing, and a PNG.

The SPR dip is a DARK band (intensity drops at resonance). dip_depth is
therefore max(ref - current, 0): ref is the bright baseline, current has the dip.
"""

import argparse
import sys
import numpy as np
from PIL import Image, ImageOps

try:
    import cv2
    HAVE_CV2 = True
except ImportError:
    HAVE_CV2 = False


# ---------------------------------------------------------------- loading ----
VIDEO_EXT = {".mp4", ".avi", ".mov", ".mkv", ".webm", ".m4v"}


def load_frame(path, frame_idx=0):
    """Return an HxWx3 uint8 (or HxW) array. Handles image or video."""
    lower = path.lower()
    is_video = any(lower.endswith(e) for e in VIDEO_EXT)

    if is_video:
        if not HAVE_CV2:
            sys.exit("Video input needs OpenCV (cv2), which isn't installed.")
        cap = cv2.VideoCapture(path)
        if not cap.isOpened():
            sys.exit(f"Could not open video: {path}")
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ok, frame = cap.read()
        cap.release()
        if not ok:
            sys.exit(f"Could not read frame {frame_idx} from {path}")
        # cv2 is BGR; flip to RGB for consistency
        return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    img = Image.open(path)
    img = ImageOps.exif_transpose(img)   # respect phone portrait/landscape tag
    # Handle 16-bit TIFFs etc. without clobbering precision
    arr = np.asarray(img)
    if arr.ndim == 2:
        return arr
    if arr.shape[2] == 4:  # drop alpha
        arr = arr[:, :, :3]
    return arr


# ------------------------------------------------------------- channel ext ---
def to_channel(frame, channel):
    """Reduce HxWx3 (or HxW) to a single-channel HxW float array."""
    if frame.ndim == 2:
        return frame.astype(np.float64)

    r, g, b = frame[:, :, 0], frame[:, :, 1], frame[:, :, 2]
    if channel == "gray":
        # Rec. 601 luma
        return 0.299 * r + 0.587 * g + 0.114 * b
    if channel == "r":
        return r.astype(np.float64)
    if channel == "g":
        return g.astype(np.float64)
    if channel == "b":
        return b.astype(np.float64)
    sys.exit(f"Unknown channel: {channel}")


# ------------------------------------------------------------- reduction -----
def reduce_profile(chan, mode):
    """
    Collapse a 2-D channel image to a 1-D profile.

    Axis note (still open in your design):
      * The dip runs along X (varies with COLUMN index):  use rows->  (length = W)
      * The dip runs along Y (varies with ROW index):     use cols->  (length = H)

    modes:
      mean-rows / sum-rows : collapse vertical -> profile indexed by column (x)
      mean-cols / sum-cols : collapse horizontal -> profile indexed by row (y)
      line-row=N           : single horizontal scan line at row N  (length = W)
      line-col=N           : single vertical   scan line at col N  (length = H)
    """
    if mode == "mean-rows":
        return chan.mean(axis=0)
    if mode == "sum-rows":
        return chan.sum(axis=0)
    if mode == "mean-cols":
        return chan.mean(axis=1)
    if mode == "sum-cols":
        return chan.sum(axis=1)
    if mode.startswith("line-row"):
        n = int(mode.split("=")[1]) if "=" in mode else chan.shape[0] // 2
        return chan[n, :]
    if mode.startswith("line-col"):
        n = int(mode.split("=")[1]) if "=" in mode else chan.shape[1] // 2
        return chan[:, n]
    sys.exit(f"Unknown reduce mode: {mode}")


def resample(profile, width):
    """Resample a 1-D profile to exactly `width` samples via linear interp."""
    if len(profile) == width:
        return profile
    x_old = np.linspace(0.0, 1.0, num=len(profile))
    x_new = np.linspace(0.0, 1.0, num=width)
    return np.interp(x_new, x_old, profile)


def scale_to_bits(profile, bits, normalize):
    """Map a float profile to integer codes in [0, 2^bits - 1]."""
    full = (1 << bits) - 1
    if normalize:
        lo, hi = float(profile.min()), float(profile.max())
        span = (hi - lo) if hi > lo else 1.0
        codes = (profile - lo) / span * full
    else:
        # Assume an 8-bit source unless values exceed 255 (then use observed max)
        src_max = 255.0 if profile.max() <= 255.0 else float(profile.max())
        codes = profile / src_max * full
    return np.clip(np.rint(codes), 0, full).astype(np.int64)


# ---------------------------------------------------------- reference gen -----
def synth_reference(codes, method, bits):
    """
    Synthesize a background/baseline line so dip_depth = max(ref - current, 0)
    isolates the dark dip. Use only when you have no real background capture.

      flat : ref = constant at the profile max  (dip_depth = max - current)
      smooth: ref = heavily blurred current     (removes only the sharp dip)
    """
    full = (1 << bits) - 1
    if method == "flat":
        return np.full_like(codes, int(codes.max()))
    if method == "smooth":
        # wide moving-average baseline; kernel ~ 1/8 of the line
        k = max(9, len(codes) // 8) | 1  # force odd
        pad = k // 2
        padded = np.pad(codes.astype(np.float64), pad, mode="edge")
        kern = np.ones(k) / k
        base = np.convolve(padded, kern, mode="valid")
        return np.clip(np.rint(base), 0, full).astype(np.int64)
    sys.exit(f"Unknown --synth-ref method: {method}")


# ------------------------------------------------------------- writers -------
def write_hex(path, codes, bits, meta):
    nib = (bits + 3) // 4
    with open(path, "w") as f:
        for line in meta:
            f.write(f"// {line}\n")
        for v in codes:
            f.write(f"{v:0{nib}X}\n")


def write_report(path, cur, ref, bits):
    dip = np.maximum(ref.astype(np.int64) - cur.astype(np.int64), 0)
    argmin = int(np.argmin(cur))
    argmax_dip = int(np.argmax(dip))
    with open(path, "w") as f:
        f.write(f"# samples={len(cur)}  bits={bits}\n")
        f.write(f"# current: min={cur.min()} max={cur.max()} "
                f"argmin(dip pos)={argmin}\n")
        f.write(f"# dip_depth: max={dip.max()} at index {argmax_dip}\n")
        f.write("# idx  current  ref  dip_depth\n")
        for i, (c, r, d) in enumerate(zip(cur, ref, dip)):
            f.write(f"{i:5d}  {c:5d}  {r:5d}  {d:5d}\n")
    return argmin, argmax_dip, int(dip.max())


def save_plot(path, cur, ref):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return False
    fig, ax = plt.subplots(figsize=(10, 3.2), dpi=110)
    ax.plot(ref, lw=1.0, label="ref_pixel", color="#888")
    ax.plot(cur, lw=1.2, label="current_pixel", color="#c0392b")
    ax.fill_between(range(len(cur)),
                    np.minimum(cur, ref), ref,
                    color="#c0392b", alpha=0.12, label="dip_depth")
    ax.set_xlabel("pixel index (p)")
    ax.set_ylabel("code")
    ax.legend(loc="lower right", fontsize=8)
    ax.set_title("SPR line profile -> test vector")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    return True


# ---------------------------------------------------------------- main -------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="image or video path (the measurement frame)")
    ap.add_argument("--ref", help="optional real background/calibration frame")
    ap.add_argument("--width", type=int, default=1024,
                    help="IMAGE_WIDTH samples (default 1024; use 1280 for S11661)")
    ap.add_argument("--bits", type=int, default=12, help="PIXEL_WIDTH (default 12)")
    ap.add_argument("--channel", default="gray", choices=["gray", "r", "g", "b"])
    ap.add_argument("--reduce", default="mean-rows",
                    help="mean-rows|sum-rows|mean-cols|sum-cols|line-row[=N]|line-col[=N]")
    ap.add_argument("--frame", type=int, default=0, help="video frame index")
    ap.add_argument("--normalize", action="store_true",
                    help="stretch min..max to full scale (emphasize the dip)")
    ap.add_argument("--synth-ref", default="flat", choices=["flat", "smooth"],
                    help="baseline model when --ref not given (default flat)")
    ap.add_argument("--out", default="current.hex")
    ap.add_argument("--ref-out", default="ref.hex")
    ap.add_argument("--report", default="vectors_report.txt")
    ap.add_argument("--plot", default="vectors_preview.png")
    args = ap.parse_args()

    # --- current frame -> profile -> codes ---
    frame = load_frame(args.input, args.frame)
    chan = to_channel(frame, args.channel)
    prof = resample(reduce_profile(chan, args.reduce), args.width)
    cur = scale_to_bits(prof, args.bits, args.normalize)

    # --- reference: real capture, else synthesized ---
    if args.ref:
        rframe = load_frame(args.ref, args.frame)
        rchan = to_channel(rframe, args.channel)
        rprof = resample(reduce_profile(rchan, args.reduce), args.width)
        ref = scale_to_bits(rprof, args.bits, args.normalize)
        ref_src = f"real capture: {args.ref}"
    else:
        ref = synth_reference(cur, args.synth_ref, args.bits)
        ref_src = f"synthesized ({args.synth_ref})"

    meta_common = [
        f"source={args.input}", f"channel={args.channel}",
        f"reduce={args.reduce}", f"width={args.width}", f"bits={args.bits}",
        f"normalize={args.normalize}",
    ]
    write_hex(args.out, cur, args.bits, meta_common + ["stream=current_pixel"])
    write_hex(args.ref_out, ref, args.bits,
              meta_common + [f"stream=ref_pixel ({ref_src})"])
    pos, dpos, dmax = write_report(args.report, cur, ref, args.bits)
    plotted = save_plot(args.plot, cur, ref)

    print(f"input frame  : {frame.shape}")
    print(f"reduce/axis  : {args.reduce}  channel={args.channel}")
    print(f"reference    : {ref_src}")
    print(f"samples      : {len(cur)}  ({args.bits}-bit, "
          f"max code {(1<<args.bits)-1})")
    print(f"current: min={cur.min()} max={cur.max()}  darkest pixel @ p={pos}")
    print(f"dip_depth: peak={dmax} @ p={dpos}  <- expect roi_centroid p_min near here")
    print(f"wrote        : {args.out}, {args.ref_out}, {args.report}"
          + (f", {args.plot}" if plotted else " (plot skipped: no matplotlib)"))


if __name__ == "__main__":
    main()