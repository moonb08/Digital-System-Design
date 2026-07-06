"""
bg_subtraction_sim.py — Python simulation of the bg_subtraction Verilog module
for SPRi (Surface Plasmon Resonance imaging).

Mirrors the RTL behaviour:
    diff_pixel = max(current - ref, 0)
    dip_depth  = max(ref - current, 0)
    overflow_flag = 1 when current < ref (dip region)

Includes:
    1. Cycle-accurate behavioural model (matches 1-cycle pipeline latency)
    2. Ten test scenarios identical to the Verilog testbench
    3. SPR dip visualisation with matplotlib
"""

import numpy as np
import matplotlib.pyplot as plt
from dataclasses import dataclass, field
from typing import List, Optional

# ────────────────────────────────────────────────────────────────
# Parameters (match Verilog defaults)
# ────────────────────────────────────────────────────────────────
PIXEL_WIDTH = 12
IMAGE_WIDTH = 1024
MAX_VAL = (1 << PIXEL_WIDTH) - 1  # 4095


# ────────────────────────────────────────────────────────────────
# Cycle-accurate model
# ────────────────────────────────────────────────────────────────
@dataclass
class BgSubtraction:
    """Cycle-accurate Python model of the bg_subtraction Verilog module."""

    pixel_width: int = PIXEL_WIDTH

    # Registered outputs (updated on posedge clk)
    diff_pixel: int = 0
    dip_depth: int = 0
    valid_out: bool = False
    overflow_flag: bool = False
    ready_out: bool = True  # always ready (combinational)

    # Internal
    _rst_n: bool = True

    def reset(self):
        """Assert active-low reset."""
        self._rst_n = False
        self.diff_pixel = 0
        self.dip_depth = 0
        self.valid_out = False
        self.overflow_flag = False

    def release_reset(self):
        """De-assert reset."""
        self._rst_n = True

    def clock(self, current_pixel: int, ref_pixel: int, valid_in: bool):
        """
        Simulate one rising clock edge.
        Returns a dict with the registered output values AFTER this edge.
        """
        if not self._rst_n:
            self.diff_pixel = 0
            self.dip_depth = 0
            self.valid_out = False
            self.overflow_flag = False
        else:
            self.valid_out = valid_in
            if valid_in:
                mask = (1 << self.pixel_width) - 1
                # 13-bit signed subtraction
                diff_raw = current_pixel - ref_pixel

                if diff_raw < 0:
                    # Negative → dip region
                    self.diff_pixel = 0
                    self.dip_depth = (-diff_raw) & mask
                    self.overflow_flag = True
                else:
                    # Positive or zero
                    self.diff_pixel = diff_raw & mask
                    self.dip_depth = 0
                    self.overflow_flag = False

        return {
            "diff_pixel": self.diff_pixel,
            "dip_depth": self.dip_depth,
            "valid_out": self.valid_out,
            "overflow_flag": self.overflow_flag,
        }


# ────────────────────────────────────────────────────────────────
# Test infrastructure
# ────────────────────────────────────────────────────────────────
pass_count = 0
fail_count = 0


def check(dut: BgSubtraction, curr: int, ref: int, test_id: int, label: str = ""):
    """Drive one pixel, check diff_pixel against expected = max(curr-ref, 0)."""
    global pass_count, fail_count

    result = dut.clock(curr, ref, valid_in=True)
    expected = max(curr - ref, 0)
    expected_dip = max(ref - curr, 0)

    ok = (result["diff_pixel"] == expected and
          result["dip_depth"] == expected_dip and
          result["valid_out"] is True)

    tag = "PASS" if ok else "FAIL"
    if ok:
        pass_count += 1
    else:
        fail_count += 1

    print(f"  [{tag}] Test {test_id:>2d}: curr={curr:>4d}  ref={ref:>4d}  | "
          f"diff={result['diff_pixel']:>4d} (exp={expected:>4d})  "
          f"dip={result['dip_depth']:>4d} (exp={expected_dip:>4d})  "
          f"overflow={int(result['overflow_flag'])}  {label}")
    return result


# ────────────────────────────────────────────────────────────────
# Test scenarios (mirrors the Verilog testbench)
# ────────────────────────────────────────────────────────────────
def run_tests():
    global pass_count, fail_count
    pass_count = 0
    fail_count = 0

    dut = BgSubtraction()

    # ── Reset ────────────────────────────────────────────────
    dut.reset()
    for _ in range(4):
        dut.clock(0, 0, False)
    dut.release_reset()
    dut.clock(0, 0, False)

    # ── TEST 1: Normal subtraction (current > ref) ──────────
    print("\n--- Test 1: Normal subtraction ---")
    check(dut, 3000, 1000, 1)
    check(dut, 4095,  100, 2)
    check(dut,  500,  200, 3)

    # ── TEST 2: Zero difference ─────────────────────────────
    print("\n--- Test 2: Zero difference ---")
    check(dut, 2048, 2048, 4)
    check(dut,    0,    0, 5)

    # ── TEST 3: Negative clamp (current < ref → 0) ─────────
    print("\n--- Test 3: Negative clamp (rectification) ---")
    check(dut,  100,  500, 6)
    check(dut,    0, 4095, 7)
    check(dut, 1000, 1001, 8)

    # ── TEST 4: SPR Dip Simulation (64 pixels) ──────────────
    print("\n--- Test 4: SPR Dip Simulation (64 pixels) ---")
    print("  Reference = 2000 (flat baseline)")
    print("  Sample    = Gaussian dip centred at pixel 32")
    print(f"  {'Pixel':>5s} | {'Curr':>4s} | {'Ref':>4s} | {'Diff':>4s} | {'Dip':>4s} | OVF")
    print("  " + "-" * 48)

    spr_current = []
    spr_ref_vals = []
    spr_diff = []
    spr_dip = []

    for pix in range(64):
        ref_val = 2000
        dist = abs(pix - 32)

        if dist == 0:
            curr_val = 500
        elif dist <= 2:
            curr_val = 700
        elif dist <= 4:
            curr_val = 1000
        elif dist <= 6:
            curr_val = 1400
        elif dist <= 8:
            curr_val = 1700
        elif dist <= 10:
            curr_val = 1900
        else:
            curr_val = 2000

        result = dut.clock(curr_val, ref_val, valid_in=True)

        spr_current.append(curr_val)
        spr_ref_vals.append(ref_val)
        spr_diff.append(result["diff_pixel"])
        spr_dip.append(result["dip_depth"])

        print(f"  p={pix:02d}  | {curr_val:4d} | {ref_val:4d} | {result['diff_pixel']:4d} | "
              f"{result['dip_depth']:4d} | {int(result['overflow_flag'])}")

    # ── TEST 5: Extreme Corners ─────────────────────────────
    print("\n--- Test 5: Extreme corners (0 and 4095) ---")
    check(dut,    0,    0,  9)
    check(dut,    0, 4095, 10)
    check(dut, 4095,    0, 11)
    check(dut, 4095, 4095, 12)

    # ── TEST 6: Boundary ±1 ─────────────────────────────────
    print("\n--- Test 6: Boundary ±1 transitions ---")
    check(dut,    1,    0, 13)
    check(dut,    0,    1, 14)
    check(dut, 4095, 4094, 15)
    check(dut, 4094, 4095, 16)
    check(dut,    1,    1, 17)
    check(dut, 4094, 4094, 18)

    # ── TEST 7: Minimal Differences ─────────────────────────
    print("\n--- Test 7: Minimal differences (single-LSB) ---")
    check(dut,    2,    1, 19)
    check(dut,    1,    2, 20)
    check(dut, 2048, 2047, 21)
    check(dut, 2047, 2048, 22)
    check(dut,  100,   99, 23)
    check(dut,   99,  100, 24)
    check(dut, 3500, 3499, 25)
    check(dut, 3499, 3500, 26)

    # ── TEST 8: Max Range ───────────────────────────────────
    print("\n--- Test 8: Max range differences ---")
    check(dut, 4095,    0, 27)
    check(dut,    0, 4095, 28)
    check(dut, 4095,    1, 29)
    check(dut,    1, 4095, 30)
    check(dut, 3072, 1024, 31)
    check(dut, 1024, 3072, 32)

    # ── TEST 9: Back-to-Back Streaming (16 pixels) ──────────
    print("\n--- Test 9: Back-to-back streaming (16 pixels) ---")
    stream_curr = [100, 200, 300, 4095, 0, 2048, 1000, 999,
                   3000, 1500, 1, 0, 4094, 4095, 2500, 750]
    stream_ref  = [50, 200, 400, 0, 4095, 2048, 999, 1000,
                   1500, 3000, 0, 1, 4095, 4094, 2500, 250]

    stream_pass = 0
    stream_fail = 0
    for s in range(16):
        result = dut.clock(stream_curr[s], stream_ref[s], valid_in=True)
        expected = max(stream_curr[s] - stream_ref[s], 0)
        ok = result["diff_pixel"] == expected
        tag = "PASS" if ok else "FAIL"
        if ok:
            pass_count += 1
            stream_pass += 1
        else:
            fail_count += 1
            stream_fail += 1
        print(f"  [{tag}] Stream[{s:02d}]: curr={stream_curr[s]:4d}  "
              f"ref={stream_ref[s]:4d}  | diff={result['diff_pixel']:4d} (exp={expected:4d})")
    print(f"  Stream result: {stream_pass} passed, {stream_fail} failed")

    # ── TEST 10: Reset During Active Operation ──────────────
    print("\n--- Test 10: Reset during active operation ---")
    dut.clock(3000, 1000, valid_in=True)
    dut.reset()
    dut.clock(0, 0, False)
    dut.clock(0, 0, False)

    test10_pass = True
    if dut.diff_pixel != 0:
        print(f"  [FAIL] Reset: diff_pixel={dut.diff_pixel} (expected 0)")
        test10_pass = False
    if dut.valid_out:
        print(f"  [FAIL] Reset: valid_out=True (expected False)")
        test10_pass = False
    if dut.overflow_flag:
        print(f"  [FAIL] Reset: overflow_flag=True (expected False)")
        test10_pass = False

    if test10_pass:
        print("  [PASS] Reset clears all outputs correctly")
        pass_count += 1
    else:
        fail_count += 1

    dut.release_reset()
    dut.clock(0, 0, False)
    print("  Verifying post-reset operation...")
    check(dut, 2000, 500, 33)

    # ── Summary ─────────────────────────────────────────────
    print("\n" + "=" * 48)
    print(f"  RESULTS: {pass_count} PASSED, {fail_count} FAILED")
    print("=" * 48)
    if fail_count == 0:
        print("  ALL TESTS PASSED")
    else:
        print("  FAILURES DETECTED - Fix before proceeding")
    print("=" * 48)

    return spr_current, spr_ref_vals, spr_diff, spr_dip


# ────────────────────────────────────────────────────────────────
# Full 1024-pixel SPR simulation
# ────────────────────────────────────────────────────────────────
def simulate_full_spr():
    """
    Simulate a realistic 1024-pixel SPR curve through the
    bg_subtraction module (S11661 sensor, 1024 linear pixels).
    """
    dut = BgSubtraction()
    dut.reset()
    dut.clock(0, 0, False)
    dut.release_reset()

    pixels = np.arange(IMAGE_WIDTH)

    # Reference: flat baseline at ~2800 counts (typical SPR reflectance)
    ref_line = np.full(IMAGE_WIDTH, 2800)

    # Sample: SPR dip centred at pixel 512
    # Gaussian dip: I(p) = baseline - depth * exp(-0.5 * ((p - centre) / sigma)^2)
    centre = 512
    depth = 2000
    sigma = 40
    sample_line = 2800 - depth * np.exp(-0.5 * ((pixels - centre) / sigma) ** 2)
    sample_line = np.clip(sample_line, 0, MAX_VAL).astype(int)

    # Add realistic sensor noise (±15 counts, ~4 bits RMS for 12-bit ADC)
    np.random.seed(42)
    noise = np.random.normal(0, 15, IMAGE_WIDTH)
    sample_noisy = np.clip(sample_line + noise, 0, MAX_VAL).astype(int)

    # Run through the module
    diff_out = []
    dip_out = []
    ovf_out = []

    for p in range(IMAGE_WIDTH):
        result = dut.clock(int(sample_noisy[p]), int(ref_line[p]), valid_in=True)
        diff_out.append(result["diff_pixel"])
        dip_out.append(result["dip_depth"])
        ovf_out.append(result["overflow_flag"])

    diff_out = np.array(diff_out)
    dip_out = np.array(dip_out)
    ovf_out = np.array(ovf_out)

    return pixels, ref_line, sample_noisy, diff_out, dip_out, ovf_out


# ────────────────────────────────────────────────────────────────
# Visualisation
# ────────────────────────────────────────────────────────────────
def plot_results(pixels, ref_line, sample, diff_out, dip_out, ovf_out):
    """Generate publication-quality plots of the bg_subtraction outputs."""

    fig, axes = plt.subplots(3, 1, figsize=(14, 10), sharex=True,
                             gridspec_kw={"height_ratios": [2, 1.5, 0.5]})
    fig.suptitle("Background Subtraction Simulation — CMOS S11661 (1024 px, 12-bit)",
                 fontsize=14, fontweight="bold", y=0.97)

    # ── Panel 1: Raw signals ────────────────────────────────
    ax1 = axes[0]
    ax1.plot(pixels, ref_line, color="#1976D2", linewidth=1.2,
             label="Reference (flat baseline)")
    ax1.plot(pixels, sample, color="#E53935", linewidth=0.8, alpha=0.85,
             label="Sample (SPR dip + noise)")
    ax1.fill_between(pixels, sample, ref_line,
                     where=(sample < ref_line),
                     color="#E53935", alpha=0.12, label="Dip region")
    ax1.set_ylabel("Pixel intensity (12-bit counts)")
    ax1.set_title("Input Signals", fontsize=11)
    ax1.legend(loc="lower right", fontsize=9)
    ax1.set_ylim(-100, MAX_VAL + 200)
    ax1.grid(True, alpha=0.3)

    # ── Panel 2: Module outputs ─────────────────────────────
    ax2 = axes[1]
    ax2.plot(pixels, diff_out, color="#43A047", linewidth=0.9,
             label="diff_pixel = max(curr − ref, 0)")
    ax2.plot(pixels, dip_out, color="#F57C00", linewidth=0.9,
             label="dip_depth = max(ref − curr, 0)")
    ax2.set_ylabel("Output (counts)")
    ax2.set_title("bg_subtraction Outputs", fontsize=11)
    ax2.legend(loc="upper right", fontsize=9)
    ax2.set_ylim(-100, max(dip_out.max(), diff_out.max()) + 200)
    ax2.grid(True, alpha=0.3)

    # ── Panel 3: Overflow flag ──────────────────────────────
    ax3 = axes[2]
    ax3.fill_between(pixels, 0, ovf_out.astype(int),
                     color="#AB47BC", alpha=0.6, step="mid")
    ax3.set_ylabel("overflow")
    ax3.set_xlabel("Pixel index")
    ax3.set_title("overflow_flag (1 = dip region)", fontsize=11)
    ax3.set_yticks([0, 1])
    ax3.set_ylim(-0.1, 1.4)
    ax3.grid(True, alpha=0.3)

    plt.tight_layout(rect=[0, 0, 1, 0.95])
    save_path = "bg_subtraction_sim_plot.png"
    plt.savefig(save_path, dpi=150, bbox_inches="tight")
    print(f"\n[INFO] Plot saved to: {save_path}")
    plt.show()


# ────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 56)
    print("  BG Subtraction — Python Simulation")
    print("  Module: bg_subtraction.v  |  Sensor: CMOS S11661")
    print("  PIXEL_WIDTH=12  IMAGE_WIDTH=1024")
    print("=" * 56)

    # Run all 10 test scenarios
    spr_curr_64, spr_ref_64, spr_diff_64, spr_dip_64 = run_tests()

    # Full 1024-pixel SPR simulation
    print("\n" + "=" * 56)
    print("  Full 1024-pixel SPR Simulation")
    print("=" * 56)
    pixels, ref_line, sample, diff_out, dip_out, ovf_out = simulate_full_spr()

    print(f"  Dip region pixels: {np.sum(ovf_out)} / {IMAGE_WIDTH}")
    print(f"  Max dip depth:     {dip_out.max()} counts at pixel {np.argmax(dip_out)}")
    print(f"  Dip centre (weighted centroid): "
          f"{np.average(pixels, weights=dip_out):.1f}" if dip_out.sum() > 0 else "N/A")

    # Plot
    plot_results(pixels, ref_line, sample, diff_out, dip_out, ovf_out)
