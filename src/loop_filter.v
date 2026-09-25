// ============================================================================
// Organization: NUAT Labs (https://github.com/nuatlabs)
// Project:      NUAT All-Digital Phase-Locked Loop (ADPLL) Silicon IP
// Module:       loop_filter
// Author:       NUAT Labs Engineering Team (admin@nuatlabs.com)
// License:      Apache-2.0 / MIT
// ============================================================================
// Dual-Stage Digital Loop Filter (Coarse AFC + Fine Bang-Bang PI Tracking).
//
// ----------------------------------------------------------------------------
// 1. WHAT IS OTW (OSCILLATOR TUNING WORD)?
// ----------------------------------------------------------------------------
// In an analog PLL, the VCO frequency is controlled by a continuous analog
// voltage (V_ctrl). In an All-Digital PLL (ADPLL), there is no analog voltage;
// the frequency is controlled by a multi-bit digital bus: OTW[15:0].
//
// - OTW is the numerical output of this filter and the digital input to the DCO.
// - Higher OTW -> Shorter DCO oscillation period -> Higher frequency.
// - Lower OTW  -> Longer DCO oscillation period  -> Lower frequency.
// - Nominal center: OTW = 32768 (midscale 16-bit) -> 1.0 GHz (1000 ps period).
//
// ----------------------------------------------------------------------------
// 2. WHY A DUAL-STAGE FILTER? (THE ALIASING PROBLEM)
// ----------------------------------------------------------------------------
// A Bang-Bang Phase Detector (BBPD) produces only 1 bit of information per
// cycle: 1 (late) or 0 (early).
//
// - Problem: If the DCO starts far from the target frequency (e.g., 800 MHz
//   instead of 1000 MHz), the phase difference rotates around 360 degrees
//   repeatedly. A 1-bit BBPD aliases and cannot differentiate between a small
//   phase error and a huge multi-cycle frequency error. The loop can wander
//   or take millions of cycles to drift into lock.
//
// - Solution: Dual-Stage Architecture:
//     * STAGE 1: Automatic Frequency Control (AFC / Coarse Acquisition):
//       Measures pure frequency (ignoring phase) by counting feedback clock
//       edges in a calibrated reference window. Takes large, proportional
//       correction jumps: otw <= otw + (freq_err * KFREQ).
//     * STAGE 2: Bang-Bang PI Phase Tracking (Fine Acquisition & Lock):
//       Once frequency error is within +/-0.5%, the filter freezes the coarse
//       baseline (otw_base) and hands control to a proportional-integral (PI)
//       loop to eliminate phase error and minimize output jitter.
//
// ----------------------------------------------------------------------------
// 3. WHY DOES THE FEEDBACK CLOCK (fb_clk) ENTER THIS FILTER?
// ----------------------------------------------------------------------------
// In traditional analog PLLs, fb_clk only connects to the phase detector.
// In this ADPLL, fb_clk MUST also connect to the loop filter because Stage 1
// (AFC) requires direct frequency measurement.
//
// The filter contains an internal edge counter (fb_edge_cnt) clocked directly
// on posedge fb_clk. At the end of every WINDOW (200) ref_clk cycles, the
// filter compares the number of fb_clk edges seen against the expected 200:
//
//     diff_latched = (fb_edge_cnt_now - fb_edge_cnt_prev) mod 256
//     freq_err     = WINDOW - diff_latched
//
// If diff_latched < 200 -> DCO is too slow -> freq_err > 0 -> Increase OTW.
// If diff_latched > 200 -> DCO is too fast -> freq_err < 0 -> Decrease OTW.
//
// Without fb_clk entering the filter, frequency measurement is impossible.
// ============================================================================

`timescale 1ps/1fs

module loop_filter #(
    parameter OTW_WIDTH    = 16,   // Bit-width of the Oscillator Tuning Word (OTW)
    parameter KP           = 50,   // Fine tracking proportional gain (damping/phase lead)
    parameter KI           = 25,   // Fine tracking integral gain (zero static phase error)
    parameter WINDOW       = 200,  // AFC measurement window in ref_clk cycles
    parameter KFREQ        = 50,   // Coarse AFC gain: OTW LSB step per unit frequency error
    parameter LOCK_WINDOWS = 3     // Confidence threshold: consecutive good windows for lock
) (
    input  wire                   ref_clk,     // Reference clock (125 MHz in this design)
    input  wire                   rst_n,       // Active-low asynchronous reset
    input  wire                   up_dn,       // 1-bit phase error from BBPD (Stage 2)
    input  wire                   fb_clk,      // Divided clock from DCO (Stage 1 frequency counter)
    input  wire [OTW_WIDTH-1:0]   otw_init,    // Initial OTW value applied upon reset
    output reg  [OTW_WIDTH-1:0]   otw,         // Output tuning word to the DCO
    output reg                    freq_locked  // Status: 1 = coarse lock achieved, PI tracking active
);

    // ========================================================================
    // STAGE 1A: FEEDBACK EDGE COUNTER (fb_clk Domain)
    // ========================================================================
    // Free-running 8-bit counter incrementing on every positive edge of fb_clk.
    // Overflows naturally modulo-256.
    reg [7:0] fb_edge_cnt;

    always @(posedge fb_clk or negedge rst_n) begin
        if (!rst_n)
            fb_edge_cnt <= 8'd0;
        else
            fb_edge_cnt <= fb_edge_cnt + 8'd1;
    end

    // ========================================================================
    // STAGE 1B: WINDOW TIMER & EDGE SAMPLING (ref_clk Domain)
    // ========================================================================
    // A window counter (win_cnt) counts 0 to WINDOW-1 (e.g. 0 to 199).
    // On terminal count:
    //   1. Computes the delta edges: (fb_edge_cnt - fb_cnt_prev) modulo 256.
    //   2. Latching diff_latched and asserting window_done for 1 cycle.
    reg [$clog2(WINDOW+1)-1:0] win_cnt;
    reg [7:0]                  fb_cnt_prev;
    reg signed [8:0]           diff_latched;
    reg                        window_done;

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            win_cnt      <= 0;
            fb_cnt_prev  <= 8'd0;
            diff_latched <= 9'sd0;
            window_done  <= 1'b0;
        end else if (win_cnt == WINDOW - 1) begin
            win_cnt      <= 0;
            // Subtract in 8-bit first so it wraps modulo-256 correctly, then sign-extend
            diff_latched <= $signed({1'b0, (fb_edge_cnt - fb_cnt_prev)});
            fb_cnt_prev  <= fb_edge_cnt;
            window_done  <= 1'b1;
        end else begin
            win_cnt     <= win_cnt + 1'b1;
            window_done <= 1'b0;
        end
    end

    // ========================================================================
    // STAGE 1C: FREQUENCY ERROR & LEAKY-BUCKET LOCK DETECTOR (ref_clk Domain)
    // ========================================================================
    // Calculates freq_err = WINDOW - diff_latched.
    // Uses a saturating confidence counter (good_windows) to prevent premature
    // handoff due to a single edge coincidence, while decrementing (leaky bucket)
    // rather than resetting to zero on jitter.
    reg signed [OTW_WIDTH-1:0] freq_err;
    reg [3:0]                  good_windows;
    wire                       match = (diff_latched >= WINDOW - 1) && (diff_latched <= WINDOW + 1);

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            freq_err     <= {OTW_WIDTH{1'b0}};
            good_windows <= 4'd0;
            freq_locked  <= 1'b0;
        end else if (window_done) begin
            freq_err <= $signed({1'b0, WINDOW}) - diff_latched;
            if (match) begin
                if (good_windows < LOCK_WINDOWS)
                    good_windows <= good_windows + 1'b1;
                if (good_windows == LOCK_WINDOWS - 1)
                    freq_locked <= 1'b1; // Trigger handoff to Stage 2
            end else if (good_windows > 0) begin
                good_windows <= good_windows - 1'b1; // Leaky bucket decrement
            end
        end
    end

    // ========================================================================
    // STAGE 2: FINE BANG-BANG PROPORTIONAL-INTEGRAL (PI) CONTROLLER
    // ========================================================================
    // When freq_locked == 0:
    //   Applies coarse OTW corrections: otw <= otw + (freq_err * KFREQ).
    //   Keeps fine integrator cleared.
    //
    // When freq_locked == 1:
    //   1. Freezes baseline: otw_base <= otw on the exact cycle of handoff.
    //   2. Accumulates phase error: integrator <= integrator +/- KI.
    //   3. Adds proportional damping: fine_error = +/- KP.
    //   4. Generates final tuning word: OTW = otw_base + integrator + fine_error.
    reg signed [OTW_WIDTH-1:0] integrator;
    reg        [OTW_WIDTH-1:0] otw_base;
    reg                        freq_locked_d;
    wire signed [OTW_WIDTH-1:0] fine_error = up_dn ? KP : -KP;

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            integrator    <= {OTW_WIDTH{1'b0}};
            otw           <= otw_init;
            otw_base      <= otw_init;
            freq_locked_d <= 1'b0;
        end else begin
            freq_locked_d <= freq_locked;
            if (!freq_locked) begin
                // Coarse AFC updates on window_done
                if (window_done)
                    otw <= otw + (freq_err * KFREQ);
                integrator <= {OTW_WIDTH{1'b0}};
            end else begin
                // Capture baseline on rising edge of freq_locked
                if (freq_locked && !freq_locked_d)
                    otw_base <= otw;

                // Fine PI update on every ref_clk edge
                integrator <= integrator + (up_dn ? KI : -KI);
                otw        <= otw_base + integrator + fine_error;
            end
        end
    end

endmodule
