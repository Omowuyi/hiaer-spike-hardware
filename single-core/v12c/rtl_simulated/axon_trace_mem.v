//=============================================================================
// axon_trace_mem.v
//
// Eligibility traces for AXON sources, so STDP works on synapses whose
// presynaptic neuron lives on another core, another FPGA or another server.
//
// WHY THIS EXISTS
// stdp_controller reads the presynaptic trace from URAM Row B:
//
//     src_group = e_src[3:0]
//     src_row_b = e_src[16:5] + 2048
//     src_half  = e_src[4]
//
// That only works for a neuron in THIS core.  A remote presynaptic neuron's
// trace lives in the source core's URAM, which this core cannot read, so every
// such synapse learned nothing.
//
// Carrying the trace in the NoC packet does not fix it: LTP fires when the
// POSTsynaptic neuron spikes, which is a later timestep than when the
// presynaptic spike arrived, so a snapshot taken at emission is stale by the
// time it is used.  It would apply the wrong weight update.
//
// Instead the trace is RECONSTRUCTED locally.  A remote spike arrives through
// noc_relay into the EEP as an AXON event, and this core sees every one of
// them -- that is how the synapse fires at all.  So the core can maintain the
// trace itself, and it comes out identical to the source's own copy up to
// transport latency (sub-microsecond on-chip, ~900 ns across three Aurora
// hops, against a timestep of tens of microseconds -- well under one timestep).
//
// It scales unchanged: a remote spike is an axon event whether it came from
// the next core or another server.  Nothing here is distance-specific.
//
// IMPLEMENTATION -- LAZY DECAY, NO SWEEP
// Storing a decaying value would need a sweep over every axon each timestep:
// 8192 entries is 8192 cycles, far more than a timestep can spare.  Instead
// each axon stores only the TIMESTEP OF ITS LAST SPIKE, and the trace is
// computed on read:
//
//     age   = now - last_ts        (mod 32, matching the 5-bit TS field)
//     trace = age >= 4 ? 0 : (4'hF >> age)      -> 15, 7, 3, 1, 0
//
// That is the same exponential shape as the neuron trace over its useful
// range, costs one subtract and one shift, and needs 5 bits per axon instead
// of 4 plus a sweep.
//
// A trace that has never been set reads 0: last_ts is initialised to a value
// that always ages out.
//=============================================================================

`timescale 1ns / 1ps

module axon_trace_mem #(
    parameter NUM_ROWS   = 512,    // axon rows; axon index = {row[12:0], group[3:0]}
    parameter ROW_BITS   = 13,
    parameter NUM_GROUPS = 16,     // neuron groups per row -- matches the EEP mask
    parameter TS_BITS    = 5,      // matches the NoC packet's TS field
    parameter TRACE_BITS = 4       // matches stdp_controller's src_trace
)(
    input  wire                   clk,
    input  wire                   resetn,

    // Current timestep, low bits.  Same counter the delay buffers tick on.
    input  wire [TS_BITS-1:0]     timestep,
    input  wire                   timestep_tick,

    //=========================================================================
    // Write: an EEP row fired.
    //
    // The EEP scans axons a ROW at a time and emits a 16-bit one-hot-per-group
    // mask, exactly as axonEvent_addr / axonEvent_data are shaped.  So the
    // write port takes a row and a mask, and 16 banks let every group in that
    // row update in one cycle.  Taking a single axon index instead would need
    // 16 sequential writes per row and would not match what the EEP produces.
    //
    // This must be asserted for BOTH host-injected axons and spikes arriving
    // over noc_relay.  A remote spike is an axon event; if it is not counted
    // here its trace never rises and the synapse still will not learn.
    //=========================================================================
    input  wire                   row_fired,
    input  wire [ROW_BITS-1:0]    row_addr,
    input  wire [NUM_GROUPS-1:0]  row_mask,

    //=========================================================================
    // Read: stdp_controller presents a full 17-bit axon index.
    //=========================================================================
    input  wire                   trace_rd_en,
    input  wire [16:0]            trace_rd_idx,
    output reg  [TRACE_BITS-1:0]  trace_rd_data
);

    localparam VW = TS_BITS + 1;      // valid bit + timestep

    // One bank per group.  Each holds the last-fired timestep for its group's
    // axon in every row, so a row write updates all sixteen at once with the
    // mask as per-bank write enables.

    wire [3:0]          rd_group = trace_rd_idx[3:0];
    wire [ROW_BITS-1:0] rd_row   = trace_rd_idx[16:4];

    // Each bank is read at the same row address every cycle and the bank is
    // selected afterwards. That gives every bank one variable address, which is
    // what a block RAM port provides, so the array infers as sixteen block RAMs
    // rather than as flip-flops. Indexing the array with a variable bank as well
    // as a variable row would require an arbitrary two-dimensional access, which
    // no block RAM can serve, and Vivado would build the whole array in
    // registers -- 786,432 bits per core, twelve and a half million across the
    // device.
    wire [VW-1:0] bank_rd [0:NUM_GROUPS-1];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_GROUPS; gi = gi + 1) begin : gen_bank
            // One flat memory per bank. A two-dimensional array is classified
            // by Vivado as a three-dimensional RAM and built in registers
            // whatever ram_style asks for, which cost 786,432 registers per
            // core. A one-dimensional array with a single variable address is
            // what a block RAM port provides and infers correctly.
            (* ram_style = "block" *)
            reg [VW-1:0] last_ts [0:NUM_ROWS-1];
            reg [VW-1:0] bank_dout;

            integer r;
            initial
                for (r = 0; r < NUM_ROWS; r = r + 1)
                    last_ts[r] = {VW{1'b0}};     // valid bit clear

            always @(posedge clk) begin
                if (row_fired && row_mask[gi])
                    last_ts[row_addr] <= {1'b1, timestep};
                if (trace_rd_en)
                    bank_dout <= last_ts[rd_row];
            end
            assign bank_rd[gi] = bank_dout;
        end
    endgenerate

    //=========================================================================
    // Read and decay.
    //
    // LAZY DECAY -- NO SWEEP.  Storing a decaying value would need a pass over
    // every axon each timestep; 8192 entries is 8192 cycles, far more than a
    // timestep can spare.  Storing only the last-fired timestep and computing
    //
    //     age   = now - last_ts        (mod 32, matching the TS field)
    //     trace = age >= 4 ? 0 : (4'hF >> age)      -> 15, 7, 3, 1, 0
    //
    // gives the same exponential shape over its useful range for one subtract
    // and one shift.
    //=========================================================================

    reg [3:0]          rd_group_q;
    reg [TS_BITS-1:0]  rd_now;
    reg                rd_pending;

    // the bank selected by the registered group index, available in the same
    // cycle rd_pending is asserted
    wire [VW-1:0] rd_ts = bank_rd[rd_group_q];

    always @(posedge clk) begin
        if (~resetn) begin
            rd_pending    <= 1'b0;
            trace_rd_data <= {TRACE_BITS{1'b0}};
        end else begin
            rd_pending <= trace_rd_en;
            if (trace_rd_en) begin
                rd_group_q <= rd_group;      // select the bank next cycle
                rd_now     <= timestep;
            end
            if (rd_pending) begin
                if (!rd_ts[VW-1])
                    trace_rd_data <= {TRACE_BITS{1'b0}};        // never fired
                else begin : decay
                    reg [TS_BITS-1:0] age;
                    age = rd_now - rd_ts[TS_BITS-1:0];          // wraps mod 32
                    trace_rd_data <= (age >= TRACE_BITS) ? {TRACE_BITS{1'b0}}
                                                         : ({TRACE_BITS{1'b1}} >> age);
                end
            end
        end
    end

    // timestep_tick is unused with lazy decay.  It stays on the port so an
    // eager-decay variant, or a wider trace needing real multiplication, can
    // be dropped in without changing every instantiation.
    wire _unused_tick = timestep_tick;

endmodule
