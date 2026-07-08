// spr_accel_axi.v — AXI4-Lite slave wrapper for SPRi accelerator
//
// Register Map (byte-addressed):
//   0x00 CTRL      [W]     bit[0] = start_frame (self-clearing pulse)
//   0x04 STATUS    [R/W1C] bit[0] = busy (centroid|fwhm), bit[1] = done_latched (W1C,
//                          set when BOTH centroid and FWHM results are valid),
//                          bit[2] = centroid done, bit[3] = fwhm done (RO latches)
//   0x08 P_MIN     [R]     bit[10:0] = resonance dip position (weighted centroid)
//   0x0C DBG_NUM   [R]     bit[31:0] = Σ(p × dip_depth) (MSB of 33 truncated)
//   0x10 DBG_DEN   [R]     bit[22:0] = Σ(dip_depth)
//   0x14 IRQ_CTRL  [R/W]   bit[0] = irq_enable, bit[1] = W1C irq_pending
//   0x18 FWHM      [R]     bit[10:0] = dip width at half-maximum
//   0x1C FWHM_CTR  [R]     bit[10:0] = dip position from FWHM midpoint
//                          (left_edge + right_edge)/2 — independent p_min estimate

`timescale 1ns / 1ps

module spr_accel_axi #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 5,
    parameter PIXEL_WIDTH  = 12,
    parameter IMAGE_WIDTH  = 1280,
    parameter ADDR_WIDTH   = 11,
    parameter ACC_WIDTH    = 33,
    parameter DEN_WIDTH    = 23
)
(
    input  wire                              S_AXI_ACLK,
    input  wire                              S_AXI_ARESETN,

    // AXI4-Lite Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [2:0]                        S_AXI_AWPROT,
    input  wire                              S_AXI_AWVALID,
    output wire                              S_AXI_AWREADY,

    // AXI4-Lite Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]   S_AXI_WSTRB,
    input  wire                              S_AXI_WVALID,
    output wire                              S_AXI_WREADY,

    // AXI4-Lite Write Response Channel
    output wire [1:0]                        S_AXI_BRESP,
    output wire                              S_AXI_BVALID,
    input  wire                              S_AXI_BREADY,

    // AXI4-Lite Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [2:0]                        S_AXI_ARPROT,
    input  wire                              S_AXI_ARVALID,
    output wire                              S_AXI_ARREADY,

    // AXI4-Lite Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output wire [1:0]                        S_AXI_RRESP,
    output wire                              S_AXI_RVALID,
    input  wire                              S_AXI_RREADY,

    // Pixel Data (connect to AXI-Stream DMA or sensor interface)
    input  wire [PIXEL_WIDTH-1:0]            current_pixel,
    input  wire [PIXEL_WIDTH-1:0]            ref_pixel,
    input  wire                              valid_in,
    output wire                              ready_out,

    // Interrupt to PS GIC
    output wire                              irq
);

    // ── Register Index (byte_addr[4:2]) ──
    localparam REG_CTRL     = 3'd0;  // 0x00
    localparam REG_STATUS   = 3'd1;  // 0x04
    localparam REG_P_MIN    = 3'd2;  // 0x08
    localparam REG_DBG_NUM  = 3'd3;  // 0x0C
    localparam REG_DBG_DEN  = 3'd4;  // 0x10
    localparam REG_IRQ_CTRL = 3'd5;  // 0x14
    localparam REG_FWHM     = 3'd6;  // 0x18
    localparam REG_FWHM_CTR = 3'd7;  // 0x1C

    // ── AXI4-Lite Protocol Registers ──
    reg                              axi_awready;
    reg                              axi_wready;
    reg                              axi_bvalid;
    reg                              axi_arready;
    reg                              axi_rvalid;
    reg  [C_S_AXI_DATA_WIDTH-1:0]    axi_rdata;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]    axi_awaddr;
    reg  [C_S_AXI_DATA_WIDTH-1:0]    axi_wdata;
    reg  [C_S_AXI_DATA_WIDTH/8-1:0]  axi_wstrb;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]    axi_araddr;
    reg                              aw_latched;
    reg                              w_latched;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid;

    // ── Control / Status Registers ──
    reg  start_frame;
    reg  done_latched;      // both results valid (user-visible, W1C)
    reg  cen_done_latched;  // centroid finished this frame
    reg  fwhm_done_latched; // fwhm finished this frame
    reg  irq_enable;
    reg  irq_pending;

    // ── Pipeline Wires ──
    wire [ADDR_WIDTH-1:0]    pipe_p_min;
    wire                     pipe_done;
    wire                     pipe_busy;
    wire [PIXEL_WIDTH-1:0]   pipe_diff_pixel;
    wire                     pipe_valid_out;
    wire                     pipe_overflow;
    wire [ACC_WIDTH-1:0]     pipe_dbg_num;
    wire [DEN_WIDTH-1:0]     pipe_dbg_den;
    wire [ADDR_WIDTH-1:0]    pipe_fwhm;
    wire [ADDR_WIDTH-1:0]    pipe_fwhm_center;
    wire                     pipe_fwhm_done;
    wire                     pipe_fwhm_busy;
    wire [PIXEL_WIDTH-1:0]   pipe_dbg_max_depth;
    wire [ADDR_WIDTH-1:0]    pipe_dbg_left_edge;
    wire [ADDR_WIDTH-1:0]    pipe_dbg_right_edge;

    // Frame complete when the LAST engine finishes (either order, or same cycle)
    wire frame_complete = (pipe_fwhm_done && (cen_done_latched  || pipe_done)) ||
                          (pipe_done      && (fwhm_done_latched || pipe_fwhm_done));

    assign irq = irq_enable & irq_pending;

    // ── Write Address Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            axi_awaddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            aw_latched  <= 1'b0;
        end
        else begin
            axi_awready <= 1'b0;
            if (wr_en) begin
                aw_latched <= 1'b0;
            end
            else if (!aw_latched && !axi_bvalid && S_AXI_AWVALID) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= S_AXI_AWADDR;
                aw_latched  <= 1'b1;
            end
        end
    end

    // ── Write Data Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_wready <= 1'b0;
            axi_wdata   <= {C_S_AXI_DATA_WIDTH{1'b0}};
            axi_wstrb   <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            w_latched   <= 1'b0;
        end
        else begin
            axi_wready <= 1'b0;
            if (wr_en) begin
                w_latched <= 1'b0;
            end
            else if (!w_latched && !axi_bvalid && S_AXI_WVALID) begin
                axi_wready <= 1'b1;
                axi_wdata   <= S_AXI_WDATA;
                axi_wstrb   <= S_AXI_WSTRB;
                w_latched   <= 1'b1;
            end
        end
    end

    // ── Write Response Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_bvalid <= 1'b0;
        else if (wr_en)
            axi_bvalid <= 1'b1;
        else if (S_AXI_BREADY && axi_bvalid)
            axi_bvalid <= 1'b0;
    end

    // ── Register Write Logic ──
    wire wr_en = aw_latched && w_latched && !axi_bvalid;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            start_frame       <= 1'b0;
            done_latched      <= 1'b0;
            cen_done_latched  <= 1'b0;
            fwhm_done_latched <= 1'b0;
            irq_enable        <= 1'b0;
            irq_pending       <= 1'b0;
        end
        else begin
            // Self-clear start after 1 cycle; re-arm per-engine done latches
            if (start_frame) begin
                start_frame       <= 1'b0;
                cen_done_latched  <= 1'b0;
                fwhm_done_latched <= 1'b0;
            end

            if (wr_en) begin
                case (axi_awaddr[4:2])
                    REG_CTRL: begin
                        if (axi_wstrb[0] && axi_wdata[0])
                            start_frame <= 1'b1;
                    end
                    REG_STATUS: begin
                        // W1C: write 1 to bit[1] clears done_latched
                        if (axi_wstrb[0] && axi_wdata[1])
                            done_latched <= 1'b0;
                    end
                    REG_IRQ_CTRL: begin
                        if (axi_wstrb[0]) begin
                            irq_enable <= axi_wdata[0];
                            if (axi_wdata[1])
                                irq_pending <= 1'b0;
                        end
                    end
                endcase
            end

            // Latch engine done pulses (placed after AXI write for priority)
            if (pipe_done)
                cen_done_latched  <= 1'b1;
            if (pipe_fwhm_done)
                fwhm_done_latched <= 1'b1;

            // Both results valid -> user-visible done + interrupt
            if (frame_complete) begin
                done_latched <= 1'b1;
                irq_pending  <= 1'b1;
            end
        end
    end

    // ── Read Address Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end
        else if (~axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            axi_arready <= 1'b1;
            axi_araddr  <= S_AXI_ARADDR;
        end
        else begin
            axi_arready <= 1'b0;
        end
    end

    // ── Read Data Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rdata  <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end
        else if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            axi_rvalid <= 1'b1;
            case (axi_araddr[4:2])
                REG_CTRL:     axi_rdata <= 32'd0;
                REG_STATUS:   axi_rdata <= {28'd0, fwhm_done_latched, cen_done_latched,
                                            done_latched, pipe_busy | pipe_fwhm_busy};
                REG_P_MIN:    axi_rdata <= {{(32-ADDR_WIDTH){1'b0}}, pipe_p_min};
                REG_DBG_NUM:  axi_rdata <= pipe_dbg_num[31:0]; // MSB truncated
                REG_DBG_DEN:  axi_rdata <= {{(32-DEN_WIDTH){1'b0}}, pipe_dbg_den};
                REG_IRQ_CTRL: axi_rdata <= {30'd0, irq_pending, irq_enable};
                REG_FWHM:     axi_rdata <= {{(32-ADDR_WIDTH){1'b0}}, pipe_fwhm};
                REG_FWHM_CTR: axi_rdata <= {{(32-ADDR_WIDTH){1'b0}}, pipe_fwhm_center};
                default:      axi_rdata <= 32'd0;
            endcase
        end
        else if (axi_rvalid && S_AXI_RREADY) begin
            axi_rvalid <= 1'b0;
        end
    end

    // ── SPR Processing Pipeline ──
    spr_pipeline #(
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .DEN_WIDTH   (DEN_WIDTH)
    ) u_pipeline (
        .clk             (S_AXI_ACLK),
        .rst_n           (S_AXI_ARESETN),
        .start_frame     (start_frame),
        .current_pixel   (current_pixel),
        .ref_pixel       (ref_pixel),
        .valid_in        (valid_in),
        .ready_out       (ready_out),
        .p_min           (pipe_p_min),
        .done            (pipe_done),
        .busy            (pipe_busy),
        .diff_pixel      (pipe_diff_pixel),
        .valid_out_pixel (pipe_valid_out),
        .overflow_flag   (pipe_overflow),
        .dbg_numerator   (pipe_dbg_num),
        .dbg_denominator (pipe_dbg_den),
        .fwhm            (pipe_fwhm),
        .fwhm_center     (pipe_fwhm_center),
        .fwhm_done       (pipe_fwhm_done),
        .fwhm_busy       (pipe_fwhm_busy),
        .dbg_max_depth   (pipe_dbg_max_depth),
        .dbg_left_edge   (pipe_dbg_left_edge),
        .dbg_right_edge  (pipe_dbg_right_edge)
    );

endmodule
