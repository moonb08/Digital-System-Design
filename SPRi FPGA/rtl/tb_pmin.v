`timescale 1ns / 1ps

module tb_pmin;
    parameter PIXEL_WIDTH  = 12;
    parameter IMAGE_WIDTH  = 1280;
    parameter ADDR_WIDTH   = 11;
    parameter ACC_WIDTH    = 33;
    parameter DEN_WIDTH    = 23;

    reg clk;
    reg rst_n;
    reg start_frame;
    reg [PIXEL_WIDTH-1:0] current_pixel;
    reg [PIXEL_WIDTH-1:0] ref_pixel;
    reg valid_in;

    wire [ADDR_WIDTH-1:0] p_min;
    wire done;
    wire busy;
    wire [ACC_WIDTH-1:0] dbg_numerator;
    wire [DEN_WIDTH-1:0] dbg_denominator;

    // Memory arrays for vectors
    reg [PIXEL_WIDTH-1:0] cur_mem [0:IMAGE_WIDTH-1];
    reg [PIXEL_WIDTH-1:0] ref_mem [0:IMAGE_WIDTH-1];

    initial begin
        $readmemh("current.hex", cur_mem);
        $readmemh("ref.hex", ref_mem);
    end

    // Instantiate pipeline
    spr_pipeline #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .DEN_WIDTH(DEN_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_frame(start_frame),
        .current_pixel(current_pixel),
        .ref_pixel(ref_pixel),
        .valid_in(valid_in),
        .ready_out(),
        .p_min(p_min),
        .done(done),
        .busy(busy),
        .diff_pixel(),
        .valid_out_pixel(),
        .overflow_flag(),
        .dbg_numerator(dbg_numerator),
        .dbg_denominator(dbg_denominator)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    integer i;

    initial begin
        rst_n = 0;
        start_frame = 0;
        valid_in = 0;
        current_pixel = 0;
        ref_pixel = 0;
        
        #100;
        rst_n = 1;
        #20;
        
        @(posedge clk);
        start_frame = 1;
        @(posedge clk);
        start_frame = 0;
        
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(posedge clk);
            #1;
            current_pixel = cur_mem[i];
            ref_pixel = ref_mem[i];
            valid_in = 1;
        end
        
        @(posedge clk);
        #1;
        valid_in = 0;
        
        // Wait for done
        @(posedge clk);
        while (!done) @(posedge clk);
        
        #1;
        $display("P_MIN=%0d", p_min);
        $display("SUM_DEPTH=%0d", dbg_denominator);
        
        $finish;
    end
    
    // Watchdog
    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
