//============================================================
// lcd_controller.v
// HD44780 driver for PmodCLP in 8-bit mode.
// On reset: runs the power-on init sequence automatically.
// Then accepts byte writes via a wr_req / wr_ready handshake.
//
// Parameter CLK_HZ scales all delays. Use 100_000_000 for real
// hardware (100 MHz clock). Use a much smaller value (e.g. 100_000)
// for fast simulation.
//============================================================
module lcd_controller #(
    parameter CLK_HZ = 100_000_000
)(
    input  wire        clk,
    input  wire        rst,         // active-high synchronous reset
    input  wire        wr_req,      // pulse high to send wr_data
    input  wire        wr_rs,       // 0 = command, 1 = data
    input  wire [7:0]  wr_data,
    output reg         wr_ready,    // high when idle, ready for new wr_req

    output reg         lcd_rs,
    output wire        lcd_rw,
    output reg         lcd_e,
    output reg  [7:0]  lcd_db
);
    assign lcd_rw = 1'b0;           // write-only (PmodCLP supports this)

    // ---- timing (in clock cycles) ----
    localparam integer US     = (CLK_HZ + 999_999) / 1_000_000; // ceil to >=1
    localparam integer T_50MS = CLK_HZ/1000 * 50;
    localparam integer T_5MS  = CLK_HZ/1000 * 5;
    localparam integer T_2MS  = CLK_HZ/1000 * 2;
    localparam integer T_200U = US * 200;
    localparam integer T_60U  = US * 60;
    localparam integer T_1U   = (US < 2) ? 2 : US;   // at least 2 cycles for E pulse

    // ---- states ----
    localparam S_PWR    = 4'd0;
    localparam S_W1     = 4'd1;
    localparam S_W2     = 4'd2;
    localparam S_W3     = 4'd3;
    localparam S_FSET   = 4'd4;
    localparam S_DOFF   = 4'd5;
    localparam S_CLR    = 4'd6;
    localparam S_ENT    = 4'd7;
    localparam S_DON    = 4'd8;
    localparam S_READY  = 4'd9;
    localparam S_SETUP  = 4'd10;
    localparam S_EHI    = 4'd11;
    localparam S_HOLD   = 4'd12;

    reg [3:0]  state, next_state;
    reg [31:0] tmr;
    reg [31:0] hold_target;

    task launch(input rs, input [7:0] d, input [3:0] nxt, input [31:0] hold);
        begin
            lcd_rs      <= rs;
            lcd_db      <= d;
            lcd_e       <= 1'b0;
            hold_target <= hold;
            next_state  <= nxt;
            state       <= S_SETUP;
            tmr         <= 0;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_PWR;
            tmr      <= 0;
            lcd_e    <= 1'b0;
            lcd_rs   <= 1'b0;
            lcd_db   <= 8'h00;
            wr_ready <= 1'b0;
            hold_target <= 0;
            next_state  <= S_PWR;
        end else begin
            tmr <= tmr + 1;
            case (state)
                S_PWR:  if (tmr >= T_50MS) launch(1'b0, 8'h30, S_W1,   T_5MS);
                S_W1:   if (tmr >= T_5MS)  launch(1'b0, 8'h30, S_W2,   T_200U);
                S_W2:   if (tmr >= T_200U) launch(1'b0, 8'h30, S_W3,   T_200U);
                S_W3:   if (tmr >= T_200U) launch(1'b0, 8'h38, S_FSET, T_60U);
                S_FSET: launch(1'b0, 8'h08, S_DOFF, T_60U);
                S_DOFF: launch(1'b0, 8'h01, S_CLR,  T_2MS);
                S_CLR:  launch(1'b0, 8'h06, S_ENT,  T_60U);
                S_ENT:  launch(1'b0, 8'h0C, S_DON,  T_60U);
                S_DON:  begin state <= S_READY; wr_ready <= 1'b1; tmr <= 0; end

                S_READY: begin
                    wr_ready <= 1'b1;
                    if (wr_req) begin
                        wr_ready <= 1'b0;
                        launch(wr_rs, wr_data, S_READY,
                               (wr_rs==1'b0 && (wr_data==8'h01 || wr_data==8'h02))
                               ? T_2MS : T_60U);
                    end
                end

                S_SETUP: if (tmr >= T_1U) begin
                    lcd_e <= 1'b1;
                    state <= S_EHI;
                    tmr   <= 0;
                end
                S_EHI: if (tmr >= T_1U) begin
                    lcd_e <= 1'b0;
                    state <= S_HOLD;
                    tmr   <= 0;
                end
                S_HOLD: if (tmr >= hold_target) begin
                    state <= next_state;
                    tmr   <= 0;
                end
                default: state <= S_PWR;
            endcase
        end
    end
endmodule
