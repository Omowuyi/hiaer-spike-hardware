`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_pkg.sv
// 
// Description:
//   Package containing all NoC type definitions, parameters, and interfaces
//   for the HiAER-Spike hierarchical multicast Network-on-Chip.
//
// Architecture:
//   - 16 cores organized into 4 clusters (4 cores each)
//   - L1 buses: Intra-cluster multicast (225 MHz)
//   - L2 bus: Inter-cluster multicast (225 MHz)
//   - Modified AHB protocol for spike packet transfer
//
// Spike Packet Format (32 bits):
//   [31:30] - Opcode: 2'b00=NOP, 2'b01=LOCAL, 2'b10=L1, 2'b11=L2
//   [29:26] - Source Core ID (4 bits)
//   [25:22] - Destination Mask for L1 (4 bits) or Cluster Mask for L2
//   [21:5]  - Neuron Address (17 bits)
//   [4:0]   - Timestamp LSBs (5 bits)
//
// Based on: HiAER-Spike ISCAS 2022 Paper
//////////////////////////////////////////////////////////////////////////////////

package noc_pkg;

    // =========================================================================
    // Global Parameters
    // =========================================================================
    parameter NUM_CORES = 16;
    parameter NUM_CLUSTERS = 4;
    parameter CORES_PER_CLUSTER = 4;
    parameter SPIKE_ADDR_WIDTH = 19;
    parameter NOC_DATA_WIDTH = 32;
    parameter NOC_FIFO_DEPTH = 64;
    
    // =========================================================================
    // Spike Packet Opcodes
    // =========================================================================
    parameter [1:0] OP_NOP   = 2'b00;  // No operation
    parameter [1:0] OP_LOCAL = 2'b01;  // Local spike (no NoC transfer)
    parameter [1:0] OP_L1    = 2'b10;  // L1 intra-cluster multicast
    parameter [1:0] OP_L2    = 2'b11;  // L2 inter-cluster multicast
    
    // =========================================================================
    // AHB Transfer Types (HTRANS)
    // =========================================================================
    parameter [1:0] HTRANS_IDLE   = 2'b00;
    parameter [1:0] HTRANS_BUSY   = 2'b01;
    parameter [1:0] HTRANS_NONSEQ = 2'b10;
    parameter [1:0] HTRANS_SEQ    = 2'b11;
    
    // =========================================================================
    // AHB Burst Types (HBURST)
    // =========================================================================
    parameter [2:0] HBURST_SINGLE = 3'b000;
    parameter [2:0] HBURST_INCR   = 3'b001;
    parameter [2:0] HBURST_WRAP4  = 3'b010;
    parameter [2:0] HBURST_INCR4  = 3'b011;
    parameter [2:0] HBURST_WRAP8  = 3'b100;
    parameter [2:0] HBURST_INCR8  = 3'b101;
    parameter [2:0] HBURST_WRAP16 = 3'b110;
    parameter [2:0] HBURST_INCR16 = 3'b111;
    
    // =========================================================================
    // AHB Response Types (HRESP)
    // =========================================================================
    parameter HRESP_OKAY  = 1'b0;
    parameter HRESP_ERROR = 1'b1;
    
    // =========================================================================
    // Spike Packet Type Definition
    // =========================================================================
    typedef struct packed {
        logic [1:0]  opcode;       // [31:30] Transfer type
        logic [3:0]  src_core;     // [29:26] Source core ID
        logic [3:0]  dest_mask;    // [25:22] Destination mask
        logic [18:0] neuron_addr;  // [21:3]  Neuron address
        logic [2:0]  timestamp;    // [2:0]   Timestamp LSBs, written and unread
    } spike_packet_t;
    
    // =========================================================================
    // Helper Functions
    // =========================================================================
    
    // Get cluster ID from core ID
    function automatic logic [1:0] get_cluster_id(input logic [3:0] core_id);
        return core_id[3:2];
    endfunction
    
    // Get local core ID within cluster (0-3)
    function automatic logic [1:0] get_local_id(input logic [3:0] core_id);
        return core_id[1:0];
    endfunction
    
    // Create spike packet
    function automatic spike_packet_t create_spike_packet(
        input logic [1:0]  opcode,
        input logic [3:0]  src_core,
        input logic [3:0]  dest_mask,
        input logic [18:0] neuron_addr,
        input logic [2:0]  timestamp
    );
        spike_packet_t pkt;
        pkt.opcode = opcode;
        pkt.src_core = src_core;
        pkt.dest_mask = dest_mask;
        pkt.neuron_addr = neuron_addr;
        pkt.timestamp = timestamp;
        return pkt;
    endfunction

endpackage

// =========================================================================
// NoC Router Interface
// =========================================================================
interface noc_router_if #(
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic resetn
);
    // Bus request/grant
    logic        hbusreq;
    logic        hgrant;
    
    // Master signals (to bus)
    logic [DATA_WIDTH-1:0] mst_hwdata;
    logic [1:0]            mst_htrans;
    logic [2:0]            mst_hburst;
    logic                  mst_hready_in;
    logic                  mst_hresp;
    
    // Slave signals (from bus)
    logic [DATA_WIDTH-1:0] slv_hwdata;
    logic [1:0]            slv_htrans;
    logic [2:0]            slv_hburst;
    logic                  slv_hready_out;
    logic                  slv_hresp;
    
    // Master port - for cores sending spikes
    modport master (
        input  clk, resetn,
        output hbusreq,
        input  hgrant,
        output mst_hwdata, mst_htrans, mst_hburst,
        input  mst_hready_in, mst_hresp
    );
    
    // Slave port - for cores receiving spikes
    modport slave (
        input  clk, resetn,
        input  slv_hwdata, slv_htrans, slv_hburst,
        output slv_hready_out, slv_hresp
    );
    
    // Bus port - for arbiter/interconnect
    modport bus (
        input  clk, resetn,
        input  hbusreq,
        output hgrant,
        input  mst_hwdata, mst_htrans, mst_hburst,
        output mst_hready_in, mst_hresp,
        output slv_hwdata, slv_htrans, slv_hburst,
        input  slv_hready_out, slv_hresp
    );
    
endinterface

// =========================================================================
// Spike FIFO Interface (between core and NoC)
// =========================================================================
interface spike_if #(
    parameter ADDR_WIDTH = 17
)(
    input logic clk,
    input logic resetn
);
    logic [ADDR_WIDTH-1:0] addr;
    logic                  valid;
    logic                  ready;
    logic [3:0]            dest_mask;
    logic [1:0]            level;      // OP_LOCAL, OP_L1, or OP_L2
    
    // Producer port (from core spike FIFO)
    modport producer (
        input  clk, resetn,
        output addr, valid, dest_mask, level,
        input  ready
    );
    
    // Consumer port (to NoC)
    modport consumer (
        input  clk, resetn,
        input  addr, valid, dest_mask, level,
        output ready
    );
    
endinterface
