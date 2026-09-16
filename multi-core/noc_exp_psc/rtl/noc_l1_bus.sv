`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_l1_bus.sv (PARALLEL CROSSBAR VERSION)
// 
// Description:
//   L1 (Level 1) intra-cluster PARALLEL multicast bus using crossbar architecture.
//   Connects 4 cores within a single cluster for local spike communication.
//
// Architecture:
//   - 4×4 crossbar switch with multicast capability
//   - All 4 cores can transmit simultaneously (no TX arbitration)
//   - Per-core RX arbitration handles collisions at destination
//   - Supports full parallel operation
//
// Features:
//   - Parallel TX: All 4 cores can send spikes simultaneously
//   - Multicast: Each spike can target any subset of 4 cores
//   - Per-core RX round-robin for collision handling
//   - L2 forwarding for inter-cluster spikes
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_l1_bus #(
    parameter CLUSTER_ID = 0,
    parameter NUM_CORES = 4,           // Added to match instantiation
    parameter DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic resetn,
    
    // =========================================================================
    // Spike Input from Cores (from routers) - RENAMED to match instantiation
    // =========================================================================
    input  logic [18:0] spike_addr_in [NUM_CORES-1:0],
    input  logic [NUM_CORES-1:0] spike_valid_in,
    output logic [NUM_CORES-1:0] spike_ready_in,
    input  logic [3:0]  spike_dest_mask [NUM_CORES-1:0],
    input  logic [1:0]  spike_level [NUM_CORES-1:0],
    
    // =========================================================================
    // Spike Output to Cores (to injectors) - RENAMED to match instantiation
    // =========================================================================
    output logic [18:0] spike_addr_out [NUM_CORES-1:0],
    output logic [NUM_CORES-1:0] spike_valid_out,
    input  logic [NUM_CORES-1:0] spike_ready_out,
    
    // =========================================================================
    // L2 Interface - RENAMED to match instantiation
    // =========================================================================
    output logic [DATA_WIDTH-1:0] l2_tx_data,
    output logic                  l2_tx_valid,
    input  logic                  l2_tx_ready,
    
    input  logic [DATA_WIDTH-1:0] l2_rx_data,
    input  logic                  l2_rx_valid,
    output logic                  l2_rx_ready,
    
    // =========================================================================
    // Status
    // =========================================================================
    output logic bus_busy
);

    // =========================================================================
    // Signal Declarations
    // =========================================================================
    
    // Crossbar Switch Matrix for L1 Traffic
    logic [NUM_CORES-1:0] xbar_req [NUM_CORES-1:0];
    logic [18:0] xbar_addr [NUM_CORES-1:0];
    logic [NUM_CORES-1:0] xbar_ack [NUM_CORES-1:0];
    
    // L2 TX signals
    logic [NUM_CORES-1:0] l2_tx_pending;
    logic [NUM_CORES-1:0] l2_core_ack;
    logic [1:0] l2_tx_rr;
    logic [1:0] l2_tx_sel;
    logic l2_tx_found;
    
    // L2 RX signals
    logic [NUM_CORES-1:0] l2_rx_dst_ack;
    
    // RX side signals (per destination)
    logic [NUM_CORES-1:0] rx_local_pending [NUM_CORES-1:0];
    logic [NUM_CORES-1:0] rx_l2_pending;
    logic [2:0] rr_priority [NUM_CORES-1:0];
    logic [2:0] rx_sel [NUM_CORES-1:0];
    logic [NUM_CORES-1:0] rx_valid_int;
    logic [18:0] rx_addr_int [NUM_CORES-1:0];

    // =========================================================================
    // L2 TX: Forward L2-level spikes to L2 bus
    // =========================================================================
    
    always_comb begin
        for (int i = 0; i < NUM_CORES; i++) begin
            l2_tx_pending[i] = spike_valid_in[i] && (spike_level[i] == OP_L2);
        end
    end
    
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            l2_tx_rr <= '0;
        end else if (l2_tx_valid && l2_tx_ready) begin
            l2_tx_rr <= l2_tx_rr + 1;
        end
    end
    
    always_comb begin
        l2_tx_sel = '0;
        l2_tx_found = 1'b0;
        for (int i = 0; i < NUM_CORES; i++) begin
            if (!l2_tx_found && l2_tx_pending[(l2_tx_rr + i) % NUM_CORES]) begin
                l2_tx_sel = (l2_tx_rr + i) % NUM_CORES;
                l2_tx_found = 1'b1;
            end
        end
    end
    
    assign l2_tx_valid = l2_tx_found;
    assign l2_tx_data = {
        OP_L2,
        CLUSTER_ID[1:0], l2_tx_sel,
        spike_dest_mask[l2_tx_sel],
        spike_addr_in[l2_tx_sel],
        3'b0
    };
    
    always_comb begin
        for (int i = 0; i < NUM_CORES; i++) begin
            l2_core_ack[i] = (l2_tx_sel == i[1:0]) && l2_tx_found && l2_tx_ready;
        end
    end

    // =========================================================================
    // TX Side: Drive crossbar requests and ready signals
    // =========================================================================
    genvar src;
    generate
        for (src = 0; src < NUM_CORES; src++) begin : gen_tx
            
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    xbar_addr[src] <= '0;
                end else if (spike_valid_in[src] && spike_level[src] == OP_L1) begin
                    xbar_addr[src] <= spike_addr_in[src];
                end
            end
            
            genvar dst;
            for (dst = 0; dst < NUM_CORES; dst++) begin : gen_dst_req
                assign xbar_req[src][dst] = spike_valid_in[src] && 
                                            (spike_level[src] == OP_L1) &&
                                            spike_dest_mask[src][dst] && 
                                            (dst != src);
            end
            
            logic all_l1_dst_ack;
            always_comb begin
                all_l1_dst_ack = 1'b1;
                if (spike_level[src] == OP_L1 && spike_valid_in[src]) begin
                    for (int d = 0; d < NUM_CORES; d++) begin
                        if (spike_dest_mask[src][d] && (d != src)) begin
                            all_l1_dst_ack = all_l1_dst_ack && xbar_ack[src][d];
                        end
                    end
                end else begin
                    all_l1_dst_ack = 1'b0;
                end
            end
            
            assign spike_ready_in[src] = (spike_level[src] == OP_L1 && all_l1_dst_ack) ||
                                         (spike_level[src] == OP_L2 && l2_core_ack[src]);
            
        end
    endgenerate

    // =========================================================================
    // RX Side: Per-core arbitration for incoming L1 spikes
    // =========================================================================
    genvar d;
    generate
        for (d = 0; d < NUM_CORES; d++) begin : gen_rx
            
            always_comb begin
                for (int s = 0; s < NUM_CORES; s++) begin
                    rx_local_pending[d][s] = xbar_req[s][d];
                end
            end
            
            assign rx_l2_pending[d] = l2_rx_valid && 
                                      ((l2_rx_data[25:22] & (1 << d)) != 0);
            
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    rr_priority[d] <= '0;
                end else if (rx_valid_int[d] && spike_ready_out[d]) begin
                    rr_priority[d] <= (rr_priority[d] >= 3'd4) ? 3'd0 : rr_priority[d] + 1;
                end
            end
            
            always_comb begin
                rx_sel[d] = 3'd7;
                rx_valid_int[d] = 1'b0;
                rx_addr_int[d] = '0;
                
                for (int i = 0; i < 5; i++) begin
                    if (rx_sel[d] == 3'd7) begin
                        automatic int check_idx = (rr_priority[d] + i) % 5;
                        if (check_idx < 4 && rx_local_pending[d][check_idx]) begin
                            rx_sel[d] = check_idx[2:0];
                            rx_valid_int[d] = 1'b1;
                            rx_addr_int[d] = xbar_addr[check_idx];
                        end else if (check_idx == 4 && rx_l2_pending[d]) begin
                            rx_sel[d] = 3'd4;
                            rx_valid_int[d] = 1'b1;
                            rx_addr_int[d] = l2_rx_data[21:3];
                        end
                    end
                end
            end
            
            always_ff @(posedge clk or negedge resetn) begin
                if (!resetn) begin
                    spike_addr_out[d] <= '0;
                    spike_valid_out[d] <= 1'b0;
                end else begin
                    if (rx_valid_int[d] && spike_ready_out[d]) begin
                        spike_addr_out[d] <= rx_addr_int[d];
                        spike_valid_out[d] <= 1'b1;
                    end else if (spike_ready_out[d]) begin
                        spike_valid_out[d] <= 1'b0;
                    end
                end
            end
            
            always_comb begin
                for (int s = 0; s < NUM_CORES; s++) begin
                    xbar_ack[s][d] = (rx_sel[d] == s[2:0]) && rx_valid_int[d] && spike_ready_out[d];
                end
            end
            
            assign l2_rx_dst_ack[d] = (rx_sel[d] == 3'd4) && rx_valid_int[d] && spike_ready_out[d];
            
        end
    endgenerate
    
    assign l2_rx_ready = |l2_rx_dst_ack;
    
    // =========================================================================
    // Status
    // =========================================================================
    assign bus_busy = |spike_valid_in || l2_rx_valid;

endmodule
