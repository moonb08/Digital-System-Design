//============================================================
// bin2bcd.v
// Signed 32-bit binary -> 10-digit packed BCD via double-dabble.
// Latency: 32 clocks after `start` until `done` pulses.
// Output `neg` tells you if the input was negative; `bcd` holds
// the absolute value as 10 nibbles (MSD in bits [39:36]).
//============================================================
module bin2bcd (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] bin_in,
    output reg                done,
    output reg                neg,
    output reg  [39:0]        bcd
);
    reg [31:0] bin_r;
    reg [39:0] bcd_r;
    reg [5:0]  cnt;
    reg        busy;
    integer    i;

    // Combinational: take bcd_r, apply add-3 to any nibble >= 5,
    // then shift left by one bit shifting in bin_r[31].
    reg [39:0] bcd_adj;
    reg [39:0] bcd_shifted;
    always @(*) begin
        bcd_adj = bcd_r;
        for (i = 0; i < 10; i = i + 1) begin
            if (bcd_adj[i*4 +: 4] >= 4'd5)
                bcd_adj[i*4 +: 4] = bcd_adj[i*4 +: 4] + 4'd3;
        end
        bcd_shifted = {bcd_adj[38:0], bin_r[31]};
    end

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            bcd  <= 40'd0;
            neg  <= 1'b0;
            bin_r<= 32'd0;
            bcd_r<= 40'd0;
            cnt  <= 0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy  <= 1'b1;
                neg   <= bin_in[31];
                bin_r <= bin_in[31] ? -bin_in : bin_in;
                bcd_r <= 40'd0;
                cnt   <= 0;
            end else if (busy) begin
                if (cnt == 6'd32) begin
                    bcd  <= bcd_r;
                    done <= 1'b1;
                    busy <= 1'b0;
                end else begin
                    bcd_r <= bcd_shifted;
                    bin_r <= {bin_r[30:0], 1'b0};
                    cnt   <= cnt + 1;
                end
            end
        end
    end
endmodule
