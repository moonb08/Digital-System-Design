#!/usr/bin/env python3
"""
run_fpga_pmin.py IMAGE [--axis x|y] [--ref REF] [--channel gray|r|g|b]
                       [--normalize] [--frame N]

Upload a phone photo -> get the pixel position (p_min) out of the SPR RTL.
Runs the ACTUAL spr_pipeline in Icarus (cycle-accurate), so the number is
what the FPGA fabric would compute, not a Python approximation.

  --axis x : dip runs left<->right   (collapse rows, profile indexed by column)
  --axis y : dip runs top<->bottom   (collapse cols, profile indexed by row)

A Python golden model of Eq. 4 (weighted centroid) is computed from the same
vectors and compared against the RTL output as a built-in sanity check.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

# In-process import instead of `python3 frame_to_hex.py` subprocess:
# saves an interpreter+numpy startup per run and exposes the raw vectors
# for the golden-model cross-check below.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from frame_to_hex import (load_frame, to_channel, reduce_profile, resample,
                          scale_to_bits, synth_reference, write_hex)

HERE = Path(__file__).resolve().parent
RTL = ["spr_pipeline.v", "bg_subtraction.v", "roi_centroid.v"]
TB = "tb_pmin.v"
SIM = HERE / "sim_pmin"
WIDTH, BITS = 1280, 12


def build_sim_if_stale():
    """(Re)compile only when the binary is missing or any source is newer."""
    src = [HERE / f for f in RTL + [TB]]
    missing = [s.name for s in src if not s.exists()]
    if missing:
        sys.exit(f"missing RTL/TB sources next to this script: {missing}")
    if SIM.exists() and SIM.stat().st_mtime > max(s.stat().st_mtime for s in src):
        return False
    r = subprocess.run(["iverilog", "-g2012", "-o", str(SIM),
                        *map(str, src)], capture_output=True, text=True)
    if r.returncode:
        sys.exit("iverilog build failed:\n" + r.stderr)
    return True


def extract_vectors(a):
    """Image/video -> (cur, ref) 12-bit code vectors, written as hex files."""
    reduce_mode = "mean-rows" if a.axis == "x" else "mean-cols"
    chan = to_channel(load_frame(a.image, a.frame), a.channel)
    cur = scale_to_bits(resample(reduce_profile(chan, reduce_mode), WIDTH),
                        BITS, a.normalize)
    if a.ref:
        rchan = to_channel(load_frame(a.ref, a.frame), a.channel)
        ref = scale_to_bits(resample(reduce_profile(rchan, reduce_mode), WIDTH),
                            BITS, a.normalize)
        ref_src = f"real capture: {a.ref}"
    else:
        ref = synth_reference(cur, "flat", BITS)
        ref_src = "synthesized (flat)"

    meta = [f"source={a.image}", f"channel={a.channel}",
            f"reduce={reduce_mode}", f"width={WIDTH}", f"bits={BITS}",
            f"normalize={a.normalize}"]
    write_hex(HERE / "current.hex", cur, BITS, meta + ["stream=current_pixel"])
    write_hex(HERE / "ref.hex", ref, BITS,
              meta + [f"stream=ref_pixel ({ref_src})"])
    return cur, ref, reduce_mode


def golden_pmin(cur, ref):
    """Python model of the RTL: dip = max(ref-cur,0); p = floor(Σp·dip / Σdip)."""
    dip = np.maximum(ref - cur, 0)
    s = int(dip.sum())
    p = int(np.arange(len(dip)) @ dip) // s if s else 0
    return p, s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--axis", choices=["x", "y"], default="x")
    ap.add_argument("--ref")
    ap.add_argument("--channel", default="gray", choices=["gray", "r", "g", "b"])
    ap.add_argument("--normalize", action="store_true")
    ap.add_argument("--frame", type=int, default=0, help="video frame index")
    a = ap.parse_args()

    cur, ref, reduce_mode = extract_vectors(a)
    exp_p, exp_sum = golden_pmin(cur, ref)

    rebuilt = build_sim_if_stale()
    run = subprocess.run(["vvp", str(SIM)], capture_output=True, text=True,
                         cwd=HERE)
    if "TIMEOUT" in run.stdout:
        sys.exit("simulation TIMEOUT (done never asserted):\n" + run.stdout)
    m = re.search(r"P_MIN\s*=\s*(\d+)", run.stdout)
    d = re.search(r"SUM_DEPTH\s*=\s*(\d+)", run.stdout)
    if not m:
        sys.exit("could not parse P_MIN:\n" + run.stdout + run.stderr)
    p_min = int(m.group(1))
    sum_depth = int(d.group(1)) if d else None

    print(f"\n  image      : {Path(a.image).name}")
    print(f"  axis       : {a.axis}  ({reduce_mode})  channel={a.channel}"
          + ("  [sim rebuilt]" if rebuilt else ""))
    print(f"  >> pixel position (p_min) = {p_min}   (range 0..{WIDTH - 1})")
    if sum_depth == 0:
        other = "y" if a.axis == "x" else "x"
        print(f"  !! SUM_DEPTH=0: no dip detected on this axis "
              f"(try --axis {other} or --normalize)")
    elif p_min == exp_p:
        print(f"  golden model agrees (p={exp_p}, Σdip={exp_sum})")
    else:
        print(f"  !! MISMATCH vs golden model: RTL={p_min}, Python={exp_p} "
              f"(Σdip={exp_sum}) — check ACC/DEN widths for saturation")


if __name__ == "__main__":
    main()