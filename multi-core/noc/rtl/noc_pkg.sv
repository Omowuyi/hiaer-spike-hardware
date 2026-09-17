`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Package: noc_pkg.sv
//
// Based on: HiAER-Spike ISCAS 2022 Paper (Multicast-HiAER)
// Modified: Parallel crossbar instead of time-multiplexed AHB
//           Expanded routing table entry to 10 bits for per-core L2 masks
//
// CHANGES FROM ORIGINAL:
//   - Removed unused AHB interface definitions (HTRANS, HBURST, HRESP)
//   - Removed unused noc_router_if and spike_if interfaces
//   - Added ROUTE_ENTRY_WIDTH = 10 for per-core mask support
//   - Added secondary mask constants
//////////////////////////////////////////////////////////////////////////////////

package noc_pkg;

    // =========================================================================
    // System Topology Parameters
    // =========================================================================
    parameter NUM_CORES          = 16;
    parameter NUM_CLUSTERS       = 4;
    parameter CORES_PER_CLUSTER  = 4;
    parameter SPIKE_ADDR_WIDTH   = 17;
    parameter NOC_DATA_WIDTH     = 32;
    parameter NOC_FIFO_DEPTH     = 64;

    // =========================================================================
    // Routing Table Parameters
    // =========================================================================
    parameter ROUTE_TABLE_SIZE   = 256;  // Indexed by addr[16:9]
    parameter ROUTE_ENTRY_WIDTH  = 10;   // [9:8]=level, [7:4]=primary, [3:0]=secondary

    // =========================================================================
    // Spike Packet Opcodes (2-bit)
    // =========================================================================
    parameter [1:0] OP_NOP   = 2'b00;  // No operation
    parameter [1:0] OP_LOCAL = 2'b01;  // Local spike (no NoC transfer, report to host)
    parameter [1:0] OP_L1    = 2'b10;  // L1 intra-cluster multicast
    parameter [1:0] OP_L2    = 2'b11;  // L2 inter-cluster multicast

    // =========================================================================
    // Spike Packet Bit Field Positions (32-bit NoC packet)
    // =========================================================================
    //  [31:30] = opcode (2b)
    //  [29:26] = source core ID (4b: {cluster[1:0], core_in_cluster[1:0]})
    //  [25:22] = mask (4b: core mask for L1, cluster mask for L2 TX)
    //  [21:5]  = neuron address (17b)
    //  [4:0]   = timestamp / secondary mask carrier (5b)
    //
    // For L2 TX packets from L1 bus:
    //  [4:1]   = secondary mask (per-core mask for destination clusters)
    //  [0]     = reserved (0)

endpackage