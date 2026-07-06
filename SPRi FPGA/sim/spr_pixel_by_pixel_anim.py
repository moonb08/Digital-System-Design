"""
spr_pixel_by_pixel_anim.py -- Pixel-by-pixel animation of the SPR pipeline.

Shows each pixel arriving one at a time, exactly as the hardware processes it:
    1. bg_subtraction computes dip_depth for each pixel
    2. roi_centroid accumulates numerator & denominator
    3. After 1024 pixels, the divider computes p_min
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.patches import FancyBboxPatch

# ----------------------------------------------------------------
# Parameters
# ----------------------------------------------------------------
PIXEL_WIDTH = 12
IMAGE_WIDTH = 1024
MAX_VAL     = (1 << PIXEL_WIDTH) - 1
ADDR_MASK   = (1 << 10) - 1

BASELINE    = 2800
DIP_DEPTH   = 2000
DIP_SIGMA   = 40
DIP_CENTRE  = 512

# Animation: process STEP pixels per frame for speed
STEP        = 8
NUM_FRAMES  = IMAGE_WIDTH // STEP + 10   # extra frames for divider phase
INTERVAL_MS = 30

# ----------------------------------------------------------------
# Pre-compute the full SPR signals
# ----------------------------------------------------------------
pixels = np.arange(IMAGE_WIDTH)
ref_line = np.full(IMAGE_WIDTH, BASELINE, dtype=int)

sample_line = BASELINE - DIP_DEPTH * np.exp(
    -0.5 * ((pixels - DIP_CENTRE) / DIP_SIGMA) ** 2)
sample_line = np.clip(sample_line, 0, MAX_VAL).astype(int)

# Pre-compute all bg_subtraction outputs
dip_full  = np.clip(ref_line - sample_line, 0, MAX_VAL).astype(int)
diff_full = np.clip(sample_line - ref_line, 0, MAX_VAL).astype(int)

# Final centroid (for reference)
total_num = int(np.sum(pixels * dip_full))
total_den = int(np.sum(dip_full))
final_centroid = total_num / total_den if total_den > 0 else 0


# ----------------------------------------------------------------
# Figure setup
# ----------------------------------------------------------------
fig = plt.figure(figsize=(14, 11))
gs = fig.add_gridspec(4, 2, height_ratios=[1.8, 1.3, 1.3, 0.8],
                      width_ratios=[3, 1.2], hspace=0.35, wspace=0.25)

ax_input = fig.add_subplot(gs[0, 0])    # input signals
ax_bg    = fig.add_subplot(gs[1, 0])    # bg_subtraction output
ax_acc   = fig.add_subplot(gs[2, 0])    # accumulator build-up
ax_ovf   = fig.add_subplot(gs[3, 0])    # overflow flag
ax_info  = fig.add_subplot(gs[:, 1])    # info panel

fig.suptitle(
    "Pixel-by-Pixel Pipeline:  bg_subtraction  ->  roi_centroid",
    fontsize=13, fontweight="bold", y=0.98)

# ── Panel 1: Input signals (ghosted full + progressive) ────
ax_input.plot(pixels, ref_line, color="#1976D2", lw=1.0, alpha=0.3)
ax_input.plot(pixels, sample_line, color="#E53935", lw=0.5, alpha=0.2)
line_ref_prog,    = ax_input.plot([], [], color="#1976D2", lw=1.5,
                                  label="Reference")
line_sample_prog, = ax_input.plot([], [], color="#E53935", lw=1.2,
                                  label="Sample")
marker_pixel,     = ax_input.plot([], [], "o", color="#FF6F00", ms=6,
                                  zorder=5, label="Current pixel")
ax_input.set_ylabel("Intensity")
ax_input.set_title("INPUT: Sensor signals", fontsize=10)
ax_input.set_xlim(0, IMAGE_WIDTH)
ax_input.set_ylim(-100, MAX_VAL + 300)
ax_input.legend(loc="lower right", fontsize=7)
ax_input.grid(True, alpha=0.2)

# ── Panel 2: bg_subtraction dip_depth (progressive) ────────
ax_bg.plot(pixels, dip_full, color="#F57C00", lw=0.5, alpha=0.15)
line_dip_prog, = ax_bg.plot([], [], color="#F57C00", lw=1.2,
                            label="dip_depth")
fill_dip_prog  = None
marker_dip,    = ax_bg.plot([], [], "o", color="#E65100", ms=5, zorder=5)
ax_bg.set_ylabel("dip_depth")
ax_bg.set_title("STAGE 1: bg_subtraction output", fontsize=10)
ax_bg.set_xlim(0, IMAGE_WIDTH)
ax_bg.set_ylim(-50, DIP_DEPTH + 200)
ax_bg.legend(loc="upper right", fontsize=7)
ax_bg.grid(True, alpha=0.2)

# ── Panel 3: Running centroid estimate ─────────────────────
line_centroid, = ax_acc.plot([], [], color="#43A047", lw=1.5,
                             label="Running centroid")
ax_acc.axhline(DIP_CENTRE, color="#888", ls="--", lw=0.8,
               label=f"True centre = {DIP_CENTRE}")
ax_acc.set_ylabel("Centroid estimate")
ax_acc.set_title("STAGE 2: Running weighted centroid", fontsize=10)
ax_acc.set_xlim(0, IMAGE_WIDTH)
ax_acc.set_ylim(0, IMAGE_WIDTH)
ax_acc.legend(loc="upper right", fontsize=7)
ax_acc.grid(True, alpha=0.2)

# ── Panel 4: Overflow flag ─────────────────────────────────
line_ovf_prog, = ax_ovf.plot([], [], color="#AB47BC", lw=1.0)
ax_ovf.set_ylabel("overflow")
ax_ovf.set_xlabel("Pixel index")
ax_ovf.set_xlim(0, IMAGE_WIDTH)
ax_ovf.set_ylim(-0.1, 1.4)
ax_ovf.set_yticks([0, 1])
ax_ovf.grid(True, alpha=0.2)

# ── Info panel ─────────────────────────────────────────────
ax_info.axis("off")
info_text = ax_info.text(
    0.05, 0.95, "", transform=ax_info.transAxes,
    fontsize=10, verticalalignment="top", fontfamily="monospace",
    bbox=dict(boxstyle="round,pad=0.6", facecolor="#E3F2FD",
              edgecolor="#1565C0", alpha=0.95))

# FSM state box
fsm_text = ax_info.text(
    0.05, 0.38, "", transform=ax_info.transAxes,
    fontsize=11, fontweight="bold", verticalalignment="top",
    fontfamily="monospace",
    bbox=dict(boxstyle="round,pad=0.5", facecolor="#E8F5E9",
              edgecolor="#43A047", alpha=0.95))

# Progress bar background
prog_bg = ax_info.barh([0.18], [1.0], height=0.04, color="#E0E0E0",
                       transform=ax_info.transAxes, left=0.05)
prog_bar = ax_info.barh([0.18], [0.0], height=0.04, color="#43A047",
                        transform=ax_info.transAxes, left=0.05)
prog_label = ax_info.text(0.5, 0.14, "", transform=ax_info.transAxes,
                          fontsize=9, ha="center", fontfamily="monospace")


# ----------------------------------------------------------------
# Animation state
# ----------------------------------------------------------------
running_num = [0]
running_den = [0]
centroid_history = []
current_px = [0]
phase = ["IDLE"]  # IDLE, ACCUMULATE, DIVIDE, DONE


def update(frame):
    global fill_dip_prog

    # Reset state at the start of each loop
    if frame == 0:
        running_num[0] = 0
        running_den[0] = 0
        centroid_history.clear()
        # Remove any centroid lines from previous loop
        for line in ax_bg.get_lines():
            if line.get_color() == "#43A047" and line.get_linestyle() == "-":
                line.remove()
        for line in ax_acc.get_lines():
            if line.get_label() and "p_min" in line.get_label():
                line.remove()
        for bar in prog_bar:
            bar.set_color("#43A047")

    p = min(frame * STEP, IMAGE_WIDTH)
    current_px[0] = p

    if p < IMAGE_WIDTH:
        phase[0] = "ACCUMULATE"

        # Process pixels up to p
        for i in range(max(0, p - STEP), p):
            running_num[0] += i * int(dip_full[i])
            running_den[0] += int(dip_full[i])

        # Running centroid
        if running_den[0] > 0:
            rc = running_num[0] / running_den[0]
        else:
            rc = 0
        centroid_history.append(rc)

        # ── Update panel 1 ─────────────────────────────────
        px_range = pixels[:p]
        line_ref_prog.set_data(px_range, ref_line[:p])
        line_sample_prog.set_data(px_range, sample_line[:p])
        if p > 0:
            marker_pixel.set_data([p - 1], [sample_line[p - 1]])
        else:
            marker_pixel.set_data([], [])

        # ── Update panel 2 ─────────────────────────────────
        line_dip_prog.set_data(px_range, dip_full[:p])
        if p > 0:
            marker_dip.set_data([p - 1], [dip_full[p - 1]])
        if fill_dip_prog is not None:
            fill_dip_prog.remove()
        fill_dip_prog = ax_bg.fill_between(
            px_range, 0, dip_full[:p], color="#F57C00", alpha=0.25)

        # ── Update panel 3 ─────────────────────────────────
        cx = np.arange(len(centroid_history)) * STEP
        line_centroid.set_data(cx, centroid_history)

        # ── Update panel 4 ─────────────────────────────────
        ovf = (sample_line[:p] < ref_line[:p]).astype(int)
        line_ovf_prog.set_data(px_range, ovf)

        # ── Info panel ─────────────────────────────────────
        info_text.set_text(
            f"  Pixel:       {p} / {IMAGE_WIDTH}\n"
            f"  Current:     {sample_line[min(p, IMAGE_WIDTH-1)]:>5d}\n"
            f"  Reference:   {ref_line[0]:>5d}\n"
            f"  dip_depth:   {dip_full[min(p, IMAGE_WIDTH-1)]:>5d}\n"
            f"\n"
            f"  Numerator:   {running_num[0]:>12d}\n"
            f"  Denominator: {running_den[0]:>12d}\n"
            f"  Centroid:    {rc:>10.2f}\n"
        )

        fsm_text.set_text(
            f"  FSM: ACCUMULATE\n"
            f"  Pixel {p}/{IMAGE_WIDTH}")

        # Progress bar
        frac = p / IMAGE_WIDTH
        for bar in prog_bar:
            bar.set_width(frac * 0.9)
        prog_label.set_text(f"Accumulating... {p}/{IMAGE_WIDTH}")

    elif p == IMAGE_WIDTH:
        phase[0] = "DIVIDE"
        # Final divider result
        if running_den[0] > 0:
            p_min = running_num[0] // running_den[0]
            p_min = p_min & ADDR_MASK
        else:
            p_min = 0
        float_c = running_num[0] / running_den[0] if running_den[0] > 0 else 0

        fsm_text.set_text(
            f"  FSM: DIVIDE -> DONE\n"
            f"  p_min = {p_min}")

        info_text.set_text(
            f"  ALL 1024 PIXELS PROCESSED\n"
            f"\n"
            f"  Numerator:   {running_num[0]:>12d}\n"
            f"  Denominator: {running_den[0]:>12d}\n"
            f"\n"
            f"  RTL p_min:   {p_min:>10d}\n"
            f"  Float ref:   {float_c:>10.2f}\n"
            f"  True centre: {DIP_CENTRE:>10d}\n"
            f"  Error:       {abs(p_min - DIP_CENTRE):>10d} px\n"
        )

        for bar in prog_bar:
            bar.set_width(0.9)
            bar.set_color("#1565C0")
        prog_label.set_text(f"DONE -- p_min = {p_min}")

        # Draw final centroid line on panels
        ax_bg.axvline(p_min, color="#43A047", ls="-", lw=2, alpha=0.8)
        ax_acc.axhline(p_min, color="#43A047", ls="-", lw=1.5,
                       alpha=0.8, label=f"p_min = {p_min}")

    return (line_ref_prog, line_sample_prog, marker_pixel,
            line_dip_prog, marker_dip, line_centroid,
            line_ovf_prog, info_text, fsm_text, prog_label)


# ----------------------------------------------------------------
# Run
# ----------------------------------------------------------------
anim = FuncAnimation(fig, update, frames=NUM_FRAMES,
                     interval=INTERVAL_MS, blit=False, repeat=True)

print("=" * 56)
print("  Pixel-by-Pixel SPR Pipeline Animation")
print(f"  {IMAGE_WIDTH} pixels, {STEP} pixels/frame")
print(f"  SPR dip at pixel {DIP_CENTRE}")
print("=" * 56)

import sys
if len(sys.argv) > 1 and sys.argv[1] == "--save":
    print("\n[INFO] Saving animation as GIF...")
    print("  This may take a minute. Please wait...")
    anim.save("sim/spr_pixel_by_pixel_anim.gif", writer="pillow", fps=15)
    print("[SUCCESS] Animation saved to: sim/spr_pixel_by_pixel_anim.gif\n")
elif len(sys.argv) > 1 and sys.argv[1] == "--save-mp4":
    print("\n[INFO] Saving animation as MP4...")
    print("  This may take a minute. Please wait...")
    anim.save("sim/spr_pixel_by_pixel_anim.mp4", writer="ffmpeg", fps=15)
    print("[SUCCESS] Animation saved to: sim/spr_pixel_by_pixel_anim.mp4\n")
else:
    print("  Run with: 'python sim/spr_pixel_by_pixel_anim.py --save' to save as GIF.")
    print("  Run with: 'python sim/spr_pixel_by_pixel_anim.py --save-mp4' to save as MP4.")
    print("  Close the window to exit.")

plt.show()


