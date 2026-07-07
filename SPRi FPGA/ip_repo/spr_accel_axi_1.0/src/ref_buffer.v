// ref_buffer.v — Single-line reference (baseline) store for SPRi
//
// Holds one line of reference pixels (the baseline captured with no analyte).
// Two phases, selected by load_en:
//   load_en = 1  CAPTURE : incoming wr_data written to mem[0..IMAGE_WIDTH-1]
//   load_en = 0  REPLAY  : rd_valid strobes emit ref[0], ref[1], ... in order
//
// The write source (sensor pixel vs PS-written data) is muxed at the top
// level onto wr_data — this module stays agnostic to where the reference
// comes from.
//
// Read is SYNCHRONOUS (models block RAM): presenting rd_valid for address p
// makes ref_out = mem[p] valid on the NEXT clock, with ref_valid aligned to
// ref_out. The consumer must delay its own current_pixel by one cycle to
// pair ref[p] against current[p]. That 1-cycle latency is the behaviour the
// testbench pins down.

module ref_buffer #(
    parameter PIXEL_WIDTH = 12,
    parameter IMAGE_WIDTH = 1280,
    parameter ADDR_WIDTH  = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Control
    input  wire                    line_start,   // pulse: reset addresses to 0
    input  wire                    load_en,      // 1 = capture, 0 = replay

    // Write side (capture) — source muxed at top level
    input  wire [PIXEL_WIDTH-1:0]  wr_data,
    input  wire                    wr_valid,

    // Read side (replay) — strobe in step with the live pixel stream
    input  wire                    rd_valid,
    output reg  [PIXEL_WIDTH-1:0]  ref_out,
    output reg                     ref_valid,    // aligned with ref_out

    // Status
    output reg                     loaded        // 1 after a full line captured
);

    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] mem [0:IMAGE_WIDTH-1];

    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [ADDR_WIDTH-1:0] rd_addr;

    // BRAM inference block (no reset)
    always @(posedge clk) begin
        if (!line_start && load_en && wr_valid)
            mem[wr_addr] <= wr_data;
        
        if (!line_start && !load_en && rd_valid)
            ref_out <= mem[rd_addr];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_addr   <= {ADDR_WIDTH{1'b0}};
            rd_addr   <= {ADDR_WIDTH{1'b0}};
            ref_valid <= 1'b0;
            loaded    <= 1'b0;
        end
        else begin
            ref_valid <= 1'b0;   // default: deassert unless a read fires

            if (line_start) begin
                // line_start dominates: resets addressing before pixel 0.
                // Any coincident valid is intentionally ignored (framing
                // contract: start pulses one cycle before the first pixel).
                wr_addr <= {ADDR_WIDTH{1'b0}};
                rd_addr <= {ADDR_WIDTH{1'b0}};
                if (load_en) loaded <= 1'b0;
            end
            else begin
                // CAPTURE
                if (load_en && wr_valid) begin
                    if (wr_addr == IMAGE_WIDTH-1) begin
                        wr_addr <= {ADDR_WIDTH{1'b0}};
                        loaded  <= 1'b1;
                    end
                    else begin
                        wr_addr <= wr_addr + 1'b1;
                    end
                end

                // REPLAY (synchronous read → ref_out valid next cycle)
                if (!load_en && rd_valid) begin
                    ref_valid <= 1'b1;
                    if (rd_addr == IMAGE_WIDTH-1)
                        rd_addr <= {ADDR_WIDTH{1'b0}};
                    else
                        rd_addr <= rd_addr + 1'b1;
                end
            end
        end
    end

endmodule