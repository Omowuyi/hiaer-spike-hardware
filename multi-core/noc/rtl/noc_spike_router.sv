`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_spike_router.sv (CORRECTED)
//
// Changes from original:
//   - Route table entries expanded from 6 to 10 bits
//     [9:8]=level, [7:4]=primary_mask, [3:0]=secondary_mask
//   - Added spike_secondary_mask output for per-core L2 routing
//   - route_cfg_data widened from 6 to 10 bits
//   - Default route entry: {OP_LOCAL, 4'b0000, 4'b0000} = all spikes to host
//   - Added OP_NOP handling (NOP level → spike silently dropped, not sent anywhere)
//
// Integration:
//   Input:  core's spike CDC FIFO output (17-bit spike addresses, aclk domain)
//   Output: L1 bus spike input (to NoC) OR host spike output (to CI/PCIe)
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_spike_router #(
    parameter CORE_ID = 0,
    parameter ROUTE_TABLE_SIZE_P = ROUTE_TABLE_SIZE
)(
    input  logic clk,
    input  logic resetn,

    // =========================================================================
    // Spike Input from Core (from CDC FIFO, aclk domain)
    // =========================================================================
    input  logic [16:0] spike_addr_in,
    input  logic        spike_valid_in,
    output logic        spike_ready_in,

    // =========================================================================
    // Spike Output to NoC (to L1 bus)
    // =========================================================================
    output logic [16:0] spike_addr_out,
    output logic        spike_valid_out,
    input  logic        spike_ready_out,
    output logic [3:0]  spike_dest_mask,       // Primary: cores (L1) or clusters (L2)
    output logic [3:0]  spike_secondary_mask,  // Secondary: per-core mask for L2 destinations
    output logic [1:0]  spike_level,           // OP_L1 or OP_L2

    // =========================================================================
    // Spike Output to Host (for LOCAL spikes - goes nowhere in NoC,
    // but the spike already reaches the CI via spk2ciFIFO independently)
    // =========================================================================
    output logic [16:0] spike_addr_host,
    output logic        spike_valid_host,
    input  logic        spike_ready_host,

    // =========================================================================
    // Routing Table Configuration (from CI via opcode 0x09)
    // =========================================================================
    input  logic              route_cfg_valid,
    input  logic [7:0]        route_cfg_addr,
    input  logic [ROUTE_ENTRY_WIDTH-1:0] route_cfg_data  // 10 bits
);

    // =========================================================================
    // Routing Table: 256 entries × 10 bits
    // =========================================================================
    // [9:8]  = level (OP_NOP/OP_LOCAL/OP_L1/OP_L2)
    // [7:4]  = primary_mask (core mask for L1, cluster mask for L2)
    // [3:0]  = secondary_mask (per-core mask in destination clusters for L2)

    logic [ROUTE_ENTRY_WIDTH-1:0] route_table [ROUTE_TABLE_SIZE_P-1:0];

    // Routing table write
    integer i;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (i = 0; i < ROUTE_TABLE_SIZE_P; i = i + 1) begin
                route_table[i] <= {OP_LOCAL, 4'b0000, 4'b0000};
            end
        end else if (route_cfg_valid) begin
            route_table[route_cfg_addr] <= route_cfg_data;
        end
    end

    // =========================================================================
    // Route Lookup (combinational, registered in FSM)
    // =========================================================================
    wire [7:0] route_idx = spike_addr_in[16:9];
    wire [ROUTE_ENTRY_WIDTH-1:0] route_entry = route_table[route_idx];
    wire [1:0] route_level     = route_entry[9:8];
    wire [3:0] route_primary   = route_entry[7:4];
    wire [3:0] route_secondary = route_entry[3:0];

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
    logic [16:0] addr_reg;
    logic [3:0]  primary_reg;
    logic [3:0]  secondary_reg;
    logic [1:0]  level_reg;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state         <= ROUTE_IDLE;
            addr_reg      <= '0;
            primary_reg   <= '0;
            secondary_reg <= '0;
            level_reg     <= OP_LOCAL;
        end else begin
            state <= next_state;

            if (state == ROUTE_IDLE && spike_valid_in) begin
                // Register lookup results when transitioning from IDLE
                addr_reg      <= spike_addr_in;
                primary_reg   <= route_primary;
                secondary_reg <= route_secondary;
                level_reg     <= route_level;
            end
        end
    end

    // =========================================================================
    // Next State and Output Logic
    // =========================================================================
    always_comb begin
        next_state      = state;
        spike_ready_in  = 1'b0;
        spike_valid_out = 1'b0;
        spike_valid_host = 1'b0;

        case (state)
            ROUTE_IDLE: begin
                if (spike_valid_in) begin
                    next_state = ROUTE_LOOKUP;
                end
            end

            ROUTE_LOOKUP: begin
                // One-cycle registered lookup, route based on level
                case (level_reg)
                    OP_L1, OP_L2: next_state = ROUTE_TO_NOC;
                    OP_LOCAL:     next_state = ROUTE_TO_HOST;
                    OP_NOP: begin
                        // NOP: silently consume the spike (drop it)
                        spike_ready_in = 1'b1;
                        next_state = ROUTE_DONE;
                    end
                    default:      next_state = ROUTE_TO_HOST;
                endcase
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
    assign spike_addr_out       = addr_reg;
    assign spike_dest_mask      = primary_reg;
    assign spike_secondary_mask = secondary_reg;
    assign spike_level          = level_reg;

    assign spike_addr_host      = addr_reg;

endmodule