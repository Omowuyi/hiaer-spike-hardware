#!/usr/bin/env python3
"""
Wire the Firefly chain into sixteen_core_noc_firefly_top -- LOWER TIER.

SCOPE, AND WHY IT IS THE LOWER TIER
-----------------------------------
The top declares two Aurora port groups, GT_SERIAL_*_AUR_0 and _AUR_1, with
refclks GT_DIFF_REFCLK1_0 and _1.  firefly_subsystem_top expects four (ff4 to
ff7).  A lower-tier device instantiates exactly ONE channel, port 7, which is
the port every device in the topology carries -- so AUR_0 maps to ff7 and the
other three are tied off.  An upper-tier build needs two further port pairs
added to the top and to the board pinout, which is separate work.

Bringing up one link before ten is the right order anyway.

THE CHAIN
    cores -> before_switch[31:0] -> switch_32_1 -> from_txFIFO_raw
                                                        |
                                              spike_classifier
                                                   /        \\
                                        m_pcie (local)   m_firefly (remote)
                                             |                  |
                                       from_txFIFO      firefly_subsystem_top
                                             |                  |
                                          PCIe             optical link
                                                                |
                                                        firefly_subsystem_top
                                                                |
                                                     remote_spike_injector
                                                                |
                                              merged into the ingress stream
                                              ahead of switch_1_32, so remote
                                              spikes enter a core as ordinary
                                              axon events

WHAT THIS PATCH DOES NOT DO
---------------------------
1. PIN CONSTRAINTS.  No XDC in the tree assigns the Aurora serial or refclk
   pins.  Two are known from the part -- T42 is ff7_refclk_p and L48 is
   ff7_txp[0] -- the other fifteen need the ADM-PCIE-9H7 pinout.  Without
   them implementation will report unconstrained ports.

2. GT PLACEMENT.  Once this patch is in and the design synthesises, Aurora's
   GTYE4_CHANNEL and GTYE4_COMMON cells exist for the first time and their
   placement can be read and, if wrong, constrained.  That is why this comes
   before the GT work, not after.

3. THE TWO REMAINING CLASSIFIER PLACEHOLDERS.  dst_server is fixed at 3'd0 and
   src_core at 4'd0.  Both are handled by fix_classifier_fields.py, applied
   separately so the two changes can be reviewed apart.

  python3 wire_firefly_top.py --check <sixteen_core_noc_firefly_top.sv>
  python3 wire_firefly_top.py         <sixteen_core_noc_firefly_top.sv>
"""

import sys, os

# --------------------------------------------------------------------------
# 1. rename the switch_32_1 output so the classifier can sit in the path
# --------------------------------------------------------------------------
A_SW = """    switch_32_1 s_32_1 (
        .s (before_switch),
        .m (from_txFIFO)
    );"""

N_SW = """    //=========================================================================
    // Egress: the aggregated core stream now passes through the classifier
    // before reaching the host path, so spikes bound for another device can
    // be diverted to the optical link.
    //=========================================================================
    AXIStream_simple #(512) from_txFIFO_raw (.aclk(aclk), .aresetn(aresetn));

    switch_32_1 s_32_1 (
        .s (before_switch),
        .m (from_txFIFO_raw)
    );"""

# --------------------------------------------------------------------------
# 2. the Firefly chain, inserted after the NoC block
# --------------------------------------------------------------------------
A_ANCHOR = """    //=========================================================================
    // Crossbar NoC -- core-to-core spike routing within this FPGA."""

FIREFLY = r"""    //=========================================================================
    // Firefly: spike transport to the other devices of this server.
    //
    // LOWER TIER.  One Aurora channel on port 7, which every device carries.
    // The top's AUR_0 pin group maps to ff7; ff4 to ff6 are tied off because
    // an upper-tier device would need two further port pairs on the connector
    // and in the board pinout.
    //
    // The classifier sits on the egress stream and splits it: spikes whose
    // destination block resolves to this device continue to the host path
    // unchanged, and the rest become 64-bit inter-device packets.  Returning
    // spikes are batched by the injector and merged into the ingress stream
    // ahead of switch_1_32, so a remote spike enters its destination core as
    // an ordinary axon event -- identical in form to one injected by the host.
    // Nothing in the neuron model, the synapse format, or the delay and
    // plasticity paths distinguishes the two.
    //=========================================================================
    localparam logic [2:0] THIS_FPGA_ID = 3'd0;   // set per device before build

    inter_fpga_spike_t  ff_tx_spike;
    logic               ff_tx_valid, ff_tx_ready;
    inter_fpga_spike_t  ff_rx_spike;
    logic               ff_rx_valid, ff_rx_ready;

    logic [3:0]  ff_channel_up;
    logic [3:0]  ff_hard_err;
    logic [31:0] ff_spikes_routed;
    logic [31:0] ff_spikes_dropped;

    // ---- egress: classify the aggregated core stream ----------------------
    spike_classifier #(
        .LOCAL_FPGA_ID (THIS_FPGA_ID)
    ) ff_classifier (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_tdata    (from_txFIFO_raw.tdata),
        .s_axis_tvalid   (from_txFIFO_raw.tvalid),
        .s_axis_tready   (from_txFIFO_raw.tready),
        .m_pcie_tdata    (from_txFIFO.tdata),
        .m_pcie_tvalid   (from_txFIFO.tvalid),
        .m_pcie_tready   (from_txFIFO.tready),
        .m_firefly_spike (ff_tx_spike),
        .m_firefly_valid (ff_tx_valid),
        .m_firefly_ready (ff_tx_ready)
    );

    // ---- the optical subsystem -------------------------------------------
    // ff4 to ff6 are unused on a lower-tier device.  Their refclks are tied
    // low and their receivers to zero; the transmit pins are left open.
    firefly_subsystem_top #(
        .FPGA_ID (THIS_FPGA_ID)
    ) ff_subsys (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .init_clk      (apb_clk),

        .ff4_refclk_p  (1'b0), .ff4_refclk_n (1'b1),
        .ff5_refclk_p  (1'b0), .ff5_refclk_n (1'b1),
        .ff6_refclk_p  (1'b0), .ff6_refclk_n (1'b1),
        .ff7_refclk_p  (GT_DIFF_REFCLK1_0_clk_p),
        .ff7_refclk_n  (GT_DIFF_REFCLK1_0_clk_n),

        .ff4_txp (), .ff4_txn (), .ff4_rxp (4'd0), .ff4_rxn (4'hF),
        .ff5_txp (), .ff5_txn (), .ff5_rxp (4'd0), .ff5_rxn (4'hF),
        .ff6_txp (), .ff6_txn (), .ff6_rxp (4'd0), .ff6_rxn (4'hF),
        .ff7_txp (GT_SERIAL_TX_AUR_0_txp),
        .ff7_txn (GT_SERIAL_TX_AUR_0_txn),
        .ff7_rxp (GT_SERIAL_RX_AUR_0_rxp),
        .ff7_rxn (GT_SERIAL_RX_AUR_0_rxn),

        .noc_tx_spike  (ff_tx_spike),
        .noc_tx_valid  (ff_tx_valid),
        .noc_tx_ready  (ff_tx_ready),
        .noc_rx_spike  (ff_rx_spike),
        .noc_rx_valid  (ff_rx_valid),
        .noc_rx_ready  (ff_rx_ready),

        .channel_up      (ff_channel_up),
        .hard_err        (ff_hard_err),
        .spikes_routed   (ff_spikes_routed),
        .spikes_dropped  (ff_spikes_dropped)
    );

    // ---- ingress: batch returning spikes into 512-bit beats ---------------
    AXIStream #(512, 5) from_firefly (.aclk(aclk), .aresetn(aresetn));

    remote_spike_injector #(
        .LOCAL_FPGA_ID (THIS_FPGA_ID)
    ) ff_injector (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .firefly_spike (ff_rx_spike),
        .firefly_valid (ff_rx_valid),
        .firefly_ready (ff_rx_ready),
        .m_axis_tdata  (from_firefly.tdata),
        .m_axis_tdest  (from_firefly.tdest[3:0]),
        .m_axis_tvalid (from_firefly.tvalid),
        .m_axis_tready (from_firefly.tready)
    );
    assign from_firefly.tdest[4] = 1'b0;

"""

# --------------------------------------------------------------------------
# 3. merge the injector stream into the ingress path ahead of switch_1_32
# --------------------------------------------------------------------------
A_S132 = """    switch_1_32 s_1_32 (
        .s (to_rxFIFO_with_dest),
        .m (after_switch)
    );"""

N_S132 = """    //=========================================================================
    // Ingress arbitration.  Host commands must not be delayed behind a burst
    // of remote spikes, and remote spikes must not be starved behind sustained
    // host traffic -- because a spike carries the timestep it was emitted in,
    // a starved spike arrives in the WRONG timestep rather than merely late.
    // axis_arbiter_2 gives a command immediate service and otherwise shares
    // the link round-robin.
    //=========================================================================
    AXIStream #(512, 5) ingress_merged (.aclk(aclk), .aresetn(aresetn));

    axis_arbiter_2 #(
        .DW (512),
        .DESTW (5)
    ) ingress_arb (
        .aclk    (aclk),
        .aresetn (aresetn),
        .s0      (to_rxFIFO_with_dest),
        .s1      (from_firefly),
        .m       (ingress_merged)
    );

    switch_1_32 s_1_32 (
        .s (ingress_merged),
        .m (after_switch)
    );"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: wire_firefly_top.py [--check] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "spike_classifier" in s:
    fail("already patched: spike_classifier is present")

for tag, a in (("switch_32_1", A_SW), ("noc anchor", A_ANCHOR), ("switch_1_32", A_S132)):
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-12s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

# the pins the patch relies on must exist in the port list
for pin in ("GT_SERIAL_TX_AUR_0_txp", "GT_SERIAL_RX_AUR_0_rxp",
            "GT_DIFF_REFCLK1_0_clk_p", "apb_clk"):
    if pin not in s:
        fail("the top does not declare %s, so the mapping in this patch is wrong" % pin)
print("  ok  Aurora pin group and init clock present")

print("\nline endings: %s" % ("CRLF, preserved" if crlf else "LF"))

if check:
    print("""
--check: nothing written.

BEFORE BUILDING, three things this patch does not cover:

  1. Pin constraints.  No XDC assigns the Aurora serial or refclk pins.  Two
     are known from the part: T42 is ff7_refclk_p and L48 is ff7_txp[0].  The
     other fifteen need the ADM-PCIE-9H7 pinout.  Implementation will report
     unconstrained ports until they are supplied.

  2. Classifier fields.  dst_server is fixed at 3'd0 and src_core at 4'd0.
     Apply fix_classifier_fields.py before any inter-server traffic.

  3. hiaer_firefly_pkg.sv must be in the project and read before the top, or
     inter_fpga_spike_t will not resolve.

AFTER SYNTHESIS the Aurora GT cells exist for the first time.  Read their
placement then:

    get_cells -hier -filter {REF_NAME =~ GTYE4_CHANNEL*}

and constrain with LOC if the wizard placed them in column X1 rather than the
X0Y40-X0Y43 that the package pins require.
""")
    sys.exit(0)

out = s.replace(A_SW, N_SW, 1)
out = out.replace(A_ANCHOR, FIREFLY + A_ANCHOR, 1)
out = out.replace(A_S132, N_S132, 1)

bak = p + ".before_firefly"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Set THIS_FPGA_ID per device before building.")
