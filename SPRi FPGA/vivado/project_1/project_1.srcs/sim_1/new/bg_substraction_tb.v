// ============================================================
//  Testbench : tb_bg_subtraction
//  Tests the bg_subtraction module with 10 scenarios:
//    1.  Normal subtraction    (current > ref)
//    2.  Zero difference       (current == ref)
//    3.  Negative clamp        (current < ref)  → output must be 0
//    4.  SPR dip simulation    (realistic pixel sweep with dip)
//    5.  Extreme corners       (all 4 corner combos of 0 and 4095)
//    6.  Boundary ±1           (transitions around 0 and 4095)
//    7.  Minimal differences   (diff = +1 and diff = -1)
//    8.  Max range             (full-scale difference)
//    9.  Back-to-back stream   (continuous valid_in, no gaps)
//   10.  Reset during active   (rst_n asserted mid-transfer)
// ============================================================

`timescale 1ns / 1ps

module tb_bg_subtraction;

// ============================================================
// Parameters
// ============================================================
    parameter PIXEL_WIDTH = 12;
    parameter CLK_PERIOD  = 20;     // 50 MHz clock (20ns period)
    parameter IMAGE_WIDTH = 1024;

// ============================================================
// DUT Signals
// ============================================================
    reg                      clk;
    reg                      rst_n;
    reg  [PIXEL_WIDTH-1:0]   current_pixel;
    reg  [PIXEL_WIDTH-1:0]   ref_pixel;
    reg                      valid_in;

    wire [PIXEL_WIDTH-1:0]   diff_pixel;
    wire                     valid_out;
    wire                     ready_out;
    wire                     overflow_flag;

// ============================================================
// Test tracking
// ============================================================
    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

// ============================================================
// DUT Instantiation
// ============================================================
    bg_subtraction #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .current_pixel (current_pixel),
        .ref_pixel     (ref_pixel),
        .valid_in      (valid_in),
        .ready_out     (ready_out),
        .diff_pixel    (diff_pixel),
        .valid_out     (valid_out),
        .overflow_flag (overflow_flag)
    );

// ============================================================
// Clock Generation: 50 MHz
// ============================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================
// Task: Apply one pixel and check result
// ============================================================
    task apply_pixel;
        input [PIXEL_WIDTH-1:0] curr;
        input [PIXEL_WIDTH-1:0] ref;
        input [PIXEL_WIDTH-1:0] expected;
        input [63:0]            test_id;
        reg   [PIXEL_WIDTH-1:0] exp_clamped;
        begin
            // Expected = max(curr - ref, 0)
            exp_clamped = (curr >= ref) ? (curr - ref) : 0;

            @(posedge clk);
            #1;                         // small delay after edge
            current_pixel = curr;
            ref_pixel     = ref;
            valid_in      = 1'b1;

            @(posedge clk);             // DUT latches input here
            #1;
            valid_in = 1'b0;            // deassert after latch

            // diff_pixel and valid_out are now available (1-cycle latency)
            if (valid_out && diff_pixel === exp_clamped) begin
                $display("[PASS] Test %0d: curr=%0d ref=%0d | diff=%0d (expected=%0d)",
                          test_id, curr, ref, diff_pixel, exp_clamped);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: curr=%0d ref=%0d | diff=%0d (expected=%0d) valid_out=%b",
                          test_id, curr, ref, diff_pixel, exp_clamped, valid_out);
                fail_count = fail_count + 1;
            end
        end
    endtask

// ============================================================
// Main Test Sequence
// ============================================================
    initial begin
        // Waveform dump for GTKWave / Vivado XSim
        $dumpfile("sim/tb_bg_subtraction.vcd");
        $dumpvars(0, tb_bg_subtraction);

        $display("========================================");
        $display("  BG Subtraction Testbench Starting");
        $display("========================================");

        // Reset
        rst_n         = 1'b0;
        current_pixel = 12'd0;
        ref_pixel     = 12'd0;
        valid_in      = 1'b0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // --------------------------------------------------
        // TEST 1: Normal subtraction (current > ref)
        // --------------------------------------------------
        $display("\n--- Test 1: Normal subtraction ---");
        apply_pixel(12'd3000, 12'd1000, 12'd2000, 1);   // expect 2000
        apply_pixel(12'd4095, 12'd100,  12'd3995, 2);   // expect 3995
        apply_pixel(12'd500,  12'd200,  12'd300,  3);   // expect 300

        // --------------------------------------------------
        // TEST 2: Zero difference
        // --------------------------------------------------
        $display("\n--- Test 2: Zero difference ---");
        apply_pixel(12'd2048, 12'd2048, 12'd0, 4);      // expect 0
        apply_pixel(12'd0,    12'd0,    12'd0, 5);      // expect 0

        // --------------------------------------------------
        // TEST 3: Negative clamp (current < ref → output = 0)
        // --------------------------------------------------
        $display("\n--- Test 3: Negative clamp (rectification) ---");
        apply_pixel(12'd100,  12'd500,  12'd0, 6);      // expect 0
        apply_pixel(12'd0,    12'd4095, 12'd0, 7);      // expect 0
        apply_pixel(12'd1000, 12'd1001, 12'd0, 8);      // expect 0

        // --------------------------------------------------
        // TEST 4: SPR Dip Simulation
        // Simulate a 64-pixel window of an SPR curve
        // Reference = flat baseline (2000 counts)
        // Sample    = SPR dip centered at pixel 32 (Gaussian-like)
        // --------------------------------------------------
        $display("\n--- Test 4: SPR Dip Simulation (64 pixels) ---");
        $display("  Reference = 2000 (flat baseline)");
        $display("  Sample    = Gaussian dip centered at pixel 32");
        $display("  Pixel | Curr | Ref  | Diff");

        begin : spr_sim
            integer pix;
            integer curr_val;
            integer ref_val;
            integer diff_val;
            integer dist;

            for (pix = 0; pix < 64; pix = pix + 1) begin
                ref_val  = 2000;

                // Simple Gaussian approximation: dip at pixel 32
                // depth = 1500 counts, width = 10 pixels
                dist = pix - 32;
                if (dist < 0) dist = -dist; // abs value

                if      (dist == 0)  curr_val = 500;
                else if (dist <= 2)  curr_val = 700;
                else if (dist <= 4)  curr_val = 1000;
                else if (dist <= 6)  curr_val = 1400;
                else if (dist <= 8)  curr_val = 1700;
                else if (dist <= 10) curr_val = 1900;
                else                 curr_val = 2000;

                diff_val = curr_val - ref_val;
                if (diff_val < 0) diff_val = 0;

                @(posedge clk);
                current_pixel = curr_val[PIXEL_WIDTH-1:0];
                ref_pixel     = ref_val[PIXEL_WIDTH-1:0];
                valid_in      = 1'b1;

                @(posedge clk);
                valid_in = 1'b0;
                #1;

                $display("  p=%02d  | %04d | %04d | %04d  overflow=%b",
                          pix, curr_val, ref_val, diff_pixel, overflow_flag);
            end
        end

        // --------------------------------------------------
        // TEST 5: Extreme Corners
        // All 4 combinations of min (0) and max (4095) inputs
        // --------------------------------------------------
        $display("\n--- Test 5: Extreme corners (0 and 4095) ---");
        apply_pixel(12'd0,    12'd0,    12'd0,    9);    // 0 - 0    = 0
        apply_pixel(12'd0,    12'd4095, 12'd0,    10);   // 0 - 4095 = clamp 0
        apply_pixel(12'd4095, 12'd0,    12'd4095, 11);   // 4095 - 0 = 4095
        apply_pixel(12'd4095, 12'd4095, 12'd0,    12);   // 4095 - 4095 = 0

        // --------------------------------------------------
        // TEST 6: Boundary ±1 Transitions
        // Values at and around the edges of the 12-bit range
        // --------------------------------------------------
        $display("\n--- Test 6: Boundary +/-1 transitions ---");
        apply_pixel(12'd1,    12'd0,    12'd1,    13);   // 1 - 0    = 1
        apply_pixel(12'd0,    12'd1,    12'd0,    14);   // 0 - 1    = clamp 0
        apply_pixel(12'd4095, 12'd4094, 12'd1,    15);   // 4095 - 4094 = 1
        apply_pixel(12'd4094, 12'd4095, 12'd0,    16);   // 4094 - 4095 = clamp 0
        apply_pixel(12'd1,    12'd1,    12'd0,    17);   // 1 - 1    = 0
        apply_pixel(12'd4094, 12'd4094, 12'd0,    18);   // 4094 - 4094 = 0

        // --------------------------------------------------
        // TEST 7: Minimal Differences (diff = +1, -1)
        // Verify single-LSB sensitivity across the range
        // --------------------------------------------------
        $display("\n--- Test 7: Minimal differences (single-LSB) ---");
        apply_pixel(12'd2,    12'd1,    12'd1,    19);   // mid-low:  2 - 1 = 1
        apply_pixel(12'd1,    12'd2,    12'd0,    20);   // mid-low:  1 - 2 = clamp 0
        apply_pixel(12'd2048, 12'd2047, 12'd1,    21);   // mid:      2048 - 2047 = 1
        apply_pixel(12'd2047, 12'd2048, 12'd0,    22);   // mid:      2047 - 2048 = clamp 0
        apply_pixel(12'd100,  12'd99,   12'd1,    23);   // low:      100 - 99 = 1
        apply_pixel(12'd99,   12'd100,  12'd0,    24);   // low:      99 - 100 = clamp 0
        apply_pixel(12'd3500, 12'd3499, 12'd1,    25);   // high:     3500 - 3499 = 1
        apply_pixel(12'd3499, 12'd3500, 12'd0,    26);   // high:     3499 - 3500 = clamp 0

        // --------------------------------------------------
        // TEST 8: Max Range (full-scale difference)
        // Largest possible positive and negative differences
        // --------------------------------------------------
        $display("\n--- Test 8: Max range differences ---");
        apply_pixel(12'd4095, 12'd0,    12'd4095, 27);   // max positive: 4095
        apply_pixel(12'd0,    12'd4095, 12'd0,    28);   // max negative: clamp 0
        apply_pixel(12'd4095, 12'd1,    12'd4094, 29);   // near-max positive: 4094
        apply_pixel(12'd1,    12'd4095, 12'd0,    30);   // near-max negative: clamp 0
        // Half-scale differences
        apply_pixel(12'd3072, 12'd1024, 12'd2048, 31);   // 3072 - 1024 = 2048
        apply_pixel(12'd1024, 12'd3072, 12'd0,    32);   // 1024 - 3072 = clamp 0

        // --------------------------------------------------
        // TEST 9: Back-to-Back Streaming
        // Continuous valid_in=1 for 16 pixels (no gaps)
        // This tests the pipeline under realistic throughput
        // --------------------------------------------------
        $display("\n--- Test 9: Back-to-back streaming (16 pixels) ---");
        begin : stream_test
            integer s;
            reg [PIXEL_WIDTH-1:0] stream_curr [0:15];
            reg [PIXEL_WIDTH-1:0] stream_ref  [0:15];
            reg [PIXEL_WIDTH-1:0] stream_exp  [0:15];
            reg [PIXEL_WIDTH-1:0] captured     [0:15];
            integer cap_idx;
            integer stream_pass;
            integer stream_fail;

            // Initialize test vectors: ramp with varying reference
            stream_curr[0]  = 12'd100;   stream_ref[0]  = 12'd50;
            stream_curr[1]  = 12'd200;   stream_ref[1]  = 12'd200;
            stream_curr[2]  = 12'd300;   stream_ref[2]  = 12'd400;
            stream_curr[3]  = 12'd4095;  stream_ref[3]  = 12'd0;
            stream_curr[4]  = 12'd0;     stream_ref[4]  = 12'd4095;
            stream_curr[5]  = 12'd2048;  stream_ref[5]  = 12'd2048;
            stream_curr[6]  = 12'd1000;  stream_ref[6]  = 12'd999;
            stream_curr[7]  = 12'd999;   stream_ref[7]  = 12'd1000;
            stream_curr[8]  = 12'd3000;  stream_ref[8]  = 12'd1500;
            stream_curr[9]  = 12'd1500;  stream_ref[9]  = 12'd3000;
            stream_curr[10] = 12'd1;     stream_ref[10] = 12'd0;
            stream_curr[11] = 12'd0;     stream_ref[11] = 12'd1;
            stream_curr[12] = 12'd4094;  stream_ref[12] = 12'd4095;
            stream_curr[13] = 12'd4095;  stream_ref[13] = 12'd4094;
            stream_curr[14] = 12'd2500;  stream_ref[14] = 12'd2500;
            stream_curr[15] = 12'd750;   stream_ref[15] = 12'd250;

            // Precompute expected values
            for (s = 0; s < 16; s = s + 1) begin
                stream_exp[s] = (stream_curr[s] >= stream_ref[s]) ?
                                (stream_curr[s] - stream_ref[s]) : 12'd0;
            end

            // Drive all 16 pixels back-to-back (valid_in=1 continuously)
            for (s = 0; s < 16; s = s + 1) begin
                @(posedge clk);
                #1;
                current_pixel = stream_curr[s];
                ref_pixel     = stream_ref[s];
                valid_in      = 1'b1;
            end

            // Deassert valid_in after last pixel
            @(posedge clk);
            #1;
            valid_in = 1'b0;

            // Wait for pipeline to flush (1 cycle latency + margin)
            @(posedge clk); #1;
            @(posedge clk); #1;

            // Capture outputs: since the DUT has 1-cycle data latency,
            // diff_pixel updates 1 cycle after each input.
            // For back-to-back, we need to re-drive and capture cycle-by-cycle.
            // Re-run with capture:
            $display("  Re-running stream with cycle-by-cycle capture...");

            cap_idx = 0;
            stream_pass = 0;
            stream_fail = 0;

            // Drive again, this time capturing outputs
            for (s = 0; s < 16; s = s + 1) begin
                @(posedge clk);
                #1;
                current_pixel = stream_curr[s];
                ref_pixel     = stream_ref[s];
                valid_in      = 1'b1;

                // After 1st cycle, previous pixel's result is available
                if (s > 0) begin
                    captured[s-1] = diff_pixel;
                end
            end

            // Capture last pixel's result
            @(posedge clk); #1;
            valid_in = 1'b0;
            captured[15] = diff_pixel;

            // Verify all captured results
            for (s = 0; s < 16; s = s + 1) begin
                if (captured[s] === stream_exp[s]) begin
                    $display("  [PASS] Stream[%02d]: curr=%04d ref=%04d | diff=%04d (exp=%04d)",
                              s, stream_curr[s], stream_ref[s], captured[s], stream_exp[s]);
                    pass_count  = pass_count + 1;
                    stream_pass = stream_pass + 1;
                end else begin
                    $display("  [FAIL] Stream[%02d]: curr=%04d ref=%04d | diff=%04d (exp=%04d)",
                              s, stream_curr[s], stream_ref[s], captured[s], stream_exp[s]);
                    fail_count  = fail_count + 1;
                    stream_fail = stream_fail + 1;
                end
            end
            $display("  Stream result: %0d passed, %0d failed", stream_pass, stream_fail);
        end

        // --------------------------------------------------
        // TEST 10: Reset During Active Operation
        // Assert reset while pipeline has valid data in-flight
        // Verify all outputs return to zero
        // --------------------------------------------------
        $display("\n--- Test 10: Reset during active operation ---");
        begin : reset_test
            reg test10_pass;
            test10_pass = 1'b1;

            // Start a valid transfer
            @(posedge clk); #1;
            current_pixel = 12'd3000;
            ref_pixel     = 12'd1000;
            valid_in      = 1'b1;

            @(posedge clk); #1;
            // Data is now latched in pipeline, assert reset
            rst_n = 1'b0;
            valid_in = 1'b0;

            // Hold reset for 2 cycles
            repeat(2) @(posedge clk);
            #1;

            // Check outputs are cleared
            if (diff_pixel !== {PIXEL_WIDTH{1'b0}}) begin
                $display("  [FAIL] Reset: diff_pixel=%0d (expected 0)", diff_pixel);
                test10_pass = 1'b0;
            end
            if (valid_out !== 1'b0) begin
                $display("  [FAIL] Reset: valid_out=%b (expected 0)", valid_out);
                test10_pass = 1'b0;
            end
            if (overflow_flag !== 1'b0) begin
                $display("  [FAIL] Reset: overflow_flag=%b (expected 0)", overflow_flag);
                test10_pass = 1'b0;
            end

            if (test10_pass) begin
                $display("  [PASS] Reset clears all outputs correctly");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end

            // Release reset and verify module resumes correctly
            rst_n = 1'b1;
            @(posedge clk); #1;

            // Run a simple pixel after reset recovery
            $display("  Verifying post-reset operation...");
            apply_pixel(12'd2000, 12'd500, 12'd1500, 33);  // should work normally
        end

        // --------------------------------------------------
        // Results Summary
        // --------------------------------------------------
        $display("\n========================================");
        $display("  RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");

        if (fail_count == 0)
            $display("  ALL TESTS PASSED - Ready for ROI module");
        else
            $display("  FAILURES DETECTED - Fix before proceeding");

        $display("========================================\n");
        $finish;
    end

    // Timeout watchdog (increased for larger test suite)
    initial begin
        #200000;
        $display("[TIMEOUT] Simulation exceeded limit");
        $finish;
    end

endmodule

