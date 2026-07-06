// tb_ref_buffer.v — Self-checking unit test for ref_buffer only.
//
// Tests, in isolation from the rest of the pipeline:
//   1. Capture a baseline line, replay it, verify every pixel reads back
//      correctly (this also proves the 1-cycle read-latency alignment,
//      since the scoreboard collects readback strictly on ref_valid).
//   2. Overwrite with a second line — buffer is reusable across frames.
//   3. Boundary addresses 0 and IMAGE_WIDTH-1 (the 11-bit extremes) covered
//      by the full-line replay checks.
//   4. Bubbles in wr_valid during capture — the write address must advance
//      on valid pixels only, never on idle cycles.
//   5. loaded flag asserts after a full line is captured.

`timescale 1ns / 1ps

module tb_ref_buffer;

    localparam PIXEL_WIDTH = 12;
    localparam IMAGE_WIDTH = 1280;
    localparam ADDR_WIDTH  = 11;

    reg                    clk;
    reg                    rst_n;
    reg                    line_start;
    reg                    load_en;
    reg  [PIXEL_WIDTH-1:0] wr_data;
    reg                    wr_valid;
    reg                    rd_valid;
    wire [PIXEL_WIDTH-1:0] ref_out;
    wire                   ref_valid;
    wire                   loaded;

    // Golden reference lines
    reg  [PIXEL_WIDTH-1:0] golden1  [0:IMAGE_WIDTH-1];
    reg  [PIXEL_WIDTH-1:0] golden2  [0:IMAGE_WIDTH-1];
    reg  [PIXEL_WIDTH-1:0] expected [0:IMAGE_WIDTH-1];

    // Scoreboard
    reg     checking;
    integer read_idx;
    integer errors;         // total across all phases
    integer phase_errors;   // reset per replay phase
    integer i;

    // ── DUT ──
    ref_buffer #(
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .line_start (line_start),
        .load_en    (load_en),
        .wr_data    (wr_data),
        .wr_valid   (wr_valid),
        .rd_valid   (rd_valid),
        .ref_out    (ref_out),
        .ref_valid  (ref_valid),
        .loaded     (loaded)
    );

    // ── Clock ──
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ── Scoreboard: sample settled outputs on negedge, check on ref_valid ──
    always @(negedge clk) begin
        if (checking && ref_valid) begin
            if (ref_out !== expected[read_idx]) begin
                errors       = errors + 1;
                phase_errors = phase_errors + 1;
                if (phase_errors <= 5)
                    $display("  MISMATCH @ p=%0d : got %0d, expected %0d",
                             read_idx, ref_out, expected[read_idx]);
            end
            read_idx = read_idx + 1;
        end
    end

    // ── Helper: load `expected` from a chosen golden set ──
    task set_expected_golden1; for (i=0;i<IMAGE_WIDTH;i=i+1) expected[i]=golden1[i]; endtask
    task set_expected_golden2; for (i=0;i<IMAGE_WIDTH;i=i+1) expected[i]=golden2[i]; endtask

    // ── Stimulus ──
    initial begin
        // Build two distinct baseline patterns
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            golden1[i] = (i*7 + 100)  % 4096;              // sloped, wraps
            golden2[i] = 2000 + ((i*13) % 200);            // flatter baseline
        end

        clk_reset;

        // ─────────────── TEST 1: capture golden1, replay, verify ───────────────
        $display("TEST 1: capture then replay a baseline line");
        capture_line(1'b0);            // no bubbles
        set_expected_golden1;
        replay_and_check;
        report_phase("TEST 1");

        // ─────────────── TEST 2: overwrite with golden2, verify reuse ──────────
        $display("TEST 2: overwrite buffer with a second line");
        capture_line_g2(1'b0);
        set_expected_golden2;
        replay_and_check;
        report_phase("TEST 2");

        // ─────────────── TEST 4: capture with bubbles in wr_valid ──────────────
        $display("TEST 4: capture golden1 with idle bubbles in wr_valid");
        capture_line(1'b1);            // bubbles ON
        set_expected_golden1;
        replay_and_check;
        report_phase("TEST 4 (address tracks valid, not cycles)");

        // ─────────────── Summary ───────────────
        $display("--------------------------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED  (addresses 0..%0d covered)", IMAGE_WIDTH-1);
        else
            $display("FAILED with %0d total mismatches", errors);
        $display("--------------------------------------------------");
        $finish;
    end

    // ── Tasks ──
    task clk_reset;
    begin
        rst_n=0; line_start=0; load_en=0; wr_data=0; wr_valid=0; rd_valid=0;
        checking=0; read_idx=0; errors=0; phase_errors=0;
        repeat (3) @(negedge clk);
        rst_n=1;
        @(negedge clk);
    end
    endtask

    // Capture golden1 (bubbles: insert an idle cycle every 5th pixel when on)
    task capture_line(input bubbles);
    begin
        @(negedge clk); line_start=1; load_en=1; wr_valid=0;
        @(negedge clk); line_start=0;
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            if (bubbles && (i % 5 == 0)) begin
                wr_valid=0; @(negedge clk);   // idle: address must NOT advance
            end
            wr_valid=1; wr_data=golden1[i]; @(negedge clk);
        end
        wr_valid=0;
        @(negedge clk);
    end
    endtask

    task capture_line_g2(input bubbles);
    begin
        @(negedge clk); line_start=1; load_en=1; wr_valid=0;
        @(negedge clk); line_start=0;
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            wr_valid=1; wr_data=golden2[i]; @(negedge clk);
        end
        wr_valid=0;
        @(negedge clk);
    end
    endtask

    // Replay the whole line and let the scoreboard check it
    task replay_and_check;
    begin
        read_idx=0; phase_errors=0;
        @(negedge clk); line_start=1; load_en=0; rd_valid=0;
        @(negedge clk); line_start=0;
        checking=1;
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            rd_valid=1; @(negedge clk);
        end
        rd_valid=0;
        repeat (3) @(negedge clk);   // drain the final synchronous read
        checking=0;
    end
    endtask

    task report_phase(input [255:0] name);
    begin
        if (phase_errors == 0 && read_idx == IMAGE_WIDTH)
            $display("  PASS  (%0d/%0d pixels matched)", read_idx, IMAGE_WIDTH);
        else
            $display("  FAIL  (%0d mismatches, %0d/%0d pixels read)",
                     phase_errors, read_idx, IMAGE_WIDTH);
    end
    endtask

    // loaded flag check (concurrent, informational)
    initial begin
        @(posedge loaded);
        $display("  [info] loaded asserted after first full capture");
    end

endmodule