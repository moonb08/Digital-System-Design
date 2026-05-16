# ZedBoard Calculator - Pure Verilog

A standalone integer calculator for the **ZedBoard Zynq-7000** with
**PmodKYPD** (4x4 keypad) and **PmodCLP** (16x2 character LCD).
No ARM core, no Vitis, no Digilent IPs. Pure Verilog RTL.

## What it does

Press digit keys to build a number. Press an operator (`+`, `-`, `*`, `/`).
Press more digits. Press `=` to compute the result. Press `C` to clear.

The LCD shows your expression as you type it, and the result after `=`.

```
1 2 + 3 4 =       displays:   12 -> 12+ -> 12+3 -> 12+34 -> = 46
9 * 9 =           displays:   = 81
5 / 0 =           displays:   ERR
```

## Files

```
zedboard_calc/
├── src/                     # Synthesizable Verilog
│   ├── lcd_controller.v     # HD44780 driver
│   ├── kypd_scanner.v       # 4x4 keypad scanner with debounce
│   ├── bin2bcd.v            # Binary -> BCD (double-dabble)
│   ├── keymap.v             # Combinational key -> ASCII
│   └── calc_top.v           # Top-level calculator
├── tb/                      # Testbenches
│   ├── tb_bin2bcd.v
│   ├── tb_lcd_controller.v
│   ├── tb_kypd_scanner.v
│   └── tb_calc_top.v
├── constraints/
│   └── calc.xdc             # ZedBoard pin constraints
├── run_all_tests.sh         # Build + run all testbenches
└── README.md                # This file
```

## Keypad mapping

The PmodKYPD has 16 keys arranged 4x4:
```
| 1 | 2 | 3 | A |   <- A = '+'
| 4 | 5 | 6 | B |   <- B = '-'
| 7 | 8 | 9 | C |   <- C = '*'
| 0 | F | E | D |   <- D = '/'    F = clear     E = '='
```

## Simulating (no board required)

You can verify the entire design works **without owning the ZedBoard**
using Icarus Verilog (free, cross-platform) or Vivado XSim.

### Option A: Icarus Verilog (Linux / macOS / Windows-WSL)

```bash
# Install (Ubuntu/Debian)
sudo apt-get install iverilog

# Run all tests
./run_all_tests.sh
```

Expected final output:
```
=== bin2bcd: ALL TESTS PASSED ===
=== lcd_controller: ALL TESTS PASSED ===
=== kypd_scanner: ALL TESTS PASSED ===
=== calc_top: ALL TESTS PASSED ===
```

### Option B: Vivado XSim (Windows / Linux)

1. **Create a project** in Vivado, target = ZedBoard.
2. **Add Sources -> Add or create design sources** -> add all 5 files from `src/`.
3. **Add Sources -> Add or create simulation sources** -> add all 4 files from `tb/`.
4. Set the simulation top to `tb_calc_top` (or another tb).
5. In Flow Navigator: **Simulation -> Run Simulation -> Run Behavioral Simulation**.
6. Watch the Tcl Console for `PASS`/`FAIL` messages.

## Building for the ZedBoard (when you get the hardware)

1. Open Vivado, create a project targeting **ZedBoard Zynq Evaluation
   and Development Kit** (install Digilent board files if missing).
2. **Add Sources** -> add all 5 files from `src/`.
3. **Add Constraints** -> add `constraints/calc.xdc`.
4. Set `calc_top` as the top module.
5. Flow Navigator -> **Generate Bitstream**.
6. **Open Hardware Manager** -> Open Target -> Auto Connect -> Program Device.

## Wiring on the ZedBoard

| Pmod    | Plug into |
|---------|-----------|
| KYPD J1 | JA (single 2x6 Pmod) |
| CLP data | JB (DB0..DB7) |
| CLP control | JC (RS, RW, E) |

**Note**: PmodCLP needs 11 signal pins, more than one Pmod (4 or 8 signal
pins) can provide. It comes with a ribbon cable that splits across two
Pmod connectors. Match the pinout in `calc.xdc` to how you cable it.

## Reset

The center pushbutton (BTNC) is the reset. Press it after powering on
or after a hang.

## What's been verified in simulation

| Module          | Tests         | Status |
|-----------------|---------------|--------|
| bin2bcd         | 10 values (0, small, large, neg) | PASS |
| lcd_controller  | Init sequence + char writes | PASS |
| kypd_scanner    | 5 keys at different (row,col) | PASS |
| calc_top        | 12+34=46, 9*9=81, 7-3=4, 8/2=4, 5/0=ERR | PASS |

## Known limitations

- Integer math only (no decimals or floating point).
- Maximum operand value before overflow: 2^31 - 1 ~= 2.1 billion.
- No operator precedence; only two operands per expression.
- Display wraps after 16 chars (rare in practice with small numbers).
- XDC pin numbers should be cross-checked against your specific
  ZedBoard revision's master XDC from Digilent.

## License

Free to use, modify, and redistribute. No warranty.
