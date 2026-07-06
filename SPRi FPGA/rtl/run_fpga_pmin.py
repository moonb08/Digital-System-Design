#!/usr/bin/env python3
"""
run_fpga_pmin.py IMAGE [--axis x|y] [--ref REF] [--channel gray|r|g|b] [--normalize]

Upload a phone photo -> get the pixel position (p_min) out of the SPR RTL.
Runs the ACTUAL spr_pipeline in Icarus (cycle-accurate), so the number is
what the FPGA fabric would compute, not a Python approximation.

  --axis x : dip runs left<->right   (collapse rows, profile indexed by column)
  --axis y : dip runs top<->bottom   (collapse cols, profile indexed by row)
"""
import argparse, subprocess, sys, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
RTL  = ["spr_pipeline.v", "bg_subtraction.v", "roi_centroid.v"]
TB   = "tb_pmin.v"
SIM  = os.path.join(HERE, "sim_pmin")


def build_sim():
    src = [os.path.join(HERE, f) for f in RTL + [TB]]
    r = subprocess.run(["iverilog", "-g2012", "-o", SIM, *src],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit("iverilog build failed:\n" + r.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--axis", choices=["x", "y"], default="x")
    ap.add_argument("--ref")
    ap.add_argument("--channel", default="gray", choices=["gray", "r", "g", "b"])
    ap.add_argument("--normalize", action="store_true")
    a = ap.parse_args()

    reduce_mode = "mean-rows" if a.axis == "x" else "mean-cols"
    cmd = ["python3", os.path.join(HERE, "frame_to_hex.py"), a.image,
           "--width", "1280", "--bits", "12", "--reduce", reduce_mode,
           "--channel", a.channel, "--out", "current.hex", "--ref-out", "ref.hex"]
    if a.ref:
        cmd += ["--ref", a.ref]
    if a.normalize:
        cmd += ["--normalize"]

    ext = subprocess.run(cmd, capture_output=True, text=True, cwd=HERE)
    if ext.returncode:
        sys.exit("extraction failed:\n" + ext.stdout + ext.stderr)

    if not os.path.exists(SIM):
        build_sim()
    run = subprocess.run(["vvp", SIM], capture_output=True, text=True, cwd=HERE)
    m = re.search(r"P_MIN\s*=\s*(\d+)", run.stdout)
    d = re.search(r"SUM_DEPTH\s*=\s*(\d+)", run.stdout)

    print(f"\n  image      : {os.path.basename(a.image)}")
    print(f"  axis       : {a.axis}  ({reduce_mode})  channel={a.channel}")
    if m:
        print(f"  >> pixel position (p_min) = {m.group(1)}   "
              f"(range 0..1279)")
        if d and int(d.group(1)) == 0:
            print("  !! SUM_DEPTH=0: no dip detected on this axis "
                  "(try --axis "
                  + ("y" if a.axis == "x" else "x")
                  + " or --normalize)")
    else:
        sys.exit("could not parse P_MIN:\n" + run.stdout + run.stderr)


if __name__ == "__main__":
    main()