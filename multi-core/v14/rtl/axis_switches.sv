//=============================================================================
// axis_switches.sv
//
// SystemVerilog replacements for the Xilinx AXI4-Stream Switch IPs used as
// switch_16_1 and switch_1_16 in sixteen_core_top_firefly.
//
// WHY REPLACE THE IP
//   - the IP is a black box: it cannot be simulated in a plain testbench, so
//     nothing in the design between the cores and PCIe/Firefly was verifiable
//   - it cannot be read, so its arbitration and routing behaviour had to be
//     taken on trust
//   - it ties the project to a specific Vivado version and IP catalogue
//
// CONFIGURATION MATCHED TO THE IP AS INSTANTIATED
//   TDATA 64 bytes (512 bits), TDEST 4 bits, TREADY enabled,
//   round-robin arbiter, arbitrate on maximum 1 transfer.
//   TLAST is carried because the top level connects it, even though the IP
//   customisation had it disabled -- carrying it is harmless and matches the
//   ports the top level drives.
//
// PORT SHAPE
// The top level concatenates per-core signals into flat vectors, e.g.
//   .s_axis_tdata ({core_tx_tdata[15], ..., core_tx_tdata[0]})
// so the aggregate ports are flat [N*512-1:0] with index 0 in the low bits.
// That ordering is what the existing instantiations assume.
//=============================================================================

`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// switch_16_1 -- N slaves to one master, round-robin
//
// Grant is held for the duration of one transfer (arbitrate on 1 transfer, as
// the IP was configured), then the priority pointer advances past the winner
// so no port can be starved.
//-----------------------------------------------------------------------------
module axis_switch_16_1 #(
    parameter int N     = 16,
    parameter int DW    = 512
)(
    input  logic                aclk,
    input  logic                aresetn,

    input  logic [N*DW-1:0]     s_axis_tdata,
    input  logic [N-1:0]        s_axis_tvalid,
    output logic [N-1:0]        s_axis_tready,
    input  logic [N-1:0]        s_axis_tlast,

    output logic [DW-1:0]       m_axis_tdata,
    output logic                m_axis_tvalid,
    input  logic                m_axis_tready,
    output logic                m_axis_tlast
);

    localparam int IW = (N > 1) ? $clog2(N) : 1;

    logic [IW-1:0] rr_ptr;      // where the next search starts

    //-------------------------------------------------------------------------
    // Round-robin select, built entirely from constant indexing.
    //
    // Rotate the valid vector so rr_ptr sits at bit 0, isolate the lowest set
    // bit, then encode.  A priority loop with a variable index would be
    // shorter to write but neither iverilog nor several lint flows handle it,
    // and this form synthesises to the same logic while staying simulable.
    //-------------------------------------------------------------------------
    logic [2*N-1:0] valid_dbl;
    logic [N-1:0]   valid_rot;
    logic [N-1:0]   onehot_rot;
    logic [IW-1:0]  sel_rot;
    logic [IW-1:0]  grant;
    logic           grant_valid;

    assign valid_dbl  = {s_axis_tvalid, s_axis_tvalid};
    assign valid_rot  = valid_dbl[rr_ptr +: N];
    assign onehot_rot = valid_rot & (~valid_rot + 1'b1);   // lowest set bit
    assign grant_valid = |s_axis_tvalid;

    // onehot -> binary, one OR-reduction per output bit
    genvar b, k;
    generate
        for (b = 0; b < IW; b++) begin : gen_enc
            logic [N-1:0] bmask;
            for (k = 0; k < N; k++) begin : gen_mask
                assign bmask[k] = (k >> b) & 1;
            end
            assign sel_rot[b] = |(onehot_rot & bmask);
        end
    endgenerate

    logic [IW:0] grant_sum;
    assign grant_sum = sel_rot + rr_ptr;
    assign grant     = (grant_sum >= N) ? (grant_sum - N) : grant_sum[IW-1:0];

    // Advance past the winner once its transfer completes.
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            rr_ptr <= '0;
        else if (grant_valid && m_axis_tready)
            rr_ptr <= (grant == N-1) ? '0 : (grant + 1'b1);
    end

    assign m_axis_tdata  = s_axis_tdata[grant*DW +: DW];
    assign m_axis_tvalid = grant_valid;
    assign m_axis_tlast  = s_axis_tlast[grant];

    // Only the granted slave sees ready -- constant indexing per instance.
    generate
        for (k = 0; k < N; k++) begin : gen_ready
            assign s_axis_tready[k] = grant_valid && (grant == k[IW-1:0])
                                      && m_axis_tready;
        end
    endgenerate

endmodule


//-----------------------------------------------------------------------------
// switch_1_16 -- one slave to N masters, routed by TDEST
//
// A single transfer goes to exactly the master named by s_axis_tdest.  An
// out-of-range tdest is dropped rather than broadcast: with N a power of two
// and tdest the same width it cannot occur, but the guard means a wider tdest
// later cannot silently flood every core.
//-----------------------------------------------------------------------------
module switch_1_16 #(
    parameter int N     = 16,
    parameter int DW    = 512,
    parameter int DESTW = 4
)(
    input  logic                aclk,
    input  logic                aresetn,

    input  logic [DW-1:0]       s_axis_tdata,
    input  logic [DESTW-1:0]    s_axis_tdest,
    input  logic                s_axis_tvalid,
    output logic                s_axis_tready,
    input  logic                s_axis_tlast,

    output logic [N*DW-1:0]     m_axis_tdata,
    output logic [N-1:0]        m_axis_tvalid,
    input  logic [N-1:0]        m_axis_tready,
    output logic [N-1:0]        m_axis_tlast
);

    logic dest_ok;
    assign dest_ok = (N == (1 << DESTW)) || (s_axis_tdest < N[DESTW-1:0]);

    logic [N-1:0] dest_onehot;

    genvar g;
    generate
        for (g = 0; g < N; g++) begin : gen_fanout
            assign dest_onehot[g] = s_axis_tdest == g[DESTW-1:0];
            // Data is broadcast; only the addressed master sees valid, so the
            // rest never sample it.  The mux ends up in the consumer.
            assign m_axis_tdata[g*DW +: DW] = s_axis_tdata;
            assign m_axis_tvalid[g] = s_axis_tvalid && dest_ok && dest_onehot[g];
            assign m_axis_tlast[g]  = s_axis_tlast;
        end
    endgenerate

    // Ready from the addressed master, as an OR-reduction so there is no
    // variable index.  An undecodable tdest is accepted and discarded rather
    // than stalling the stream forever.
    assign s_axis_tready = dest_ok ? |(m_axis_tready & dest_onehot) : 1'b1;

endmodule


//-----------------------------------------------------------------------------
// axis_arbiter_2 -- two AXI-Stream sources into one, carrying TDEST
//
// Replaces noc_input_arbiter.sv.  Same ports and the same job: merge PCIe
// commands and remote FireFly spikes into the stream feeding switch_1_16.
//
// WHY THE POLICY CHANGED
// The original gave PCIe STRICT priority: FireFly was served only when PCIe
// was idle.  Under sustained host traffic -- loading a large network, or
// continuous exec_step -- remote spikes can be starved indefinitely.  That is
// worse than a throughput problem: spikes are timestep-tagged, so a starved
// remote spike does not merely arrive late, it arrives in the WRONG TIMESTEP
// and is silently misapplied.
//
// This keeps commands prompt without allowing starvation:
//
//   - a PCIe COMMAND always wins immediately.  Commands are rare, bursty and
//     latency-sensitive, and starving them would stall configuration.
//   - PCIe SPIKES and FireFly spikes share the link round-robin.  Both are
//     spike traffic with the same deadline, so neither should outrank the
//     other.
//
// BIAS_GRANTS lets PCIe take that many spike transfers per FireFly one if the
// host path needs more share; 1 is fair.  Set 0 for strict round-robin.
//-----------------------------------------------------------------------------
module axis_arbiter_2 #(
    parameter int DW          = 512,
    parameter int DESTW       = 4,
    parameter int BIAS_GRANTS = 1,
    // A command is anything whose header is not the spike marker.
    parameter logic [31:0] SPIKE_HEADER = 32'hEEEE_EEEE
)(
    input  logic             aclk,
    input  logic             aresetn,

    input  logic [DW-1:0]    pcie_tdata,
    input  logic [DESTW-1:0] pcie_tdest,
    input  logic             pcie_tvalid,
    output logic             pcie_tready,

    input  logic [DW-1:0]    firefly_tdata,
    input  logic [DESTW-1:0] firefly_tdest,
    input  logic             firefly_tvalid,
    output logic             firefly_tready,

    output logic [DW-1:0]    m_axis_tdata,
    output logic [DESTW-1:0] m_axis_tdest,
    output logic             m_axis_tvalid,
    input  logic             m_axis_tready
);

    logic pcie_is_spike, pcie_is_command;
    assign pcie_is_spike   = (pcie_tdata[DW-1 -: 32] == SPIKE_HEADER);
    assign pcie_is_command = pcie_tvalid && !pcie_is_spike;

    // Count PCIe spike grants since the last FireFly one.  When the count
    // reaches BIAS_GRANTS, FireFly gets the next contested transfer.
    localparam int CW = (BIAS_GRANTS > 0) ? $clog2(BIAS_GRANTS + 1) : 1;
    logic [CW-1:0] pcie_run;
    logic          firefly_turn;

    assign firefly_turn = (pcie_run >= BIAS_GRANTS[CW-1:0]);

    logic sel_pcie, sel_firefly;
    always_comb begin
        sel_pcie    = 1'b0;
        sel_firefly = 1'b0;
        if (pcie_is_command)                       sel_pcie    = 1'b1;
        else if (pcie_tvalid && !firefly_tvalid)   sel_pcie    = 1'b1;
        else if (!pcie_tvalid && firefly_tvalid)   sel_firefly = 1'b1;
        else if (pcie_tvalid && firefly_tvalid) begin
            if (firefly_turn) sel_firefly = 1'b1;
            else              sel_pcie    = 1'b1;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            pcie_run <= '0;
        else if (m_axis_tvalid && m_axis_tready) begin
            if (sel_firefly)                 pcie_run <= '0;
            else if (sel_pcie && pcie_is_spike && pcie_run < BIAS_GRANTS[CW-1:0])
                                             pcie_run <= pcie_run + 1'b1;
            // A command does not consume the spike budget: it must never cost
            // FireFly its turn, or a burst of commands would starve it again.
        end
    end

    assign m_axis_tdata  = sel_pcie ? pcie_tdata : firefly_tdata;
    assign m_axis_tdest  = sel_pcie ? pcie_tdest : firefly_tdest;
    assign m_axis_tvalid = sel_pcie | sel_firefly;

    assign pcie_tready    = sel_pcie    & m_axis_tready;
    assign firefly_tready = sel_firefly & m_axis_tready;

endmodule
