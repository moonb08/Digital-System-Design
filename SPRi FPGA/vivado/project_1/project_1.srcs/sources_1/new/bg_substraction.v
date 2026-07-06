`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08.06.2026 09:33:19
// Design Name: 
// Module Name: bg_substraction
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module bg_subtraction #(
    parameter PIXEL_WIDTH = 12,         // 12-bit pixels (S11661 sensor)
    parameter IMAGE_WIDTH = 1024        // pixels per row (from paper)
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,          // active low reset
    // Input: current sample frame pixel
    input  wire [PIXEL_WIDTH-1:0]   current_pixel,
    // Input: reference frame pixel (H2O baseline)
    input  wire [PIXEL_WIDTH-1:0]   ref_pixel,
    // Input handshake
    input  wire                     valid_in,       // input pixel is valid
    output wire                     ready_out,      // module ready to accept
    // Output: subtracted pixel
    output reg  [PIXEL_WIDTH-1:0]   diff_pixel,     // rectified difference
    // Output handshake
    output reg                      valid_out,      // output pixel is valid
    // Status
    output reg                      overflow_flag   // set if any pixel clipped
);
// ============================================================
// Internal signals
// ============================================================
    // One extra bit to detect sign (underflow)
    wire signed [PIXEL_WIDTH:0] diff_raw;
    // Registered valid_in to match 1-cycle output latency
    reg valid_in_r;
    // Always ready - pure combinational pipeline (1 cycle latency)
    assign ready_out = 1'b1;
    // Signed subtraction with overflow detection
    // Extended by 1 bit to catch negative result
    assign diff_raw = {1'b0, current_pixel} - {1'b0, ref_pixel};
// ============================================================
// Output Register (1 cycle latency)
// ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_pixel    <= {PIXEL_WIDTH{1'b0}};
            valid_out     <= 1'b0;
            valid_in_r    <= 1'b0;
            overflow_flag <= 1'b0;
        end
        else begin
            valid_in_r <= valid_in;         // register valid one cycle ahead
            valid_out  <= valid_in_r;       // valid_out aligns with registered output
            if (valid_in) begin
                // Rectification: clamp negative to zero
                if (diff_raw[PIXEL_WIDTH]) begin
                    // MSB = 1 means result is negative
                    diff_pixel    <= {PIXEL_WIDTH{1'b0}};   // clamp to 0
                    overflow_flag <= 1'b1;                   // flag underflow
                end
                else begin
                    diff_pixel    <= diff_raw[PIXEL_WIDTH-1:0];
                    overflow_flag <= 1'b0;
                end
            end
        end
    end
endmodule
