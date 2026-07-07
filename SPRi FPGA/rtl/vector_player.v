// vector_player.v — On-chip test-vector source for board bring-up.
// Holds one line of current/ref pixels in block ROM (initialised from .mem
// files at synthesis) and streams them into spr_accel_axi once per rising
// edge of `trigger` (drive from an AXI GPIO bit).
//
// GAP_CYCLES idle cycles separate the trigger from the first valid pixel, so
// software can safely do: GPIO=0 -> write CTRL.start -> GPIO=1.
// Uses synchronous reset, consistent with the rest of the design.

module vector_player #(
    parameter PIXEL_WIDTH = 12,
    parameter IMAGE_WIDTH = 1280,
    parameter ADDR_WIDTH  = 11,
    parameter CUR_FILE    = "current.mem",
    parameter REF_FILE    = "ref.mem",
    parameter GAP_CYCLES  = 8
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    trigger,       // rising edge = play one line
    output reg  [PIXEL_WIDTH-1:0]  current_pixel,
    output reg  [PIXEL_WIDTH-1:0]  ref_pixel,
    output reg                     valid,
    output reg                     streaming      // high while a line is playing
);
    (* rom_style = "block" *) reg [PIXEL_WIDTH-1:0] cur_mem [0:IMAGE_WIDTH-1];
    (* rom_style = "block" *) reg [PIXEL_WIDTH-1:0] ref_mem [0:IMAGE_WIDTH-1];
    initial begin
        $readmemh(CUR_FILE, cur_mem);
        $readmemh(REF_FILE, ref_mem);
    end

    localparam S_IDLE = 2'd0, S_GAP = 2'd1, S_RUN = 2'd2;
    reg [1:0]            state;
    reg                  trig_d;
    reg [ADDR_WIDTH-1:0] addr;
    reg [3:0]            gap;
    wire trig_rise = trigger & ~trig_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;  trig_d <= 1'b0;  addr <= {ADDR_WIDTH{1'b0}};
            gap   <= 4'd0;    valid  <= 1'b0;  streaming <= 1'b0;
        end
        else begin
            trig_d <= trigger;
            valid  <= 1'b0;
            case (state)
                S_IDLE: begin
                    streaming <= 1'b0;
                    if (trig_rise) begin
                        addr      <= {ADDR_WIDTH{1'b0}};
                        gap       <= GAP_CYCLES[3:0];
                        streaming <= 1'b1;
                        state     <= S_GAP;
                    end
                end
                S_GAP: begin
                    gap <= gap - 4'd1;
                    if (gap == 4'd0)
                        state <= S_RUN;
                end
                S_RUN: begin
                    current_pixel <= cur_mem[addr];   // sync ROM read
                    ref_pixel     <= ref_mem[addr];
                    valid         <= 1'b1;
                    addr          <= addr + 1'b1;
                    if (addr == IMAGE_WIDTH-1)
                        state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
