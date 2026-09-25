// ============================================================================
// Organization: NUAT Labs (https://github.com/nuatlabs)
// Project:      NUAT All-Digital Phase-Locked Loop (ADPLL) Silicon IP
// Module:       clk_divider
// Author:       NUAT Labs Engineering Team (admin@nuatlabs.com)
// License:      Apache-2.0 / MIT
// ============================================================================
// Programmable Integer Feedback Clock Divider (/N).
//
// ----------------------------------------------------------------------------
// 1. PRINCIPLE OF OPERATION
// ----------------------------------------------------------------------------
// In an ADPLL frequency synthesizer, the feedback divider establishes the
// multiplication ratio between the input reference clock and the high-speed DCO:
//
//     F_DCO = N * F_REF
//     T_REF = N * T_DCO
//
// Here, with N = 8 and F_REF = 125 MHz:
//     F_DCO = 8 * 125 MHz = 1.0 GHz
//     T_DCO = 8000 ps / 8 = 1000 ps (1.0 ns)
//
// ----------------------------------------------------------------------------
// 2. 50% DUTY CYCLE TOGGLE ARCHITECTURE
// ----------------------------------------------------------------------------
// To ensure the feedback clock (fb_clk) has an exact 50% duty cycle, this
// module maintains an internal modulo counter (cnt) that counts up to HALF - 1,
// where HALF = N / 2.
//
// On every terminal count, clk_out toggles its state (invert):
//     HALF cycles HIGH, HALF cycles LOW -> Total period = 2 * HALF = N cycles.
//
// ----------------------------------------------------------------------------
// 3. PHYSICAL DESIGN & TIMING CONSIDERATIONS
// ----------------------------------------------------------------------------
// - Highest Speed Path in the PLL: This divider is clocked directly by clk_in
//   (1.0 GHz DCO output, period = 1000 ps).
// - Critical Path: clk_in -> flip-flop clock-to-q -> comparator (cnt == HALF-1)
//   -> next-state mux -> flip-flop setup time.
// - At 1 GHz in standard digital CMOS (e.g. Sky130 or Nangate45), this counter
//   must be kept compact (low bit-width, fast adder) to meet setup timing.
// ============================================================================

`timescale 1ps/1fs

module clk_divider #(
    parameter integer N         = 8, // Feedback divide ratio (F_DCO = N * F_REF)
    parameter integer CNT_WIDTH = 8  // Bit-width of the internal cycle counter
) (
    input  wire clk_in,   // High-speed clock input from DCO (e.g. 1.0 GHz)
    input  wire rst_n,    // Active-low asynchronous reset
    output reg  clk_out   // Divided feedback clock output (e.g. 125 MHz, 50% duty cycle)
);

    reg [CNT_WIDTH-1:0] cnt;
    localparam [CNT_WIDTH-1:0] HALF_LIMIT = ((N/2 < 1) ? 1'b0 : (N[CNT_WIDTH-1:0]/2 - 1'b1));

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= {CNT_WIDTH{1'b0}};
            clk_out <= 1'b0;
        end else if (cnt == HALF_LIMIT) begin
            cnt     <= {CNT_WIDTH{1'b0}};
            clk_out <= ~clk_out;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule
