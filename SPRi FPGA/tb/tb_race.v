`timescale 1ns/1ps
// Directed race test: force pipe_done onto the SAME clock edge as a W1C
// register write and check which one wins.
//   Race 1: W1C to STATUS.done   vs pipe_done setting done_latched
//   Race 2: W1C to IRQ.pending   vs pipe_done setting irq_pending
// Correct behavior: the hardware event (done) must win; losing it means
// software polls forever / misses an interrupt.
module tb_race;
  reg clk=0, rstn=0; always #5 clk=~clk;
  reg [4:0] awaddr=0; reg awvalid=0; wire awready;
  reg [31:0] wdata=0; reg [3:0] wstrb=4'hF; reg wvalid=0; wire wready;
  wire [1:0] bresp; wire bvalid; reg bready=0;
  reg [4:0] araddr=0; reg arvalid=0; wire arready;
  wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=0;
  wire rdy, irq;

  spr_accel_axi dut(.S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
    .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
    .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
    .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
    .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
    .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
    .current_pixel(12'd0), .ref_pixel(12'd0), .valid_in(1'b0), .ready_out(rdy), .irq(irq));

  reg [31:0] rd;
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

  // Collide: whenever armed, watch for the decode cycle (wr_en) at negedge
  // (signals stable mid-cycle), force done for exactly that clock edge.
  reg arm=0;
  always @(negedge clk) if (arm && dut.wr_en) begin
    force dut.pipe_done = 1'b1;
    @(posedge clk); #1;
    release dut.pipe_done;
    arm = 0;
  end

  initial begin
    repeat(4) @(posedge clk); rstn=1; repeat(2) @(posedge clk);

    // Race 1: W1C(done) colliding with done pulse
    arm = 1;
    axi_wr(5'h04, 32'h2);              // STATUS W1C bit1, done forced same edge
    axi_rd(5'h04);
    if (rd[1]) $display("PASS race1: done_latched survived simultaneous W1C");
    else       $display("FAIL race1: done event LOST to simultaneous W1C");
    axi_wr(5'h04, 32'h2); axi_rd(5'h04);
    if (!rd[1]) $display("PASS race1b: normal W1C still clears afterwards");
    else        $display("FAIL race1b: W1C no longer clears");

    // Race 2: IRQ_CTRL W1C(pending) colliding with done pulse
    axi_wr(5'h14, 32'h1);              // irq_enable=1
    arm = 1;
    axi_wr(5'h14, 32'h3);              // enable + W1C pending, done forced same edge
    axi_rd(5'h14);
    if (rd[1] && irq) $display("PASS race2: irq_pending survived simultaneous W1C (irq=%b)", irq);
    else              $display("FAIL race2: irq event LOST (pending=%b irq=%b)", rd[1], irq);
    $finish;
  end
  initial begin #200000 $display("TIMEOUT"); $finish; end
endmodule
