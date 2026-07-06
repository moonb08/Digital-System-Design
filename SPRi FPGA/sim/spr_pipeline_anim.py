"""
spr_pipeline_anim.py -- Animated SPR pipeline simulation
    Shows the SPR dip sweeping across the sensor while
    bg_subtraction and roi_centroid track it in real-time.
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation

# ----------------------------------------------------------------
# Parameters
# ----------------------------------------------------------------
PIXEL_WIDTH = 12
IMAGE_WIDTH = 1024
MAX_VAL     = (1 << PIXEL_WIDTH) - 1
ACC_WIDTH   = 32
DEN_WIDTH   = 22
ACC_MASK    = (1 << ACC_WIDTH) - 1
DEN_MASK    = (1 << DEN_WIDTH) - 1
ADDR_MASK   = (1 << 10) - 1

BASELINE    = 2800
DIP_DEPTH   = 2000
DIP_SIGMA   = 40
NUM_FRAMES  = 120       # animation frames
INTERVAL_MS = 80        # ms between frames


# ----------------------------------------------------------------
# Pipeline functions
# ----------------------------------------------------------------
def bg_subtraction_frame(sample, ref):
    dip = np.clip(ref - sample, 0, MAX_VAL).astype(int)
    diff = np.clip(sample - ref, 0, MAX_VAL).astype(int)
    ovf = (sample < ref)
    return diff, dip, ovf


def restoring_divider(dividend, divisor):
    if divisor == 0:
        return 0
    q, r = 0, 0
    for i in range(ACC_WIDTH):
        bit = (dividend >> (ACC_WIDTH - 1 - i)) & 1
        trial = ((r << 1) | bit) & ACC_MASK
        if trial >= divisor:
            r = (trial - divisor) & ACC_MASK
            q = ((q << 1) | 1) & ACC_MASK
        else:
            r = trial
            q = (q << 1) & ACC_MASK
    return q & ADDR_MASK


def roi_centroid(dip_depths):
    pixels = np.arange(IMAGE_WIDTH)
    num = int(np.sum(pixels * dip_depths)) & ACC_MASK
    den = int(np.sum(dip_depths)) & DEN_MASK
    p_min = restoring_divider(num, den)
    return p_min, num, den


# ----------------------------------------------------------------
# Dip centre trajectory: sweep left -> right -> left
# ----------------------------------------------------------------
centres = np.concatenate([
    np.linspace(150, 874, NUM_FRAMES // 2),
    np.linspace(874, 150, NUM_FRAMES // 2),
]).astype(int)

pixels = np.arange(IMAGE_WIDTH)
ref_line = np.full(IMAGE_WIDTH, BASELINE, dtype=int)


# ----------------------------------------------------------------
# Set up figure
# ----------------------------------------------------------------
fig, axes = plt.subplots(3, 1, figsize=(13, 9), sharex=True,
                         gridspec_kw={"height_ratios": [2, 1.5, 1.5]})
fig.suptitle("SPR Pipeline Animation:  bg_subtraction  ->  roi_centroid",
             fontsize=13, fontweight="bold")

# Panel 1: Input signals
ax1 = axes[0]
line_ref,    = ax1.plot([], [], color="#1976D2", lw=1.2, label="Reference")
line_sample, = ax1.plot([], [], color="#E53935", lw=1.0, label="Sample")
fill_dip     = None
vline_true1  = ax1.axvline(0, color="#888", ls="--", lw=0.8, label="True centre")
ax1.set_ylabel("Intensity (counts)")
ax1.set_title("INPUT: Sensor signals", fontsize=11)
ax1.set_xlim(0, IMAGE_WIDTH)
ax1.set_ylim(-100, MAX_VAL + 300)
ax1.legend(loc="lower right", fontsize=8)
ax1.grid(True, alpha=0.3)

# Panel 2: bg_subtraction outputs
ax2 = axes[1]
line_dip,  = ax2.plot([], [], color="#F57C00", lw=0.9, label="dip_depth")
line_diff, = ax2.plot([], [], color="#43A047", lw=0.7, alpha=0.6,
                      label="diff_pixel")
ax2.set_ylabel("Counts")
ax2.set_title("STAGE 1: bg_subtraction", fontsize=11)
ax2.set_xlim(0, IMAGE_WIDTH)
ax2.set_ylim(-50, DIP_DEPTH + 200)
ax2.legend(loc="upper right", fontsize=8)
ax2.grid(True, alpha=0.3)

# Panel 3: Centroid
ax3 = axes[2]
fill_weight  = None
vline_rtl    = ax3.axvline(0, color="#43A047", ls="-", lw=2.5,
                           label="RTL p_min")
vline_true3  = ax3.axvline(0, color="#888", ls="--", lw=0.8,
                           label="True centre")
text_result  = ax3.text(0.98, 0.92, "", transform=ax3.transAxes,
                        fontsize=10, ha="right", va="top",
                        fontfamily="monospace",
                        bbox=dict(boxstyle="round,pad=0.4",
                                  facecolor="#E8F5E9",
                                  edgecolor="#43A047", alpha=0.9))
ax3.set_ylabel("dip_depth (counts)")
ax3.set_xlabel("Pixel index")
ax3.set_title("STAGE 2: roi_centroid  ->  p_min", fontsize=11)
ax3.set_xlim(0, IMAGE_WIDTH)
ax3.set_ylim(-50, DIP_DEPTH + 200)
ax3.legend(loc="upper left", fontsize=8)
ax3.grid(True, alpha=0.3)

plt.tight_layout(rect=[0, 0, 1, 0.95])


# ----------------------------------------------------------------
# Animation update
# ----------------------------------------------------------------
def update(frame):
    global fill_dip, fill_weight

    centre = centres[frame]

    # Generate sample with dip at current centre
    sample = BASELINE - DIP_DEPTH * np.exp(
        -0.5 * ((pixels - centre) / DIP_SIGMA) ** 2)
    sample = np.clip(sample, 0, MAX_VAL).astype(int)

    # Stage 1: bg_subtraction
    diff_out, dip_out, ovf_out = bg_subtraction_frame(sample, ref_line)

    # Stage 2: roi_centroid
    p_min, num, den = roi_centroid(dip_out)

    # ── Update panel 1 ─────────────────────────────────────
    line_ref.set_data(pixels, ref_line)
    line_sample.set_data(pixels, sample)
    vline_true1.set_xdata([centre])

    if fill_dip is not None:
        fill_dip.remove()
    fill_dip = ax1.fill_between(pixels, sample, ref_line,
                                where=(sample < ref_line),
                                color="#E53935", alpha=0.12)

    # ── Update panel 2 ─────────────────────────────────────
    line_dip.set_data(pixels, dip_out)
    line_diff.set_data(pixels, diff_out)

    # ── Update panel 3 ─────────────────────────────────────
    if fill_weight is not None:
        fill_weight.remove()
    fill_weight = ax3.fill_between(pixels, 0, dip_out,
                                   color="#F57C00", alpha=0.4)
    vline_rtl.set_xdata([p_min])
    vline_true3.set_xdata([centre])

    text_result.set_text(
        f"Frame {frame + 1}/{NUM_FRAMES}\n"
        f"True:  {centre}\n"
        f"p_min: {p_min}\n"
        f"Error: {abs(p_min - centre)} px")

    return (line_ref, line_sample, line_dip, line_diff,
            vline_true1, vline_rtl, vline_true3, text_result)


# ----------------------------------------------------------------
# Run
# ----------------------------------------------------------------
anim = FuncAnimation(fig, update, frames=NUM_FRAMES,
                     interval=INTERVAL_MS, blit=False, repeat=True)

print("=" * 56)
print("  SPR Pipeline Animation")
print("  Dip sweeps from pixel 150 -> 874 -> 150")
print(f"  {NUM_FRAMES} frames at {INTERVAL_MS}ms interval")
print("=" * 56)

import sys
if len(sys.argv) > 1 and sys.argv[1] == "--save":
    print("\n[INFO] Saving animation as GIF...")
    print("  This may take a minute. Please wait...")
    anim.save("sim/spr_pipeline_anim.gif", writer="pillow", fps=15)
    print("[SUCCESS] Animation saved to: sim/spr_pipeline_anim.gif\n")
elif len(sys.argv) > 1 and sys.argv[1] == "--save-mp4":
    print("\n[INFO] Saving animation as MP4...")
    print("  This may take a minute. Please wait...")
    anim.save("sim/spr_pipeline_anim.mp4", writer="ffmpeg", fps=15)
    print("[SUCCESS] Animation saved to: sim/spr_pipeline_anim.mp4\n")
else:
    print("  Run with: 'python sim/spr_pipeline_anim.py --save' to save as GIF.")
    print("  Run with: 'python sim/spr_pipeline_anim.py --save-mp4' to save as MP4.")
    print("  Close the window to exit.")

plt.show()


