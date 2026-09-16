#!/usr/bin/env python3
"""
Point aurora_channel_wrapper at the real IP, with the right port names.

WHAT SYNTHESIS REPORTED
-----------------------
Eight "named port connection does not exist" errors on instance u_aurora, then
the enclosing chain failing: xpm_fifo_async, aurora_channel_wrapper,
firefly_subsystem_top, and the top.  The xpm failures are NOT independent --
they are the modules that contain the failing instance.

WHAT IS ACTUALLY WRONG
----------------------
Two things, and neither is a missing capability.

1. THE WRONG IP.  The wrapper instantiates `aurora_64b66b_port7`.  The IP that
   is configured for this design -- 4 lanes, 25.78125 Gb/s, 161.13 MHz refclk
   -- is named `aurora_64b66b_port7_logic`.  Vivado found a stub for the other
   name and elaborated against that.

2. PORT NAMES.  Comparing the wrapper's 27 connections against the 135 ports
   the real IP declares, exactly eight are absent, and each has a counterpart:

       gt_rxp  gt_rxn  gt_txp  gt_txn   ->   rxp  rxn  txp  txn

       gt_qpllclk_quad1_in                   gt_qpllclk_quad1_out
       gt_qplllock_quad1_in            ->    gt_qplllock_quad1_out
       gt_qpllrefclk_quad1_in                gt_qpllrefclk_quad1_out
       gt_qpllrefclklost_quad1_in            gt_qpllrefclklost_quad1_out

   Everything else the wrapper needs -- gt_refclk1_p/n, user_clk_out,
   init_clk, s_axi_tx_*, m_axi_rx_*, channel_up, lane_up, hard_err, soft_err,
   sys_reset_out, link_reset_out, loopback, pma_init, reset_pb, power_down --
   exists under the same name.

   The four QPLL connections are removed rather than renamed.  The wrapper
   leaves them empty, and on this IP they are OUTPUTS: the core was generated
   with shared logic INSIDE it, so it produces the QPLL for others rather than
   consuming one.  A single-channel device has nobody to share with.

  python3 fix_aurora_wrapper_ports.py --check <aurora_channel_wrapper.sv>
  python3 fix_aurora_wrapper_ports.py         <aurora_channel_wrapper.sv>
"""

import sys, os, re

RENAMES = [
    (".gt_rxp                 (gt_rxp),",  ".rxp                    (gt_rxp),"),
    (".gt_rxn                 (gt_rxn),",  ".rxn                    (gt_rxn),"),
    (".gt_txp                 (gt_txp),",  ".txp                    (gt_txp),"),
    (".gt_txn                 (gt_txn),",  ".txn                    (gt_txn),"),
]

DROP_PREFIXES = (
    ".gt_qpllclk_quad1_in",
    ".gt_qplllock_quad1_in",
    ".gt_qpllrefclk_quad1_in",
    ".gt_qpllrefclklost_quad1_in",
)

MODULE_OLD = "            aurora_64b66b_port7 u_aurora ("
MODULE_NEW = ("            // The configured IP is named _logic: 4 lanes, 25.78125 Gb/s,\n"
              "            // 161.13 MHz reference.  `aurora_64b66b_port7` is a different,\n"
              "            // unconfigured IP that Vivado was stubbing.\n"
              "            aurora_64b66b_port7_logic u_aurora (")


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_aurora_wrapper_ports.py [--check] <aurora_channel_wrapper.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "aurora_64b66b_port7_logic u_aurora" in s:
    fail("already patched")

if s.count(MODULE_OLD) != 1:
    fail("module instantiation anchor matched %d times, expected 1" % s.count(MODULE_OLD))
print("  ok  port7 instantiation found (line %d)"
      % (s[:s.index(MODULE_OLD)].count("\n") + 1))

# The four generate branches (ports 4,5,6,7) each carry identical connection
# text, so every edit must be scoped to the port7 block or the other three are
# corrupted too.  Isolate it by its own instantiation and closing paren.
start = s.index(MODULE_OLD)
end   = s.index("\n            );", start) + len("\n            );")
blk   = s[start:end]

for old, _ in RENAMES:
    if blk.count(old) != 1:
        fail("in the port7 block, %r matched %d times, expected 1"
             % (old.strip(), blk.count(old)))
print("  ok  4 serial-pin connections verified INSIDE the port7 block")
print("      (each appears %d times file-wide -- one per generate branch)"
      % s.count(RENAMES[0][0]))

lines = blk.split("\n")
drop = [i for i, l in enumerate(lines)
        if any(l.strip().startswith(d) for d in DROP_PREFIXES)]
print("  ok  %d QPLL connection(s) to remove" % len(drop))
for i in drop[:4]:
    print("        line %d: %s" % (i + 1, lines[i].strip()[:56]))
if len(drop) != 4:
    fail("expected 4 QPLL connections, found %d" % len(drop))

if check:
    print("""
--check: nothing written.

After applying, confirm the project really contains the _logic IP:

    get_ips *aurora*

If both aurora_64b66b_port7 and aurora_64b66b_port7_logic are listed, remove
the former -- it is unconfigured and only serves to produce a misleading stub:

    remove_files [get_files aurora_64b66b_port7.xci]
""")
    sys.exit(0)

newblk = "\n".join(l for i, l in enumerate(lines) if i not in set(drop))
newblk = newblk.replace(MODULE_OLD, MODULE_NEW, 1)
for old, new in RENAMES:
    newblk = newblk.replace(old, new, 1)
out = s[:start] + newblk + s[end:]

bak = p + ".before_auroraports"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
