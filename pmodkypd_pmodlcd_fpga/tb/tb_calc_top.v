`timescale 1ns / 1ps
//============================================================
// tb_calc_top.v
// Integration test for the full calculator.
// Simulates keypresses, captures bytes emitted to the LCD,
// verifies the expected ASCII characters appear.
//============================================================
module tb_calc_top;
    reg        clk = 0;
    reg        rst = 1;
    wire [3:0] row;
    reg  [3:0] col_drv = 4'b1111;
    wire       lcd_rs, lcd_rw, lcd_e;
    wire [7:0] lcd_db;

    calc_top #(.CLK_HZ(100_000)) dut (
        .clk(clk), .rst(rst),
        .row(row), .col(col_drv),
        .lcd_rs(lcd_rs), .lcd_rw(lcd_rw),
        .lcd_e(lcd_e), .lcd_db(lcd_db)
    );

    always #5 clk = ~clk;

    // Capture LCD bytes
    reg [7:0] lcd_log [0:511];
    reg [8:0] lcd_n = 0;
    always @(negedge lcd_e) begin
        if (!rst) begin
            lcd_log[lcd_n] = lcd_db;
            lcd_n = lcd_n + 1;
        end
    end

    // Press a key: pattern is the col value when its row is being scanned
    task press_key(input [1:0] target_row, input [3:0] col_pattern);
        integer cycles;
        begin
            for (cycles = 0; cycles < 4000; cycles = cycles + 1) begin
                @(negedge clk);
                if (row == ~(4'b0001 << target_row))
                    col_drv = col_pattern;
                else
                    col_drv = 4'b1111;
            end
            col_drv = 4'b1111;
            // wait for key release + a few row cycles
            #2000000;
        end
    endtask

    // Convenience tasks per key
    task press_0; press_key(2'd3, 4'b1110); endtask
    task press_1; press_key(2'd0, 4'b1110); endtask
    task press_2; press_key(2'd0, 4'b1101); endtask
    task press_3; press_key(2'd0, 4'b1011); endtask
    task press_4; press_key(2'd1, 4'b1110); endtask
    task press_5; press_key(2'd1, 4'b1101); endtask
    task press_6; press_key(2'd1, 4'b1011); endtask
    task press_7; press_key(2'd2, 4'b1110); endtask
    task press_8; press_key(2'd2, 4'b1101); endtask
    task press_9; press_key(2'd2, 4'b1011); endtask
    task press_plus;  press_key(2'd0, 4'b0111); endtask  // A
    task press_minus; press_key(2'd1, 4'b0111); endtask  // B
    task press_mul;   press_key(2'd2, 4'b0111); endtask  // C
    task press_div;   press_key(2'd3, 4'b0111); endtask  // D
    task press_eq;    press_key(2'd3, 4'b1011); endtask  // E
    task press_clr;   press_key(2'd3, 4'b1101); endtask  // F

    // Search the LCD log starting from `start_idx` for a substring of ASCII
    function integer find_substring(input integer start_idx,
                                    input [127:0] needle, input integer nlen);
        integer i, j, ok;
        begin
            find_substring = -1;
            for (i = start_idx; i <= lcd_n - nlen; i = i + 1) begin
                ok = 1;
                for (j = 0; j < nlen; j = j + 1) begin
                    if (lcd_log[i+j] !== needle[(nlen-1-j)*8 +: 8])
                        ok = 0;
                end
                if (ok) begin
                    find_substring = i;
                    i = lcd_n;  // break
                end
            end
        end
    endfunction

    integer errors = 0;
    integer start_idx;
    integer found;

    task check_contains(input integer from, input [127:0] needle,
                        input integer nlen, input [255:0] label);
        begin
            found = find_substring(from, needle, nlen);
            if (found >= 0)
                $display("PASS %0s: found at idx %0d", label, found);
            else begin
                $display("FAIL %0s: NOT found after idx %0d", label, from);
                errors = errors + 1;
            end
        end
    endtask

    task dump_log;
        integer i;
        begin
            $write("LCD log: ");
            for (i = 0; i < lcd_n; i = i + 1) begin
                if (lcd_log[i] >= 8'h20 && lcd_log[i] < 8'h7F)
                    $write("%c", lcd_log[i]);
                else
                    $write("[%02h]", lcd_log[i]);
            end
            $write("\n");
        end
    endtask

    initial begin
        $dumpfile("calc.vcd");
        $dumpvars(0, tb_calc_top);
        #200; rst = 0;

        // wait for LCD init
        wait (dut.u_lcd.wr_ready == 1);
        #5000;
        start_idx = lcd_n;

        // Test 1: 12 + 34 = 46
        $display("\n--- Test 1: 12 + 34 = 46 ---");
        press_1; press_2; press_plus; press_3; press_4; press_eq;
        #5000000;
        dump_log;
        check_contains(start_idx, {"= 46"}, 4, "12+34=46");

        start_idx = lcd_n;
        press_clr;
        #2000000;

        // Test 2: 9 * 9 = 81
        $display("\n--- Test 2: 9 * 9 = 81 ---");
        press_9; press_mul; press_9; press_eq;
        #5000000;
        dump_log;
        check_contains(start_idx, {"= 81"}, 4, "9*9=81");

        start_idx = lcd_n;
        press_clr;
        #2000000;

        // Test 3: 7 - 3 = 4
        $display("\n--- Test 3: 7 - 3 = 4 ---");
        press_7; press_minus; press_3; press_eq;
        #5000000;
        dump_log;
        check_contains(start_idx, {"= 4"}, 3, "7-3=4");

        start_idx = lcd_n;
        press_clr;
        #2000000;

        // Test 4: 8 / 2 = 4
        $display("\n--- Test 4: 8 / 2 = 4 ---");
        press_8; press_div; press_2; press_eq;
        #5000000;
        dump_log;
        check_contains(start_idx, {"= 4"}, 3, "8/2=4");

        start_idx = lcd_n;
        press_clr;
        #2000000;

        // Test 5: 5 / 0 should show ERR
        $display("\n--- Test 5: 5 / 0 = ERR ---");
        press_5; press_div; press_0; press_eq;
        #5000000;
        dump_log;
        check_contains(start_idx, {"ERR"}, 3, "5/0=ERR");

        if (errors == 0)
            $display("\n=== calc_top: ALL TESTS PASSED ===");
        else
            $display("\n=== calc_top: %0d FAILURES ===", errors);
        $finish;
    end

    // Watchdog
    initial begin
        #200000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
