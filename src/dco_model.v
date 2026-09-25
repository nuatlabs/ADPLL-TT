// ============================================================================
// File: dco_model.v
// Module: dco_model
// Project: All-Digital Phase-Locked Loop (ADPLL) - SCL 180nm C2S Node
//
// DESCRIPTION:
// Digitally Controlled Oscillator behavioral simulation model.
// Scaled for 180nm CMOS node: 100 MHz target center frequency.
// ============================================================================
`timescale 1ps/1fs

module dco_model #(
    parameter OTW_WIDTH       = 16,
    parameter integer OTW_CENTER   = 32768,   // Center code
    parameter real    T_CENTER_PS  = 10000.0, // 10,000 ps = 10.0 ns -> 100 MHz
    parameter real    GAIN_PS_PER_LSB = 0.2   // 0.2 ps of period change per LSB
) (
    input  wire [OTW_WIDTH-1:0] otw,
    output reg                  clk_out
);

    real period_ps;

    initial begin
        clk_out = 1'b0;
        period_ps = T_CENTER_PS;
    end

    always @(otw) begin
        period_ps = T_CENTER_PS - (($signed({1'b0, otw}) - OTW_CENTER) * GAIN_PS_PER_LSB);
        if (period_ps < 500.0) period_ps = 500.0;
    end

    always begin
        #(period_ps/2.0);
        clk_out = ~clk_out;
    end

endmodule
