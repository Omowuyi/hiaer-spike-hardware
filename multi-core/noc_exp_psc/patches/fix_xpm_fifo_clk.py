#!/usr/bin/env python3
"""
Fix the xpm_fifo_sync clock port name in inter_fpga_router.sv.

    [Synth 8-11365] for the instance 'u_tx_fifo' of module 'xpm_fifo_sync'
    named port connection 'clk' does not exist
    inter_fpga_router.sv:278

xpm_fifo_sync names its clock wr_clk, not clk -- the same name the asynchronous
variant uses for its write side.  aurora_channel_wrapper.sv gets this right in
both of its xpm_fifo_async instances, which is what confirms the convention
rather than leaving it to memory.

WHY THIS SURFACED ONLY NOW
--------------------------
inter_fpga_router.sv has been in the project for weeks but nothing instantiated
it, so synthesis never elaborated its body.  Wiring the Firefly chain into the
top is what first caused this module to be compiled.  The same is true of every
other Firefly source: any error inside them is being seen for the first time.

  python3 fix_xpm_fifo_clk.py --check <inter_fpga_router.sv>
  python3 fix_xpm_fifo_clk.py         <inter_fpga_router.sv>
"""

import sys, os, re

OLD = """                ) u_tx_fifo (
                    .clk            (aclk),"""
NEW = """                ) u_tx_fifo (
                    // xpm_fifo_sync calls its clock wr_clk, not clk.
                    .wr_clk         (aclk),"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_xpm_fifo_clk.py [--check] <inter_fpga_router.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if ".wr_clk         (aclk)," in s:
    fail("already patched")

n = s.count(OLD)
if n != 1:
    fail("anchor matched %d times, expected 1" % n)
print("  ok  anchor verified (line %d)" % (s[:s.index(OLD)].count("\n") + 1))

# any other xpm instance in this file with the same mistake
others = [(i + 1, l) for i, l in enumerate(s.split("\n"))
          if re.match(r"\s*\.clk\s*\(", l)]
if others:
    print("  !!  %d further '.clk(' connection(s) in this file:" % len(others))
    for ln, l in others[:8]:
        print("        line %d: %s" % (ln, l.strip()))
    print("      check each against its module -- only XPM instances need wr_clk")
else:
    print("  ok  no other '.clk(' connections in this file")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_xpmclk"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
out = s.replace(OLD, NEW, 1)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
