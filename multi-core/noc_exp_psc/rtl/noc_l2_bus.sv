`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_l2_bus.sv (PARALLEL CROSSBAR VERSION)
// 
// Description:
//   L2 (Level 2) inter-cluster PARALLEL multicast bus using crossbar architecture.
//   Connects 4 clusters for cross-cluster spike communication.
//
// Architecture:
//   - 4×4 crossbar switch with multicast capability
//   - All 4 clusters can transmit simultaneously (no TX arbitration)
//   - Per-cluster RX arbitration handles collisions at destination
//   - Supports full parallel operation
//
// Features:
//   - Parallel TX: All 4 clusters can send spikes simultaneously
//   - Multicast: Each spike can target any subset of 4 clusters
//   - Per-cluster RX round-robin arbitration for collision handling
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_l2_bus #(
    parameter NUM_CLUSTERS = 4,        // Added to match instantiation
    parameter DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic resetn,
    
    // =========================================================================
    // L2 Spike Inputs from Clusters - RENAMED to match instantiation
    // =========================================================================
    input  logic [DATA_WIDTH-1:0] l1_tx_data [NUM_CLUSTERS-1:0],
    input  logic [NUM_CLUSTERS-1:0] l1_tx_valid,
    output logic [NUM_CLUSTERS-1:0] l1_tx_ready,
    
    // =========================================================================
    // L2 Spike Outputs to Clusters - RENAMED to match instantiation
    // =========================================================================
    output logic [DATA_WIDTH-1:0] l1_rx_data [NUM_CLUSTERS-1:0],
    output logic [NUM_CLUSTERS-1:0] l1_rx_valid,
    input  logic [NUM_CLUSTERS-1:0] l1_rx_ready,
    
    // =========================================================================
    // Status
    // =========================================================================
    output logic bus_busy
);

    // =========================================================================
    // Signal Declarations
    // =========================================================================
    
    logic [NUM_CLUSTERS-1:0] xbar_req [NUM_CLUSTERS-1:0];
    logic [DATA_WIDTH-1:0] xbar_data [NUM_CLUSTERS-1:0];
    logic [3:0] xbar_dest_mask [NUM_CLUSTERS-1:0];
    logic [NUM_CLUSTERS-1:0] xbar_ack [NUM_CLUSTERS-1:0];
    logic [NUM_CLUSTERS-1:0] xbar_valid_reg;
    
    logic [NUM_CLUSTERS-1:0] rx_pending [NUM_CLUSTERS-1:0];
    logic [1:0] rr_priority [NUM_CLUSTERS-1:0];
    logic [1:0] rx_sel [NUM_CLUSTERS-1:0];
    logic [NUM_CLUSTERS-1:0] rx_found;
    logic [DATA_WIDTH-1:0] rx_data_hold [NUM_CLUSTERS-1:0];
    logic [NUM_CLUSTERS-1:0] rx_valid_hold;

    // =========================================================================
    // TX Side: Register inputs and drive crossbar requests
    // =========================================================================
    genvar src;
    generate
        for (src = 0; src < NUM_CLUSTERS; src++) begin : gen_tx
            
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    xbar_data[src] <= '0;
                    xbar_dest_mask[src] <= '0;
                    xbar_valid_reg[src] <= 1'b0;
                end else begin
                    if (l1_tx_valid[src] && !xbar_valid_reg[src]) begin
                        xbar_dest_mask[src] <= l1_tx_data[src][25:22];
                        xbar_data[src] <= {
                            OP_L1,
                            l1_tx_data[src][29:26],
                            4'b1111,
                            l1_tx_data[src][21:0]
                        };
                        xbar_valid_reg[src] <= 1'b1;
                    end else if (l1_tx_ready[src]) begin
                        xbar_valid_reg[src] <= 1'b0;
                    end
                end
            end
            
            genvar dst;
            for (dst = 0; dst < NUM_CLUSTERS; dst++) begin : gen_dst_req
                assign xbar_req[src][dst] = xbar_valid_reg[src] && 
                                            xbar_dest_mask[src][dst] && 
                                            (dst != src);
            end
            
            logic all_dst_ack;
            always_comb begin
                all_dst_ack = xbar_valid_reg[src];
                if (xbar_valid_reg[src]) begin
                    for (int d = 0; d < NUM_CLUSTERS; d++) begin
                        if (xbar_dest_mask[src][d] && (d != src)) begin
                            all_dst_ack = all_dst_ack && xbar_ack[src][d];
                        end
                    end
                end
            end
            assign l1_tx_ready[src] = all_dst_ack;
            
        end
    endgenerate

    // =========================================================================
    // RX Side: Per-cluster round-robin arbitration
    // =========================================================================
    genvar dst;
    generate
        for (dst = 0; dst < NUM_CLUSTERS; dst++) begin : gen_rx
            
            always_comb begin
                for (int s = 0; s < NUM_CLUSTERS; s++) begin
                    if (s != dst) begin
                        rx_pending[dst][s] = xbar_req[s][dst];
                    end else begin
                        rx_pending[dst][s] = 1'b0;
                    end
                end
            end
            
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    rr_priority[dst] <= '0;
                end else if (rx_valid_hold[dst] && l1_rx_ready[dst]) begin
                    rr_priority[dst] <= rr_priority[dst] + 1;
                end
            end
            
            always_comb begin
                rx_sel[dst] = '0;
                rx_found[dst] = 1'b0;
                
                for (int i = 0; i < NUM_CLUSTERS; i++) begin
                    if (!rx_found[dst]) begin
                        automatic int check_idx = (rr_priority[dst] + i) % NUM_CLUSTERS;
                        if (rx_pending[dst][check_idx]) begin
                            rx_sel[dst] = check_idx[1:0];
                            rx_found[dst] = 1'b1;
                        end
                    end
                end
            end
            
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    rx_data_hold[dst] <= '0;
                    rx_valid_hold[dst] <= 1'b0;
                end else begin
                    if (!rx_valid_hold[dst] && rx_found[dst]) begin
                        rx_data_hold[dst] <= xbar_data[rx_sel[dst]];
                        rx_valid_hold[dst] <= 1'b1;
                    end else if (rx_valid_hold[dst] && l1_rx_ready[dst]) begin
                        if (rx_found[dst]) begin
                            rx_data_hold[dst] <= xbar_data[rx_sel[dst]];
                            rx_valid_hold[dst] <= 1'b1;
                        end else begin
                            rx_valid_hold[dst] <= 1'b0;
                        end
                    end
                end
            end
            
            assign l1_rx_data[dst] = rx_data_hold[dst];
            assign l1_rx_valid[dst] = rx_valid_hold[dst];
            
            always_comb begin
                for (int s = 0; s < NUM_CLUSTERS; s++) begin
                    xbar_ack[s][dst] = rx_pending[dst][s] && 
                                       (rx_sel[dst] == s[1:0]) && 
                                       rx_found[dst] && 
                                       (!rx_valid_hold[dst] || l1_rx_ready[dst]);
                end
            end
            
        end
    endgenerate
    
    // =========================================================================
    // Status
    // =========================================================================
    assign bus_busy = |l1_tx_valid || |xbar_valid_reg;

endmodule
