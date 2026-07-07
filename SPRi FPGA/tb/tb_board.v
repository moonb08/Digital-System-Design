`timescale 1ns/1ps
// Simulates the exact board scenario: PS writes CTRL.start over AXI, then
// raises a GPIO bit; vector_player streams the ROM line; PS polls STATUS and
// reads P_MIN. Two frames back-to-back to prove repeatability.
module tb_board;
  reg clk=0, rstn=0, gpio=0; always #5 clk=~clk;
  reg [4:0] awaddr=0; reg awvalid=0; wire awready;
  reg [31:0] wdata=0; reg [3:0] wstrb=4'hF; reg wvalid=0; wire wready;
  wire [1:0] bresp; wire bvalid; reg bready=0;
  reg [4:0] araddr=0; reg arvalid=0; wire arready;
  wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=0;
  wire rdy, irq, vld, strm; wire [11:0] cur, refp;

  vector_player u_play(.clk(clk), .rst_n(rstn), .trigger(gpio),
    .current_pixel(cur), .ref_pixel(refp), .valid(vld), .streaming(strm));

  spr_accel_axi dut(.S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
    .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
    .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
    .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
    .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
    .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
    .current_pixel(cur), .ref_pixel(refp), .valid_in(vld), .ready_out(rdy), .irq(irq));

  reg [31:0] rd; integer frame;
  task axi_wr(input [4:0] a, input [31:0] d); begin
    @(posedge clk); awaddr<=a; wdata<=d; awvalid<=1; wvalid<=1; bready<=1;
    wait(awready); wait(wready); @(posedge clk); awvalid<=0; wvalid<=0;
    wait(bvalid); @(posedge clk); bready<=0; @(posedge clk);
  end endtask
  task axi_rd(input [4:0] a); begin
    @(posedge clk); araddr<=a; arvalid<=1; rready<=1;
    wait(arready); @(posedge clk); arvalid<=0;
    wait(rvalid); rd = rdata; @(posedge clk); rready<=0; @(posedge clk);
  end endtask

  initial begin
    repeat(6) @(posedge clk); rstn=1; repeat(4) @(posedge clk);
    for (frame=1; frame<=2; frame=frame+1) begin
      axi_wr(5'h00, 32'h1);           // CTRL.start (before pixels: framing contract)
      gpio <= 1;                      // GPIO -> trigger the player
      rd = 0;
      while (!rd[1]) axi_rd(5'h04);   // poll STATUS.done_latched
      gpio <= 0;
      axi_rd(5'h08);
      if (rd == 32'd639) $display("FRAME %0d PASS p_min=%0d", frame, rd);
      else               $display("FRAME %0d FAIL p_min=%0d (want 639)", frame, rd);
      axi_wr(5'h04, 32'h2);           // W1C done for next frame
    end
    $finish;
  end
  initial begin #900000 $display("TIMEOUT"); $finish; end
endmodule
