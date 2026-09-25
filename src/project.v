/*
 * Copyright (c) 2026 NUAT Labs
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_nuatlabs_adpll (
    input  wire [7:0] ui_in,    // Dedicated inputs: [7:0] = optional coarse otw_init override
    output wire [7:0] uo_out,   // Dedicated outputs: [0]=clk_out, [1]=fb_clk, [2]=freq_locked, [3]=up_dn, [7:4]=otw[15:12]
    input  wire [7:0] uio_in,   // IOs: Input path (unused)
    output wire [7:0] uio_out,  // IOs: Output path: [7:0] = otw[11:4]
    output wire [7:0] uio_oe,   // IOs: Enable path: 8'hFF (all outputs for OTW monitoring)
    input  wire       ena,      // Always 1 when design is powered
    input  wire       clk,      // Reference Clock (12.5 MHz)
    input  wire       rst_n     // Active-low asynchronous reset
);

    // Internal wires
    wire [15:0] otw;
    wire        clk_out;
    wire        fb_clk;
    wire        freq_locked;
    wire        up_dn;

    // Coarse OTW initialization:
    // If ui_in is 0, default to 16'd28000 (standard acquisition test point).
    // If ui_in is non-zero, allow external user setting of the upper 8 bits.
    wire [15:0] otw_init = (ui_in == 8'h00) ? 16'd28000 : {ui_in, 8'h00};

    // Instantiate All-Digital Phase-Locked Loop core
    adpll_digital_top #(
        .OTW_WIDTH        (16),
        .N                (8),
        .KP               (10),
        .KI               (2),
        .USE_INTERNAL_DCO (1)
    ) u_adpll (
        .ref_clk     (clk),
        .rst_n       (rst_n & ena),
        .dco_clk_in  (1'b0),
        .otw_init    (otw_init),
        .otw         (otw),
        .clk_out     (clk_out),
        .freq_locked (freq_locked),
        .up_dn       (up_dn),
        .fb_clk      (fb_clk)
    );

    // Dedicated outputs
    assign uo_out[0]   = clk_out;      // Primary 100 MHz locked output clock
    assign uo_out[1]   = fb_clk;       // Divided 12.5 MHz feedback clock
    assign uo_out[2]   = freq_locked;  // 1 when frequency acquisition has achieved lock
    assign uo_out[3]   = up_dn;        // 1-bit Bang-Bang Phase Detector output
    assign uo_out[7:4] = otw[15:12];   // Top 4 MSBs of the Oscillator Tuning Word

    // Bidirectional IOs: configured as active outputs to expose OTW bits [11:4]
    assign uio_out[7:0] = otw[11:4];
    assign uio_oe[7:0]  = 8'hFF;       // Set all 8 bidirectional pins as outputs

    // Suppress unused warnings
    wire _unused = &{uio_in, 1'b0};

endmodule
