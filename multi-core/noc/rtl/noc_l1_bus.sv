`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_l1_bus.sv (CORRECTED)
//
// L1 Intra-Cluster NoC Bus - Parallel Crossbar (4×4)
//
// Changes from original:
//   - Port names corrected to match cores_with_noc.v instantiation
//   - Added spike_secondary_mask input for per-core L2 destination masking
//   - L2 TX packet now carries secondary_mask at [4:1]
//   - L2 RX path already uses [25:22] as per-core mask - no change needed
//
// Architecture:
//   - Simultaneous TX from all 4 cores (no TX arbitration)
//   - Per-core RX round-robin arbitration (local L1 vs L2 incoming)
//   - Multicast via destination mask
//   - L2 forwarding for inter-cluster spikes
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_l1_bus #(
    parameter CLUSTER_ID = 0,
    parameter DATA_WIDTH = NOC_DATA_WIDTH
)(
    input  logic clk,
    input  logic resetn,

    // =========================================================================
    // Spike Input from per-core Routers (CORES_PER_CLUSTER = 4)
    // =========================================================================
    input  logic [16:0] spike_addr_in    [CORES_PER_CLUSTER-1:0],
    input  logic [CORES_PER_CLUSTER-1:0] spike_valid_in,
    output logic [CORES_PER_CLUSTER-1:0] spike_ready_in,
    input  logic [3:0]  spike_dest_mask  [CORES_PER_CLUSTER-1:0],  // Primary: cores (L1) or clusters (L2)
    input  logic [3:0]  spike_secondary  [CORES_PER_CLUSTER-1:0],  // Secondary: per-core mask for L2
    input  logic [1:0]  spike_level      [CORES_PER_CLUSTER-1:0],

    // =========================================================================
    // Spike Output to per-core Injectors
    // =========================================================================
    output logic [16:0] spike_addr_out   [CORES_PER_CLUSTER-1:0],
    output logic [CORES_PER_CLUSTER-1:0] spike_valid_out,
    input  logic [CORES_PER_CLUSTER-1:0] spike_ready_out,

    // =========================================================================
    // L2 Bus Interface - TX (spikes going to other clusters)
    // =========================================================================
    output logic [DATA_WIDTH-1:0] l2_tx_data,
    output logic                  l2_tx_valid,
    input  logic                  l2_tx_ready,

    // =========================================================================
    // L2 Bus Interface - RX (spikes arriving from other clusters)
    // =========================================================================
    input  logic [DATA_WIDTH-1:0] l2_rx_data,
    input  logic                  l2_rx_valid,
    output logic                  l2_rx_ready,

    // =========================================================================
    // Status
    // =========================================================================
    output logic bus_busy
);

    // =========================================================================
    // L1 Crossbar - Parallel delivery (all sources can TX simultaneously)
    // =========================================================================
    // For each destination core d, check all source cores s:
    //   If source s has an L1 spike with dest_mask bit d set → deliver

    logic [CORES_PER_CLUSTER-1:0] l1_pending  [CORES_PER_CLUSTER-1:0]; // [dst][src]
    logic [CORES_PER_CLUSTER-1:0] l2_pending;                          // L2 RX pending per dst

    genvar d, s;
    generate
        for (d = 0; d < CORES_PER_CLUSTER; d = d + 1) begin : gen_dst
            for (s = 0; s < CORES_PER_CLUSTER; s = s + 1) begin : gen_src
                // L1 spike from core s destined for core d
                assign l1_pending[d][s] = spike_valid_in[s] &&
                                          (spike_level[s] == OP_L1) &&
                                          spike_dest_mask[s][d];
            end

            // L2 RX spike destined for core d (mask at [25:22])
            assign l2_pending[d] = l2_rx_valid &&
                                   ((l2_rx_data[25:22] & (4'b0001 << d)) != 4'b0000);
        end
    endgenerate

    // =========================================================================
    // Per-Destination RX Arbitration (round-robin between L1 sources + L2)
    // =========================================================================
    logic [2:0] rx_arb_ptr [CORES_PER_CLUSTER-1:0];  // Arbitration pointer per dst

    // RX output and ready signals
    generate
        for (d = 0; d < CORES_PER_CLUSTER; d = d + 1) begin : gen_rx_arb
            logic       rx_valid_d;
            logic [16:0] rx_addr_d;
            logic       rx_from_l2;

            always_comb begin
                rx_valid_d = 1'b0;
                rx_addr_d  = 17'b0;
                rx_from_l2 = 1'b0;

                // Simple priority: check L1 sources first (round-robin), then L2
                // Start from arb_ptr and wrap around
                for (int k = 0; k < CORES_PER_CLUSTER; k = k + 1) begin
                    automatic int idx = (rx_arb_ptr[d] + k) % CORES_PER_CLUSTER;
                    if (!rx_valid_d && l1_pending[d][idx]) begin
                        rx_valid_d = 1'b1;
                        rx_addr_d  = spike_addr_in[idx];
                    end
                end

                // If no L1 source matched, check L2
                if (!rx_valid_d && l2_pending[d]) begin
                    rx_valid_d = 1'b1;
                    rx_addr_d  = l2_rx_data[21:5];  // Neuron address from L2 packet
                    rx_from_l2 = 1'b1;
                end
            end

            assign spike_valid_out[d] = rx_valid_d;
            assign spike_addr_out[d]  = rx_addr_d;

            // Update arbitration pointer
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    rx_arb_ptr[d] <= 3'd0;
                end else if (rx_valid_d && spike_ready_out[d] && !rx_from_l2) begin
                    rx_arb_ptr[d] <= (rx_arb_ptr[d] + 1) % CORES_PER_CLUSTER;
                end
            end
        end
    endgenerate

    // =========================================================================
    // L1 TX Ready - a source is "consumed" when all its L1 destinations have accepted
    // For simplicity, grant ready after one cycle of valid assertion
    // =========================================================================
    generate
        for (s = 0; s < CORES_PER_CLUSTER; s = s + 1) begin : gen_tx_ready
            // L1 spikes: ready when the crossbar has delivered this cycle
            // L2 spikes: ready is handled by the L2 TX arbiter below
            logic l1_destinations_served;

            always_comb begin
                l1_destinations_served = 1'b1;
                if (spike_valid_in[s] && spike_level[s] == OP_L1) begin
                    for (int dd = 0; dd < CORES_PER_CLUSTER; dd = dd + 1) begin
                        if (spike_dest_mask[s][dd] && !spike_ready_out[dd])
                            l1_destinations_served = 1'b0;
                    end
                end
            end

            assign spike_ready_in[s] = (spike_level[s] == OP_L1) ? l1_destinations_served :
                                       (spike_level[s] == OP_L2) ? (l2_tx_sel_valid && (l2_tx_sel == s[1:0])) :
                                       1'b1; // LOCAL/NOP: always ready (handled by router)
        end
    endgenerate

    // =========================================================================
    // L2 TX Arbitration - round-robin among cores with L2 spikes
    // =========================================================================
    logic [1:0]  l2_tx_sel;
    logic        l2_tx_sel_valid;
    logic [1:0]  l2_tx_arb_ptr;

    always_comb begin
        l2_tx_sel_valid = 1'b0;
        l2_tx_sel       = 2'b00;

        for (int k = 0; k < CORES_PER_CLUSTER; k = k + 1) begin
            automatic int idx = (l2_tx_arb_ptr + k) % CORES_PER_CLUSTER;
            if (!l2_tx_sel_valid && spike_valid_in[idx] && spike_level[idx] == OP_L2) begin
                l2_tx_sel_valid = 1'b1;
                l2_tx_sel       = idx[1:0];
            end
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            l2_tx_arb_ptr <= 2'd0;
        else if (l2_tx_sel_valid && l2_tx_ready)
            l2_tx_arb_ptr <= (l2_tx_arb_ptr + 1) % CORES_PER_CLUSTER;
    end

    // =========================================================================
    // L2 TX Packet Assembly
    // =========================================================================
    // Format: [31:30] OP_L2
    //         [29:26] source core = {CLUSTER_ID[1:0], local_core[1:0]}
    //         [25:22] primary_mask (cluster destination mask)
    //         [21:5]  neuron address (17b)
    //         [4:1]   secondary_mask (per-core mask for destination clusters)
    //         [0]     reserved (0)

    assign l2_tx_data = l2_tx_sel_valid ? {
        OP_L2,                                          // [31:30]
        CLUSTER_ID[1:0], l2_tx_sel,                     // [29:26]
        spike_dest_mask[l2_tx_sel],                     // [25:22] cluster mask
        spike_addr_in[l2_tx_sel],                       // [21:5]  neuron address
        spike_secondary[l2_tx_sel],                     // [4:1]   per-core mask
        1'b0                                            // [0]     reserved
    } : {DATA_WIDTH{1'b0}};

    assign l2_tx_valid = l2_tx_sel_valid;

    // =========================================================================
    // L2 RX Ready
    // =========================================================================
    // Accept L2 data when at least one destination core is ready
    logic l2_any_dst_ready;
    always_comb begin
        l2_any_dst_ready = 1'b0;
        for (int dd = 0; dd < CORES_PER_CLUSTER; dd = dd + 1) begin
            if (l2_pending[dd] && spike_ready_out[dd])
                l2_any_dst_ready = 1'b1;
        end
    end
    assign l2_rx_ready = l2_any_dst_ready || !l2_rx_valid;

    // =========================================================================
    // Bus Busy
    // =========================================================================
    assign bus_busy = (|spike_valid_in) || l2_rx_valid;

endmodule