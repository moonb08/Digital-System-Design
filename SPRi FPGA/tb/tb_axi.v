`timescale 1ns/1ps
// AXI4-Lite level test of spr_accel_axi (fixed):
//  1. write CTRL.start, stream the a4_pen_line vectors, poll STATUS,
//     read P_MIN and check against golden 639
//  2. W1C clear of done, verify STATUS
//  3. stress: two pipelined writes with BREADY held low -> must get 2 BRESPs
module tb_axi;
  localparam W=1280, PW=12;
  reg clk=0, rstn=0;
  always #5 clk=~clk;

  reg [4:0] awaddr=0; reg awvalid=0; wire awready;
  reg [31:0] wdata=0; reg [3:0] wstrb=4'hF; reg wvalid=0; wire wready;
  wire [1:0] bresp; wire bvalid; reg bready=0;
  reg [4:0] araddr=0; reg arvalid=0; wire arready;
  wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=0;
  reg [PW-1:0] cur=0, refp=0; reg vld=0; wire rdy, irq;
  reg [PW-1:0] cur_mem [0:W-1]; reg [PW-1:0] ref_mem [0:W-1];

  spr_accel_axi dut(.S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
    .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
    .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
    .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
    .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
    .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
    .current_pixel(cur), .ref_pixel(refp), .valid_in(vld), .ready_out(rdy), .irq(irq));

  integer i, bcount, wr_acc;
  reg [31:0] rd;

  task axi_wr(input [4:0] a, input [31:0] d); begin
    @(posedge clk); awaddr<=a; wdata<=d; awvalid<=1; wvalid<=1; bready<=1;
    wait(awready && wready); @(posedge clk); awvalid<=0; wvalid<=0;
    wait(bvalid); @(posedge clk); bready<=0;
  end endtask

  task axi_rd(input [4:0] a); begin
    @(posedge clk); araddr<=a; arvalid<=1; rready<=1;
    wait(arready); @(posedge clk); arvalid<=0;
    wait(rvalid); rd = rdata; @(posedge clk); rready<=0;
  end endtask

  initial begin
    $readmemh("current.hex", cur_mem); $readmemh("ref.hex", ref_mem);
    repeat(4) @(posedge clk); rstn=1; repeat(2) @(posedge clk);

    // --- 1: start via AXI, stream, poll, read result ---
    axi_wr(5'h00, 32'h1);                     // CTRL.start
    @(posedge clk);
    for (i=0;i<W;i=i+1) begin
      cur<=cur_mem[i]; refp<=ref_mem[i]; vld<=1; @(posedge clk);
    end
    vld<=0;
    rd = 0;
    while (!rd[1]) axi_rd(5'h04);             // poll STATUS.done_latched
    axi_rd(5'h08);
    if (rd == 32'd639) $display("PASS p_min=%0d", rd);
    else               $display("FAIL p_min=%0d (want 639)", rd);
    axi_rd(5'h10); $display("SUM_DEPTH=%0d", rd);

    // --- 2: W1C ---
    axi_wr(5'h04, 32'h2);
    axi_rd(5'h04);
    if (rd[1]) $display("FAIL W1C: done still set"); else $display("PASS W1C");

    // --- 3: pipelined writes, delayed BREADY: expect 2 accepts AND 2 BRESPs ---
    bcount = 0; wr_acc = 0;
    fork
      forever @(posedge clk) begin                          // monitor (killed at $finish)
        if (bvalid && bready) bcount = bcount + 1;          // response handshakes
        if (awready && awvalid && wready && wvalid) wr_acc = wr_acc + 1;
      end
      begin repeat(8) @(posedge clk); bready <= 1; end      // release B late
    join_none
    @(posedge clk); awaddr<=5'h14; wdata<=32'h1; awvalid<=1; wvalid<=1; bready<=0;
    do @(posedge clk); while (!(awready && wready));        // accept #1 edge
    awaddr<=5'h14; wdata<=32'h0;                            // present write #2 back-to-back
    do @(posedge clk); while (!(awready && wready));        // accept #2 edge
    awvalid<=0; wvalid<=0;
    repeat(30) @(posedge clk);
    $display("%s pipelined writes: accepted=%0d responses=%0d (want 2/2)",
             (wr_acc==2 && bcount==2) ? "PASS" : "FAIL", wr_acc, bcount);
    $finish;
  end
  initial begin #400000 $display("TIMEOUT"); $finish; end
endmodule
