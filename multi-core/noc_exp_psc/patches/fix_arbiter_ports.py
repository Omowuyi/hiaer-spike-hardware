#!/usr/bin/env python3
"""
Correct the axis_arbiter_2 instantiation in the patched top.

wire_firefly_top.py instantiated the arbiter with SystemVerilog interface
ports:

    axis_arbiter_2 #(.DW(512), .DESTW(5)) ingress_arb (
        .aclk(aclk), .aresetn(aresetn),
        .s0 (to_rxFIFO_with_dest),
        .s1 (from_firefly),
        .m  (ingress_merged)
    );

The module does not have those ports.  axis_switches.sv line 196 declares
discrete signals instead -- pcie_tdata / tdest / tvalid / tready, the same four
prefixed firefly_, and m_axis_*.  Elaboration would fail with three ports that
do not exist and twelve left unconnected.

The names are not arbitrary either: the arbiter inspects pcie_tdata's top
thirty-two bits against SPIKE_HEADER to tell a host COMMAND from a host SPIKE,
and gives commands immediate service.  So the PCIe stream must go to the pcie_
side and the Firefly stream to the firefly_ side -- swapping them would let a
burst of remote spikes delay configuration writes, and would stop commands
being recognised at all.

DESTW is set to 5 because the ingress path feeds switch_1_32, which selects
among thirty-two destinations.  The module defaults to 4.

  python3 fix_arbiter_ports.py --check <top.sv>
  python3 fix_arbiter_ports.py         <top.sv>
"""

import sys, os

OLD = """    axis_arbiter_2 #(
        .DW (512),
        .DESTW (5)
    ) ingress_arb (
        .aclk    (aclk),
        .aresetn (aresetn),
        .s0      (to_rxFIFO_with_dest),
        .s1      (from_firefly),
        .m       (ingress_merged)
    );"""

NEW = """    axis_arbiter_2 #(
        .DW    (512),
        .DESTW (5)          // ingress feeds switch_1_32: 32 destinations
    ) ingress_arb (
        .aclk    (aclk),
        .aresetn (aresetn),

        // Host stream.  The arbiter reads the top 32 bits of pcie_tdata and
        // treats anything that is not the spike header as a COMMAND, which
        // always wins immediately.  The host stream must therefore be on this
        // side, not the firefly_ side.
        .pcie_tdata     (to_rxFIFO_with_dest.tdata),
        .pcie_tdest     (to_rxFIFO_with_dest.tdest),
        .pcie_tvalid    (to_rxFIFO_with_dest.tvalid),
        .pcie_tready    (to_rxFIFO_with_dest.tready),

        // Spikes returning from other devices.
        .firefly_tdata  (from_firefly.tdata),
        .firefly_tdest  (from_firefly.tdest),
        .firefly_tvalid (from_firefly.tvalid),
        .firefly_tready (from_firefly.tready),

        .m_axis_tdata   (ingress_merged.tdata),
        .m_axis_tdest   (ingress_merged.tdest),
        .m_axis_tvalid  (ingress_merged.tvalid),
        .m_axis_tready  (ingress_merged.tready)
    );"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_arbiter_ports.py [--check] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if ".pcie_tdata     (to_rxFIFO_with_dest.tdata)" in s:
    fail("already patched")

n = s.count(OLD)
if n != 1:
    fail("anchor matched %d times, expected 1" % n)
print("  ok  arbiter instantiation found (line %d)" % (s[:s.index(OLD)].count("\n") + 1))

# the interface members this patch reaches into must exist
for iface, member in (("to_rxFIFO_with_dest", "tdest"), ("from_firefly", "tdest"),
                      ("ingress_merged", "tdest")):
    if iface not in s:
        fail("interface %s is not declared in this file" % iface)
print("  ok  all three stream interfaces declared")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_arbfix"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
out = s.replace(OLD, NEW, 1)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
