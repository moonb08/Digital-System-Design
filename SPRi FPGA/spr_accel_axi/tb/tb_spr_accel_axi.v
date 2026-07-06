// ============================================================
//  Testbench : tb_spr_accel_axi
//  Tests AXI4-Lite register access and full accelerator flow:
//    T1: Register defaults after reset
//    T2: AXI-triggered single-spike frame → verify p_min via register read
//    T3: Done-latch and W1C clear
//    T4: IRQ enable, fire, and W1C clear
//    T5: Back-to-back frames
// ============================================================

`timescale 1ns / 1ps

module tb_spr_accel_axi;

    parameter C_S_AXI_DATA_WIDTH = 32;
    parameter C_S_AXI_ADDR_WIDTH = 5;
    parameter PIXEL_WIDTH  = 12;
    parameter IMAGE_WIDTH  = 64;
    parameter ADDR_WIDTH   = 10;
    parameter ACC_WIDTH    = 32;
    parameter DEN_WIDTH    = 22;
    parameter CLK_PERIOD   = 20;

    // Register offsets
    localparam ADDR_CTRL     = 5'h00;
    localparam ADDR_STATUS   = 5'h04;
    localparam ADDR_P_MIN    = 5'h08;
    localparam ADDR_DBG_NUM  = 5'h0C;
    localparam ADDR_DBG_DEN  = 5'h10;
    localparam ADDR_IRQ_CTRL = 5'h14;

    reg                              aclk;
    reg                              aresetn;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]    awaddr;
    reg  [2:0]                       awprot;
    reg                              awvalid;
    wire                             awready;
    reg  [C_S_AXI_DATA_WIDTH-1:0]    wdata;
    reg  [3:0]                       wstrb;
    reg                              wvalid;
    wire                             wready;
    wire [1:0]                       bresp;
    wire                             bvalid;
    reg                              bready;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]    araddr;
    reg  [2:0]                       arprot;
    reg                              arvalid;
    wire                             arready;
    wire [C_S_AXI_DATA_WIDTH-1:0]    rdata;
    wire [1:0]                       rresp;
    wire                             rvalid;
    reg                              rready;

    reg  [PIXEL_WIDTH-1:0]           current_pixel;
    reg  [PIXEL_WIDTH-1:0]           ref_pixel;
    reg                              valid_in;
    wire                             ready_out;
    wire                             irq;

    integer i;
    integer pass_count = 0;
    integer fail_count = 0;
    reg [C_S_AXI_DATA_WIDTH-1:0] rd;

    spr_accel_axi #(
        .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH),
        .PIXEL_WIDTH  (PIXEL_WIDTH),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ACC_WIDTH    (ACC_WIDTH),
        .DEN_WIDTH    (DEN_WIDTH)
    ) dut (
        .S_AXI_ACLK    (aclk),
        .S_AXI_ARESETN (aresetn),
        .S_AXI_AWADDR  (awaddr),
        .S_AXI_AWPROT  (awprot),
        .S_AXI_AWVALID (awvalid),
        .S_AXI_AWREADY (awready),
        .S_AXI_WDATA   (wdata),
        .S_AXI_WSTRB   (wstrb),
        .S_AXI_WVALID  (wvalid),
        .S_AXI_WREADY  (wready),
        .S_AXI_BRESP   (bresp),
        .S_AXI_BVALID  (bvalid),
        .S_AXI_BREADY  (bready),
        .S_AXI_ARADDR  (araddr),
        .S_AXI_ARPROT  (arprot),
        .S_AXI_ARVALID (arvalid),
        .S_AXI_ARREADY (arready),
        .S_AXI_RDATA   (rdata),
        .S_AXI_RRESP   (rresp),
        .S_AXI_RVALID  (rvalid),
        .S_AXI_RREADY  (rready),
        .current_pixel  (current_pixel),
        .ref_pixel      (ref_pixel),
        .valid_in       (valid_in),
        .ready_out      (ready_out),
        .irq            (irq)
    );

    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // ── AXI4-Lite Write Task ──
    task axi_write;
        input [C_S_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S_AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge aclk); #1;
            awaddr  = addr;
            awprot  = 3'b000;
            awvalid = 1'b1;
            wdata   = data;
            wstrb   = 4'hF;
            wvalid  = 1'b1;
            bready  = 1'b1;

            @(posedge aclk);
            while (!(awready && wready)) @(posedge aclk);
            #1;
            awvalid = 1'b0;
            wvalid  = 1'b0;

            while (!bvalid) @(posedge aclk);
            @(posedge aclk); #1;
            bready = 1'b0;
        end
    endtask

    // ── AXI4-Lite Read Task ──
    task axi_read;
        input  [C_S_AXI_ADDR_WIDTH-1:0] addr;
        output [C_S_AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge aclk); #1;
            araddr  = addr;
            arprot  = 3'b000;
            arvalid = 1'b1;
            rready  = 1'b1;

            @(posedge aclk);
            while (!arready) @(posedge aclk);
            #1;
            arvalid = 1'b0;

            while (!rvalid) @(posedge aclk);
            data = rdata;
            @(posedge aclk); #1;
            rready = 1'b0;
        end
    endtask

    // ── Stream One Frame ──
    // Spike at pixel spike_pos with depth spike_depth, all other pixels 0
    task stream_spike_frame;
        input [ADDR_WIDTH-1:0] spike_pos;
        input [PIXEL_WIDTH-1:0] spike_depth;
        integer p;
        begin
            for (p = 0; p < IMAGE_WIDTH; p = p + 1) begin
                @(posedge aclk); #1;
                // ref = baseline, current = baseline - spike at spike_pos
                ref_pixel     = 12'd2000;
                current_pixel = (p == spike_pos) ? (12'd2000 - spike_depth) : 12'd2000;
                valid_in      = 1'b1;
            end
            @(posedge aclk); #1;
            valid_in      = 1'b0;
            current_pixel = 12'd0;
            ref_pixel     = 12'd0;
        end
    endtask

    // ── Wait for Done Latch ──
    task wait_done;
        reg [C_S_AXI_DATA_WIDTH-1:0] stat;
        begin
            stat = 32'd0;
            while (!stat[1]) begin
                axi_read(ADDR_STATUS, stat);
            end
        end
    endtask

    // ── Check Helper ──
    task check;
        input [255:0] label;
        input [C_S_AXI_DATA_WIDTH-1:0] actual;
        input [C_S_AXI_DATA_WIDTH-1:0] expected;
        begin
            if (actual === expected) begin
                $display("[PASS] %0s: got 0x%08h", label, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: got 0x%08h, expected 0x%08h", label, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_spr_accel_axi.vcd");
        $dumpvars(0, tb_spr_accel_axi);

        $display("========================================");
        $display("  AXI4-Lite Wrapper Testbench");
        $display("  IMAGE_WIDTH=%0d  PIXEL_WIDTH=%0d", IMAGE_WIDTH, PIXEL_WIDTH);
        $display("========================================");

        aresetn       = 1'b0;
        awaddr = 0; awprot = 0; awvalid = 0;
        wdata = 0; wstrb = 0; wvalid = 0; bready = 0;
        araddr = 0; arprot = 0; arvalid = 0; rready = 0;
        current_pixel = 0; ref_pixel = 0; valid_in = 0;

        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        // ── T1: Register defaults after reset ──
        $display("\n--- T1: Register defaults after reset ---");
        axi_read(ADDR_CTRL, rd);     check("CTRL reset",     rd, 32'd0);
        axi_read(ADDR_STATUS, rd);   check("STATUS reset",   rd, 32'd0);
        axi_read(ADDR_P_MIN, rd);    check("P_MIN reset",    rd, 32'd0);
        axi_read(ADDR_IRQ_CTRL, rd); check("IRQ_CTRL reset", rd, 32'd0);

        // ── T2: Single spike at pixel 32 → p_min = 32 ──
        $display("\n--- T2: AXI-triggered spike at pixel 32 ---");
        axi_write(ADDR_CTRL, 32'h1);          // start_frame pulse
        stream_spike_frame(10'd32, 12'd800);  // spike depth=800 at pixel 32
        wait_done();

        axi_read(ADDR_P_MIN, rd);
        check("p_min spike@32", rd[ADDR_WIDTH-1:0], 10'd32);

        axi_read(ADDR_STATUS, rd);
        check("STATUS busy=0 done=1", rd[1:0], 2'b10);

        // ── T3: Done-latch W1C clear ──
        $display("\n--- T3: Clear done_latched via W1C ---");
        axi_write(ADDR_STATUS, 32'h2);        // write 1 to bit[1] → clear done
        axi_read(ADDR_STATUS, rd);
        check("STATUS after W1C", rd[1:0], 2'b00);

        // ── T4: IRQ enable, fire, clear ──
        $display("\n--- T4: IRQ test ---");
        axi_write(ADDR_IRQ_CTRL, 32'h1);      // irq_enable = 1
        axi_read(ADDR_IRQ_CTRL, rd);
        check("IRQ enabled", rd[0], 1'b1);

        axi_write(ADDR_CTRL, 32'h1);
        stream_spike_frame(10'd50, 12'd600);
        wait_done();

        axi_read(ADDR_IRQ_CTRL, rd);
        check("IRQ pending set", rd[1], 1'b1);
        if (irq !== 1'b1) begin
            $display("[FAIL] irq output not asserted"); fail_count = fail_count + 1;
        end else begin
            $display("[PASS] irq output asserted"); pass_count = pass_count + 1;
        end

        axi_write(ADDR_IRQ_CTRL, 32'h3);      // clear pending (bit[1]), keep enable (bit[0])
        axi_read(ADDR_IRQ_CTRL, rd);
        check("IRQ cleared", rd[1:0], 2'b01);
        if (irq !== 1'b0) begin
            $display("[FAIL] irq output not deasserted"); fail_count = fail_count + 1;
        end else begin
            $display("[PASS] irq output deasserted"); pass_count = pass_count + 1;
        end

        axi_read(ADDR_P_MIN, rd);
        check("p_min spike@50", rd[ADDR_WIDTH-1:0], 10'd50);

        // ── T5: Back-to-back frames ──
        $display("\n--- T5: Back-to-back frame (spike@10) ---");
        axi_write(ADDR_STATUS, 32'h2);        // clear done_latched first
        axi_write(ADDR_CTRL, 32'h1);
        stream_spike_frame(10'd10, 12'd500);
        wait_done();

        axi_read(ADDR_P_MIN, rd);
        check("p_min spike@10", rd[ADDR_WIDTH-1:0], 10'd10);

        // ── Summary ──
        $display("\n========================================");
        $display("  RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

    initial begin
        #500000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
