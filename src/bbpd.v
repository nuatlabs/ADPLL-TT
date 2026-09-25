// ============================================================================
// Organization: NUAT Labs (https://github.com/nuatlabs)
// Project:      NUAT All-Digital Phase-Locked Loop (ADPLL) Silicon IP
// Module:       bbpd
// Author:       NUAT Labs Engineering Team (admin@nuatlabs.com)
// License:      Apache-2.0 / MIT
// ============================================================================
// Bang-Bang Phase Detector (BBPD), also known as an Alexander Phase Detector.
//
// ----------------------------------------------------------------------------
// 1. PRINCIPLE OF OPERATION
// ----------------------------------------------------------------------------
// Traditional analog PLLs use Phase Frequency Detectors (PFDs) consisting of
// two D-flip-flops and a reset gate, driving an analog charge pump. The charge
// pump generates continuous analog current pulses proportional to the phase error.
//
// In an All-Digital PLL (ADPLL), the BBPD replaces the analog PFD + charge pump
// with a single digital flip-flop sampling the feedback clock:
//
//     up_dn = ~fb_clk sampled on posedge ref_clk
//
// - If fb_clk is LOW when ref_clk rises:
//   The DCO/feedback clock is lagging behind the reference (running slow).
//   up_dn = 1 (command the loop to speed up the DCO).
//
// - If fb_clk is HIGH when ref_clk rises:
//   The DCO/feedback clock is leading ahead of the reference (running fast).
//   up_dn = 0 (command the loop to slow down the DCO).
//
// ----------------------------------------------------------------------------
// 2. MATHEMATICAL MODEL & NON-LINEAR DYNAMICS
// ----------------------------------------------------------------------------
// The BBPD has a binary signum transfer function:
//
//     up_dn(t) = sgn(theta_ref(t) - theta_fb(t))
//
// Characteristics of Bang-Bang PLLs:
// - Gain (K_bb): Infinite small-signal slope at zero phase error; smoothed in
//   the presence of input noise/jitter into an effective linearized Gaussian gain.
// - Limit Cycle: In locked steady-state, the BBPD toggles rapidly between
//   1 and 0 (...1, 0, 1, 0...) around zero phase difference. This residual
//   dither is the normal signature of a locked bang-bang PLL.
//
// ----------------------------------------------------------------------------
// 3. SYNTHESIS & PHYSICAL DESIGN (PD) NOTES
// ----------------------------------------------------------------------------
// - Cell mapping: Maps directly to a single standard-cell D-type Flip-Flop (DFF).
// - Timing constraints: The data input (fb_clk) and clock input (ref_clk)
//   originate from different clock networks. Setup/hold timing at this DFF
//   determines the detector's metastability window. In deep submicron designs,
//   a dedicated high-speed arbiter or sense-amplifier latch is often used.
// ============================================================================

`timescale 1ps/1fs

module bbpd (
    input  wire ref_clk,   // Golden reference clock input (e.g., 125 MHz)
    input  wire rst_n,     // Active-low asynchronous reset
    input  wire fb_clk,    // Divided feedback clock from DCO (e.g., 125 MHz)
    output reg  up_dn      // 1-bit phase error decision: 1 = Speed Up, 0 = Slow Down
);

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n)
            up_dn <= 1'b0;
        else
            up_dn <= ~fb_clk;   // Sample inverse of feedback clock
    end

endmodule
