## ===============================================================
## calc.xdc - ZedBoard Calculator Constraints
## LCD  -> JA + JB    KYPD -> JC
## ===============================================================
create_clock -period 10.000 -name sys_clk_in [get_ports clk]
create_generated_clock -name clk_sys -source [get_ports clk] -divide_by 2 [get_pins bufg_div/O]


## ---- RESET (BTNC) ----
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports rst]

## ---- LCD DATA on JA ----
set_property -dict {PACKAGE_PIN Y11  IOSTANDARD LVCMOS33} [get_ports {lcd_db[0]}]
set_property -dict {PACKAGE_PIN AA11 IOSTANDARD LVCMOS33} [get_ports {lcd_db[1]}]
set_property -dict {PACKAGE_PIN Y10  IOSTANDARD LVCMOS33} [get_ports {lcd_db[2]}]
set_property -dict {PACKAGE_PIN AA9  IOSTANDARD LVCMOS33} [get_ports {lcd_db[3]}]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS33} [get_ports {lcd_db[4]}]
set_property -dict {PACKAGE_PIN AB10 IOSTANDARD LVCMOS33} [get_ports {lcd_db[5]}]
set_property -dict {PACKAGE_PIN AB9  IOSTANDARD LVCMOS33} [get_ports {lcd_db[6]}]
set_property -dict {PACKAGE_PIN AA8  IOSTANDARD LVCMOS33} [get_ports {lcd_db[7]}]

## ---- LCD CONTROL on JB ----
set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS33} [get_ports lcd_rs]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports lcd_rw]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports lcd_e]

## ---- KEYPAD COLUMNS (inputs, pullups) ----
set_property -dict {PACKAGE_PIN AB6 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {col[0]}]
set_property -dict {PACKAGE_PIN AB7 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {col[1]}]
set_property -dict {PACKAGE_PIN AA4 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {col[2]}]
set_property -dict {PACKAGE_PIN Y4  IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {col[3]}]

## ---- KEYPAD ROWS (outputs) ----
set_property -dict {PACKAGE_PIN T6 IOSTANDARD LVCMOS33} [get_ports {row[0]}]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVCMOS33} [get_ports {row[1]}]
set_property -dict {PACKAGE_PIN U4 IOSTANDARD LVCMOS33} [get_ports {row[2]}]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD LVCMOS33} [get_ports {row[3]}]
## ---- DEBUG LED: mirrors lcd_e ----
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports led_e]