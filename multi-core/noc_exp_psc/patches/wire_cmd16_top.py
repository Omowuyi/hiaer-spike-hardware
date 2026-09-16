#!/usr/bin/env python3
"""
Final CMD 16 edit: carry core 0's config signals to the classifier.

Run add_cmd16_remote_cfg.py and thread_cmd16.py first.

The cores are instantiated in a generate loop over j, so the signals come out
as arrays and the classifier takes index 0.  There is ONE classifier for the
device -- it sits after switch_32_1, not inside a core -- so only one core's
copy is used, and a CMD 16 must be steered to core 0 the same way a CMD 15 is
steered to the core whose routing table it targets.

The arrays are sized 0:15 because only j<16 instantiates a core_wrapper; the
upper sixteen indices of the j<32 loop are not populated in this design.

  python3 wire_cmd16_top.py --check <sixteen_core_noc_firefly_top.sv>
  python3 wire_cmd16_top.py         <sixteen_core_noc_firefly_top.sv>
"""

import sys, os

A_DECL = "    logic [3:0]  ff_channel_up;"
N_DECL = """    // CMD 16 config, out of each core's command interpreter.  Only index 0
    // reaches the classifier -- see the header of this script.
    wire        core_remote_cfg_valid [0:15];
    wire [7:0]  core_remote_cfg_addr  [0:15];
    wire [5:0]  core_remote_cfg_data  [0:15];

    logic [3:0]  ff_channel_up;"""

A_INST = """                 core_wrapper my_core(
                    .aclk(aclk),"""
N_INST = """                 core_wrapper my_core(
                    .remote_cfg_valid(core_remote_cfg_valid[j]),
                    .remote_cfg_addr(core_remote_cfg_addr[j]),
                    .remote_cfg_data(core_remote_cfg_data[j]),
                    .aclk(aclk),"""

A_CLS = """        .m_firefly_spike (ff_tx_spike),
        .m_firefly_valid (ff_tx_valid),
        .m_firefly_ready (ff_tx_ready)
    );"""
N_CLS = """        .m_firefly_spike (ff_tx_spike),
        .m_firefly_valid (ff_tx_valid),
        .m_firefly_ready (ff_tx_ready),
        // Core 0's CMD 16 writes.  Until the table is loaded every block
        // resolves to this device and nothing leaves over the optical link.
        .remote_cfg_valid (core_remote_cfg_valid[0]),
        .remote_cfg_addr  (core_remote_cfg_addr[0]),
        .remote_cfg_data  (core_remote_cfg_data[0])
    );"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: wire_cmd16_top.py [--check] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "core_remote_cfg_valid" in s:
    fail("already patched")
if "spike_classifier" not in s:
    fail("the Firefly patch is not applied to this file")

for tag, a in (("decl", A_DECL), ("core inst", A_INST), ("classifier", A_CLS)):
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-11s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

# the loop variable must really be j, or the array index is wrong
blk = s[s.index(A_INST) - 400:s.index(A_INST)]
if "for(j=0;" not in blk.replace(" ", ""):
    print("  !!  the enclosing loop may not use j -- check before applying")
else:
    print("  ok  enclosing generate loop uses j")

if check:
    print("""
--check: nothing written.

HOST SIDE, once built:

    cmd[63] = 16
    val     = (block << 6) | (server << 3) | fpga
    cmd[0]  = val & 0xFF
    cmd[1]  = (val >> 8) & 0xFF

steered to core 0 via HIAER_CORE_ID.  256 packets programme one device.

Block index is spike_addr[16:9], the same 512-neuron granularity the NoC
routing table uses -- so one partitioning decision fills both tables and they
cannot disagree.
""")
    sys.exit(0)

out = s.replace(A_DECL, N_DECL, 1).replace(A_INST, N_INST, 1).replace(A_CLS, N_CLS, 1)
bak = p + ".before_cmd16top"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
