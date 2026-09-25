// ============================================================================
// File: tb_adpll.v
// Module: tb_adpll
// Project: All-Digital Phase-Locked Loop (ADPLL) - SCL 180nm C2S Node
//
// DESCRIPTION:
// Testbench for verifying adpll_top with behavioral dco_model on 180nm:
// - Reference Clock: 12.5 MHz (Period = 80.0 ns = 80,000 ps)
// - Feedback Divider: N = 8
// - Target DCO Clock: 100 MHz (Period = 10.0 ns = 10,000 ps)
// ============================================================================
`timescale 1ps/1fs

module tb_adpll;

    localparam OTW_WIDTH = 16;
    localparam integer N = 8;
    localparam real REF_PERIOD_PS = 80000.0; // 12.5 MHz reference -> target DCO = 100 MHz (10,000 ps)

    reg                   ref_clk;
    reg                   rst_n;
    reg  [OTW_WIDTH-1:0]  otw_init;
    wire                  clk_out;
    wire                  fb_clk;
    wire [OTW_WIDTH-1:0]  otw_dbg;
    wire                  freq_locked;

    adpll_top #(
        .OTW_WIDTH (OTW_WIDTH),
        .N         (N),
        .KP        (10),
        .KI        (2)
    ) dut (
        .ref_clk     (ref_clk),
        .rst_n       (rst_n),
        .otw_init    (otw_init),
        .clk_out     (clk_out),
        .fb_clk      (fb_clk),
        .otw_dbg     (otw_dbg),
        .freq_locked (freq_locked)
    );

    // Reference clock: 12.5 MHz
    initial ref_clk = 0;
    always #(REF_PERIOD_PS / 2.0) ref_clk = ~ref_clk;

    // Output period / lock measurement
    real t_prev, t_now, period_meas;
    integer edge_cnt;
    reg locked;

    initial begin
        t_prev = 0; edge_cnt = 0; locked = 0;
    end

    always @(posedge clk_out) begin
        t_now = $realtime;
        if (t_prev != 0) begin
            period_meas = t_now - t_prev;
            edge_cnt = edge_cnt + 1;
            if (!locked && edge_cnt > 100 &&
                period_meas > (REF_PERIOD_PS / N) * 0.99 &&
                period_meas < (REF_PERIOD_PS / N) * 1.01) begin
                locked = 1;
                $display("[%0t ps] 180nm DCO LOCKED! Measured period = %0.3f ps (target %0.3f ps), OTW=%0d",
                          $realtime, period_meas, REF_PERIOD_PS / N, otw_dbg);
            end
        end
        t_prev = t_now;
    end

    initial begin
        $dumpfile("adpll.vcd");
        $dumpvars(0, tb_adpll);

        rst_n    = 0;
        otw_init = 16'd28000;
        #(REF_PERIOD_PS * 3);
        rst_n = 1;

        #(REF_PERIOD_PS * 6000);

        if (locked)
            $display("TEST PASSED: PLL acquired lock on 180nm parameters. Final OTW=%0d, period=%0.3f ps", otw_dbg, period_meas);
        else
            $display("TEST FAILED: PLL did not lock within simulation window.");

        $display("Reference period = %0.3f ps (12.5 MHz), Divider N = %0d, Target DCO period = %0.3f ps (100 MHz)",
                  REF_PERIOD_PS, N, REF_PERIOD_PS / N);

        $finish;
    end

    // Safety timeout
    initial begin
        #(REF_PERIOD_PS * 10000);
        $display("TIMEOUT: simulation ran too long without finishing.");
        $finish;
    end

endmodule
