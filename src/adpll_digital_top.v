// ============================================================================
// Organization: NUAT Labs (https://github.com/nuatlabs)
// Project:      NUAT All-Digital Phase-Locked Loop (ADPLL) Silicon IP
// Module:       adpll_digital_top
// Author:       NUAT Labs Engineering Team (admin@nuatlabs.com)
// License:      Apache-2.0 / MIT
// ============================================================================
// 1. ARCHITECTURAL OVERVIEW (180 nm SCL NODE / IHP 130 nm TT FLOW)
// ----------------------------------------------------------------------------
// Comprehensive All-Digital Phase-Locked Loop (ADPLL) Architecture:
//
//   ref_clk (12.5 MHz Reference)                                                       fb_clk (12.5 MHz Feedback)
//      |           +-----------------------------------------------------------------------+          |
//      +---------->|             DUAL-STAGE DIGITAL LOOP FILTER (loop_filter.v)            |<---------+ (AFC Edge Clock)
//      |           |                                                                       |          |
//      |           | [STAGE 1: AFC Coarse Frequency Acquisition]                           |          |
//      |           | - Window counter on ref_clk (WINDOW = 200 cycles)                     |          |
//      |           | - Edge counter clocked on fb_clk (fb_edge_cnt)                        |          |
//      |           | - Frequency error: freq_err = 200 - diff_latched                      |          |
//      |           | - Fast coarse jumps: otw <= otw + (freq_err * 50)                     |          |
//      |           |                            |                                          |          |
//      |           |                            v (Handoff: |freq_err| <= 1)               |          |
//      |           |                            | (freq_locked = 1, freeze otw_base)       |          |
//      |           |                            v                                          |          |
//      |  up_dn -->| [STAGE 2: Bang-Bang PI Fine Tracking Loop]                            |          |
//      | (1-bit)   | - Proportional Lead: fine_err = (up_dn ? +10 : -10)                   |          |
//      |    ^      | - Integral Lag:     integrator <= integrator +/- 2                    |          |
//      +----+----->| - Locked Tuning Word: otw = otw_base + integrator + fine_err          |          |
//      |    |      | - Clocks PI accumulator on posedge ref_clk                            |          |
//      |    |      +-----------------------------------------------------------------------+          |
//      |    |                                  |                                                      |
//      |    |                                  | otw[15:0] (16-bit Tuning Word)                       |
//      |    |                                  v                                                      |
//      |    |      +-----------------------------------------------------------------------+          |
//      |    |      |                   DIGITAL DCO CORE (dco_digital.v)                    |          |
//      |    |      |                                                                       |          |
//      |    |      | - Coarse Tuning Bank: otw[15:13] (3-bit)                              |          |
//      |    |      |   31-stage tapped delay line inverter MUX                             |          |
//      |    |      |                                                                       |          |
//      |    |      | - Fine Tuning Bank:   otw[12:0] (13-bit)                              |          |
//      |    |      |   0.1 ps fine delay / capacitive varactor steps                       |          |
//      |    |      +-----------------------------------------------------------------------+          |
//      |    |                                  |                                                      |
//      |    |                                  | clk_out (100 MHz Locked Clock)                       |
//      |    |                                  +--------------------+------------------------> clk_out (100 MHz)
//      |    |                                  |                    |                          [Pad uo_out[0]]
//      |    |                                  |                    v                                 |
//      |    |                                  |        +-----------------------+                     |
//      |    |                                  |        | FEEDBACK CLOCK DIVIDER|                     |
//      |    |                                  |        |    (clk_divider.v)    |                     |
//      |    |                                  |        | - Integer divide: /8  |                     |
//      |    |  up_dn (1-bit)                   |        | - 50% duty cycle      |                     |
//      |    |                                  |        +-----------------------+                     |
//      |    |                                  |                    |                                 |
//      |    |                                  |                    | fb_clk (12.5 MHz)               |
//      |  +-+------------------------+         |                    +---+--------------------> fb_clk (12.5 MHz)
//      |  |   BBPD PHASE DETECTOR    |         |                    |   |                      [Pad uo_out[7]]
//      |  |        (bbpd.v)          |         |                    |   |                             |
//      |  |                          |         |                    |   +-----------------------------+
//      +->| - Samples ~fb_clk on     |<--------+--------------------+
//         |   posedge of ref_clk     |         fb_clk Feedback Bus
//         +--------------------------+
//
// ----------------------------------------------------------------------------
// 2. CONFIGURABLE DCO INTEGRATION MODES
// ----------------------------------------------------------------------------
// Parameter: USE_INTERNAL_DCO
//
// - USE_INTERNAL_DCO = 1 (Default: Fully Self-Contained All-Digital PLL):
//   Instantiates dco_digital internally. The module generates its own 100 MHz
//   clock on clk_out. No external oscillator is required.
//
// - USE_INTERNAL_DCO = 0 (ASIC Hard-Macro Partitioning Mode):
//   Excludes the internal DCO logic. The tuning word is exported via port otw
//   to an external analog/mixed-signal custom DCO hard macro, and the returning
//   clock is received on port dco_clk_in.
//
// ----------------------------------------------------------------------------
// 3. KEY METRICS & FORMULAS (180 nm C2S SCALED)
// ----------------------------------------------------------------------------
// - Reference Clock:        F_REF = 12.5 MHz (T_REF = 80.0 ns = 80,000 ps)
// - Output Frequency:       F_DCO = N * F_REF = 8 * 12.5 MHz = 100 MHz
// - Output Period:          T_DCO = T_REF / N = 80,000 ps / 8 = 10,000 ps (10.0 ns)
// - Tuning Word Relation:   T_period = 10,000 ps - ( (OTW - 32768) * 0.2 ps )
// ============================================================================

`timescale 1ps/1fs

module adpll_digital_top #(
    parameter OTW_WIDTH        = 16, // Bit-width of the Oscillator Tuning Word
    parameter integer N        = 8,  // Feedback multiplication ratio: F_DCO = N * F_REF
    parameter KP               = 10, // Proportional gain for fine tracking
    parameter KI               = 2,  // Integral gain for fine tracking
    parameter USE_INTERNAL_DCO = 1   // 1 = Synthesizable internal DCO, 0 = External macro
) (
    input  wire                 ref_clk,     // Golden reference clock (e.g., 125 MHz)
    input  wire                 rst_n,       // Active-low asynchronous system reset
    input  wire                 dco_clk_in,  // External DCO clock input (used if USE_INTERNAL_DCO = 0)
    input  wire [OTW_WIDTH-1:0] otw_init,    // Initial tuning word supplied on reset
    output wire [OTW_WIDTH-1:0] otw,         // Current tuning word (for debug or external DCO)
    output wire                 clk_out,     // PLL high-speed output clock (100 MHz)
    output wire                 freq_locked, // 1 = Frequency acquisition complete, PI active
    output wire                 up_dn,       // 1-bit Bang-Bang phase detector sign decision
    output wire                 fb_clk       // Feedback clock divided by N (phase-locked to ref_clk)
);

    // Internal interconnects
    wire dco_clk_internal;
    wire dco_active_clk;

    // ------------------------------------------------------------------------
    // Sub-Module 1: Bang-Bang Phase Detector (BBPD)
    // ------------------------------------------------------------------------
    // Samples ~fb_clk on posedge ref_clk to generate a 1-bit early/late decision
    bbpd u_bbpd (
        .ref_clk (ref_clk),
        .rst_n   (rst_n),
        .fb_clk  (fb_clk),
        .up_dn   (up_dn)
    );

    // ------------------------------------------------------------------------
    // Sub-Module 2: Dual-Stage Digital Loop Filter
    // ------------------------------------------------------------------------
    // Stage 1 (AFC): Counts fb_clk edges over a 200-cycle ref_clk window to correct
    //                large initial frequency offsets without phase-aliasing.
    // Stage 2 (PI):  Proportional-Integral tracking on up_dn for zero phase error.
    loop_filter #(
        .OTW_WIDTH (OTW_WIDTH),
        .KP        (KP),
        .KI        (KI)
    ) u_loop_filter (
        .ref_clk     (ref_clk),
        .rst_n       (rst_n),
        .up_dn       (up_dn),
        .fb_clk      (fb_clk),
        .otw_init    (otw_init),
        .otw         (otw),
        .freq_locked (freq_locked)
    );

    // ------------------------------------------------------------------------
    // Sub-Module 3: Digitally Controlled Oscillator (DCO)
    // ------------------------------------------------------------------------
    generate
        if (USE_INTERNAL_DCO) begin : gen_internal_dco
            dco_digital #(
                .OTW_WIDTH (OTW_WIDTH)
            ) u_dco (
                .rst_n   (rst_n),
                .otw     (otw),
                .clk_out (dco_clk_internal)
            );
            assign dco_active_clk = dco_clk_internal;
        end else begin : gen_external_dco
            assign dco_clk_internal = 1'b0;
            assign dco_active_clk   = dco_clk_in;
        end
    endgenerate

    // Drive primary PLL high-speed clock output
    assign clk_out = dco_active_clk;

    // ------------------------------------------------------------------------
    // Sub-Module 4: Programmable Integer Feedback Divider (/N)
    // ------------------------------------------------------------------------
    // Divides high-speed DCO clock down to ref_clk frequency with 50% duty cycle
    clk_divider #(
        .N (N)
    ) u_div (
        .clk_in  (dco_active_clk),
        .rst_n   (rst_n),
        .clk_out (fb_clk)
    );

    // Suppress unused input warning when internal DCO is active
    wire _unused_top = &{dco_clk_in, 1'b0};

endmodule
