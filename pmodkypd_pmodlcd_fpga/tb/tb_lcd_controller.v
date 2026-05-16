`timescale 1ns / 1ps
//============================================================
// tb_lcd_controller.v
// Verify the LCD controller emits the correct HD44780 init
// sequence and accepts data writes correctly.
//============================================================
module tb_lcd_controller;
    reg        clk = 0;
    reg        rst = 1;
    reg        wr_req = 0;
    reg        wr_rs = 0;
    reg  [7:0] wr_data = 0;
    wire       wr_ready;
    wire       lcd_rs, lcd_rw, lcd_e;
    wire [7:0] lcd_db;

    // Tiny CLK_HZ so init delays simulate quickly
    lcd_controller #(.CLK_HZ(100_000)) dut (
        .clk(clk), .rst(rst),
        .wr_req(wr_req), .wr_rs(wr_rs), .wr_data(wr_data),
        .wr_ready(wr_ready),
        .lcd_rs(lcd_rs), .lcd_rw(lcd_rw),
        .lcd_e(lcd_e), .lcd_db(lcd_db)
    );

    always #5 clk = ~clk;

    // Capture every byte the LCD sees on the falling edge of E.
    // Ignore captures during reset.
    reg [7:0] captured [0:31];
    reg       captured_rs [0:31];
    integer   cap_n = 0;

    always @(negedge lcd_e) begin
        if (!rst) begin
            captured[cap_n]    = lcd_db;
            captured_rs[cap_n] = lcd_rs;
            $display("[%0t]  byte#%0d  RS=%b  DB=0x%02h ('%c')",
                     $time, cap_n, lcd_rs, lcd_db,
                     (lcd_db >= 8'h20 && lcd_db < 8'h7F) ? lcd_db : ".");
            cap_n = cap_n + 1;
        end
    end

    integer errors = 0;
    task expect_byte(input integer idx, input rs_exp, input [7:0] db_exp,
                     input [127:0] label);
        begin
            if (captured[idx] !== db_exp || captured_rs[idx] !== rs_exp) begin
                $display("FAIL %0s: byte#%0d got RS=%b DB=0x%02h, expected RS=%b DB=0x%02h",
                          label, idx, captured_rs[idx], captured[idx], rs_exp, db_exp);
                errors = errors + 1;
            end else begin
                $display("PASS %0s: byte#%0d RS=%b DB=0x%02h",
                          label, idx, rs_exp, db_exp);
            end
        end
    endtask

    initial begin
        $dumpfile("lcd.vcd");
        $dumpvars(0, tb_lcd_controller);
        #200; rst = 0;

        // wait for init
        wait (wr_ready == 1);
        #1000;

        // Verify the 8 init bytes
        expect_byte(0, 1'b0, 8'h30, "wakeup1");
        expect_byte(1, 1'b0, 8'h30, "wakeup2");
        expect_byte(2, 1'b0, 8'h30, "wakeup3");
        expect_byte(3, 1'b0, 8'h38, "func_set");
        expect_byte(4, 1'b0, 8'h08, "disp_off");
        expect_byte(5, 1'b0, 8'h01, "clear");
        expect_byte(6, 1'b0, 8'h06, "entry");
        expect_byte(7, 1'b0, 8'h0C, "disp_on");

        // Send 'H'
        @(negedge clk);
        wr_rs   = 1; wr_data = "H"; wr_req = 1;
        @(negedge clk); wr_req = 0;
        wait (wr_ready == 0);
        wait (wr_ready == 1);

        expect_byte(8, 1'b1, "H", "char_H");

        // Send 'i'
        @(negedge clk);
        wr_rs   = 1; wr_data = "i"; wr_req = 1;
        @(negedge clk); wr_req = 0;
        wait (wr_ready == 0);
        wait (wr_ready == 1);

        expect_byte(9, 1'b1, "i", "char_i");

        if (errors == 0)
            $display("\n=== lcd_controller: ALL TESTS PASSED ===");
        else
            $display("\n=== lcd_controller: %0d FAILURES ===", errors);

        #500;
        $finish;
    end
endmodule
