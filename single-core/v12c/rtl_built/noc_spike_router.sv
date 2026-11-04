`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_spike_router.sv
//
// Spike router between a core's NoC spike output and the NoC.  Routes each spike by the routing
// table entry of its address block (addr[16:9], 256 blocks of 512 addresses):
//   - LOCAL (and NOP): to the host output
//   - L1: intra-cluster multicast via the L1 bus;  L2: inter-cluster multicast via the L2 bus
//
// v10 (fix 15): pipelined, one spike per cycle.  The previous version spent four cycles per spike
// (idle, lookup, send, done).  Valid/ready on every port: a spike is accepted when the output stage
// is empty or being emptied in the same cycle; the table entry is read in the accepting cycle; the
// spike is held until its destination (host or NoC) takes it.  No spike is dropped, order is kept.
// The table index is addr[16:9] (8 bits for the 256 entries; the old addr[18:9] was 10 bits).
// Ports and routing-table interface unchanged.
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_spike_router #(
    parameter CORE_ID = 0,
    parameter ROUTE_TABLE_SIZE = 256  // Number of routing entries
)(
    input  logic clk,
    input  logic resetn,
    // spike input from the core (valid/ready)
    input  logic [18:0] spike_addr_in,
    input  logic        spike_valid_in,
    output logic        spike_ready_in,
    // spike output to the NoC (L1 bus)
    output logic [18:0] spike_addr_out,
    output logic        spike_valid_out,
    input  logic        spike_ready_out,
    output logic [3:0]  spike_dest_mask,   // destination cores (L1) or clusters (L2)
    output logic [1:0]  spike_level,       // OP_LOCAL, OP_L1 or OP_L2
    // spike output to the host (non-routed spikes)
    output logic [18:0] spike_addr_host,
    output logic        spike_valid_host,
    input  logic        spike_ready_host,
    // routing table configuration
    input  logic        route_cfg_valid,
    input  logic [9:0]  route_cfg_addr,    // which entry to configure (low 8 bits used)
    input  logic [5:0]  route_cfg_data     // [5:4] = level, [3:0] = mask
);

    // routing table: [5:4] level, [3:0] destination mask; default LOCAL (everything to the host)
    logic [5:0] route_table [ROUTE_TABLE_SIZE-1:0];
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (int i = 0; i < ROUTE_TABLE_SIZE; i++) route_table[i] <= {OP_LOCAL, 4'b0000};
        end else if (route_cfg_valid) begin
            route_table[route_cfg_addr[7:0]] <= route_cfg_data;
        end
    end

    // lookup for the spike at the input
    wire [7:0] route_idx   = spike_addr_in[16:9];
    wire [5:0] route_entry = route_table[route_idx];

    // output stage
    logic        out_valid;
    logic [18:0] out_addr;
    logic [3:0]  out_mask;
    logic [1:0]  out_level;
    wire out_to_noc = (out_level == OP_L1) || (out_level == OP_L2);
    wire out_taken  = out_valid && (out_to_noc ? spike_ready_out : spike_ready_host);
    assign spike_ready_in = !out_valid || out_taken;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            out_valid <= 1'b0;
            out_addr  <= '0;
            out_mask  <= '0;
            out_level <= OP_LOCAL;
        end else if (spike_valid_in && spike_ready_in) begin
            out_valid <= 1'b1;
            out_addr  <= spike_addr_in;
            out_mask  <= route_entry[3:0];
            out_level <= route_entry[5:4];
        end else if (out_taken) begin
            out_valid <= 1'b0;
        end
    end

    assign spike_valid_out  = out_valid &&  out_to_noc;
    assign spike_valid_host = out_valid && !out_to_noc;
    assign spike_addr_out   = out_addr;
    assign spike_addr_host  = out_addr;
    assign spike_dest_mask  = out_mask;
    assign spike_level      = out_level;

endmodule
