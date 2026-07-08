// fwhm_calc.v — Full Width at Half Maximum of SPR dip
//
// FWHM = right_edge - left_edge + 1
// Half-max threshold = max(dip_depth) / 2
//
// FSM: IDLE -> STORE (1280 cyc) -> SCAN (1281 cyc) -> DONE -> IDLE
// Uses Block RAM to store dip profile for two-pass analysis

`timescale 1ns / 1ps

module fwhm_calc #(
    parameter PIXEL_WIDTH = 12,         
    parameter IMAGE_WIDTH = 1280,
    parameter ADDR_WIDTH  = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [PIXEL_WIDTH-1:0]  dip_depth,
    input  wire                    valid_in,
    output reg  [ADDR_WIDTH-1:0]   fwhm,
    output reg  [ADDR_WIDTH-1:0]   fwhm_center,
    output reg                     done,
    output reg                     busy,
    output reg  [PIXEL_WIDTH-1:0]  dbg_max_depth,
    output reg  [ADDR_WIDTH-1:0]   dbg_left_edge,
    output reg  [ADDR_WIDTH-1:0]   dbg_right_edge
);

    localparam IDLE    = 2'd0;
    localparam STORE   = 2'd1;
    localparam SCAN    = 2'd2;
    localparam DONE_ST = 2'd3;

    reg [1:0] state;

    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] dip_mem [0:IMAGE_WIDTH-1];

    reg [ADDR_WIDTH-1:0]   wr_addr;
    reg [ADDR_WIDTH-1:0]   pix_count;
    reg [PIXEL_WIDTH-1:0]  max_depth;
    reg [PIXEL_WIDTH-1:0]  half_max;

    reg [ADDR_WIDTH-1:0]   scan_addr;
    reg [ADDR_WIDTH:0]     scan_count;
    reg [PIXEL_WIDTH-1:0]  rd_data;

    // BRAM inference block (no reset)
    always @(posedge clk) begin
        if (state == STORE && valid_in)
            dip_mem[wr_addr] <= dip_depth;
        rd_data <= dip_mem[scan_addr];
    end

    reg [ADDR_WIDTH-1:0]   left_edge;
    reg [ADDR_WIDTH-1:0]   right_edge;
    reg                    found_left;

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= IDLE;
            wr_addr        <= {ADDR_WIDTH{1'b0}};
            pix_count      <= {ADDR_WIDTH{1'b0}};
            max_depth      <= {PIXEL_WIDTH{1'b0}};
            half_max       <= {PIXEL_WIDTH{1'b0}};
            scan_addr      <= {ADDR_WIDTH{1'b0}};
            scan_count     <= {(ADDR_WIDTH+1){1'b0}};
            left_edge      <= {ADDR_WIDTH{1'b0}};
            right_edge     <= {ADDR_WIDTH{1'b0}};
            found_left     <= 1'b0;
            fwhm           <= {ADDR_WIDTH{1'b0}};
            fwhm_center    <= {ADDR_WIDTH{1'b0}};
            done           <= 1'b0;
            busy           <= 1'b0;
            dbg_max_depth  <= {PIXEL_WIDTH{1'b0}};
            dbg_left_edge  <= {ADDR_WIDTH{1'b0}};
            dbg_right_edge <= {ADDR_WIDTH{1'b0}};
        end
        else begin
            done <= 1'b0;

            case (state)

                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        wr_addr    <= {ADDR_WIDTH{1'b0}};
                        pix_count  <= {ADDR_WIDTH{1'b0}};
                        max_depth  <= {PIXEL_WIDTH{1'b0}};
                        left_edge  <= {ADDR_WIDTH{1'b0}};
                        right_edge <= {ADDR_WIDTH{1'b0}};
                        found_left <= 1'b0;
                        busy       <= 1'b1;
                        state      <= STORE;
                    end
                end

                // Pass 1: Write dip_depth to BRAM, track maximum
                STORE: begin
                    if (valid_in) begin
                        if (dip_depth > max_depth)
                            max_depth <= dip_depth;

                        wr_addr   <= wr_addr + 1'b1;
                        pix_count <= pix_count + 1'b1;

                        if (pix_count == IMAGE_WIDTH - 1) begin
                            if (dip_depth > max_depth) begin
                                half_max      <= ({1'b0, dip_depth} + 1'b1) >> 1;
                                dbg_max_depth <= dip_depth;
                            end
                            else begin
                                half_max      <= ({1'b0, max_depth} + 1'b1) >> 1;
                                dbg_max_depth <= max_depth;
                            end

                            scan_addr  <= {ADDR_WIDTH{1'b0}};
                            scan_count <= {(ADDR_WIDTH+1){1'b0}};

                            if (max_depth == {PIXEL_WIDTH{1'b0}} && dip_depth == {PIXEL_WIDTH{1'b0}}) begin
                                fwhm          <= {ADDR_WIDTH{1'b0}};
                                dbg_max_depth <= {PIXEL_WIDTH{1'b0}};
                                state         <= DONE_ST;
                            end
                            else begin
                                state <= SCAN;
                            end
                        end
                    end
                end

                // Pass 2: Read BRAM, find half-max crossings
                // 1-cycle read latency: scan_count tracks processed pixel
                SCAN: begin
                    if (scan_addr < IMAGE_WIDTH - 1)
                        scan_addr <= scan_addr + 1'b1;

                    if (scan_count > 0) begin
                        if (rd_data >= half_max && half_max > {PIXEL_WIDTH{1'b0}}) begin
                            if (!found_left) begin
                                left_edge  <= scan_count - 1'b1;
                                found_left <= 1'b1;
                            end
                            right_edge <= scan_count - 1'b1;
                        end
                    end

                    scan_count <= scan_count + 1'b1;

                    if (scan_count == IMAGE_WIDTH)
                        state <= DONE_ST;
                end

                // Compute FWHM and its center from edge positions
                DONE_ST: begin
                    if (found_left) begin
                        fwhm        <= right_edge - left_edge + 1'b1;
                        // Zero-extend before summing: left+right can need
                        // ADDR_WIDTH+1 bits (centers past pixel 1024 would wrap)
                        fwhm_center <= ({1'b0, left_edge} + {1'b0, right_edge}) >> 1;
                    end
                    else begin
                        fwhm        <= {ADDR_WIDTH{1'b0}};
                        fwhm_center <= {ADDR_WIDTH{1'b0}};
                    end

                    dbg_left_edge  <= left_edge;
                    dbg_right_edge <= right_edge;
                    done           <= 1'b1;
                    busy           <= 1'b0;
                    state          <= IDLE;
                end

            endcase
        end
    end

endmodule
