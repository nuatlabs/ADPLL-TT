// ============================================================================
// Organization: NUAT Labs (https://github.com/nuatlabs)
// Project:      NUAT All-Digital Phase-Locked Loop (ADPLL) Silicon IP
// Module:       dco_digital
// Author:       NUAT Labs Engineering Team (admin@nuatlabs.com)
// License:      Apache-2.0 / MIT
// ============================================================================
// Digitally Controlled Oscillator (DCO) Component.
// Scaled for 180nm CMOS node (C2S eChip Hub initiative / IHP 130nm TT flow).
//
// Features:
// 1. Physical ASIC Synthesis (`ifdef SYNTHESIS`):
//    Fully synthesizable standard-cell tapped ring oscillator with gate-level
//    synthesis attributes (* keep = "true", dont_touch = "true" *).
//    Free of non-synthesizable constructs (no real types, no # delays).
//
// 2. High-Precision Behavioral Simulation (`else`):
//    Digital-to-period transfer function modeled in 0.1 ps integer units.
//    Center Period = 10,000 ps = 10.0 ns (100 MHz).
//    Sensitivity   = 0.2 ps/LSB (scaled 10x for 100 MHz target).
// ============================================================================

`timescale 1ps/1fs

module dco_digital #(
    parameter integer OTW_WIDTH  = 16,
    parameter integer OTW_CENTER = 32768
) (
    input  wire                 rst_n,   // Active-low asynchronous reset / enable
    input  wire [OTW_WIDTH-1:0] otw,     // Oscillator Tuning Word from loop filter
    output wire                 clk_out  // Generated high-speed DCO clock (100 MHz)
);

`ifdef SYNTHESIS
    // ------------------------------------------------------------------------
    // Physical Silicon Implementation: Synthesizable Tapped Ring Oscillator
    // ------------------------------------------------------------------------
    // Odd number of inverting stages with an active-low reset NAND gate.
    // keep="true" and dont_touch="true" prevent Yosys and ABC optimizer from
    // optimizing away or simplifying the combinational feedback loop.
    localparam integer NUM_STAGES = 31;
    (* keep = "true", dont_touch = "true" *) wire [NUM_STAGES-1:0] chain;
    (* keep = "true", dont_touch = "true" *) wire feedback_tap;

    // Stage 0: Active-low reset NAND gate (starts oscillation when rst_n = 1)
    assign chain[0] = ~(rst_n & feedback_tap);

    // Inverter delay chain
    genvar k;
    generate
        for (k = 1; k < NUM_STAGES; k = k + 1) begin : gen_ring_inv
            assign chain[k] = ~chain[k-1];
        end
    endgenerate

    // Delay tap multiplexer controlled by upper bits of OTW:
    reg tap_sel;
    always @(*) begin
        case (otw[15:13])
            3'd0:    tap_sel = chain[15];
            3'd1:    tap_sel = chain[17];
            3'd2:    tap_sel = chain[19];
            3'd3:    tap_sel = chain[21];
            3'd4:    tap_sel = chain[23];
            3'd5:    tap_sel = chain[25];
            3'd6:    tap_sel = chain[27];
            default: tap_sel = chain[29];
        endcase
    end

    assign feedback_tap = tap_sel;
    assign clk_out      = chain[0];

    // Suppress unused signal warnings for lower OTW bits during synthesis
    wire _unused_otw = &{otw[12:0], 1'b0};

`else
    // ------------------------------------------------------------------------
    // High-Precision Behavioral Simulation Model (Icarus / Cocotb / Verilator)
    // ------------------------------------------------------------------------
    // Modeled in units of 0.1 ps (100 fs).
    // Center half-period: 5,000.0 ps = 50,000 units of 0.1 ps.
    // Gain: 0.2 ps/LSB period -> 0.1 ps/LSB half-period (1 unit per LSB).
    reg signed [31:0] half_period_x10;
    reg               osc_node;

    always @(otw or rst_n) begin
        if (!rst_n) begin
            half_period_x10 = 32'sd50000;
        end else begin
            // Higher OTW -> shorter period -> higher frequency
            half_period_x10 = 32'sd50000 - ($signed({1'b0, otw}) - 32'sd32768);

            // Safety clamp: minimum half-period 500 ps (5,000 * 0.1 ps)
            if (half_period_x10 < 32'sd5000)
                half_period_x10 = 32'sd5000;
        end
    end

    initial begin
        osc_node = 1'b0;
    end

    // Gated oscillation loop
    always begin
        if (!rst_n) begin
            osc_node = 1'b0;
            @(posedge rst_n);
        end else begin
            #(half_period_x10 / 10.0);
            if (rst_n)
                osc_node = ~osc_node;
            else
                osc_node = 1'b0;
        end
    end

    assign clk_out = osc_node;

`endif

endmodule
