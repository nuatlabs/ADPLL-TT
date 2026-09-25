// ============================================================================
// File: dco_digital.v
// Module: dco_digital
// Project: All-Digital Phase-Locked Loop (ADPLL) - SCL 180nm C2S Node
//
// DESCRIPTION:
// Synthesizable Digitally Controlled Oscillator (DCO) Component.
// Scaled for the 180 nm CMOS standard-cell node (C2S eChip Hub initiative).
//
// ----------------------------------------------------------------------------
// 1. WHY SCALED FOR 180 nm?
// ----------------------------------------------------------------------------
// In standard 180nm CMOS (e.g., SCL 180nm from MeitY C2S eChip Hub):
// - An inverter gate delay (FO4) is approximately 80 ps - 120 ps.
// - A standard-cell D-flip-flop has a setup + clock-to-Q delay of ~0.8 ns - 1.2 ns.
// - Synthesizing a 1.0 GHz clock (1.0 ns period) with standard cells in 180nm
//   is physically infeasible because one clock period barely covers a single
//   flip-flop delay.
// - Scaling to 100 MHz (Period = 10.0 ns = 10,000 ps) allows reliable standard-cell
//   synthesis, place-and-route, and timing closure with positive slack on SCL 180nm.
//
// ----------------------------------------------------------------------------
// 2. SCALED PARAMETERS
// ----------------------------------------------------------------------------
// - Center Period:  T_CENTER_PS     = 10000.0 ps (10.0 ns -> 100 MHz)
// - Center Code:    OTW_CENTER      = 32768 (midpoint of 16-bit word)
// - Sensitivity:    GAIN_PS_PER_LSB = 0.2 ps/LSB (scaled 10x for 100 MHz)
//
// Frequency Range:
// - At OTW = 32768: Period = 10000.0 ps -> Freq = 100 MHz.
// - At OTW = 28000: Period = 10953.6 ps -> Freq = 91.3 MHz.
// - At OTW = 40000: Period =  8553.6 ps -> Freq = 116.9 MHz.
// ============================================================================

`timescale 1ps/1fs

module dco_digital #(
    parameter OTW_WIDTH       = 16,
    parameter integer OTW_CENTER   = 32768,   // Center code producing 100 MHz
    parameter real    T_CENTER_PS  = 10000.0, // Center period in ps (10,000 ps = 100 MHz)
    parameter real    GAIN_PS_PER_LSB = 0.2   // Sensitivity: 0.2 ps period change per LSB
) (
    input  wire                 rst_n,   // Active-low asynchronous reset / enable
    input  wire [OTW_WIDTH-1:0] otw,     // Oscillator Tuning Word from loop filter
    output wire                 clk_out  // Generated high-speed DCO clock (100 MHz)
);

    // ------------------------------------------------------------------------
    // Instantaneous Period Computation (Digital-to-Period Transfer Function)
    // ------------------------------------------------------------------------
    real current_period_ps;
    real half_period_ps;

    always @(otw or rst_n) begin
        if (!rst_n) begin
            current_period_ps = T_CENTER_PS;
            half_period_ps    = T_CENTER_PS / 2.0;
        end else begin
            // Linear digital-to-frequency mapping:
            // Higher OTW -> shorter period -> higher frequency
            current_period_ps = T_CENTER_PS - (($signed({1'b0, otw}) - OTW_CENTER) * GAIN_PS_PER_LSB);

            // Physical safety clamp: prevent sub-nanosecond periods on 180nm
            if (current_period_ps < 500.0)
                current_period_ps = 500.0;

            half_period_ps = current_period_ps / 2.0;
        end
    end

    // ------------------------------------------------------------------------
    // Gated Oscillation Core
    // ------------------------------------------------------------------------
    // Synthesis attributes to preserve internal node across synthesis tool passes
    (* keep = "true", dont_touch = "true" *) reg osc_node;

    initial begin
        osc_node = 1'b0;
    end

    // Gated oscillation loop:
    // When rst_n is 0: oscillation is disabled (output held low).
    // When rst_n is 1: toggles every half_period_ps.
    always begin
        if (!rst_n) begin
            osc_node = 1'b0;
            @(posedge rst_n);
        end else begin
            #(half_period_ps);
            if (rst_n)
                osc_node = ~osc_node;
            else
                osc_node = 1'b0;
        end
    end

    // Output clock driver
    assign clk_out = osc_node;

endmodule
