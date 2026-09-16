`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_spike_router.sv
// 
// Description:
//   Spike router module that interfaces between a core's spike FIFO output
//   and the NoC. Routes spikes based on destination:
//   - LOCAL: No NoC transfer (spike stays in same core)
//   - L1: Intra-cluster multicast via L1 bus
//   - L2: Inter-cluster multicast via L2 bus
//
// Integration Points:
//   - Input: Connected to core's spk2ciFIFO output (17-bit spike addresses)
//   - Output: Connected to noc_l1_bus spike input ports
//
// Destination Encoding:
//   The destination mask and level are determined by looking up a routing
//   table based on the neuron address. This table is configured by software
//   during network setup.
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_spike_router #(
    parameter CORE_ID = 0,
    parameter ROUTE_TABLE_SIZE = 256  // Number of routing entries
)(
    input  logic clk,
    input  logic resetn,
    
    // =========================================================================
    // Spike Input from Core (from spk2ciFIFO)
    // =========================================================================
    input  logic [18:0] spike_addr_in,
    input  logic        spike_valid_in,
    output logic        spike_ready_in,
    
    // =========================================================================
    // Spike Output to NoC (to L1 bus)
    // =========================================================================
    output logic [18:0] spike_addr_out,
    output logic        spike_valid_out,
    input  logic        spike_ready_out,
    output logic [3:0]  spike_dest_mask,   // Destination cores (L1) or clusters (L2)
    output logic [1:0]  spike_level,       // OP_LOCAL, OP_L1, or OP_L2
    
    // =========================================================================
    // Spike Output to Host (for non-routed spikes going to PCIe)
    // =========================================================================
    output logic [18:0] spike_addr_host,
    output logic        spike_valid_host,
    input  logic        spike_ready_host,
    
    // =========================================================================
    // Routing Table Configuration Interface
    // =========================================================================
    input  logic        route_cfg_valid,
    input  logic [9:0]  route_cfg_addr,    // Which entry to configure
    input  logic [5:0]  route_cfg_data     // [5:4]=level, [3:0]=mask
);

    // =========================================================================
    // Routing Table
    // =========================================================================
    // Each entry: [5:4] = level (LOCAL/L1/L2), [3:0] = destination mask
    // Indexed by upper bits of neuron address
    
    logic [5:0] route_table [ROUTE_TABLE_SIZE-1:0];
    
    // Routing table write
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            // Default: all spikes go to host (LOCAL, no NoC transfer)
            for (int i = 0; i < ROUTE_TABLE_SIZE; i++) begin
                route_table[i] <= {OP_LOCAL, 4'b0000};
            end
        end else if (route_cfg_valid) begin
            route_table[route_cfg_addr] <= route_cfg_data;
        end
    end
    
    // =========================================================================
    // Route Lookup
    // =========================================================================
    
    // Use upper 8 bits of neuron address to index routing table
    wire [9:0] route_idx = spike_addr_in[18:9];
    wire [5:0] route_entry = route_table[route_idx];
    wire [1:0] route_level = route_entry[5:4];
    wire [3:0] route_mask = route_entry[3:0];
    
    // =========================================================================
    // Routing FSM
    // =========================================================================
    
    typedef enum logic [2:0] {
        ROUTE_IDLE      = 3'b000,
        ROUTE_LOOKUP    = 3'b001,
        ROUTE_TO_NOC    = 3'b010,
        ROUTE_TO_HOST   = 3'b011,
        ROUTE_DONE      = 3'b100
    } route_state_t;
    
    route_state_t state, next_state;
    
    // Registered outputs
    logic [18:0] addr_reg;
    logic [3:0]  mask_reg;
    logic [1:0]  level_reg;
    
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= ROUTE_IDLE;
            addr_reg <= '0;
            mask_reg <= '0;
            level_reg <= OP_LOCAL;
        end else begin
            state <= next_state;
            
            if (state == ROUTE_LOOKUP) begin
                addr_reg <= spike_addr_in;
                mask_reg <= route_mask;
                level_reg <= route_level;
            end
        end
    end
    
    // =========================================================================
    // Next State Logic
    // =========================================================================
    
    always_comb begin
        next_state = state;
        spike_ready_in = 1'b0;
        spike_valid_out = 1'b0;
        spike_valid_host = 1'b0;
        
        case (state)
            ROUTE_IDLE: begin
                if (spike_valid_in) begin
                    next_state = ROUTE_LOOKUP;
                end
            end
            
            ROUTE_LOOKUP: begin
                // Registered lookup, proceed to routing
                if (route_level == OP_LOCAL || route_level == OP_L1 || route_level == OP_L2) begin
                    if (route_level == OP_LOCAL) begin
                        next_state = ROUTE_TO_HOST;  // LOCAL spikes go to host
                    end else begin
                        next_state = ROUTE_TO_NOC;   // L1/L2 spikes go to NoC
                    end
                end else begin
                    next_state = ROUTE_TO_HOST;  // Default to host
                end
            end
            
            ROUTE_TO_NOC: begin
                spike_valid_out = 1'b1;
                if (spike_ready_out) begin
                    spike_ready_in = 1'b1;
                    next_state = ROUTE_DONE;
                end
            end
            
            ROUTE_TO_HOST: begin
                spike_valid_host = 1'b1;
                if (spike_ready_host) begin
                    spike_ready_in = 1'b1;
                    next_state = ROUTE_DONE;
                end
            end
            
            ROUTE_DONE: begin
                next_state = ROUTE_IDLE;
            end
            
            default: begin
                next_state = ROUTE_IDLE;
            end
        endcase
    end
    
    // =========================================================================
    // Output Assignments
    // =========================================================================
    
    assign spike_addr_out = addr_reg;
    assign spike_dest_mask = mask_reg;
    assign spike_level = level_reg;
    
    assign spike_addr_host = addr_reg;

endmodule
