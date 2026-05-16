//============================================================
// calc_top.v
// Top-level integer calculator.
//
//   - Reads keys from PmodKYPD via kypd_scanner
//   - Builds operand A, accepts operator (A/B/C/D = + - * /),
//     builds operand B, on '=' (E) computes and displays via bin2bcd
//   - 'C' (F) clears.
//
// IMPORTANT: '/' uses shift-based divide (power-of-2 only) to
// meet 100 MHz timing. If B is not a power of 2 (or is 0), the
// display shows "ERR". Truncates toward zero.
//
// Display behavior:
//   While typing A:    show digits of A
//   After operator:    show "A op"
//   While typing B:    show "A op B"
//   After '=':         show "= result"
//   On error:          show "ERR"
//============================================================
module calc_top #(
    parameter CLK_HZ = 100_000_000
)(
    input  wire        clk,
    input  wire        rst,

    output wire [3:0]  row,
    input  wire [3:0]  col,

    output wire        lcd_rs,
    output wire        lcd_rw,
    output wire        lcd_e,
    output wire [7:0]  lcd_db
);

    // ------------------------------------------------------------
    // Sub-blocks
    // ------------------------------------------------------------
    wire [3:0] key_code;
    wire       key_valid;
    kypd_scanner #(.CLK_HZ(CLK_HZ)) u_kypd (
        .clk(clk), .rst(rst),
        .row(row), .col(col),
        .key_code(key_code), .key_valid(key_valid)
    );

    reg        wr_req;
    reg        wr_rs;
    reg  [7:0] wr_data;
    wire       wr_ready;
    lcd_controller #(.CLK_HZ(CLK_HZ)) u_lcd (
        .clk(clk), .rst(rst),
        .wr_req(wr_req), .wr_rs(wr_rs), .wr_data(wr_data),
        .wr_ready(wr_ready),
        .lcd_rs(lcd_rs), .lcd_rw(lcd_rw),
        .lcd_e(lcd_e), .lcd_db(lcd_db)
    );

    wire        bcd_done;
    wire        bcd_neg;
    wire [39:0] bcd_val;
    reg         bcd_start;
    reg signed [31:0] bcd_in;
    bin2bcd u_b2b (
        .clk(clk), .rst(rst),
        .start(bcd_start), .bin_in(bcd_in),
        .done(bcd_done), .neg(bcd_neg), .bcd(bcd_val)
    );

    // ------------------------------------------------------------
    // Calculator state
    // ------------------------------------------------------------
    localparam M_A   = 3'd0;
    localparam M_B   = 3'd1;
    localparam M_RES = 3'd2;
    localparam M_ERR = 3'd3;
    reg [2:0] mode;

    reg signed [31:0] a, b;
    reg        [3:0]  op;

    wire is_digit = (key_code <= 4'h9);
    wire is_op    = (key_code >= 4'hA) && (key_code <= 4'hD);
    wire is_eq    = (key_code == 4'hE);
    wire is_clr   = (key_code == 4'hF);

    // ------------------------------------------------------------
    // Display buffer
    // ------------------------------------------------------------
    reg [7:0] dbuf [0:15];
    reg [4:0] dlen;
    reg       redraw;
    integer k;

    // ------------------------------------------------------------
    // Compute pipeline FSM
    // ------------------------------------------------------------
    localparam F_IDLE = 3'd0;
    localparam F_CALC = 3'd1;
    localparam F_KICK = 3'd2;
    localparam F_WAIT = 3'd3;
    localparam F_EMIT = 3'd4;
    reg [2:0] flow;
    reg [3:0] dig_idx;
    reg       seen_nz;
    reg signed [31:0] result_latched;

    // ------------------------------------------------------------
    // Shift-based divide helpers (power-of-2 only).
    // is_pow2(x): true if x has exactly one bit set
    // log2_pos(x): position of the set bit (0..31), valid only when is_pow2
    // ------------------------------------------------------------
    wire [31:0] b_abs   = b[31] ? -b : b;
    wire        b_pow2  = (b_abs != 0) && ((b_abs & (b_abs - 1)) == 0);

    // Priority encoder: find the bit position of the (assumed single) set bit
    reg [4:0] shift_amt;
    integer si;
    always @(*) begin
        shift_amt = 5'd0;
        for (si = 0; si < 32; si = si + 1) begin
            if (b_abs[si]) shift_amt = si[4:0];
        end
    end

    // Compute combinationally; gets latched in F_CALC
    wire signed [31:0] add_res = a + b;
    wire signed [31:0] sub_res = a - b;
    wire signed [31:0] mul_res = a * b;
    // Arithmetic right shift truncates toward -infinity in Verilog, but for
    // a calculator we want truncation toward zero (like C/Python's int).
    // For positive a, >>> is fine. For negative a, add (1<<shift_amt - 1)
    // before shifting so we truncate toward zero.
    wire signed [31:0] a_adj  = a[31] ? (a + ((32'sd1 <<< shift_amt) - 32'sd1)) : a;
    wire signed [31:0] shr_res = a_adj >>> shift_amt;
    // If b was negative, negate the result
    wire signed [31:0] div_res = b[31] ? -shr_res : shr_res;

    wire bad_div = (op == 4'hD) && (!b_pow2);  // div by 0 OR by non-power-of-2

    // ------------------------------------------------------------
    // Main state machine
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            mode      <= M_A;
            a         <= 0;
            b         <= 0;
            op        <= 4'h0;
            bcd_start <= 1'b0;
            bcd_in    <= 0;
            redraw    <= 1'b0;
            flow      <= F_IDLE;
            dig_idx   <= 0;
            seen_nz   <= 1'b0;
            dlen      <= 0;
            result_latched <= 0;
            for (k = 0; k < 16; k = k + 1) dbuf[k] <= " ";
        end else begin
            bcd_start <= 1'b0;
            redraw    <= 1'b0;

            // ---- key handling (only when calculator is idle) ----
            if (key_valid && flow == F_IDLE) begin
                if (is_clr) begin
                    mode <= M_A;
                    a    <= 0;
                    b    <= 0;
                    op   <= 4'h0;
                    dlen <= 0;
                    for (k = 0; k < 16; k = k + 1) dbuf[k] <= " ";
                    redraw <= 1'b1;
                end
                else case (mode)
                    M_A: begin
                        if (is_digit) begin
                            a <= a*10 + key_code;
                            if (dlen < 16) begin
                                dbuf[dlen] <= "0" + key_code;
                                dlen       <= dlen + 1;
                            end
                            redraw <= 1'b1;
                        end else if (is_op) begin
                            op   <= key_code;
                            mode <= M_B;
                            if (dlen < 16) begin
                                case (key_code)
                                    4'hA: dbuf[dlen] <= "+";
                                    4'hB: dbuf[dlen] <= "-";
                                    4'hC: dbuf[dlen] <= "*";
                                    4'hD: dbuf[dlen] <= "/";
                                endcase
                                dlen <= dlen + 1;
                            end
                            redraw <= 1'b1;
                        end
                    end
                    M_B: begin
                        if (is_digit) begin
                            b <= b*10 + key_code;
                            if (dlen < 16) begin
                                dbuf[dlen] <= "0" + key_code;
                                dlen       <= dlen + 1;
                            end
                            redraw <= 1'b1;
                        end else if (is_eq) begin
                            if (bad_div) begin
                                mode <= M_ERR;
                                for (k = 0; k < 16; k = k + 1) dbuf[k] <= " ";
                                dbuf[0] <= "E";
                                dbuf[1] <= "R";
                                dbuf[2] <= "R";
                                dlen    <= 3;
                                redraw  <= 1'b1;
                            end else begin
                                mode <= M_RES;
                                flow <= F_CALC;
                            end
                        end
                    end
                    M_RES: begin
                        if (is_digit) begin
                            a    <= key_code;
                            b    <= 0;
                            op   <= 4'h0;
                            mode <= M_A;
                            for (k = 0; k < 16; k = k + 1) dbuf[k] <= " ";
                            dbuf[0] <= "0" + key_code;
                            dlen    <= 1;
                            redraw  <= 1'b1;
                        end
                    end
                    M_ERR: begin
                        mode <= M_A;
                        a    <= 0; b <= 0; op <= 0;
                        for (k = 0; k < 16; k = k + 1) dbuf[k] <= " ";
                        dlen <= 0;
                        redraw <= 1'b1;
                    end
                endcase
            end

            // ---- compute pipeline ----
            case (flow)
                F_CALC: begin
                    case (op)
                        4'hA: result_latched <= add_res;
                        4'hB: result_latched <= sub_res;
                        4'hC: result_latched <= mul_res;
                        4'hD: result_latched <= div_res;
                        default: result_latched <= a;
                    endcase
                    flow <= F_KICK;
                end
                F_KICK: begin
                    for (k = 0; k < 16; k = k + 1) dbuf[k] <= " ";
                    dbuf[0] <= "=";
                    dbuf[1] <= " ";
                    dlen    <= 2;
                    bcd_in    <= result_latched;
                    bcd_start <= 1'b1;
                    seen_nz   <= 1'b0;
                    dig_idx   <= 4'd9;
                    flow      <= F_WAIT;
                end
                F_WAIT: if (bcd_done) begin
                    if (bcd_neg) begin
                        dbuf[dlen] <= "-";
                        dlen       <= dlen + 1;
                    end
                    flow <= F_EMIT;
                end
                F_EMIT: begin
                    if (seen_nz || (bcd_val[dig_idx*4 +: 4] != 0) || (dig_idx == 0)) begin
                        dbuf[dlen] <= "0" + bcd_val[dig_idx*4 +: 4];
                        dlen       <= dlen + 1;
                        seen_nz    <= 1'b1;
                    end
                    if (dig_idx == 0) begin
                        flow   <= F_IDLE;
                        redraw <= 1'b1;
                    end else begin
                        dig_idx <= dig_idx - 1;
                    end
                end
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------
    // LCD writer FSM
    // ------------------------------------------------------------
    localparam W_IDLE   = 3'd0;
    localparam W_SENDP  = 3'd1;
    localparam W_WAITP  = 3'd2;
    localparam W_SENDC  = 3'd3;
    localparam W_WAITC  = 3'd4;
    reg [2:0] wstate;
    reg [4:0] widx;

    always @(posedge clk) begin
        if (rst) begin
            wstate <= W_IDLE;
            widx   <= 0;
            wr_req <= 1'b0;
            wr_rs  <= 1'b0;
            wr_data<= 8'h00;
        end else begin
            wr_req <= 1'b0;
            case (wstate)
                W_IDLE: if (redraw && wr_ready) begin
                    wr_rs   <= 1'b0;
                    wr_data <= 8'h80;
                    wr_req  <= 1'b1;
                    widx    <= 0;
                    wstate  <= W_WAITP;
                end
                W_WAITP: if (!wr_ready) wstate <= W_SENDP;
                W_SENDP: if (wr_ready) wstate <= W_SENDC;
                W_SENDC: if (wr_ready) begin
                    if (widx == 5'd16) begin
                        wstate <= W_IDLE;
                    end else begin
                        wr_rs   <= 1'b1;
                        wr_data <= dbuf[widx];
                        wr_req  <= 1'b1;
                        widx    <= widx + 1;
                        wstate  <= W_WAITC;
                    end
                end
                W_WAITC: if (!wr_ready) wstate <= W_SENDC;
            endcase
        end
    end
endmodule