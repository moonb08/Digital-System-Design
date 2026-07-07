// bg_subtraction.v — Pixel-wise background subtraction for SPRi
// Formula: diff_pixel = max(current - ref, 0)
//          dip_depth  = max(ref - current, 0)

module bg_subtraction #(
    parameter PIXEL_WIDTH = 12,     //ADC resolution
    parameter IMAGE_WIDTH = 1280    //Number of pixels per line (Position)
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire [PIXEL_WIDTH-1:0]   current_pixel,
    input  wire [PIXEL_WIDTH-1:0]   ref_pixel,
    input  wire                     valid_in,
    output wire                     ready_out,
    output reg  [PIXEL_WIDTH-1:0]   diff_pixel,
    output reg                      valid_out,
    output reg                      overflow_flag,
    output reg  [PIXEL_WIDTH-1:0]   dip_depth
);

    wire signed [PIXEL_WIDTH:0] diff_raw;

    assign ready_out = 1'b1;

    // 13-bit signed subtraction: {0, current} - {0, ref}
    assign diff_raw = {1'b0, current_pixel} - {1'b0, ref_pixel};

    always @(posedge clk) begin
        if (!rst_n) begin
            diff_pixel    <= {PIXEL_WIDTH{1'b0}};
            valid_out     <= 1'b0;
            overflow_flag <= 1'b0;
            dip_depth     <= {PIXEL_WIDTH{1'b0}};
        end
        else begin
            valid_out <= valid_in;

            if (valid_in) begin
                if (diff_raw[PIXEL_WIDTH]) begin
                    // Negative: current < ref (dip region)
                    diff_pixel    <= {PIXEL_WIDTH{1'b0}};
                    dip_depth     <= (~diff_raw[PIXEL_WIDTH-1:0]) + 1'b1;
                    overflow_flag <= 1'b1;
                end
                else begin
                    // Positive: current >= ref
                    diff_pixel    <= diff_raw[PIXEL_WIDTH-1:0];
                    dip_depth     <= {PIXEL_WIDTH{1'b0}};
                    overflow_flag <= 1'b0;
                end
            end
        end
    end

endmodule
