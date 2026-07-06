// ============================================================
//  Testbench : tb_spr_pipeline
//  Tests the full SPR processing pipeline (Stage 1 + Stage 2):
//    1. Instantiates spr_pipeline.v
//    2. Generates a realistic Gaussian SPR dip (centered at pixel 512)
//    3. Streams the pixels into the background subtraction block
//    4. Feeds the resulting dip depths to the centroid accumulator
//    5. Monitors the sequential divider and verifies the final p_min output.
// ============================================================

`timescale 1ns / 1ps

module tb_spr_pipeline;

    parameter PIXEL_WIDTH  = 12;
    parameter IMAGE_WIDTH  = 1280;
    parameter ADDR_WIDTH   = 11;
    parameter ACC_WIDTH    = 33;
    parameter DEN_WIDTH    = 23;
    parameter CLK_PERIOD   = 20;     // 50 MHz

    reg                      clk;
    reg                      rst_n;
    reg                      start_frame;
    reg  [PIXEL_WIDTH-1:0]   current_pixel;
    reg  [PIXEL_WIDTH-1:0]   ref_pixel;
    reg                      valid_in;

    wire [ADDR_WIDTH-1:0]    p_min;
    wire                     done;
    wire                     busy;

    wire [PIXEL_WIDTH-1:0]   diff_pixel;
    wire                     valid_out_pixel;
    wire                     overflow_flag;
    wire [ACC_WIDTH-1:0]     dbg_numerator;
    wire [DEN_WIDTH-1:0]     dbg_denominator;

    integer i;
    real    dist, val;
    integer curr_val;
    integer ref_val;

    // Instantiate Full Pipeline DUT
    spr_pipeline #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .DEN_WIDTH(DEN_WIDTH)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_frame     (start_frame),
        .current_pixel   (current_pixel),
        .ref_pixel       (ref_pixel),
        .valid_in        (valid_in),
        .ready_out       (), // unconnected
        .p_min           (p_min),
        .done            (done),
        .busy            (busy),
        .diff_pixel      (diff_pixel),
        .valid_out_pixel (valid_out_pixel),
        .overflow_flag   (overflow_flag),
        .dbg_numerator   (dbg_numerator),
        .dbg_denominator (dbg_denominator)
    );

    // Clock Gen
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("sim/tb_spr_pipeline.vcd");
        $dumpvars(0, tb_spr_pipeline);

        $display("========================================");
        $display("  Full SPR Pipeline Testbench Starting");
        $display("  Sensor Size: %0d pixels | ADC: %0d-bit", IMAGE_WIDTH, PIXEL_WIDTH);
        $display("========================================");

        // Reset
        rst_n       = 1'b0;
        start_frame = 1'b0;
        current_pixel = 12'd0;
        ref_pixel     = 12'd0;
        valid_in      = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // --------------------------------------------------
        // TEST: Gaussian Dip centred at pixel 512
        // Baseline = 2800 counts, depth = 2000 counts, sigma = 40
        // --------------------------------------------------
        $display("\n--- Starting SPR Frame Simulation ---");
        $display("  Simulating Gaussian dip at pixel 512...");

        @(posedge clk);
        start_frame = 1'b1;
        @(posedge clk);
        start_frame = 1'b0;

        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            // Baseline reference is flat at 2800 counts
            ref_val = 2800;

            // Generate Gaussian dip
            dist = i - 512;
            val = 2800.0 - 2000.0 * $exp(-0.5 * (dist / 40.0) * (dist / 40.0));
            curr_val = $rtoi(val);

            // Clip outputs to valid 12-bit ADC range
            if (curr_val < 0) curr_val = 0;
            if (curr_val > 4095) curr_val = 4095;

            @(posedge clk);
            #1;
            current_pixel = curr_val[PIXEL_WIDTH-1:0];
            ref_pixel     = ref_val[PIXEL_WIDTH-1:0];
            valid_in      = 1'b1;

            // Display a few samples around the dip center for logging
            if (i >= 508 && i <= 516) begin
                $display("  Pixel %0d: sample=%0d, ref=%0d, diff=%0d, overflow=%b (latency corrected)", 
                         i-1, current_pixel, ref_pixel, diff_pixel, overflow_flag);
            end
        end

        @(posedge clk);
        #1;
        valid_in      = 1'b0;
        current_pixel = 12'd0;
        ref_pixel     = 12'd0;

        $display("  Frame streamed in. Waiting for division & centroid completion...");

        // Wait for Done
        @(posedge clk);
        while (!done) begin
            @(posedge clk);
        end
        #1;

        $display("\n========================================");
        $display("  Pipeline Execution Completed");
        $display("  RTL Centroid p_min: %0d", p_min);
        $display("  Numerator sum:      %0d", dbg_numerator);
        $display("  Denominator sum:    %0d", dbg_denominator);
        $display("========================================");

        // Verification: true center was 512, acceptable integer division error is +/- 1 pixel
        if (p_min >= 11'd511 && p_min <= 11'd513) begin
            $display("[PASS] Centroid matches expected true center (512) within tolerance!");
        end else begin
            $display("[FAIL] Centroid is off! Expected ~512, Got %0d", p_min);
        end
        $display("========================================\n");

        $finish;
    end

    // Watchdog Timeout
    initial begin
        #300000;
        $display("[TIMEOUT] Simulation timed out");
        $finish;
    end

endmodule
