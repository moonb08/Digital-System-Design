`timescale 1ns / 1ps
//============================================================
// tb_kypd_scanner.v
// Drive the keypad scanner's `col` inputs in sync with `row`
// outputs to simulate physical key presses.
//============================================================
module tb_kypd_scanner;
    reg        clk = 0;
    reg        rst = 1;
    wire [3:0] row;
    reg  [3:0] col_drv = 4'b1111;
    wire [3:0] key_code;
    wire       key_valid;

    // Use small CLK_HZ so debounce ticks happen quickly
    kypd_scanner #(.CLK_HZ(100_000)) dut (
        .clk(clk), .rst(rst),
        .row(row), .col(col_drv),
        .key_code(key_code), .key_valid(key_valid)
    );

    always #5 clk = ~clk;   // 100 MHz

    // Simulate pressing a key:
    //   target_row 0..3 = which row in the matrix
    //   target_col_pattern = the col bit pattern when scanner drives that row
    //   (e.g. 4'b1110 means col[0] pulled low = leftmost column)
    task press_key(input [1:0] target_row, input [3:0] col_pattern);
        integer cycles;
        begin
            // Hold the key for long enough that the scanner sees it on
            // many row-scans. Each row scan is 1ms = 100 ticks at CLK_HZ=100k.
            // Debounce requires 20 stable row visits = ~80ms simulated.
            // So we hold for ~150ms simulated = 15000 cycles.
            for (cycles = 0; cycles < 15000; cycles = cycles + 1) begin
                @(negedge clk);
                // When scanner is driving the target row low, present the col pattern
                if (row == ~(4'b0001 << target_row))
                    col_drv = col_pattern;
                else
                    col_drv = 4'b1111;
            end
            // release
            col_drv = 4'b1111;
            // wait until "held" releases (one full row cycle = 4ms = 400 cycles)
            #4000000;
        end
    endtask

    reg [3:0] last_key;
    reg       saw_valid;
    integer   errors = 0;

    always @(posedge clk) begin
        if (key_valid) begin
            last_key  <= key_code;
            saw_valid <= 1'b1;
            $display("[%0t]  key_valid! code=0x%h", $time, key_code);
        end
    end

    task check_key(input [3:0] expected, input [255:0] label);
        begin
            saw_valid = 0;
            wait (saw_valid);
            @(posedge clk);
            if (last_key === expected)
                $display("PASS %0s: got 0x%h", label, last_key);
            else begin
                $display("FAIL %0s: got 0x%h, expected 0x%h",
                         label, last_key, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("kypd.vcd");
        $dumpvars(0, tb_kypd_scanner);
        #100; rst = 0;
        #100;

        // Press "1" -> row 0, col[0] low -> pattern 4'b1110, expect 0x1
        fork
            press_key(2'd0, 4'b1110);
            check_key(4'h1, "key_1");
        join

        // Press "5" -> row 1, col[1] low -> pattern 4'b1101, expect 0x5
        fork
            press_key(2'd1, 4'b1101);
            check_key(4'h5, "key_5");
        join

        // Press "0" -> row 3, col[0] low -> pattern 4'b1110, expect 0x0
        fork
            press_key(2'd3, 4'b1110);
            check_key(4'h0, "key_0");
        join

        // Press "A" -> row 0, col[3] low -> pattern 4'b0111, expect 0xA
        fork
            press_key(2'd0, 4'b0111);
            check_key(4'hA, "key_A");
        join

        // Press "E" -> row 3, col[2] low -> pattern 4'b1011, expect 0xE
        fork
            press_key(2'd3, 4'b1011);
            check_key(4'hE, "key_E");
        join

        if (errors == 0)
            $display("\n=== kypd_scanner: ALL TESTS PASSED ===");
        else
            $display("\n=== kypd_scanner: %0d FAILURES ===", errors);
        $finish;
    end
endmodule
