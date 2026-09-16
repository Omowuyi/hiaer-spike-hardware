`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// AXON DELAY BUFFER — Per-axon hardware delay for input spike events
//
// Sits between the Command Interpreter and the External Events Processor.
// Each axon has a configurable delay (6-bit, 0–63 timesteps) stored in a
// BRAM lookup table. When an axon fires:
//   delay=0: event passes through immediately to EEP
//   delay>0: event is buffered and delivered delay timesteps later
//
// Architecture:
//   1. Delay lookup table: BRAM, 8192 × 6 bits (one entry per axon address)
//   2. Circular buffer: 64 delay slots × 1024 entries per slot
//      Entry = {addr[12:0], data[15:0]} = 29 bits
//   3. On timestep_tick: drain all entries from slot[current_slot] to EEP,
//      then advance current_slot
//
// Programming: host loads delay table via delay_table_wr interface.
// The CI routes delay table writes from a new CMD or from CMD_04 extension.
//
// Clock: aclk (125 MHz, same as CI and EEP)
//
// BACKWARD COMPATIBILITY: when all delays are 0 (default after reset),
// all events pass through immediately. Zero overhead.
////////////////////////////////////////////////////////////////////////////////

module axon_delay_buffer #(
    parameter MAX_DELAY        = 64,
    parameter ENTRIES_PER_SLOT = 1024,
    parameter NUM_AXONS        = 8192
)(
    input  wire        clk,
    input  wire        resetn,

    //=========================================================================
    // Input: axon events from Command Interpreter
    //=========================================================================
    input  wire        axon_in_set,
    input  wire [12:0] axon_in_addr,
    input  wire [15:0] axon_in_data,

    //=========================================================================
    // Output: axon events to External Events Processor
    //=========================================================================
    output wire        axon_out_set,
    output wire [12:0] axon_out_addr,
    output wire [15:0] axon_out_data,

    //=========================================================================
    // Timestep control
    //=========================================================================
    input  wire        timestep_tick,    // pulse at start of each timestep
    output wire        drain_busy,       // 1 while draining buffered events

    //=========================================================================
    // Delay table programming (from CI)
    //=========================================================================
    input  wire [12:0] delay_table_waddr,
    input  wire [5:0]  delay_table_wdata,
    input  wire        delay_table_wr
);

    //=========================================================================
    // Delay lookup table: 8192 × 6-bit
    // Port A: write (host programming via CI)
    // Port B: read (lookup on axon event arrival)
    //=========================================================================
    (* ram_style = "ultra" *)
    reg [5:0] delay_table [0:NUM_AXONS-1];


    reg [5:0] lookup_delay;
    reg       lookup_valid;
    reg [12:0] lookup_addr_r;
    reg [15:0] lookup_data_r;

    // Write port (programming)
    always @(posedge clk) begin
        if (delay_table_wr)
            delay_table[delay_table_waddr] <= delay_table_wdata;
    end

    // Read port (lookup) — 1-cycle latency
    always @(posedge clk) begin
        if (~resetn) begin
            lookup_delay <= 6'd0;
            lookup_valid <= 1'b0;
            lookup_addr_r <= 13'd0;
            lookup_data_r <= 16'd0;
        end else begin
            lookup_valid <= axon_in_set;
            lookup_addr_r <= axon_in_addr;
            lookup_data_r <= axon_in_data;
            if (axon_in_set)
                lookup_delay <= delay_table[axon_in_addr];
        end
    end

    //=========================================================================
    // Immediate bypass: delay=0 events go directly to EEP
    //=========================================================================
    wire immediate_set = lookup_valid && (lookup_delay == 6'd0);

    //=========================================================================
    // Circular buffer: stores delayed axon events
    // Address = {slot[5:0], entry_index[9:0]} = 16 bits
    // Entry = {addr[12:0], data[15:0]} = 29 bits
    //=========================================================================
    localparam ENTRY_WIDTH = 29;  // 13-bit addr + 16-bit data

    (* ram_style = "ultra" *)
    reg [ENTRY_WIDTH-1:0] buffer_mem [0:(MAX_DELAY * ENTRIES_PER_SLOT) - 1];


    // Per-slot write pointers (distributed RAM: 64 × 10 bits)
    reg [9:0] slot_wr_ptr [0:63];

    reg [5:0] current_slot;

    // Write path: delayed events
    wire       write_en = lookup_valid && (lookup_delay != 6'd0);
    wire [5:0] target_slot = current_slot + lookup_delay;  // wraps at 64

    always @(posedge clk) begin
        if (write_en)
            buffer_mem[{target_slot, slot_wr_ptr[target_slot]}] <= {lookup_addr_r, lookup_data_r};
    end

    // Update write pointer (MERGED: write + drain-done reset in ONE always block)
    integer s;
    always @(posedge clk) begin
        if (~resetn) begin
            for (s = 0; s < MAX_DELAY; s = s + 1)
                slot_wr_ptr[s] <= 10'd0;
        end else begin
            if (write_en)
                slot_wr_ptr[target_slot] <= slot_wr_ptr[target_slot] + 10'd1;
            if (drain_state == DRAIN_DONE)
                slot_wr_ptr[current_slot] <= 10'd0;
        end
    end

    //=========================================================================
    // Drain state machine: reads all events from slot[current_slot]
    // Triggered by timestep_tick. Outputs events to EEP.
    //=========================================================================
    localparam DRAIN_IDLE   = 2'd0;
    localparam DRAIN_READ   = 2'd1;
    localparam DRAIN_OUTPUT = 2'd2;
    localparam DRAIN_DONE   = 2'd3;

    reg [1:0]  drain_state;
    reg [9:0]  drain_count;       // entries to drain from current slot
    reg [9:0]  drain_idx;         // current read index
    reg [ENTRY_WIDTH-1:0] drain_data_r;
    reg        drain_valid;
    reg [12:0] drain_addr;
    reg [15:0] drain_data_out;

    // BRAM read (1-cycle latency)
    reg [15:0] bram_rd_addr;
    reg        bram_rd_en;
    reg [ENTRY_WIDTH-1:0] bram_rd_data;

    always @(posedge clk) begin
        if (bram_rd_en)
            bram_rd_data <= buffer_mem[bram_rd_addr];
    end

    assign drain_busy = (drain_state != DRAIN_IDLE);

    always @(posedge clk) begin
        if (~resetn) begin
            drain_state <= DRAIN_IDLE;
            drain_count <= 10'd0;
            drain_idx <= 10'd0;
            drain_valid <= 1'b0;
            drain_addr <= 13'd0;
            drain_data_out <= 16'd0;
            current_slot <= 6'd0;
            bram_rd_en <= 1'b0;
        end else begin
            bram_rd_en <= 1'b0;
            drain_valid <= 1'b0;

            case (drain_state)
                DRAIN_IDLE: begin
                    if (timestep_tick) begin
                        // FIX J: advance the slot HERE, before Phase 2
                        // pushes.  Advancing at DRAIN_DONE meant a push
                        // saw an already-advanced slot AND a slot was
                        // drained a timestep after current_slot reached
                        // it, so requested delay N arrived at N+2.
                        current_slot <= current_slot + 6'd1;
                        drain_count <= slot_wr_ptr[current_slot + 6'd1];
                        drain_idx <= 10'd0;
                        if (slot_wr_ptr[current_slot + 6'd1] == 10'd0) begin
                            // Nothing to drain
                            drain_state <= DRAIN_DONE;
                        end else begin
                            bram_rd_addr <= {current_slot + 6'd1, 10'd0};
                            bram_rd_en <= 1'b1;
                            drain_state <= DRAIN_READ;
                        end
                    end
                end

                DRAIN_READ: begin
                    // 1-cycle BRAM latency
                    drain_state <= DRAIN_OUTPUT;
                end

                DRAIN_OUTPUT: begin
                    // Present buffered event on output
                    drain_valid <= 1'b1;
                    drain_addr <= bram_rd_data[28:16];   // addr[12:0]
                    drain_data_out <= bram_rd_data[15:0]; // data[15:0]

                    drain_idx <= drain_idx + 10'd1;
                    if (drain_idx + 10'd1 >= drain_count) begin
                        drain_state <= DRAIN_DONE;
                    end else begin
                        bram_rd_addr <= {current_slot, drain_idx + 10'd1};
                        bram_rd_en <= 1'b1;
                        drain_state <= DRAIN_READ;
                    end
                end

                DRAIN_DONE: begin
                    // slot_wr_ptr reset moved to write pointer always block (fix multi-driven net)
                    // FIX J: advance moved to DRAIN_IDLE.
                    drain_state <= DRAIN_IDLE;
                end

                default: drain_state <= DRAIN_IDLE;
            endcase
        end
    end

    //=========================================================================
    // Output mux: immediate events OR drained buffered events
    // Immediate events take priority (they occur during command processing).
    // Drained events occur at timestep boundaries (before Phase 0).
    // Both should not collide because drain happens on timestep_tick and
    // immediate events happen during CI command processing (different times).
    //=========================================================================
    assign axon_out_set  = immediate_set | drain_valid;
    assign axon_out_addr = drain_valid ? drain_addr  : lookup_addr_r;
    assign axon_out_data = drain_valid ? drain_data_out : lookup_data_r;

endmodule
