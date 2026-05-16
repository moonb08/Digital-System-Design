//============================================================
// kypd_scanner.v
// 4x4 matrix keypad scanner for PmodKYPD.
// - Drives rows low one at a time at ~1 kHz row rate
// - Synchronizes column inputs
// - Debounces (a press must be stable for ~20 row-ticks)
// - Outputs a 4-bit key_code (0x0..0xF) and a 1-cycle key_valid pulse
//
// PmodKYPD physical layout:
//   row0: 1 2 3 A
//   row1: 4 5 6 B
//   row2: 7 8 9 C
//   row3: 0 F E D
//============================================================
module kypd_scanner #(
    parameter CLK_HZ = 100_000_000
)(
    input  wire        clk,
    input  wire        rst,
    output reg  [3:0]  row,         // active-low row drive
    input  wire [3:0]  col,         // active-low column sense (pull-ups on board)
    output reg  [3:0]  key_code,
    output reg         key_valid    // 1-cycle pulse on new press
);
    // ---- tick every ~1 ms ----
    localparam integer TICK_DIV = CLK_HZ / 1000;
    localparam TDW = (TICK_DIV <= 1) ? 1 : $clog2(TICK_DIV);
    reg [TDW-1:0] tcnt;
    reg           tick;

    always @(posedge clk) begin
        if (rst) begin
            tcnt <= 0;
            tick <= 1'b0;
        end else if (tcnt == TICK_DIV-1) begin
            tcnt <= 0;
            tick <= 1'b1;
        end else begin
            tcnt <= tcnt + 1;
            tick <= 1'b0;
        end
    end

    // ---- row cycler ----
    reg [1:0] rsel;
    always @(posedge clk) begin
        if (rst) begin
            rsel <= 2'd0;
            row  <= 4'b1110;
        end else if (tick) begin
            rsel <= rsel + 2'd1;
            case (rsel + 2'd1)
                2'd0: row <= 4'b1110;
                2'd1: row <= 4'b1101;
                2'd2: row <= 4'b1011;
                2'd3: row <= 4'b0111;
            endcase
        end
    end

    // ---- synchronize col input ----
    reg [3:0] cs0, cs1;
    always @(posedge clk) begin
        cs0 <= col;
        cs1 <= cs0;
    end

    // ---- decode (row, col) -> key value ----
    function [3:0] decode;
        input [1:0] r;
        input [3:0] c;
        begin
            case ({r, c})
                {2'd0, 4'b1110}: decode = 4'h9;
                {2'd0, 4'b1101}: decode = 4'hC;
                {2'd0, 4'b1011}: decode = 4'h7;
                {2'd0, 4'b0111}: decode = 4'h8;
                {2'd1, 4'b1110}: decode = 4'hE;
                {2'd1, 4'b1101}: decode = 4'hD;
                {2'd1, 4'b1011}: decode = 4'h0;
                {2'd1, 4'b0111}: decode = 4'hF;
                {2'd2, 4'b1110}: decode = 4'h3;
                {2'd2, 4'b1101}: decode = 4'hA;
                {2'd2, 4'b1011}: decode = 4'h1;
                {2'd2, 4'b0111}: decode = 4'h2;
                {2'd3, 4'b1110}: decode = 4'h6;
                {2'd3, 4'b1101}: decode = 4'hB;
                {2'd3, 4'b1011}: decode = 4'h4;
                {2'd3, 4'b0111}: decode = 4'h5;
                default:         decode = 4'hF;
            endcase
        end
    endfunction

    wire any_press = (cs1 != 4'b1111);

    // ---- debounce + edge detect ----
    // Strategy: every row-scan tick, if a key is currently observed,
    // require it to be the same key for 4 consecutive observations
    // (one observation per row scan when that key's row is active).
    // Release: after 4 consecutive ticks with no press anywhere.
    reg       held;
    reg [3:0] candidate;
    reg [4:0] obs_count;
    reg [2:0] no_press_count;

    wire [3:0] this_key = decode(rsel, cs1);

    always @(posedge clk) begin
        if (rst) begin
            held      <= 1'b0;
            candidate <= 4'h0;
            obs_count <= 0;
            no_press_count <= 0;
            key_code  <= 4'h0;
            key_valid <= 1'b0;
        end else begin
            key_valid <= 1'b0;
            if (tick) begin
                if (any_press) begin
                    no_press_count <= 0;
                    if (this_key == candidate) begin
                        if (!held) begin
                            if (obs_count == 5'd4) begin
                                held      <= 1'b1;
                                key_code  <= candidate;
                                key_valid <= 1'b1;
                            end else begin
                                obs_count <= obs_count + 1;
                            end
                        end
                    end else begin
                        candidate <= this_key;
                        obs_count <= 0;
                    end
                end else begin
                    // No press this tick
                    if (no_press_count != 3'd5)
                        no_press_count <= no_press_count + 1;
                    if (no_press_count >= 3'd4 && held) begin
                        held      <= 1'b0;
                        candidate <= 4'h0;
                        obs_count <= 0;
                    end
                end
            end
        end
    end
endmodule