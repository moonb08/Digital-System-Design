"""
roi_centroid_sim.py -- Python simulation of the roi_centroid Verilog module
for SPRi (Surface Plasmon Resonance imaging).

Mirrors the RTL behaviour:
    FSM: IDLE -> ACCUMULATE (1024 cycles) -> DIVIDE (32 cycles) -> DONE -> IDLE

    Weighted centroid formula (Eq. 4 from the paper):
                  sum( p * dip_depth[p] )
        p_min = -------------------------
                  sum( dip_depth[p] )

Includes:
    1. Cycle-accurate behavioural model with restoring divider
    2. Python reference model (floating-point) for comparison
    3. Multiple test scenarios
    4. Full 1024-pixel SPR simulation with visualisation
"""

import numpy as np
import matplotlib.pyplot as plt
from dataclasses import dataclass


# ----------------------------------------------------------------
# Parameters (match Verilog defaults)
# ----------------------------------------------------------------
PIXEL_WIDTH = 12
IMAGE_WIDTH = 1024
ADDR_WIDTH  = 10
ACC_WIDTH   = 32
DEN_WIDTH   = 22
MAX_VAL     = (1 << PIXEL_WIDTH) - 1   # 4095


# ----------------------------------------------------------------
# Masks for fixed-width arithmetic (emulate Verilog bit-widths)
# ----------------------------------------------------------------
ADDR_MASK = (1 << ADDR_WIDTH) - 1       # 0x3FF
ACC_MASK  = (1 << ACC_WIDTH)  - 1       # 0xFFFF_FFFF
DEN_MASK  = (1 << DEN_WIDTH)  - 1       # 0x3F_FFFF


# ----------------------------------------------------------------
# FSM states
# ----------------------------------------------------------------
IDLE       = 0
ACCUMULATE = 1
DIVIDE     = 2
DONE_ST    = 3

STATE_NAMES = {IDLE: "IDLE", ACCUMULATE: "ACCUMULATE",
               DIVIDE: "DIVIDE", DONE_ST: "DONE"}


# ----------------------------------------------------------------
# Cycle-accurate model
# ----------------------------------------------------------------
@dataclass
class RoiCentroid:
    """Cycle-accurate Python model of the roi_centroid Verilog module."""

    # Registered outputs
    p_min: int = 0
    done: bool = False
    busy: bool = False
    dbg_numerator: int = 0
    dbg_denominator: int = 0

    # Internal state
    state: int = IDLE
    pixel_addr: int = 0
    pix_count: int = 0
    numerator: int = 0
    denominator: int = 0

    # Sequential divider
    div_dividend: int = 0
    div_divisor: int = 0
    div_quotient: int = 0
    div_remainder: int = 0
    div_count: int = 0

    # Reset flag
    _rst_n: bool = True

    def reset(self):
        """Assert active-low reset -- clear all registers."""
        self._rst_n = False
        self.state = IDLE
        self.pixel_addr = 0
        self.pix_count = 0
        self.numerator = 0
        self.denominator = 0
        self.p_min = 0
        self.done = False
        self.busy = False
        self.div_count = 0
        self.div_quotient = 0
        self.div_remainder = 0
        self.div_dividend = 0
        self.div_divisor = 0
        self.dbg_numerator = 0
        self.dbg_denominator = 0

    def release_reset(self):
        self._rst_n = True

    def clock(self, start: bool = False, dip_depth: int = 0,
              valid_in: bool = False):
        """
        Simulate one rising clock edge.
        Returns dict of registered outputs after this edge.
        """
        if not self._rst_n:
            self.reset()
            return self._snapshot()

        # done is a single-cycle pulse, clear it every cycle
        self.done = False

        weight = dip_depth & MAX_VAL

        if self.state == IDLE:
            self.busy = False
            if start:
                self.numerator = 0
                self.denominator = 0
                self.pixel_addr = 0
                self.pix_count = 0
                self.busy = True
                self.state = ACCUMULATE

        elif self.state == ACCUMULATE:
            if valid_in:
                # numerator += pixel_addr * weight
                self.numerator = (self.numerator
                                  + self.pixel_addr * weight) & ACC_MASK
                # denominator += weight
                self.denominator = (self.denominator + weight) & DEN_MASK

                self.pixel_addr = (self.pixel_addr + 1) & ADDR_MASK
                self.pix_count = (self.pix_count + 1) & ADDR_MASK

                # Last pixel -- latch final sums into divider
                if self.pix_count == IMAGE_WIDTH - 1:
                    final_num = (self.numerator
                                 + self.pixel_addr * weight) & ACC_MASK
                    final_den = (self.denominator + weight) & DEN_MASK

                    self.div_dividend = final_num
                    self.div_divisor = final_den
                    self.dbg_numerator = final_num
                    self.dbg_denominator = final_den

                    self.div_count = 0
                    self.div_quotient = 0
                    self.div_remainder = 0
                    self.state = DIVIDE

                    # Update running accumulators too (they were already
                    # incremented above with the *previous* values; the
                    # Verilog uses non-blocking assigns so the final sums
                    # are computed combinationally from the old values)
                    self.numerator = final_num
                    self.denominator = final_den

        elif self.state == DIVIDE:
            if self.div_divisor == 0:
                # Division by zero guard
                self.p_min = 0
                self.state = DONE_ST
            else:
                # Restoring divider -- one bit per cycle
                # Shift remainder left by 1 and bring in MSB of dividend
                bit_idx = ACC_WIDTH - 1 - self.div_count
                bit_val = (self.div_dividend >> bit_idx) & 1

                trial = ((self.div_remainder << 1) | bit_val) & ACC_MASK

                # Compare with divisor (zero-extended to ACC_WIDTH)
                if trial >= self.div_divisor:
                    self.div_remainder = (trial - self.div_divisor) & ACC_MASK
                    self.div_quotient = ((self.div_quotient << 1) | 1) & ACC_MASK
                else:
                    self.div_remainder = trial & ACC_MASK
                    self.div_quotient = ((self.div_quotient << 1) | 0) & ACC_MASK

                self.div_count += 1

                if self.div_count == ACC_WIDTH:
                    self.state = DONE_ST

        elif self.state == DONE_ST:
            self.p_min = self.div_quotient & ADDR_MASK
            self.done = True
            self.busy = False
            self.state = IDLE

        return self._snapshot()

    def _snapshot(self):
        return {
            "p_min":           self.p_min,
            "done":            self.done,
            "busy":            self.busy,
            "state":           STATE_NAMES.get(self.state, "?"),
            "dbg_numerator":   self.dbg_numerator,
            "dbg_denominator": self.dbg_denominator,
        }

    def run_full_frame(self, dip_depths, verbose=False):
        """
        Drive an entire IMAGE_WIDTH frame through the FSM.
        dip_depths: list/array of length IMAGE_WIDTH (12-bit values).
        Returns (p_min, numerator, denominator, total_cycles).
        """
        assert len(dip_depths) == IMAGE_WIDTH

        # Pulse start
        self.clock(start=True, dip_depth=0, valid_in=False)

        # ACCUMULATE phase: feed 1024 pixels
        for p in range(IMAGE_WIDTH):
            self.clock(start=False, dip_depth=int(dip_depths[p]),
                       valid_in=True)

        # DIVIDE phase: 32 clock cycles (ACC_WIDTH)
        for _ in range(ACC_WIDTH + 1):
            snap = self.clock(start=False, dip_depth=0, valid_in=False)

        # DONE_ST -> IDLE: one more cycle to capture done pulse
        snap = self.clock(start=False, dip_depth=0, valid_in=False)

        # If done didn't fire yet, keep clocking
        cycles_extra = 0
        while not snap["done"] and cycles_extra < 10:
            snap = self.clock(start=False, dip_depth=0, valid_in=False)
            cycles_extra += 1

        if verbose:
            print(f"    FSM finished: p_min={snap['p_min']}  "
                  f"num={snap['dbg_numerator']}  "
                  f"den={snap['dbg_denominator']}  "
                  f"state={snap['state']}")

        return (snap["p_min"], snap["dbg_numerator"],
                snap["dbg_denominator"])


# ----------------------------------------------------------------
# Python reference model (floating-point)
# ----------------------------------------------------------------
def reference_centroid(dip_depths):
    """Compute weighted centroid using floating-point for comparison."""
    pixels = np.arange(len(dip_depths))
    weights = np.array(dip_depths, dtype=np.float64)
    total_weight = weights.sum()
    if total_weight == 0:
        return 0, 0, 0
    centroid = np.sum(pixels * weights) / total_weight
    return centroid, int(np.sum(pixels * weights)), int(total_weight)


# ----------------------------------------------------------------
# Background subtraction helper (from bg_subtraction module)
# ----------------------------------------------------------------
def bg_subtract(current, reference):
    """Pixel-wise: dip_depth = max(ref - current, 0)."""
    dip = np.clip(reference - current, 0, MAX_VAL).astype(int)
    return dip


# ----------------------------------------------------------------
# Test infrastructure
# ----------------------------------------------------------------
pass_count = 0
fail_count = 0


def run_test(dut, dip_depths, expected_centroid, test_id, label,
             tolerance=1):
    """
    Run a full frame through the DUT, compare p_min against expected.
    tolerance: allowed integer error (due to fixed-point truncation).
    """
    global pass_count, fail_count

    dut.reset()
    dut.clock()
    dut.release_reset()
    dut.clock()

    p_min, num, den = dut.run_full_frame(dip_depths)
    ref_c, ref_num, ref_den = reference_centroid(dip_depths)

    error = abs(p_min - expected_centroid)
    ok = error <= tolerance

    tag = "PASS" if ok else "FAIL"
    if ok:
        pass_count += 1
    else:
        fail_count += 1

    print(f"  [{tag}] Test {test_id:>2d}: {label}")
    print(f"         RTL model:  p_min={p_min:>4d}  num={num:>10d}  den={den:>8d}")
    print(f"         Reference:  p_min={ref_c:>7.2f}  num={ref_num:>10d}  den={ref_den:>8d}")
    if not ok:
        print(f"         ERROR: |{p_min} - {expected_centroid}| = {error} > {tolerance}")
    print()

    return p_min, ref_c


# ----------------------------------------------------------------
# Generate SPR dip profiles
# ----------------------------------------------------------------
def make_gaussian_dip(centre, depth, sigma, baseline=2800, noise_std=0):
    """Create a 1024-pixel SPR intensity curve with a Gaussian dip."""
    pixels = np.arange(IMAGE_WIDTH)
    intensity = baseline - depth * np.exp(
        -0.5 * ((pixels - centre) / sigma) ** 2)
    if noise_std > 0:
        np.random.seed(42)
        intensity += np.random.normal(0, noise_std, IMAGE_WIDTH)
    intensity = np.clip(intensity, 0, MAX_VAL).astype(int)
    ref = np.full(IMAGE_WIDTH, baseline, dtype=int)
    dip = bg_subtract(intensity, ref)
    return intensity, ref, dip


def make_flat(value=0):
    """All pixels have the same dip_depth."""
    return np.full(IMAGE_WIDTH, value, dtype=int)


def make_single_spike(position, depth=1000):
    """Single non-zero pixel at given position."""
    dip = np.zeros(IMAGE_WIDTH, dtype=int)
    dip[position] = min(depth, MAX_VAL)
    return dip


def make_two_dips(c1, c2, d1=1500, d2=1500, sigma=30, baseline=2800):
    """Two Gaussian dips -- centroid should land between them."""
    pixels = np.arange(IMAGE_WIDTH)
    dip1 = d1 * np.exp(-0.5 * ((pixels - c1) / sigma) ** 2)
    dip2 = d2 * np.exp(-0.5 * ((pixels - c2) / sigma) ** 2)
    intensity = baseline - dip1 - dip2
    intensity = np.clip(intensity, 0, MAX_VAL).astype(int)
    ref = np.full(IMAGE_WIDTH, baseline, dtype=int)
    dip = bg_subtract(intensity, ref)
    return intensity, ref, dip


# ----------------------------------------------------------------
# Test scenarios
# ----------------------------------------------------------------
def run_tests():
    global pass_count, fail_count
    pass_count = 0
    fail_count = 0

    dut = RoiCentroid()

    # ── TEST 1: Centred Gaussian dip at pixel 512 ───────────
    print("--- Test 1: Gaussian dip centred at pixel 512 ---")
    _, _, dip1 = make_gaussian_dip(centre=512, depth=2000, sigma=40)
    run_test(dut, dip1, 512, 1, "Gaussian @ 512, depth=2000, sigma=40")

    # ── TEST 2: Dip at pixel 200 (left side) ────────────────
    print("--- Test 2: Gaussian dip at pixel 200 ---")
    _, _, dip2 = make_gaussian_dip(centre=200, depth=1800, sigma=35)
    run_test(dut, dip2, 200, 2, "Gaussian @ 200, depth=1800, sigma=35")

    # ── TEST 3: Dip at pixel 900 (right side) ───────────────
    print("--- Test 3: Gaussian dip at pixel 900 ---")
    _, _, dip3 = make_gaussian_dip(centre=900, depth=2500, sigma=50)
    run_test(dut, dip3, 900, 3, "Gaussian @ 900, depth=2500, sigma=50")

    # ── TEST 4: Single-pixel spike ──────────────────────────
    print("--- Test 4: Single pixel spike at p=300 ---")
    dip4 = make_single_spike(300, depth=2000)
    run_test(dut, dip4, 300, 4, "Single spike @ 300, depth=2000",
             tolerance=0)

    # ── TEST 5: Single-pixel at edge (p=0) ──────────────────
    print("--- Test 5: Single pixel spike at p=0 ---")
    dip5 = make_single_spike(0, depth=4095)
    run_test(dut, dip5, 0, 5, "Single spike @ 0 (left edge)",
             tolerance=0)

    # ── TEST 6: Single-pixel at edge (p=1023) ───────────────
    print("--- Test 6: Single pixel spike at p=1023 ---")
    dip6 = make_single_spike(1023, depth=4095)
    run_test(dut, dip6, 1023, 6, "Single spike @ 1023 (right edge)",
             tolerance=0)

    # ── TEST 7: Uniform dip_depth -- centroid should be 511 ─
    print("--- Test 7: Uniform dip_depth (all pixels = 100) ---")
    dip7 = make_flat(100)
    # Weighted centroid of uniform = (0+1+...+1023)/1024 = 511.5 -> truncated to 511
    run_test(dut, dip7, 511, 7, "Uniform weight=100, expected ~511",
             tolerance=1)

    # ── TEST 8: All zeros -- div-by-zero guard ──────────────
    print("--- Test 8: All zeros (div-by-zero guard) ---")
    dip8 = make_flat(0)
    run_test(dut, dip8, 0, 8, "All zeros, div-by-zero -> p_min=0",
             tolerance=0)

    # ── TEST 9: Two equal dips -- centroid between them ─────
    print("--- Test 9: Two equal Gaussian dips at 300 and 700 ---")
    _, _, dip9 = make_two_dips(300, 700, d1=1500, d2=1500, sigma=30)
    run_test(dut, dip9, 500, 9,
             "Two equal dips @ 300,700 -> centroid ~500", tolerance=2)

    # ── TEST 10: Two unequal dips -- centroid biased ────────
    print("--- Test 10: Two unequal dips (deeper at 700) ---")
    _, _, dip10 = make_two_dips(300, 700, d1=500, d2=2000, sigma=30)
    ref_c10 = reference_centroid(dip10)[0]
    run_test(dut, dip10, int(round(ref_c10)), 10,
             f"Dips @ 300(d=500), 700(d=2000) -> ~{ref_c10:.0f}",
             tolerance=2)

    # ── TEST 11: Narrow dip (sigma=5) ───────────────────────
    print("--- Test 11: Very narrow dip (sigma=5) at pixel 600 ---")
    _, _, dip11 = make_gaussian_dip(centre=600, depth=2000, sigma=5)
    run_test(dut, dip11, 600, 11, "Narrow Gaussian @ 600, sigma=5",
             tolerance=1)

    # ── TEST 12: Wide dip (sigma=150) ───────────────────────
    print("--- Test 12: Very wide dip (sigma=150) at pixel 512 ---")
    _, _, dip12 = make_gaussian_dip(centre=512, depth=1000, sigma=150)
    run_test(dut, dip12, 512, 12, "Wide Gaussian @ 512, sigma=150",
             tolerance=2)

    # ── TEST 13: Noisy SPR curve ────────────────────────────
    print("--- Test 13: Noisy SPR dip (noise_std=20) at pixel 512 ---")
    _, _, dip13 = make_gaussian_dip(centre=512, depth=2000, sigma=40,
                                     noise_std=20)
    ref_c13 = reference_centroid(dip13)[0]
    run_test(dut, dip13, int(round(ref_c13)), 13,
             f"Noisy Gaussian @ 512 -> ref={ref_c13:.1f}", tolerance=1)

    # ── TEST 14: Maximum depth dip ──────────────────────────
    print("--- Test 14: Max depth dip (baseline=4095) at pixel 400 ---")
    _, _, dip14 = make_gaussian_dip(centre=400, depth=4095, sigma=40,
                                     baseline=4095)
    ref_c14 = reference_centroid(dip14)[0]
    run_test(dut, dip14, int(round(ref_c14)), 14,
             f"Max depth @ 400 -> ref={ref_c14:.1f}", tolerance=1)

    # ── Summary ─────────────────────────────────────────────
    print("=" * 56)
    print(f"  RESULTS: {pass_count} PASSED, {fail_count} FAILED")
    print("=" * 56)
    if fail_count == 0:
        print("  ALL TESTS PASSED")
    else:
        print("  FAILURES DETECTED - Fix before proceeding")
    print("=" * 56)

    return pass_count, fail_count


# ----------------------------------------------------------------
# Full 1024-pixel SPR simulation with visualisation
# ----------------------------------------------------------------
def simulate_and_plot():
    """Run several SPR scenarios and plot the results."""

    scenarios = [
        {"centre": 300, "depth": 2000, "sigma": 40,
         "label": "Dip @ 300 (sigma=40)"},
        {"centre": 512, "depth": 2000, "sigma": 40,
         "label": "Dip @ 512 (sigma=40)"},
        {"centre": 800, "depth": 1500, "sigma": 60,
         "label": "Dip @ 800 (sigma=60)"},
    ]

    fig, axes = plt.subplots(len(scenarios), 3, figsize=(18, 4 * len(scenarios)),
                             gridspec_kw={"width_ratios": [2, 2, 1.2]})
    fig.suptitle(
        "ROI Centroid Simulation -- CMOS S11661 (1024 px, 12-bit)\n"
        "p_min = sum(p * dip_depth[p]) / sum(dip_depth[p])",
        fontsize=14, fontweight="bold", y=1.0)

    dut = RoiCentroid()
    pixels = np.arange(IMAGE_WIDTH)

    for row, sc in enumerate(scenarios):
        intensity, ref, dip = make_gaussian_dip(
            sc["centre"], sc["depth"], sc["sigma"])

        # Run through DUT
        dut.reset()
        dut.clock()
        dut.release_reset()
        dut.clock()
        p_min, num, den = dut.run_full_frame(dip)
        ref_centroid = reference_centroid(dip)[0]

        # ── Panel 1: Input signals ──────────────────────────
        ax1 = axes[row, 0]
        ax1.plot(pixels, ref, color="#1976D2", linewidth=1.2,
                 label="Reference (baseline)")
        ax1.plot(pixels, intensity, color="#E53935", linewidth=0.8,
                 alpha=0.85, label="Sample (SPR dip)")
        ax1.fill_between(pixels, intensity, ref,
                         where=(intensity < ref),
                         color="#E53935", alpha=0.12)
        ax1.axvline(sc["centre"], color="#888", ls="--", lw=0.8,
                    label=f"True centre = {sc['centre']}")
        ax1.axvline(p_min, color="#43A047", ls="-", lw=1.5,
                    label=f"RTL p_min = {p_min}")
        ax1.set_ylabel("Intensity (counts)")
        ax1.set_title(f"{sc['label']} -- Input", fontsize=10)
        ax1.legend(loc="lower right", fontsize=8)
        ax1.set_ylim(-100, MAX_VAL + 300)
        ax1.grid(True, alpha=0.3)

        # ── Panel 2: dip_depth profile ──────────────────────
        ax2 = axes[row, 1]
        ax2.fill_between(pixels, 0, dip, color="#F57C00", alpha=0.5,
                         label="dip_depth")
        ax2.plot(pixels, dip, color="#E65100", linewidth=0.6)
        ax2.axvline(p_min, color="#43A047", ls="-", lw=1.5,
                    label=f"RTL p_min = {p_min}")
        ax2.axvline(ref_centroid, color="#1565C0", ls="--", lw=1.2,
                    label=f"Float ref = {ref_centroid:.2f}")
        ax2.set_ylabel("dip_depth (counts)")
        ax2.set_title(f"dip_depth + Centroid", fontsize=10)
        ax2.legend(loc="upper right", fontsize=8)
        ax2.grid(True, alpha=0.3)

        # ── Panel 3: Summary text box ───────────────────────
        ax3 = axes[row, 2]
        ax3.axis("off")
        summary = (
            f"Centre (true):   {sc['centre']}\n"
            f"RTL p_min:       {p_min}\n"
            f"Float centroid:  {ref_centroid:.2f}\n"
            f"Error (int):     {abs(p_min - sc['centre'])}\n"
            f"Error (float):   {abs(p_min - ref_centroid):.2f}\n"
            f"\n"
            f"Numerator:       {num}\n"
            f"Denominator:     {den}\n"
            f"Depth:           {sc['depth']}\n"
            f"Sigma:           {sc['sigma']}\n"
        )
        ax3.text(0.05, 0.95, summary, transform=ax3.transAxes,
                 fontsize=10, verticalalignment="top",
                 fontfamily="monospace",
                 bbox=dict(boxstyle="round,pad=0.5",
                           facecolor="#E8F5E9", edgecolor="#43A047",
                           alpha=0.9))
        ax3.set_title("Results", fontsize=10)

    for ax in axes[-1, :2]:
        ax.set_xlabel("Pixel index")

    plt.tight_layout(rect=[0, 0, 1, 0.96])
    save_path = "roi_centroid_sim_plot.png"
    plt.savefig(save_path, dpi=150, bbox_inches="tight")
    print(f"\n[INFO] Plot saved to: {save_path}")
    plt.show()


# ----------------------------------------------------------------
# Sweep: centroid accuracy vs. dip position
# ----------------------------------------------------------------
def accuracy_sweep():
    """Sweep dip centre across the sensor and plot accuracy."""
    dut = RoiCentroid()
    centres = list(range(50, 1000, 50))
    rtl_results = []
    float_results = []

    for c in centres:
        _, _, dip = make_gaussian_dip(centre=c, depth=2000, sigma=40)
        dut.reset()
        dut.clock()
        dut.release_reset()
        dut.clock()
        p_min, _, _ = dut.run_full_frame(dip)
        ref_c = reference_centroid(dip)[0]
        rtl_results.append(p_min)
        float_results.append(ref_c)

    rtl_results = np.array(rtl_results)
    float_results = np.array(float_results)
    errors = np.abs(rtl_results - float_results)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 7), sharex=True)
    fig.suptitle("ROI Centroid Accuracy Sweep (depth=2000, sigma=40)",
                 fontsize=13, fontweight="bold")

    ax1.plot(centres, centres, "k--", lw=0.8, label="Ideal (y=x)")
    ax1.plot(centres, rtl_results, "o-", color="#43A047", ms=5,
             label="RTL model (integer)")
    ax1.plot(centres, float_results, "s-", color="#1565C0", ms=4,
             alpha=0.7, label="Float reference")
    ax1.set_ylabel("Computed centroid (pixel)")
    ax1.legend(fontsize=9)
    ax1.grid(True, alpha=0.3)
    ax1.set_title("Centroid vs. True Centre")

    ax2.bar(centres, errors, width=30, color="#F57C00", alpha=0.7,
            edgecolor="#E65100")
    ax2.set_xlabel("True dip centre (pixel)")
    ax2.set_ylabel("|RTL - Float| error")
    ax2.set_title(f"Absolute Error (max = {errors.max():.2f} px)")
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    save_path = "roi_centroid_accuracy_sweep.png"
    plt.savefig(save_path, dpi=150, bbox_inches="tight")
    print(f"[INFO] Accuracy sweep plot saved to: {save_path}")
    plt.show()


# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------
if __name__ == "__main__":
    print("=" * 56)
    print("  ROI Centroid -- Python Simulation")
    print("  Module: roi_centroid.v  |  Sensor: CMOS S11661")
    print(f"  PIXEL_WIDTH={PIXEL_WIDTH}  IMAGE_WIDTH={IMAGE_WIDTH}")
    print(f"  ACC_WIDTH={ACC_WIDTH}  DEN_WIDTH={DEN_WIDTH}")
    print("=" * 56)

    # Run all test scenarios
    run_tests()

    # Full SPR visualisation
    print("\n" + "=" * 56)
    print("  Full 1024-pixel SPR Centroid Visualisation")
    print("=" * 56)
    simulate_and_plot()

    # Accuracy sweep
    print("\n" + "=" * 56)
    print("  Accuracy Sweep (centre from 50 to 950)")
    print("=" * 56)
    accuracy_sweep()
