`timescale 1ns / 1ps
// tb_axi_fwhm.v — checks 0x18/0x1C registers and done gated on BOTH engines
module tb_axi_fwhm;
    reg clk=0, rst_n;
    reg [11:0] cur, refp; reg valid;
    reg [4:0] awaddr, araddr; reg awvalid, wvalid, bready, arvalid, rready;
    reg [31:0] wdata;
    wire awready, wready, bvalid, arready, rvalid;
    wire [31:0] rdata; wire [1:0] bresp, rresp;
    wire irq, ready_out;

    spr_accel_axi dut (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(4'hF), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
        .current_pixel(cur), .ref_pixel(refp), .valid_in(valid), .ready_out(ready_out), .irq(irq));

    always #10 clk = ~clk;

    reg [11:0] cur_mem [0:1279]; reg [11:0] ref_mem [0:1279];
    integer i, errors = 0;
    reg [31:0] rd;

    task axi_write(input [4:0] a, input [31:0] d);
        begin
            @(posedge clk); #1; awaddr=a; wdata=d; awvalid=1; wvalid=1; bready=1;
            wait (bvalid); @(posedge clk); #1; awvalid=0; wvalid=0;
            wait (!bvalid); @(posedge clk);
        end
    endtask

    task axi_read(input [4:0] a, output [31:0] d);
        begin
            @(posedge clk); #1; araddr=a; arvalid=1; rready=1;
            wait (rvalid); d = rdata; @(posedge clk); #1; arvalid=0;
            wait (!rvalid); @(posedge clk);
        end
    endtask

    initial begin
        rst_n=0; cur=0; refp=0; valid=0;
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; awaddr=0; araddr=0; wdata=0;
        $readmemh("current.mem", cur_mem); $readmemh("ref.mem", ref_mem);
        #100 rst_n=1; #40;

        axi_write(5'h14, 32'h1);      // irq_enable
        axi_write(5'h00, 32'h1);      // start_frame
        repeat (4) @(posedge clk);
        for (i=0;i<1280;i=i+1) begin @(posedge clk); #1; cur=cur_mem[i]; refp=ref_mem[i]; valid=1; end
        @(posedge clk); #1; valid=0;

        // centroid done ~ +34 cyc; fwhm needs ~1281 more. Check done NOT set early.
        repeat (100) @(posedge clk);
        axi_read(5'h04, rd);
        if (rd[1]) begin $display("FAIL done set before fwhm complete (STATUS=%h)", rd); errors=errors+1; end
        else if (!rd[2]) begin $display("FAIL centroid latch not set (STATUS=%h)", rd); errors=errors+1; end
        else $display("PASS early STATUS=%h (cen done, fwhm pending)", rd);

        // wait for fwhm to finish
        repeat (1500) @(posedge clk);
        axi_read(5'h04, rd);
        if (rd[1] && rd[3]) $display("PASS final STATUS=%h", rd); else begin $display("FAIL final STATUS=%h", rd); errors=errors+1; end
        if (irq) $display("PASS irq asserted"); else begin $display("FAIL irq not asserted"); errors=errors+1; end

        axi_read(5'h08, rd); if (rd==639)    $display("PASS P_MIN=%0d", rd);   else begin $display("FAIL P_MIN=%0d", rd); errors=errors+1; end
        axi_read(5'h10, rd); if (rd==121834) $display("PASS DEN=%0d", rd);     else begin $display("FAIL DEN=%0d", rd); errors=errors+1; end
        axi_read(5'h18, rd); if (rd==30)     $display("PASS FWHM=%0d", rd);    else begin $display("FAIL FWHM=%0d", rd); errors=errors+1; end
        axi_read(5'h1C, rd); if (rd==639)    $display("PASS FWHM_CTR=%0d", rd); else begin $display("FAIL FWHM_CTR=%0d", rd); errors=errors+1; end

        // W1C done, W1C irq
        axi_write(5'h04, 32'h2);
        axi_write(5'h14, 32'h3);
        axi_read(5'h04, rd); if (!rd[1]) $display("PASS done W1C"); else begin $display("FAIL done W1C"); errors=errors+1; end
        if (!irq) $display("PASS irq cleared"); else begin $display("FAIL irq stuck"); errors=errors+1; end

        if (errors==0) $display("ALL AXI TESTS PASSED"); else $display("%0d ERRORS", errors);
        $finish;
    end
    initial begin #4000000; $display("TIMEOUT"); $finish; end
endmodule
