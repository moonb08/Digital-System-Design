`timescale 1ns / 1ps

module tb_fwhm_calc;

    parameter PIXEL_WIDTH = 12;
    parameter IMAGE_WIDTH = 1280;
    parameter ADDR_WIDTH  = 11;
    parameter CLK_PERIOD  = 20;     // 50 MHz

    reg                      clk;
    reg                      rst_n;
    reg                      start;
    reg  [PIXEL_WIDTH-1:0]   dip_depth;
    reg                      valid_in;

    wire [ADDR_WIDTH-1:0]    fwhm;
    wire [ADDR_WIDTH-1:0]    fwhm_center;
    wire                     done;
    wire                     busy;
    wire [PIXEL_WIDTH-1:0]   dbg_max_depth;
    wire [ADDR_WIDTH-1:0]    dbg_left_edge;
    wire [ADDR_WIDTH-1:0]    dbg_right_edge;

    // Instantiate the Unit Under Test (UUT)
    fwhm_calc #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .dip_depth(dip_depth),
        .valid_in(valid_in),
        .fwhm(fwhm),
        .fwhm_center(fwhm_center),
        .done(done),
        .busy(busy),
        .dbg_max_depth(dbg_max_depth),
        .dbg_left_edge(dbg_left_edge),
        .dbg_right_edge(dbg_right_edge)
    );

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    integer i;
    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        // Initialize Inputs
        clk       = 0;
        rst_n     = 0;
        start     = 0;
        dip_depth = 0;
        valid_in  = 0;

        $display("\n========================================");
        $display("  FWHM Calculator Testbench Starting");
        $display("  Sensor Size: %0d pixels", IMAGE_WIDTH);
        $display("========================================");

        // Reset
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        // --------------------------------------------------
        // TEST 1: Triangular Dip
        // Peak at 500 (value 1000). Ramps up from 400, down to 600.
        // Half-max = 500. Crosses at 450 (left) and 550 (right).
        // Expected FWHM = 550 - 450 + 1 = 101.
        // --------------------------------------------------
        $display("\n--- Test 1: Triangular Dip ---");
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(posedge clk);
            #1;
            if (i >= 400 && i <= 500)
                dip_depth = (i - 400) * 10;
            else if (i > 500 && i <= 600)
                dip_depth = 1000 - ((i - 500) * 10);
            else
                dip_depth = 0;
                
            valid_in = 1'b1;
        end
        
        @(posedge clk);
        #1;
        valid_in  = 1'b0;
        dip_depth = 0;

        // Wait for done flag
        @(posedge clk);
        while (!done) begin
            @(posedge clk);
        end
        #1;

        $display("  Max depth detected: %0d (Expected: 1000)", dbg_max_depth);
        $display("  Left edge:  %0d (Expected: 450)", dbg_left_edge);
        $display("  Right edge: %0d (Expected: 550)", dbg_right_edge);

        if (fwhm === 11'd101 && fwhm_center === 11'd500) begin
            $display("[PASS] FWHM correctly computed at %0d, center at %0d (Expected: 101, 500)", fwhm, fwhm_center);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] FWHM computed at %0d, center at %0d (Expected: 101, 500)", fwhm, fwhm_center);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------
        // TEST 2: Rectangular pulse
        // Peak at 1000 from pixel 800 to 850.
        // Left = 800, Right = 850.
        // Expected FWHM = 850 - 800 + 1 = 51.
        // --------------------------------------------------
        $display("\n--- Test 2: Rectangular Pulse ---");
        #(CLK_PERIOD * 10);
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(posedge clk);
            #1;
            if (i >= 800 && i <= 850)
                dip_depth = 1000;
            else
                dip_depth = 0;
                
            valid_in = 1'b1;
        end
        
        @(posedge clk);
        #1;
        valid_in  = 1'b0;
        dip_depth = 0;

        // Wait for done flag
        @(posedge clk);
        while (!done) begin
            @(posedge clk);
        end
        #1;

        if (fwhm === 11'd51 && fwhm_center === 11'd825) begin
            $display("[PASS] FWHM correctly computed at %0d, center at %0d (Expected: 51, 825)", fwhm, fwhm_center);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] FWHM computed at %0d, center at %0d (Expected: 51, 825)", fwhm, fwhm_center);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------
        // TEST 3: Flat Baseline (No Dip)
        // All pixels 0. FWHM should be 0.
        // --------------------------------------------------
        $display("\n--- Test 3: Flat Baseline (No Dip) ---");
        #(CLK_PERIOD * 10);
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(posedge clk);
            #1;
            dip_depth = 0;
            valid_in = 1'b1;
        end
        
        @(posedge clk);
        #1;
        valid_in  = 1'b0;
        dip_depth = 0;

        // Wait for done flag
        @(posedge clk);
        while (!done) begin
            @(posedge clk);
        end
        #1;

        if (fwhm === 11'd0 && fwhm_center === 11'd0) begin
            $display("[PASS] FWHM correctly computed as 0 on flat baseline.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] FWHM computed as %0d, center %0d (Expected: 0, 0)", fwhm, fwhm_center);
            fail_count = fail_count + 1;
        end

        $display("\n========================================");
        $display("  RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

    // Watchdog
    initial begin
        #500000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
