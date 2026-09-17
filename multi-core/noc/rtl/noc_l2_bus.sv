`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_l2_bus.sv (CORRECTED)
//
// L2 Inter-Cluster NoC Bus - Parallel Crossbar (4×4)
//
// Changes from original:
//   - Port names corrected to match cores_with_noc.v instantiation
//   - Per-core mask forwarding: extracts secondary_mask from [4:1] of incoming
//     packet and places it at [25:22] of forwarded packet, instead of
//     hardcoding 4'b1111 (broadcast to all cores in destination cluster)
//   - Added OP_NOP in the opcode comments for clarity
//
// Architecture:
//   - Simultaneous TX from all 4 clusters (no TX arbitration)
//   - Per-cluster RX round-robin arbitration
//   - Multicast via cluster destination mask at [25:22] of incoming L2 packet
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_l2_bus #(
    parameter DATA_WIDTH = NOC_DATA_WIDTH
)(
    input  logic clk,
    input  logic resetn,

    // =========================================================================
    // L1 Bus TX Interface (spikes from clusters going inter-cluster)
    // One port per cluster
    // =========================================================================
    input  logic [DATA_WIDTH-1:0] l1_tx_data  [NUM_CLUSTERS-1:0],
    input  logic [NUM_CLUSTERS-1:0]           l1_tx_valid,
    output logic [NUM_CLUSTERS-1:0]           l1_tx_ready,

    // =========================================================================
    // L1 Bus RX Interface (spikes delivered to destination clusters)
    // One port per cluster
    // =========================================================================
    output logic [DATA_WIDTH-1:0] l1_rx_data  [NUM_CLUSTERS-1:0],
    output logic [NUM_CLUSTERS-1:0]           l1_rx_valid,
    input  logic [NUM_CLUSTERS-1:0]           l1_rx_ready,

    // =========================================================================
    // Status
    // =========================================================================
    output logic bus_busy
);

    // =========================================================================
    // L2 Crossbar - Route based on cluster destination mask
    // =========================================================================
    // Incoming L2 packet from cluster src:
    //   [31:30] = OP_L2
    //   [29:26] = source core ID
    //   [25:22] = cluster destination mask (which clusters to send to)
    //   [21:5]  = neuron address
    //   [4:1]   = per-core mask (secondary, for destination clusters)
    //   [0]     = reserved

    // For each destination cluster, check if any source cluster has a packet for it
    logic [NUM_CLUSTERS-1:0] xbar_pending [NUM_CLUSTERS-1:0];  // [dst][src]

    genvar dst, src;
    generate
        for (dst = 0; dst < NUM_CLUSTERS; dst = dst + 1) begin : gen_dst
            for (src = 0; src < NUM_CLUSTERS; src = src + 1) begin : gen_src
                // Source src has packet for destination dst?
                // Don't route back to same cluster
                assign xbar_pending[dst][src] = l1_tx_valid[src] &&
                                                (src != dst) &&
                                                ((l1_tx_data[src][25:22] & (4'b0001 << dst)) != 4'b0000);
            end
        end
    endgenerate

    // =========================================================================
    // Per-Destination RX Arbitration (round-robin among source clusters)
    // =========================================================================
    logic [1:0] rx_arb_ptr [NUM_CLUSTERS-1:0];

    generate
        for (dst = 0; dst < NUM_CLUSTERS; dst = dst + 1) begin : gen_rx_arb

            logic       rx_sel_valid;
            logic [1:0] rx_sel;

            always_comb begin
                rx_sel_valid = 1'b0;
                rx_sel       = 2'b00;
                for (int k = 0; k < NUM_CLUSTERS; k = k + 1) begin
                    automatic int idx = (rx_arb_ptr[dst] + k) % NUM_CLUSTERS;
                    if (!rx_sel_valid && xbar_pending[dst][idx]) begin
                        rx_sel_valid = 1'b1;
                        rx_sel       = idx[1:0];
                    end
                end
            end

            // =====================================================================
            // Packet transformation: L2 → L1 for local delivery
            // =====================================================================
            // CRITICAL CHANGE: Use per-core mask from [4:1] instead of 4'b1111
            //
            // Before (original):  mask = 4'b1111 (broadcast to all cores)
            // After  (corrected): mask = l1_tx_data[rx_sel][4:1] (per-core mask)

            always_comb begin
                if (rx_sel_valid) begin
                    l1_rx_data[dst] = {
                        OP_L1,                             // [31:30] Change opcode to L1
                        l1_tx_data[rx_sel][29:26],         // [29:26] Source core (unchanged)
                        l1_tx_data[rx_sel][4:1],           // [25:22] Per-core mask from secondary
                        l1_tx_data[rx_sel][21:5],          // [21:5]  Neuron address
                        5'b0                               // [4:0]   Timestamp (cleared)
                    };
                end else begin
                    l1_rx_data[dst] = {DATA_WIDTH{1'b0}};
                end
            end

            assign l1_rx_valid[dst] = rx_sel_valid;

            // Update arbitration pointer
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn)
                    rx_arb_ptr[dst] <= 2'd0;
                else if (rx_sel_valid && l1_rx_ready[dst])
                    rx_arb_ptr[dst] <= (rx_arb_ptr[dst] + 1) % NUM_CLUSTERS;
            end

        end
    endgenerate

    // =========================================================================
    // TX Ready - source consumed when all destination clusters have accepted
    // =========================================================================
    generate
        for (src = 0; src < NUM_CLUSTERS; src = src + 1) begin : gen_tx_ready
            logic all_dst_served;

            always_comb begin
                all_dst_served = 1'b1;
                for (int dd = 0; dd < NUM_CLUSTERS; dd = dd + 1) begin
                    if (xbar_pending[dd][src] && !l1_rx_ready[dd])
                        all_dst_served = 1'b0;
                end
            end

            assign l1_tx_ready[src] = all_dst_served;
        end
    endgenerate

    // =========================================================================
    // Bus Busy
    // =========================================================================
    assign bus_busy = |l1_tx_valid;

endmodule