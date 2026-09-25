// -----------------------------------------------------------------------
// dco_ring_structural.v -- Structural Standard-Cell / FPGA Ring Oscillator DCO
//
// This module demonstrates the physical gate-level architecture of a
// Digitally Controlled Ring Oscillator (DCRO) for ASIC standard-cell or FPGA:
//
// 1. Enable / Oscillation Control:
//    An initial NAND2 gate (osc_en & feedback) allows clean startup and shutdown.
//
// 2. Coarse Tuning (OTW MSBs):
//    Selects the path length through an odd-length inverter delay chain.
//    A multiplexer taps into shorter or longer paths:
//      - Fewer inverters  -> shorter loop delay -> higher frequency
//      - More inverters   -> longer loop delay  -> lower frequency
//
// 3. Fine Tuning (OTW LSBs):
//    Digital varactor bank emulation: turns on/off parallel tri-state drivers
//    or dummy capacitive load gates attached to internal oscillation nodes.
//
// 4. Synthesis Protection:
//    (* keep = "true", dont_touch = "true" *) directives prevent synthesis
//    tools from collapsing or optimizing away the combinational loop.
// -----------------------------------------------------------------------
`timescale 1ps/1fs

module dco_ring_structural #(
    parameter NUM_TAPS = 8,
    parameter STAGES_PER_TAP = 2  // Each coarse step adds 2 inverters (maintaining odd total)
) (
    input  wire        en,        // 1 = oscillate, 0 = stop
    input  wire [2:0]  coarse_sel,// Taps into inverter chain
    input  wire [3:0]  fine_sel,  // Enables parallel load / drive cells
    output wire        clk_out
);

    localparam TOTAL_STAGES = 1 + (NUM_TAPS * STAGES_PER_TAP);

    (* keep = "true", dont_touch = "true" *) wire [TOTAL_STAGES-1:0] chain;
    (* keep = "true", dont_touch = "true" *) wire feedback_tap;

    // Stage 0: Gated inverting element (NAND gate)
    assign chain[0] = ~(en & feedback_tap);

    // Inverter chain (coarse delay line)
    genvar i;
    generate
        for (i = 1; i < TOTAL_STAGES; i = i + 1) begin : gen_inv_chain
            (* keep = "true", dont_touch = "true" *) assign chain[i] = ~chain[i-1];
        end
    endgenerate

    // Coarse Multiplexer: selects delay tap from the chain
    reg tap_selected;
    always @(*) begin
        case (coarse_sel)
            3'd0: tap_selected = chain[1 * STAGES_PER_TAP];
            3'd1: tap_selected = chain[2 * STAGES_PER_TAP];
            3'd2: tap_selected = chain[3 * STAGES_PER_TAP];
            3'd3: tap_selected = chain[4 * STAGES_PER_TAP];
            3'd4: tap_selected = chain[5 * STAGES_PER_TAP];
            3'd5: tap_selected = chain[6 * STAGES_PER_TAP];
            3'd6: tap_selected = chain[7 * STAGES_PER_TAP];
            3'd7: tap_selected = chain[8 * STAGES_PER_TAP];
            default: tap_selected = chain[1 * STAGES_PER_TAP];
        endcase
    end

    // Fine Tuning: parallel tri-state drivers modulating drive strength on the tap node
    (* keep = "true", dont_touch = "true" *) wire fine_node;
    assign fine_node = tap_selected;

    genvar j;
    generate
        for (j = 0; j < 4; j = j + 1) begin : gen_fine_drivers
            // In standard cells or FPGA, these are parallel tri-state buffers
            // or capacitive dummy loads connected to the node
            assign fine_node = fine_sel[j] ? tap_selected : 1'bz;
        end
    endgenerate

    assign feedback_tap = fine_node;
    assign clk_out      = chain[0];

endmodule
