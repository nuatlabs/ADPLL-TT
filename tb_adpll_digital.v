// ============================================================================
// Organization: NUAT Labs (https://github.com/nuatlabs)
// Project:      NUAT All-Digital Phase-Locked Loop (ADPLL) Silicon IP
// Module:       tb_adpll_digital
// Author:       NUAT Labs Engineering Team (admin@nuatlabs.com)
// License:      Apache-2.0 / MIT
// ============================================================================
// Testbench for verifying adpll_digital_top scaled for 180nm CMOS:
// - Reference Clock: 12.5 MHz (Period = 80.0 ns = 80,000 ps)
// - Feedback Divider: N = 8
// - Target DCO Clock: 100 MHz (Period = 10.0 ns = 10,000 ps)
// ============================================================================
`timescale 1ps/1fs

module tb_adpll_digital;

    localparam OTW_WIDTH = 16;
    localparam integer N = 8;
    localparam real REF_PERIOD_PS = 80000.0; // 12.5 MHz reference -> Target DCO = 100 MHz (10,000 ps)

    reg                  ref_clk;
    reg                  rst_n;
    reg  [OTW_WIDTH-1:0] otw_init;
    wire                 clk_out;
    wire                 fb_clk;
    wire [OTW_WIDTH-1:0] otw;
    wire                 freq_locked;

    adpll_digital_top #(
        .OTW_WIDTH        (OTW_WIDTH),
        .N                (N),
        .KP               (10),
        .KI               (2),
        .USE_INTERNAL_DCO (1)
    ) dut (
        .ref_clk     (ref_clk),
        .rst_n       (rst_n),
        .dco_clk_in  (1'b0), // Unused when USE_INTERNAL_DCO = 1
        .otw_init    (otw_init),
        .otw         (otw),
        .clk_out     (clk_out),
        .freq_locked (freq_locked),
        .up_dn       (),
        .fb_clk      (fb_clk)
    );

    // Reference clock: 12.5 MHz
    initial ref_clk = 0;
    always #(REF_PERIOD_PS / 2.0) ref_clk = ~ref_clk;

    // Measurement logic
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
            // Declare lock once period stays within 1% of 10,000 ps target
            if (!locked && edge_cnt > 100 &&
                period_meas > (REF_PERIOD_PS / N) * 0.99 &&
                period_meas < (REF_PERIOD_PS / N) * 1.01) begin
                locked = 1;
                $display("[%0t ps] 180nm ADPLL LOCKED! Measured period = %0.3f ps (target %0.3f ps), OTW=%0d",
                          $realtime, period_meas, REF_PERIOD_PS / N, otw);
            end
        end
        t_prev = t_now;
    end

    initial begin
        $dumpfile("adpll_180nm.vcd");
        $dumpvars(0, tb_adpll_digital);

        rst_n    = 0;
        otw_init = 16'd28000; // Start deliberately off-center (period ~10,953 ps)
        #(REF_PERIOD_PS * 3);
        rst_n = 1;

        #(REF_PERIOD_PS * 6000); // Allow loop settling

        if (locked)
            $display("TEST PASSED: 180nm ADPLL locked successfully! Final OTW=%0d, period=%0.3f ps", otw, period_meas);
        else
            $display("TEST FAILED: Loop did not lock in time.");

        $display("Reference Freq = 12.5 MHz (Period = %0.1f ps), Target DCO Freq = 100 MHz (Period = %0.1f ps)",
                  REF_PERIOD_PS, REF_PERIOD_PS / N);

        $finish;
    end

    // Safety timeout
    initial begin
        #(REF_PERIOD_PS * 10000);
        $display("TIMEOUT: Simulation ran too long without finishing.");
        $finish;
    end

endmodule
