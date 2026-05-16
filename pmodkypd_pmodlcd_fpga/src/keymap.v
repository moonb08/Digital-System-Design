//============================================================
// keymap.v
// Combinational mapping from 4-bit keypad code to ASCII character.
//============================================================
module keymap (
    input  wire [3:0] key,
    output reg  [7:0] ascii
);
    always @(*) begin
        case (key)
            4'h0: ascii = "0";
            4'h1: ascii = "1";
            4'h2: ascii = "2";
            4'h3: ascii = "3";
            4'h4: ascii = "4";
            4'h5: ascii = "5";
            4'h6: ascii = "6";
            4'h7: ascii = "7";
            4'h8: ascii = "8";
            4'h9: ascii = "9";
            4'hA: ascii = "+";
            4'hB: ascii = "-";
            4'hC: ascii = "*";
            4'hD: ascii = "/";
            4'hE: ascii = "=";
            4'hF: ascii = "C";    // clear
            default: ascii = "?";
        endcase
    end
endmodule
