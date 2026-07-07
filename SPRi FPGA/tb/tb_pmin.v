`timescale 1ns/1ps
// Streams current.hex / ref.hex through the real spr_pipeline and prints P_MIN.
module tb_pmin;
  localparam W=1280, PW=12, AW=11, ACCW=32, DENW=23;
  reg clk=0, rst_n=0, start=0, valid=0;
  reg [PW-1:0] cur_mem [0:W-1];
  reg [PW-1:0] ref_mem [0:W-1];
  reg [PW-1:0] cur_px=0, ref_px=0;
  wire [AW-1:0] p_min; wire done, busy;
  wire [ACCW-1:0] dbg_num; wire [DENW-1:0] dbg_den;
  integer i;

  spr_pipeline #(.PIXEL_WIDTH(PW),.IMAGE_WIDTH(W),.ADDR_WIDTH(AW),
                 .ACC_WIDTH(ACCW),.DEN_WIDTH(DENW)) dut (
    .clk(clk),.rst_n(rst_n),.start_frame(start),
    .current_pixel(cur_px),.ref_pixel(ref_px),.valid_in(valid),.ready_out(),
    .p_min(p_min),.done(done),.busy(busy),
    .diff_pixel(),.valid_out_pixel(),.overflow_flag(),
    .dbg_numerator(dbg_num),.dbg_denominator(dbg_den));

  always #5 clk = ~clk;

  initial begin
    $readmemh("current.hex", cur_mem);
    $readmemh("ref.hex",     ref_mem);
    repeat(4) @(posedge clk); rst_n = 1;
    @(posedge clk); start <= 1;
    @(posedge clk); start <= 0;
    for (i=0;i<W;i=i+1) begin
      cur_px <= cur_mem[i]; ref_px <= ref_mem[i]; valid <= 1;
      @(posedge clk);
    end
    valid <= 0;
    wait (done); @(posedge clk);
    $display("P_MIN = %0d", p_min);
    $display("SUM_DEPTH = %0d", dbg_den);
    $finish;
  end
  initial begin #500000 $display("TIMEOUT"); $finish; end
endmodule