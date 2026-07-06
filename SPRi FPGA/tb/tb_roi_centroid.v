// ============================================================
//  Testbench : tb_roi_centroid
//  Tests the roi_centroid module with basic scenarios:
//    1.  Centred spike (e.g., at pixel 500)
//    2.  Uniform dip depth (all pixels equal)
//    3.  Division by zero guard (all zeros)
// ============================================================

`timescale 1ns / 1ps

module tb_roi_centroid;

    parameter PIXEL_WIDTH  = 12;
    parameter IMAGE_WIDTH  = 1280;
    parameter ADDR_WIDTH   = 11;
    parameter ACC_WIDTH    = 33;
    parameter DEN_WIDTH    = 23;
    parameter CLK_PERIOD   = 20;     // 50 MHz

    reg                      clk;
    reg                      rst_n;
    reg                      start;
    reg  [PIXEL_WIDTH-1:0]   dip_depth;
    reg                      valid_in;

    wire [ADDR_WIDTH-1:0]    p_min;
    wire                     done;
    wire                     busy;
    wire [ACC_WIDTH-1:0]     dbg_numerator;
    wire [DEN_WIDTH-1:0]     dbg_denominator;

    integer i;
    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    roi_centroid #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .DEN_WIDTH(DEN_WIDTH)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .dip_depth       (dip_depth),
        .valid_in        (valid_in),
        .p_min           (p_min),
        .done            (done),
        .busy            (busy),
        .dbg_numerator   (dbg_numerator),
        .dbg_denominator (dbg_denominator)
    );

    // Clock Gen
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("sim/tb_roi_centroid.vcd");
        $dumpvars(0, tb_roi_centroid);

        $display("========================================");
        $display("  ROI Centroid Testbench Starting");
        $display("========================================");

        // Reset
        rst_n     = 1'b0;
        start     = 1'b0;
        dip_depth = 12'd0;
        valid_in  = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // --------------------------------------------------
        // TEST 1: Single Spike at Pixel 500
        // Centroid must be exactly 500
        // --------------------------------------------------
        $display("\n--- Test 1: Single spike at pixel 500 ---");
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(posedge clk);
            #1;
            dip_depth = (i == 500) ? 12'd1000 : 12'd0;
            valid_in  = 1'b1;
        end
        
        @(posedge clk);
        #1;
        valid_in  = 1'b0;
        dip_depth = 12'd0;

        // Wait for done flag
        @(posedge clk);
        while (!done) begin
            @(posedge clk);
        end
        #1;

        if (p_min === 11'd500) begin
            $display("[PASS] Centroid correctly detected at %0d (expected 500)", p_min);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Centroid detected at %0d (expected 500)", p_min);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------
        // TEST 2: Division by Zero Guard (all zeros)
        // Centroid must default to 0
        // --------------------------------------------------
        $display("\n--- Test 2: Division by Zero Guard (all zeros) ---");
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(posedge clk);
            #1;
            dip_depth = 12'd0;
            valid_in  = 1'b1;
        end
        
        @(posedge clk);
        #1;
        valid_in  = 1'b0;

        // Wait for done flag
        @(posedge clk);
        while (!done) begin
            @(posedge clk);
        end
        #1;

        if (p_min === 11'd0) begin
            $display("[PASS] Centroid correctly defaulted to 0 on zero inputs");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Centroid detected at %0d (expected 0)", p_min);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------
        // TEST 3: Uniform weights (all pixels = 10)
        // Weighted centroid = (0+1+...+1279)/1280 = 639.5 -> truncated to 639
        // --------------------------------------------------
        $display("\n--- Test 3: Uniform dip depths (all pixels = 10) ---");
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(posedge clk);
            #1;
            dip_depth = 12'd10;
            valid_in  = 1'b1;
        end
        
        @(posedge clk);
        #1;
        valid_in  = 1'b0;

        // Wait for done flag
        @(posedge clk);
        while (!done) begin
            @(posedge clk);
        end
        #1;

        if (p_min === 11'd639 || p_min === 11'd640) begin
            $display("[PASS] Centroid correctly computed at %0d (expected ~639)", p_min);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Centroid detected at %0d (expected ~639)", p_min);
            fail_count = fail_count + 1;
        end

        $display("\n========================================");
        $display("  RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

    // Watchdog
    initial begin
        #300000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
