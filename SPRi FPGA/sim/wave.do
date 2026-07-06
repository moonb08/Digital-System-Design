onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group tb /tb_bg_subtraction/clk
add wave -noupdate -expand -group tb /tb_bg_subtraction/rst_n
add wave -noupdate -expand -group tb /tb_bg_subtraction/current_pixel
add wave -noupdate -expand -group tb /tb_bg_subtraction/ref_pixel
add wave -noupdate -expand -group tb /tb_bg_subtraction/valid_in
add wave -noupdate -expand -group tb /tb_bg_subtraction/diff_pixel
add wave -noupdate -expand -group tb /tb_bg_subtraction/valid_out
add wave -noupdate -expand -group tb /tb_bg_subtraction/ready_out
add wave -noupdate -expand -group tb /tb_bg_subtraction/overflow_flag
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/clk
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/rst_n
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/current_pixel
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/ref_pixel
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/valid_in
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/ready_out
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/diff_pixel
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/valid_out
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/overflow_flag
add wave -noupdate -expand -group dut /tb_bg_subtraction/dut/diff_raw
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {31563 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 301
configure wave -valuecolwidth 386
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {273918 ps}
