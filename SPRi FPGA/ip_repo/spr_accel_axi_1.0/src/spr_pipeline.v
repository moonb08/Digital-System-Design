// spr_pipeline.v — Top-level pipeline wrapper for SPRi processing
// Combines bg_subtraction and roi_centroid modules.

`timescale 1ns / 1ps

module spr_pipeline #(
    parameter PIXEL_WIDTH  = 12,
    parameter IMAGE_WIDTH  = 1280,
    parameter ADDR_WIDTH   = 11,
    parameter ACC_WIDTH    = 33,
    parameter DEN_WIDTH    = 23
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control
    input  wire                     start_frame,    // pulse to start a new frame
    
    // Input Stream (from sensor/ADC)
    input  wire [PIXEL_WIDTH-1:0]   current_pixel,
    input  wire [PIXEL_WIDTH-1:0]   ref_pixel,
    input  wire                     valid_in,
    output wire                     ready_out,
    
    // Output Result (Centroid)
    output wire [ADDR_WIDTH-1:0]    p_min,
    output wire                     done,
    output wire                     busy,
    
    // Debug / Monitoring
    output wire [PIXEL_WIDTH-1:0]   diff_pixel,
    output wire                     valid_out_pixel,
    output wire                     overflow_flag,
    output wire [ACC_WIDTH-1:0]     dbg_numerator,
    output wire [DEN_WIDTH-1:0]     dbg_denominator
);

    wire [PIXEL_WIDTH-1:0]   bg_dip_depth;
    wire                     bg_valid_out;

    // Instantiate Stage 1: Background Subtraction
    bg_subtraction #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) u_bg_sub (
        .clk           (clk),
        .rst_n         (rst_n),
        .current_pixel (current_pixel),
        .ref_pixel     (ref_pixel),
        .valid_in      (valid_in),
        .ready_out     (ready_out),
        .diff_pixel    (diff_pixel),
        .valid_out     (bg_valid_out),
        .overflow_flag (overflow_flag),
        .dip_depth     (bg_dip_depth)
    );

    assign valid_out_pixel = bg_valid_out;

    // Instantiate Stage 2: ROI Centroid Calculator
    roi_centroid #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .DEN_WIDTH(DEN_WIDTH)
    ) u_centroid (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start_frame),
        .dip_depth       (bg_dip_depth),
        .valid_in        (bg_valid_out),
        .p_min           (p_min),
        .done            (done),
        .busy            (busy),
        .dbg_numerator   (dbg_numerator),
        .dbg_denominator (dbg_denominator)
    );

endmodule
