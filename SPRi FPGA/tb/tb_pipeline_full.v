`timescale 1ns / 1ps
// tb_pipeline_full.v — self-checking: centroid + FWHM + fwhm_center
// Test 1: real vectors (current.mem/ref.mem), golden from golden.py
// Test 2: synthetic dip centered at 1200 (fwhm_center overflow regression)
// Test 3: flat frame (no dip): fwhm=0, den=0, done still completes

module tb_pipeline_full;
    parameter PIXEL_WIDTH = 12, IMAGE_WIDTH = 1280, ADDR_WIDTH = 11;
    parameter ACC_WIDTH = 33, DEN_WIDTH = 23;

    reg clk=0, rst_n, start_frame, valid_in;
    reg  [PIXEL_WIDTH-1:0] current_pixel, ref_pixel;
    wire [ADDR_WIDTH-1:0]  p_min, fwhm, fwhm_center;
    wire done, busy, fwhm_done, fwhm_busy;
    wire [ACC_WIDTH-1:0] dbg_numerator;
    wire [DEN_WIDTH-1:0] dbg_denominator;
    wire [PIXEL_WIDTH-1:0] dbg_max_depth;
    wire [ADDR_WIDTH-1:0]  dbg_left_edge, dbg_right_edge;

    reg [PIXEL_WIDTH-1:0] cur_mem [0:IMAGE_WIDTH-1];
    reg [PIXEL_WIDTH-1:0] ref_mem [0:IMAGE_WIDTH-1];

    spr_pipeline #(.PIXEL_WIDTH(PIXEL_WIDTH), .IMAGE_WIDTH(IMAGE_WIDTH),
                   .ADDR_WIDTH(ADDR_WIDTH), .ACC_WIDTH(ACC_WIDTH), .DEN_WIDTH(DEN_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .start_frame(start_frame),
        .current_pixel(current_pixel), .ref_pixel(ref_pixel), .valid_in(valid_in),
        .ready_out(), .p_min(p_min), .done(done), .busy(busy),
        .fwhm(fwhm), .fwhm_center(fwhm_center), .fwhm_done(fwhm_done), .fwhm_busy(fwhm_busy),
        .diff_pixel(), .valid_out_pixel(), .overflow_flag(),
        .dbg_numerator(dbg_numerator), .dbg_denominator(dbg_denominator),
        .dbg_max_depth(dbg_max_depth), .dbg_left_edge(dbg_left_edge), .dbg_right_edge(dbg_right_edge));

    always #10 clk = ~clk;

    integer i, errors = 0;
    reg seen_done, seen_fwhm_done;

    task run_frame;
        begin
            seen_done = 0; seen_fwhm_done = 0;
            @(posedge clk); start_frame = 1;
            @(posedge clk); start_frame = 0;
            for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
                @(posedge clk); #1;
                current_pixel = cur_mem[i]; ref_pixel = ref_mem[i]; valid_in = 1;
            end
            @(posedge clk); #1; valid_in = 0;
            // wait until BOTH engines have pulsed done
            while (!(seen_done && seen_fwhm_done)) @(posedge clk);
            @(posedge clk); #1;
        end
    endtask

    always @(posedge clk) begin
        if (done)      seen_done      <= 1;
        if (fwhm_done) seen_fwhm_done <= 1;
    end

    task check;
        input [31:0] got, exp;
        input [127:0] name;
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got %0d expected %0d", name, got, exp);
                errors = errors + 1;
            end else
                $display("PASS %0s = %0d", name, got);
        end
    endtask

    initial begin
        rst_n = 0; start_frame = 0; valid_in = 0; current_pixel = 0; ref_pixel = 0;
        #100 rst_n = 1; #20;

        // ── Test 1: real image vectors ──
        $readmemh("current.mem", cur_mem);
        $readmemh("ref.mem", ref_mem);
        run_frame;
        $display("--- Test 1: real vectors ---");
        check(p_min, 639, "p_min");
        check(dbg_denominator, 121834, "den");
        check(fwhm, 30, "fwhm");
        check(fwhm_center, 639, "fwhm_center");
        check(dbg_left_edge, 625, "left_edge");
        check(dbg_right_edge, 654, "right_edge");

        // ── Test 2: synthetic dip at 1200 (center > 1024 overflow check) ──
        // triangle dip depth 1000 over [1180,1220]
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            ref_mem[i] = 12'd3000;
            if (i >= 1180 && i <= 1220)
                cur_mem[i] = 3000 - (1000 - ((i>1200 ? i-1200 : 1200-i) * 48));
            else
                cur_mem[i] = 12'd3000;
        end
        run_frame;
        $display("--- Test 2: dip centered at 1200 ---");
        check(p_min, 1200, "p_min");
        check(fwhm_center, 1200, "fwhm_center");
        if (fwhm_center < 1024) begin
            $display("FAIL fwhm_center wrapped (overflow bug)"); errors = errors + 1;
        end

        // ── Test 3: flat frame, no dip ──
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            cur_mem[i] = 12'd2000; ref_mem[i] = 12'd2000;
        end
        run_frame;
        $display("--- Test 3: flat frame ---");
        check(fwhm, 0, "fwhm");
        check(fwhm_center, 0, "fwhm_center");
        check(p_min, 0, "p_min");
        check(dbg_denominator, 0, "den");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d ERRORS", errors);
        $finish;
    end

    initial begin #2000000; $display("TIMEOUT"); $finish; end
endmodule
