`timescale 1ns/1ps
module tb_refbuf;
  localparam W=1280, PW=12;
  reg clk=0, rst_n=0, ls=0, le=1, wv=0, rv=0; reg [PW-1:0] wd=0;
  always #5 clk=~clk;
  wire [PW-1:0] ro; wire rvo, ld;
  ref_buffer dut(.clk(clk),.rst_n(rst_n),.line_start(ls),.load_en(le),
    .wr_data(wd),.wr_valid(wv),.rd_valid(rv),.ref_out(ro),.ref_valid(rvo),.loaded(ld));
  integer i, errs=0;
  reg [PW-1:0] exp_q [0:4095]; integer qw=0, qr=0;   // scoreboard FIFO
  always @(posedge clk) if (rvo) begin
    if (ro !== exp_q[qr]) begin errs=errs+1;
      $display("DATA MISMATCH idx=%0d got=%h want=%h", qr, ro, exp_q[qr]); end
    qr = qr + 1;
  end
  initial begin
    repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
    // capture a full line of pseudo-random data
    ls<=1; @(posedge clk); ls<=0;
    for (i=0;i<W;i=i+1) begin wd <= (i*2654435761) % 4096; wv<=1; @(posedge clk); end
    wv<=0; @(posedge clk);
    if (!ld) begin errs=errs+1; $display("FAIL: loaded not set after full capture"); end
    // replay twice through the wrap, with gaps in rd_valid (every 3rd cycle idle)
    le<=0; ls<=1; @(posedge clk); ls<=0;
    for (i=0;i<2*W;i=i+1) begin
      exp_q[qw] = ((i%W)*2654435761) % 4096; qw = qw + 1;
      rv<=1; @(posedge clk);
      if (i%3==2) begin rv<=0; @(posedge clk); end
    end
    rv<=0; repeat(3) @(posedge clk);
    if (qr != 2*W) begin errs=errs+1; $display("FAIL: %0d reads seen, want %0d", qr, 2*W); end
    // start a recapture: loaded must clear, then set again after full line
    le<=1; ls<=1; @(posedge clk); ls<=0; @(posedge clk);
    if (ld) begin errs=errs+1; $display("FAIL: loaded not cleared on recapture line_start"); end
    for (i=0;i<W-1;i=i+1) begin wd<=i[11:0]; wv<=1; @(posedge clk); end
    wv<=0; @(posedge clk);
    if (ld) begin errs=errs+1; $display("FAIL: loaded set after partial (W-1) recapture"); end
    wd<=12'hABC; wv<=1; @(posedge clk); wv<=0; @(posedge clk);
    if (!ld) begin errs=errs+1; $display("FAIL: loaded not set after completing recapture"); end
    if (errs==0) $display("REFBUF ALL PASS (2560 replay reads checked, loaded lifecycle OK)");
    else $display("REFBUF FAIL: %0d errors", errs);
    $finish;
  end
  initial begin #900000 $display("TIMEOUT"); $finish; end
endmodule
