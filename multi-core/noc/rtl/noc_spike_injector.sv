`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_spike_injector.sv (CORRECTED)
//
// Description:
//   Receives spikes from the NoC L1 bus and writes them to the core's
//   NoC Relay Event FIFO in the External Events Processor (EEP).
//   EEP Phase 3 then processes the FIFO and writes to axon BRAM.
//
// Integration:
//   Input:  L1 bus spike output (17-bit destination neuron address)
//   Output: EEP noc_relay_din/wren/full interface
//
// Spike Address Format (17 bits):
//   [16:13] = Neuron Group (0-15)
//   [12:0]  = Neuron index within group
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module noc_spike_injector #(
    parameter CORE_ID = 0
)(
    input  logic clk,
    input  logic resetn,

    // =========================================================================
    // Spike Input from NoC (from L1 bus)
    // =========================================================================
    input  logic [16:0] noc_spike_addr,
    input  logic        noc_spike_valid,
    output logic        noc_spike_ready,

    // =========================================================================
    // NoC Relay FIFO Output (to external_events_processor)
    // =========================================================================
    output logic [16:0] noc_relay_addr,
    output logic        noc_relay_valid,
    input  logic        noc_relay_full,

    // =========================================================================
    // Status / Debug
    // =========================================================================
    output logic [15:0] inject_count,
    output logic        overflow_error,

    // =========================================================================
    // Timestep sync (reset counters)
    // =========================================================================
    input  logic        exec_run
);

    // =========================================================================
    // Injection Logic - simple flow-through with backpressure
    // =========================================================================
    logic [15:0] count_reg;
    logic        overflow_reg;

    assign noc_spike_ready = !noc_relay_full;
    assign noc_relay_addr  = noc_spike_addr;
    assign noc_relay_valid = noc_spike_valid && !noc_relay_full;

    // =========================================================================
    // Statistics Counters
    // =========================================================================
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            count_reg    <= 16'd0;
            overflow_reg <= 1'b0;
        end else begin
            if (exec_run) begin
                count_reg    <= 16'd0;
                overflow_reg <= 1'b0;
            end else begin
                if (noc_spike_valid && !noc_relay_full)
                    count_reg <= count_reg + 1'b1;
                if (noc_spike_valid && noc_relay_full)
                    overflow_reg <= 1'b1;
            end
        end
    end

    assign inject_count   = count_reg;
    assign overflow_error = overflow_reg;

endmodule