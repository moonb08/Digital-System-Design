`timescale 1ns / 1ps
//============================================================
// tb_bin2bcd.v
// Test the bin2bcd converter with several inputs.
//============================================================
module tb_bin2bcd;
    reg               clk = 0;
    reg               rst = 1;
    reg               start = 0;
    reg signed [31:0] bin_in = 0;
    wire              done;
    wire              neg;
    wire       [39:0] bcd;

    bin2bcd dut (
        .clk(clk), .rst(rst),
        .start(start), .bin_in(bin_in),
        .done(done), .neg(neg), .bcd(bcd)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer expected;

    task check(input signed [31:0] val, input integer exp);
        integer dig9, dig8, dig7, dig6, dig5, dig4, dig3, dig2, dig1, dig0;
        integer reconstructed;
        begin
            @(negedge clk);
            bin_in = val;
            start  = 1;
            @(negedge clk);
            start  = 0;
            wait (done);
            @(negedge clk);
            dig9 = bcd[39:36];
            dig8 = bcd[35:32];
            dig7 = bcd[31:28];
            dig6 = bcd[27:24];
            dig5 = bcd[23:20];
            dig4 = bcd[19:16];
            dig3 = bcd[15:12];
            dig2 = bcd[11:8];
            dig1 = bcd[7:4];
            dig0 = bcd[3:0];
            reconstructed = dig9*1000000000 + dig8*100000000 + dig7*10000000
                          + dig6*1000000   + dig5*100000    + dig4*10000
                          + dig3*1000      + dig2*100       + dig1*10 + dig0;
            if (neg) reconstructed = -reconstructed;
            if (reconstructed == exp) begin
                $display("PASS  bin=%0d  bcd=%d%d%d%d%d%d%d%d%d%d  neg=%b",
                          val, dig9,dig8,dig7,dig6,dig5,dig4,dig3,dig2,dig1,dig0, neg);
            end else begin
                $display("FAIL  bin=%0d  got=%0d  expected=%0d",
                          val, reconstructed, exp);
                errors = errors + 1;
            end
            #50;
        end
    endtask

    initial begin
        $dumpfile("bin2bcd.vcd");
        $dumpvars(0, tb_bin2bcd);
        #20 rst = 0;
        #20;

        check(0, 0);
        check(1, 1);
        check(9, 9);
        check(10, 10);
        check(42, 42);
        check(123, 123);
        check(1234567890, 1234567890);
        check(-1, -1);
        check(-12345, -12345);
        check(-2147483647, -2147483647);

        if (errors == 0)
            $display("\n=== bin2bcd: ALL TESTS PASSED ===");
        else
            $display("\n=== bin2bcd: %0d FAILURES ===", errors);
        $finish;
    end
endmodule
