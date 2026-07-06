"""
spr_pipeline_sim.py -- Full SPR pipeline simulation
    Stage 1: bg_subtraction  (pixel-wise background removal)
    Stage 2: roi_centroid    (weighted centroid for dip position)

Single example: Gaussian SPR dip on a 1024-pixel CMOS S11661 sensor.
"""

import numpy as np
import matplotlib.pyplot as plt

# ----------------------------------------------------------------
# Parameters (match Verilog defaults)
# ----------------------------------------------------------------
PIXEL_WIDTH = 12
IMAGE_WIDTH = 1024
ADDR_WIDTH  = 10
ACC_WIDTH   = 32
DEN_WIDTH   = 22
MAX_VAL     = (1 << PIXEL_WIDTH) - 1  # 4095


# ================================================================
#  STAGE 1 : bg_subtraction  (mirrors bg_subtraction.v)
# ================================================================
def bg_subtraction(current_pixel, ref_pixel):
    """
    Pixel-wise background subtraction (one pixel at a time).
        diff_pixel = max(current - ref, 0)
        dip_depth  = max(ref - current, 0)
        overflow   = 1 if current < ref
    """
    diff = int(current_pixel) - int(ref_pixel)
    if diff < 0:
        diff_pixel    = 0
        dip_depth     = (-diff) & MAX_VAL
        overflow_flag = True
    else:
        diff_pixel    = diff & MAX_VAL
        dip_depth     = 0
        overflow_flag = False
    return diff_pixel, dip_depth, overflow_flag


def run_bg_subtraction(sample_line, ref_line):
    """Run bg_subtraction on an entire 1024-pixel frame."""
    diff_out = np.zeros(IMAGE_WIDTH, dtype=int)
    dip_out  = np.zeros(IMAGE_WIDTH, dtype=int)
    ovf_out  = np.zeros(IMAGE_WIDTH, dtype=bool)

    for p in range(IMAGE_WIDTH):
        diff_out[p], dip_out[p], ovf_out[p] = bg_subtraction(
            sample_line[p], ref_line[p])

    return diff_out, dip_out, ovf_out


# ================================================================
#  STAGE 2 : roi_centroid  (mirrors roi_centroid.v)
# ================================================================
ACC_MASK  = (1 << ACC_WIDTH) - 1
DEN_MASK  = (1 << DEN_WIDTH) - 1
ADDR_MASK = (1 << ADDR_WIDTH) - 1


def restoring_divider(dividend, divisor, width=ACC_WIDTH):
    """
    32-cycle restoring divider (matches the Verilog sequential divider).
    Returns integer quotient.
    """
    if divisor == 0:
        return 0

    quotient  = 0
    remainder = 0

    for i in range(width):
        bit_idx = width - 1 - i
        bit_val = (dividend >> bit_idx) & 1

        trial = ((remainder << 1) | bit_val) & ACC_MASK

        if trial >= divisor:
            remainder = (trial - divisor) & ACC_MASK
            quotient  = ((quotient << 1) | 1) & ACC_MASK
        else:
            remainder = trial
            quotient  = ((quotient << 1) | 0) & ACC_MASK

    return quotient & ADDR_MASK


def run_roi_centroid(dip_depths):
    """
    Run the roi_centroid FSM on 1024 dip_depth values.
    Returns (p_min, numerator, denominator).
    """
    numerator   = 0
    denominator = 0

    # ACCUMULATE phase: 1024 cycles
    for p in range(IMAGE_WIDTH):
        weight = int(dip_depths[p]) & MAX_VAL
        numerator   = (numerator + p * weight) & ACC_MASK
        denominator = (denominator + weight) & DEN_MASK

    # DIVIDE phase: 32-cycle restoring divider
    p_min = restoring_divider(numerator, denominator)

    return p_min, numerator, denominator


# ================================================================
#  Generate SPR test data
# ================================================================
def make_spr_signals(centre=512, depth=2000, sigma=40,
                     baseline=2800, noise_std=15):
    """
    Create a realistic 1024-pixel SPR curve.
    Returns (sample_line, ref_line).
    """
    pixels = np.arange(IMAGE_WIDTH)

    # Reference: flat baseline
    ref_line = np.full(IMAGE_WIDTH, baseline, dtype=int)

    # Sample: baseline with a Gaussian dip
    sample = baseline - depth * np.exp(
        -0.5 * ((pixels - centre) / sigma) ** 2)

    # Add sensor noise
    np.random.seed(42)
    sample += np.random.normal(0, noise_std, IMAGE_WIDTH)
    sample = np.clip(sample, 0, MAX_VAL).astype(int)

    return sample, ref_line


# ================================================================
#  Run the full pipeline
# ================================================================
def run_pipeline():
    # --- Configuration ---
    DIP_CENTRE = 512
    DIP_DEPTH  = 2000
    DIP_SIGMA  = 40
    BASELINE   = 2800
    NOISE_STD  = 0       # set to 15 for realistic sensor noise

    pixels = np.arange(IMAGE_WIDTH)

    print("=" * 60)
    print("  SPR Pipeline Simulation")
    print("  bg_subtraction.v  ->  roi_centroid.v")
    print(f"  Sensor: CMOS S11661  |  {IMAGE_WIDTH} pixels  |  12-bit")
    print("=" * 60)
    print(f"\n  SPR dip parameters:")
    print(f"    Centre   = {DIP_CENTRE}")
    print(f"    Depth    = {DIP_DEPTH} counts")
    print(f"    Sigma    = {DIP_SIGMA} pixels")
    print(f"    Baseline = {BASELINE} counts")
    print(f"    Noise    = +/-{NOISE_STD} counts RMS")

    # ── Generate input signals ──────────────────────────────
    sample, ref = make_spr_signals(
        centre=DIP_CENTRE, depth=DIP_DEPTH,
        sigma=DIP_SIGMA, baseline=BASELINE, noise_std=NOISE_STD)

    # ── STAGE 1: Background Subtraction ─────────────────────
    print("\n" + "-" * 60)
    print("  STAGE 1: bg_subtraction")
    print("    diff_pixel = max(current - ref, 0)")
    print("    dip_depth  = max(ref - current, 0)")
    print("-" * 60)

    diff_out, dip_out, ovf_out = run_bg_subtraction(sample, ref)

    dip_pixels = np.sum(ovf_out)
    max_dip    = np.max(dip_out)
    max_dip_px = np.argmax(dip_out)

    print(f"    Dip region:    {dip_pixels} / {IMAGE_WIDTH} pixels")
    print(f"    Max dip_depth: {max_dip} counts at pixel {max_dip_px}")

    # ── STAGE 2: ROI Centroid ───────────────────────────────
    print("\n" + "-" * 60)
    print("  STAGE 2: roi_centroid")
    print("    p_min = sum(p * dip_depth[p]) / sum(dip_depth[p])")
    print("-" * 60)

    p_min, numerator, denominator = run_roi_centroid(dip_out)

    # Float reference for comparison
    total_weight = float(np.sum(dip_out))
    if total_weight > 0:
        float_centroid = np.sum(pixels * dip_out) / total_weight
    else:
        float_centroid = 0.0

    print(f"    Numerator:     {numerator}")
    print(f"    Denominator:   {denominator}")
    print(f"    RTL p_min:     {p_min}  (integer, 10-bit)")
    print(f"    Float ref:     {float_centroid:.2f}")
    print(f"    Error:         {abs(p_min - float_centroid):.2f} pixels")
    print(f"    True centre:   {DIP_CENTRE}")
    print(f"    Offset:        {abs(p_min - DIP_CENTRE)} pixels")

    # ── Results ─────────────────────────────────────────────
    print("\n" + "=" * 60)
    print(f"  RESULT:  SPR dip detected at pixel {p_min}")
    print(f"           (true = {DIP_CENTRE}, error = "
          f"{abs(p_min - DIP_CENTRE)} px)")
    print("=" * 60)

    # ── Plot ────────────────────────────────────────────────
    plot_pipeline(pixels, sample, ref, diff_out, dip_out, ovf_out,
                  p_min, float_centroid, DIP_CENTRE)


# ================================================================
#  Visualisation
# ================================================================
def plot_pipeline(pixels, sample, ref, diff_out, dip_out, ovf_out,
                  p_min, float_centroid, true_centre):
    """4-panel plot showing the full pipeline."""

    fig, axes = plt.subplots(4, 1, figsize=(14, 12), sharex=True,
                             gridspec_kw={"height_ratios": [2, 1.5, 1.5, 0.5]})
    fig.suptitle(
        "SPR Pipeline:  bg_subtraction  ->  roi_centroid\n"
        f"CMOS S11661  |  {IMAGE_WIDTH} px  |  12-bit  |  "
        f"Detected dip at pixel {p_min}",
        fontsize=13, fontweight="bold", y=0.98)

    # ── Panel 1: Raw input signals ──────────────────────────
    ax = axes[0]
    ax.plot(pixels, ref, color="#1976D2", lw=1.2,
            label="Reference (flat baseline)")
    ax.plot(pixels, sample, color="#E53935", lw=0.8, alpha=0.85,
            label="Sample (SPR dip + noise)")
    ax.fill_between(pixels, sample, ref, where=(sample < ref),
                    color="#E53935", alpha=0.12, label="Dip region")
    ax.axvline(true_centre, color="#888", ls="--", lw=0.8,
               label=f"True centre = {true_centre}")
    ax.set_ylabel("Intensity (counts)")
    ax.set_title("INPUT: Sensor signals", fontsize=11)
    ax.legend(loc="lower right", fontsize=8)
    ax.set_ylim(-100, MAX_VAL + 300)
    ax.grid(True, alpha=0.3)

    # ── Panel 2: bg_subtraction outputs ─────────────────────
    ax = axes[1]
    ax.plot(pixels, diff_out, color="#43A047", lw=0.8,
            label="diff_pixel = max(curr - ref, 0)")
    ax.plot(pixels, dip_out, color="#F57C00", lw=0.9,
            label="dip_depth = max(ref - curr, 0)")
    ax.set_ylabel("Counts")
    ax.set_title("STAGE 1: bg_subtraction outputs", fontsize=11)
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(True, alpha=0.3)

    # ── Panel 3: dip_depth + centroid ───────────────────────
    ax = axes[2]
    ax.fill_between(pixels, 0, dip_out, color="#F57C00", alpha=0.4,
                    label="dip_depth (weights)")
    ax.plot(pixels, dip_out, color="#E65100", lw=0.6)
    ax.axvline(p_min, color="#43A047", ls="-", lw=2.0,
               label=f"RTL p_min = {p_min}")
    ax.axvline(float_centroid, color="#1565C0", ls="--", lw=1.2,
               label=f"Float centroid = {float_centroid:.2f}")
    ax.axvline(true_centre, color="#888", ls=":", lw=1.0,
               label=f"True centre = {true_centre}")
    ax.set_ylabel("dip_depth (counts)")
    ax.set_title("STAGE 2: roi_centroid  ->  p_min", fontsize=11)
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(True, alpha=0.3)

    # ── Panel 4: overflow flag ──────────────────────────────
    ax = axes[3]
    ax.fill_between(pixels, 0, ovf_out.astype(int),
                    color="#AB47BC", alpha=0.6, step="mid")
    ax.set_ylabel("overflow")
    ax.set_xlabel("Pixel index")
    ax.set_title("overflow_flag (1 = dip region)", fontsize=11)
    ax.set_yticks([0, 1])
    ax.set_ylim(-0.1, 1.4)
    ax.grid(True, alpha=0.3)

    plt.tight_layout(rect=[0, 0, 1, 0.94])
    save_path = "spr_pipeline_plot.png"
    plt.savefig(save_path, dpi=150, bbox_inches="tight")
    print(f"\n[INFO] Plot saved to: {save_path}")
    plt.show()


# ================================================================
#  Main
# ================================================================
if __name__ == "__main__":
    run_pipeline()
