#!/bin/bash
#============================================================
# run_all_tests.sh
# Compile and run every testbench. Prints a final summary.
# Requires: iverilog and vvp (Icarus Verilog) on PATH.
#============================================================
set -e
cd "$(dirname "$0")"
mkdir -p build

echo "========================================"
echo "Test 1/4: bin2bcd"
echo "========================================"
iverilog -g2012 -o build/tb_bin2bcd  src/bin2bcd.v  tb/tb_bin2bcd.v
vvp build/tb_bin2bcd | tail -3

echo ""
echo "========================================"
echo "Test 2/4: lcd_controller"
echo "========================================"
iverilog -g2012 -o build/tb_lcd  src/lcd_controller.v  tb/tb_lcd_controller.v
vvp build/tb_lcd | tail -3

echo ""
echo "========================================"
echo "Test 3/4: kypd_scanner"
echo "========================================"
iverilog -g2012 -o build/tb_kypd  src/kypd_scanner.v  tb/tb_kypd_scanner.v
vvp build/tb_kypd | tail -3

echo ""
echo "========================================"
echo "Test 4/4: calc_top (integration)"
echo "========================================"
iverilog -g2012 -o build/tb_calc \
    src/bin2bcd.v src/kypd_scanner.v src/lcd_controller.v \
    src/keymap.v src/calc_top.v tb/tb_calc_top.v
vvp build/tb_calc | tail -3

echo ""
echo "========================================"
echo "All tests complete. Inspect output above."
echo "========================================"
