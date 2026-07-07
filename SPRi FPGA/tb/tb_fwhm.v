`timescale 1ns/1ps
module tb_fwhm;
  localparam W=1280, PW=12, AW=11;
  reg clk=0, rst_n=0, start=0, vld=0; reg [PW-1:0] d=0;
  always #5 clk=~clk;
  wire [AW-1:0] f,c,le,re; wire dn,bs; wire [PW-1:0] mx;
  fwhm_calc dut(.clk(clk),.rst_n(rst_n),.start(start),.dip_depth(d),.valid_in(vld),
    .fwhm(f),.fwhm_center(c),.done(dn),.busy(bs),
    .dbg_max_depth(mx),.dbg_left_edge(le),.dbg_right_edge(re));
  reg [PW-1:0] v [0:W-1]; integer i; reg [8*16-1:0] name;
  task run_vec(input [8*16-1:0] nm); begin
    name = nm;
    $readmemh({nm,".hex"}, v);
    start<=1; @(posedge clk); start<=0;
    for (i=0;i<W;i=i+1) begin d<=v[i]; vld<=1; @(posedge clk); end
    vld<=0; wait(dn); @(posedge clk);
    $display("RTL %0s: fwhm=%0d center=%0d max=%0d l=%0d r=%0d", nm, f, c, mx, le, re);
    repeat(3) @(posedge clk);
  end endtask
  initial begin
    repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
    run_vec("vec_real_a4"); run_vec("vec_odd_max"); run_vec("vec_zeros");
    run_vec("vec_one_px"); run_vec("vec_plateau");
    $finish;
  end
  initial begin #900000 $display("TIMEOUT"); $finish; end
endmodule
