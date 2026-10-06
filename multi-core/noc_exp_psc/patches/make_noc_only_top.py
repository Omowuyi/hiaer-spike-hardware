#!/usr/bin/env python3
"""
Generate sixteen_core_noc_top.sv from sixteen_core_noc_firefly_top.sv.

THE POINT

The Firefly top is READ, never written.  Everything Firefly -- the four Aurora
cores, the GT pins, the classifier, the injector, their constraints -- is
untouched by this script, so a NoC-only build cannot regress the Firefly build.

The generated top is a separate module with NO ff* ports at all.  That is what
removes the DRC failure: write_bitstream requires every logical port to carry
an IOSTANDARD and a LOC, and the GT serial pins have neither by design.  A port
that does not exist raises nothing.  Waiving NSTD-1/UCIO-1 instead would
disable exactly the checks that protect the Firefly build's pin constraints.

WHAT IS REMOVED, AND WHAT REPLACES IT

  ff4..ff7 ports          removed from the port list entirely
  axis_arbiter_2          nothing arrives from off-device, so the host stream
                          connects straight to ingress_merged
  spike_classifier        every spike is local: from_txFIFO_raw passes through
  firefly_subsystem_top   not instantiated
  remote_spike_injector   not instantiated
  Firefly status LEDs     tied off (active low, held high)

Everything else -- the 16 cores, the NoC, PCIe, HBM, the 512-bit host path --
is copied through byte for byte.

REGENERATING

This is the cost of keeping the two tops separate: a change to the shared
internals has to be re-run through here.  One command, and the diff shows
exactly what moved.

  python3 make_noc_only_top.py <firefly top .sv> [output .sv]
"""

import sys
import os
import io
import hashlib

SRC_MD5 = "b1b8c993677dce3eb21599952769e39f"

NEW_MODULE = "sixteen_core_noc_top"
OLD_MODULE = "sixteen_core_noc_firefly_top"

# ---- port block: first and last line of the ff4..ff7 declarations -----------
PORT_FIRST = "    input        ff4_refclk_p,"
PORT_LAST = "    output [3:0] ff7_txn,"

# ---- the ingress arbiter, replaced by a direct connection ------------------
OLD_ARBITER_HEAD = "    axis_arbiter_2 #("
ARBITER_TAIL = "        .m_axis_tready  (ingress_merged.tready)\n    );\n"

NEW_ARBITER = """    // No spikes arrive from off-device in this build, so there is nothing to
    // arbitrate against: the host stream is the only producer of ingress
    // traffic and connects straight through.
    // AXIStream carries SIX wires (types.sv:97-102): tdata, tvalid, tlast,
    // tkeep, tdest, tready.  All six must be driven -- an undriven tkeep is
    // legal SystemVerilog and passes synthesis and timing, then resolves to X
    // in hardware and the first host write never completes, leaving the
    // driver blocked in adxdma_h2c_release.
    // tlast/tkeep take the same values pcie_tdest_generator assigns on the
    // equivalent path (switch_1_32.sv:12-13).
    assign ingress_merged.tdata       = to_rxFIFO_with_dest.tdata;
    assign ingress_merged.tdest       = to_rxFIFO_with_dest.tdest;
    assign ingress_merged.tvalid      = to_rxFIFO_with_dest.tvalid;
    assign ingress_merged.tlast       = 1'b0;
    assign ingress_merged.tkeep       = {64{1'b1}};
    assign to_rxFIFO_with_dest.tready = ingress_merged.tready;
"""

# ---- the Firefly block, from its banner to the from_firefly tdest assign ----
FF_FIRST = "    // Firefly: spike transport to the other devices of this server."
FF_LAST = "    assign from_firefly.tdest = {1'b0, ff_inject_core};"

NEW_FF = """    //=========================================================================
    // Per-core CMD 16 outputs.  These are declared inside the Firefly block in
    // the Firefly top, where the classifier consumes core 0's copy to build the
    // remote destination table.  noc_integration drives them from every core's
    // command interpreter regardless, so the declarations have to survive here
    // even though nothing reads them in a NoC-only build.
    //=========================================================================
    wire        core_fpga_id_valid    [0:15];
    wire [2:0]  core_fpga_id_data     [0:15];
    wire        core_remote_cfg_valid [0:15];
    wire [7:0]  core_remote_cfg_addr  [0:15];
    wire [5:0]  core_remote_cfg_data  [0:15];

    // Firefly status, read by top_vio probes 30-33.  The VIO is outside the
    // Firefly block and keeps those probes, so the signals are declared and
    // held at zero here.  Tied off rather than removed so the probe numbering
    // and the .ltx match the Firefly build exactly -- a probe that moves
    // between the two bitstreams is worse on the bench than one reading zero.
    wire [3:0]  ff_channel_up    = 4'd0;
    wire [3:0]  ff_hard_err      = 4'd0;
    wire [31:0] ff_spikes_routed = 32'd0;
    wire [31:0] ff_spikes_dropped= 32'd0;

    //=========================================================================
    // Egress, NoC-only: every spike produced on this device stays on it, so
    // the aggregated core stream reaches the host path unchanged.  In the
    // Firefly build a spike_classifier sits here and diverts spikes bound for
    // another device to the optical link.
    //=========================================================================
    assign from_txFIFO.tdata      = from_txFIFO_raw.tdata;
    assign from_txFIFO.tvalid     = from_txFIFO_raw.tvalid;
    assign from_txFIFO_raw.tready = from_txFIFO.tready;

    // The four status LEDs report the optical link, which this build does not
    // have.  Active low, so held high leaves all four dark.
    assign user_led_g0_l = 1'b1;
    assign user_led_g1_l = 1'b1;
    assign user_led_g2_l = 1'b1;
    assign user_led_g3_l = 1'b1;
"""

HEADER = """//=============================================================================
// GENERATED FILE -- do not edit by hand.
//
// Produced by make_noc_only_top.py from %s.sv
// Source md5: %s
//
// NoC-only variant: 16 cores, the crossbar NoC, PCIe and HBM, with no Firefly
// optical path and no GT transceiver ports.  Regenerate after any change to
// the shared internals of the Firefly top.
//=============================================================================

"""


def cut_range(lines, first, last, replacement, what):
    """Replace lines[i..j] where lines[i] is `first` and lines[j] is `last`."""
    try:
        i = next(n for n, l in enumerate(lines) if l.rstrip() == first.rstrip())
    except StopIteration:
        raise SystemExit("FAIL  could not find the start of %s:\n  %s" % (what, first))
    try:
        j = next(n for n, l in enumerate(lines) if n >= i and l.rstrip() == last.rstrip())
    except StopIteration:
        raise SystemExit("FAIL  could not find the end of %s:\n  %s" % (what, last))
    print("  %-22s lines %d-%d  (%d lines)" % (what, i + 1, j + 1, j - i + 1))
    return lines[:i] + ([replacement] if replacement else []) + lines[j + 1:]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("usage: make_noc_only_top.py <firefly top .sv> [output .sv]")
        return 2
    src = args[0]
    if not os.path.isfile(src):
        print("FAIL  no such file: %s" % src)
        return 2

    raw = io.open(src, "rb").read()
    md5 = hashlib.md5(raw).hexdigest()
    print("source   %s" % src)
    print("md5      %s  %s" % (md5, "(expected)" if md5 == SRC_MD5 else
                               "** DIFFERS from %s **" % SRC_MD5))
    if md5 != SRC_MD5:
        print("\nThe Firefly top has changed since this script was written.")
        print("Re-read it before trusting the output -- the cut boundaries are")
        print("matched on text, so they will fail loudly rather than silently,")
        print("but a new Firefly signal used OUTSIDE the cut would not be caught.")

    out = args[1] if len(args) > 1 else os.path.join(
        os.path.dirname(src) or ".", NEW_MODULE + ".sv")

    lines = io.open(src, encoding="utf-8").read().splitlines(keepends=True)
    print("\ncuts:")

    # 1. the ff4..ff7 port declarations
    lines = cut_range(lines, PORT_FIRST, PORT_LAST, None, "ff4..ff7 ports")

    # 2. the ingress arbiter
    try:
        i = next(n for n, l in enumerate(lines)
                 if l.rstrip() == OLD_ARBITER_HEAD.rstrip())
    except StopIteration:
        raise SystemExit("FAIL  could not find the ingress arbiter")
    body = "".join(lines[i:])
    k = body.find(ARBITER_TAIL)
    if k < 0:
        raise SystemExit("FAIL  could not find the end of the ingress arbiter")
    consumed = body[:k + len(ARBITER_TAIL)].count("\n")
    print("  %-22s lines %d-%d  (%d lines)"
          % ("ingress arbiter", i + 1, i + consumed, consumed))
    lines = lines[:i] + [NEW_ARBITER] + lines[i + consumed:]

    # 3. the Firefly block
    lines = cut_range(lines, FF_FIRST, FF_LAST, NEW_FF, "firefly block")

    text = "".join(lines)

    # 4. module name
    n = text.count("module " + OLD_MODULE)
    if n != 1:
        raise SystemExit("FAIL  found %d module declarations, expected 1" % n)
    text = text.replace("module " + OLD_MODULE, "module " + NEW_MODULE, 1)

    # the banner line above the removed ports is now orphaned
    text = text.replace("    //=========================================================================\n"
                        "    // FireFly optical ports.\n", "", 1)

    text = HEADER % (OLD_MODULE, md5) + text

    # ---- checks ----------------------------------------------------------
    print("\nchecks:")
    bad = False
    for tok in ["ff4_", "ff5_", "ff6_", "ff7_", "spike_classifier",
                "firefly_subsystem_top", "remote_spike_injector",
                "from_firefly", "ff_tx_spike", "ff_rx_spike", "THIS_FPGA_ID"]:
        c = text.count(tok)
        # tokens are allowed to survive only inside the explanatory comments
        real = sum(1 for l in text.splitlines()
                   if tok in l and not l.lstrip().startswith("//"))
        status = "OK" if real == 0 else "** %d in code **" % real
        if real:
            bad = True
        print("  %-24s %2d total, %s" % (tok, c, status))

    for tok in ["noc_integration", "switch_1_32", "switch_32_1", "pcie_dma",
                "clock_and_buffer",
                # declared inside the Firefly block but driven by
                # noc_integration, so they must survive the cut
                "core_fpga_id_valid", "core_fpga_id_data",
                "core_remote_cfg_valid", "core_remote_cfg_addr",
                "core_remote_cfg_data",
                "ff_channel_up", "ff_hard_err",
                "ff_spikes_routed", "ff_spikes_dropped"]:
        c = text.count(tok)
        print("  %-24s %2d  %s" % (tok, c, "OK" if c else "** MISSING **"))
        if not c:
            bad = True

    if bad:
        print("\nFAIL  output not written.")
        return 1

    io.open(out, "w", encoding="utf-8").write(text)
    print("\nwrote    %s  (%d lines, source had %d)"
          % (out, text.count("\n"), raw.decode("utf-8").count("\n")))
    print("""
NEXT
  1. add this file to the project as the top of a SECOND synthesis run
  2. leave the Firefly run's top, constraints and fileset untouched
  3. the ff*_pins.xdc / gt_loc.xdc / hiaer_multicore_firefly_complete.xdc
     constraints belong to the Firefly run only -- this top has no ff* ports,
     so they would fail to match here""")
    return 0


if __name__ == "__main__":
    sys.exit(main())
