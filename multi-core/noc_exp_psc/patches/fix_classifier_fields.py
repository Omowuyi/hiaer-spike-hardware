#!/usr/bin/env python3
"""
Fill in the two fields spike_classifier still hardcodes.

Run fix_classifier_dest.py FIRST -- this depends on get_dest_server() and the
remote_dst table existing.

    m_firefly_spike.src_core = 4'd0;   // "Could be extracted from
                                       //  packet metadata"

dst_server was already fixed by fix_classifier_dest.py, which replaced the
hardcoded 3'd0 with get_dest_server(spike_addr[spike_idx]).  This patch does
not touch it.

src_core
--------
The comment says the core "could be extracted from packet metadata".  It can:
command_interpreter.v line 517 builds each 32-bit spike word as

    [31:24] execRun_ctr[7:0]     timestamp
    [23]    1'b1                 valid
    [22:21] 2'b00                reserved for FPGA_ID
    [20:17] CORE_ID[3:0]         source core
    [16:0]  neuron address

and the classifier already slices [16:0] out of the same word to get the
address.  The core sits immediately above it.

Leaving src_core at zero means a receiving device cannot tell which core sent a
spike.  Nothing on the current return path needs it, but the field exists so
that a reply, a trace, or any per-core accounting can identify the origin --
and a field that is silently always zero is worse than one that is absent,
because it reads as information.

NOT CHANGED
-----------
timestamp.  Line 272 assigns exec_run, which is an 8-bit register loaded from
s_axis_tdata[7:0] -- the execRun_ctr the emitting core stamped on the readout
packet.  That is correct and must not be replaced by a local counter: it
records the timestep the spikes were EMITTED in, which a counter sampled at
classification time would have moved past.

payload.  Line 274 sets 16'd1 with the comment "Default weight".  A spike's
weight comes from the synapse at the destination, not from the packet, so this
field is probably unused -- but it is left alone because "probably unused" is
not a basis for changing a value on a path that has never carried traffic.

  python3 fix_classifier_fields.py --check <spike_classifier.sv>
  python3 fix_classifier_fields.py         <spike_classifier.sv>
"""

import sys, os

A_CORE = """            m_firefly_spike.src_core    = 4'd0;  // Could be extracted from packet metadata"""
N_CORE = """            // command_interpreter.v line 517 puts the emitting core at bits
            // [20:17] of every 32-bit spike word, immediately above the
            // neuron address this module already slices out.
            m_firefly_spike.src_core    = packet_reg[32*(spike_idx+1) + 17 +: 4];"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_classifier_fields.py [--check] <spike_classifier.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "get_dest_server" not in s:
    fail("get_dest_server() is absent -- run fix_classifier_dest.py first")
print("  ok  get_dest_server() present")

if "packet_reg[32*(spike_idx+1) + 17 +: 4]" in s:
    fail("already patched")

for tag, a in (("src_core", A_CORE),):
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-10s verified (line %d)"
          % (tag, s[:s.index(a)].count("\n") + 1))

# the slice this patch introduces must match the one already used for the address
if "packet_reg[32*(spike_idx+1) +: 17]" not in s and \
   "packet_reg[32*(i+1) +: 17]" not in s:
    print("  !!  the existing address slice does not use the expected form;")
    print("      check that packet_reg[32*(n+1) +: 17] is how a spike word is read")

if check:
    print("\n--check: nothing written.")
    print("""
After applying, the classifier still needs its configuration driven: the top
must supply remote_cfg_valid / remote_cfg_addr / remote_cfg_data, which needs a
CMD 16 handler alongside the CMD 15 routing-table handler.  Until the table is
loaded every entry reads {3'd0, LOCAL_FPGA_ID}, so every spike classifies as
local and nothing reaches the optical link -- which is the correct and safe
default for a device whose table has not been programmed.
""")
    sys.exit(0)

out = s.replace(A_CORE, N_CORE, 1)
bak = p + ".before_fields"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
