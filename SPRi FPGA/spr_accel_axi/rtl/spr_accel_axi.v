// spr_accel_axi.v — AXI4-Lite slave wrapper for SPRi accelerator
//
// Register Map (byte-addressed):
//   0x00 CTRL      [W]     bit[0] = start_frame (self-clearing pulse)
//   0x04 STATUS    [R/W1C] bit[0] = busy, bit[1] = done_latched (W1C)
//   0x08 P_MIN     [R]     bit[9:0] = resonance dip position
//   0x0C DBG_NUM   [R]     bit[31:0] = Σ(p × dip_depth)
//   0x10 DBG_DEN   [R]     bit[21:0] = Σ(dip_depth)
//   0x14 IRQ_CTRL  [R/W]   bit[0] = irq_enable, bit[1] = W1C irq_pending

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

    // ── AXI4-Lite Protocol Registers ──
    reg                              axi_awready;
    reg                              axi_wready;
    reg                              axi_bvalid;
    reg                              axi_arready;
    reg                              axi_rvalid;
    reg  [C_S_AXI_DATA_WIDTH-1:0]    axi_rdata;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]    axi_awaddr;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]    axi_araddr;

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
    reg  done_latched;
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

    assign irq = irq_enable & irq_pending;

    // ── Write Address Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            axi_awaddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end
        else if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
            axi_awready <= 1'b1;
            axi_awaddr  <= S_AXI_AWADDR;
        end
        else begin
            axi_awready <= 1'b0;
        end
    end

    // ── Write Data Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_wready <= 1'b0;
        else if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID)
            axi_wready <= 1'b1;
        else
            axi_wready <= 1'b0;
    end

    // ── Write Response Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_bvalid <= 1'b0;
        else if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && ~axi_bvalid)
            axi_bvalid <= 1'b1;
        else if (S_AXI_BREADY && axi_bvalid)
            axi_bvalid <= 1'b0;
    end

    // ── Register Write Logic ──
    wire wr_en = axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            start_frame  <= 1'b0;
            done_latched <= 1'b0;
            irq_enable   <= 1'b0;
            irq_pending  <= 1'b0;
        end
        else begin
            // Self-clear start after 1 cycle
            if (start_frame)
                start_frame <= 1'b0;

            // Latch done pulse from pipeline
            if (pipe_done) begin
                done_latched <= 1'b1;
                irq_pending  <= 1'b1;
            end

            if (wr_en) begin
                case (axi_awaddr[4:2])
                    REG_CTRL: begin
                        if (S_AXI_WSTRB[0] && S_AXI_WDATA[0])
                            start_frame <= 1'b1;
                    end
                    REG_STATUS: begin
                        // W1C: write 1 to bit[1] clears done_latched
                        if (S_AXI_WSTRB[0] && S_AXI_WDATA[1])
                            done_latched <= 1'b0;
                    end
                    REG_IRQ_CTRL: begin
                        if (S_AXI_WSTRB[0]) begin
                            irq_enable <= S_AXI_WDATA[0];
                            if (S_AXI_WDATA[1])
                                irq_pending <= 1'b0;
                        end
                    end
                endcase
            end
        end
    end

    // ── Read Address Channel ──
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end
        else if (~axi_arready && S_AXI_ARVALID) begin
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
                REG_STATUS:   axi_rdata <= {30'd0, done_latched, pipe_busy};
                REG_P_MIN:    axi_rdata <= {{(32-ADDR_WIDTH){1'b0}}, pipe_p_min};
                REG_DBG_NUM:  axi_rdata <= pipe_dbg_num;
                REG_DBG_DEN:  axi_rdata <= {{(32-DEN_WIDTH){1'b0}}, pipe_dbg_den};
                REG_IRQ_CTRL: axi_rdata <= {30'd0, irq_pending, irq_enable};
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
        .dbg_denominator (pipe_dbg_den)
    );

endmodule
