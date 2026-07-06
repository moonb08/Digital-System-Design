// roi_centroid.v — Weighted centroid for SPR dip position
//
// Formula (Eq. 4):
//            Σ[ p × dip_depth[p] ]
//   p_min = ───────────────────────
//            Σ[ dip_depth[p] ]
//
// FSM: IDLE -> ACCUMULATE (1024 cyc) -> DIVIDE (32 cyc) -> DONE -> IDLE

module roi_centroid #(
    parameter PIXEL_WIDTH  = 12,
    parameter IMAGE_WIDTH  = 1280,
    parameter ADDR_WIDTH   = 11,
    parameter ACC_WIDTH    = 33,
    parameter DEN_WIDTH    = 23
)
(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [PIXEL_WIDTH-1:0]   dip_depth,
    input  wire                     valid_in,
    output reg  [ADDR_WIDTH-1:0]    p_min,
    output reg                      done,
    output reg                      busy,
    output reg  [ACC_WIDTH-1:0]     dbg_numerator,
    output reg  [DEN_WIDTH-1:0]     dbg_denominator
);

    localparam IDLE       = 2'd0;
    localparam ACCUMULATE = 2'd1;
    localparam DIVIDE     = 2'd2;
    localparam DONE_ST    = 2'd3;

    reg [1:0] state;

    reg [ADDR_WIDTH-1:0]    pixel_addr;
    reg [ACC_WIDTH-1:0]     numerator;
    reg [DEN_WIDTH-1:0]     denominator;
    reg [ADDR_WIDTH-1:0]    pix_count;

    // weight = dip_depth (0 outside dip, proportional to depth inside)
    wire [PIXEL_WIDTH-1:0] weight;
    assign weight = dip_depth;

    // Sequential divider registers
    reg  [ACC_WIDTH-1:0]    div_dividend;
    reg  [DEN_WIDTH-1:0]    div_divisor;
    reg  [ACC_WIDTH-1:0]    div_quotient;
    reg  [ACC_WIDTH-1:0]    div_remainder;
    reg  [5:0]              div_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            pixel_addr   <= {ADDR_WIDTH{1'b0}};
            pix_count    <= {ADDR_WIDTH{1'b0}};
            numerator    <= {ACC_WIDTH{1'b0}};
            denominator  <= {DEN_WIDTH{1'b0}};
            p_min        <= {ADDR_WIDTH{1'b0}};
            done         <= 1'b0;
            busy         <= 1'b0;
            div_count    <= 6'd0;
            div_quotient <= {ACC_WIDTH{1'b0}};
            div_remainder<= {ACC_WIDTH{1'b0}};
            div_dividend <= {ACC_WIDTH{1'b0}};
            div_divisor  <= {DEN_WIDTH{1'b0}};
            dbg_numerator   <= {ACC_WIDTH{1'b0}};
            dbg_denominator <= {DEN_WIDTH{1'b0}};
        end
        else begin
            done <= 1'b0;

            case (state)

                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        numerator   <= {ACC_WIDTH{1'b0}};
                        denominator <= {DEN_WIDTH{1'b0}};
                        pixel_addr  <= {ADDR_WIDTH{1'b0}};
                        pix_count   <= {ADDR_WIDTH{1'b0}};
                        busy        <= 1'b1;
                        state       <= ACCUMULATE;
                    end
                end

                // numerator += p × weight, denominator += weight
                ACCUMULATE: begin
                    if (valid_in) begin
                        numerator   <= numerator
                                     + ({{(ACC_WIDTH-ADDR_WIDTH){1'b0}}, pixel_addr}
                                     *  {{(ACC_WIDTH-PIXEL_WIDTH){1'b0}}, weight});

                        denominator <= denominator
                                     + {{(DEN_WIDTH-PIXEL_WIDTH){1'b0}}, weight};

                        pixel_addr  <= pixel_addr + 1'b1;
                        pix_count   <= pix_count  + 1'b1;

                        // Last pixel: save final sums for divider
                        if (pix_count == IMAGE_WIDTH - 1) begin
                            div_dividend  <= numerator
                                           + ({{(ACC_WIDTH-ADDR_WIDTH){1'b0}}, pixel_addr}
                                           *  {{(ACC_WIDTH-PIXEL_WIDTH){1'b0}}, weight});
                            div_divisor   <= denominator
                                           + {{(DEN_WIDTH-PIXEL_WIDTH){1'b0}}, weight};

                            dbg_numerator   <= numerator
                                            + ({{(ACC_WIDTH-ADDR_WIDTH){1'b0}}, pixel_addr}
                                            *  {{(ACC_WIDTH-PIXEL_WIDTH){1'b0}}, weight});
                            dbg_denominator <= denominator
                                            + {{(DEN_WIDTH-PIXEL_WIDTH){1'b0}}, weight};

                            div_count     <= 6'd0;
                            div_quotient  <= {ACC_WIDTH{1'b0}};
                            div_remainder <= {ACC_WIDTH{1'b0}};
                            state         <= DIVIDE;
                        end
                    end
                end

                // Restoring divider: quotient = dividend / divisor (32 cycles)
                DIVIDE: begin
                    if (div_divisor == {DEN_WIDTH{1'b0}}) begin
                        p_min <= {ADDR_WIDTH{1'b0}};    // div-by-zero guard
                        state <= DONE_ST;
                    end
                    else begin
                        if ({div_remainder[ACC_WIDTH-2:0],
                             div_dividend[ACC_WIDTH-1-div_count]}
                             >= {{(ACC_WIDTH-DEN_WIDTH){1'b0}}, div_divisor})
                        begin
                            div_remainder <= {div_remainder[ACC_WIDTH-2:0],
                                              div_dividend[ACC_WIDTH-1-div_count]}
                                           - {{(ACC_WIDTH-DEN_WIDTH){1'b0}}, div_divisor};
                            div_quotient  <= {div_quotient[ACC_WIDTH-2:0], 1'b1};
                        end
                        else begin
                            div_remainder <= {div_remainder[ACC_WIDTH-2:0],
                                              div_dividend[ACC_WIDTH-1-div_count]};
                            div_quotient  <= {div_quotient[ACC_WIDTH-2:0], 1'b0};
                        end

                        div_count <= div_count + 1'b1;

                        if (div_count == ACC_WIDTH - 1)
                            state <= DONE_ST;
                    end
                end

                // p_min = quotient[9:0], pulse done
                DONE_ST: begin
                    p_min <= div_quotient[ADDR_WIDTH-1:0];
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
