#!/usr/bin/env python3
"""
Correct the NoC relay address decode in external_events_processor_simple.

THE DEFECT
----------
A neuron address is seventeen bits carrying a thirteen-bit row and a four-bit
group, and everywhere else in the design the group is the LOW four bits:

    internal_events_processor.v  ({uram_waddr[i], i[3:0]} < num_outputs)
    internal_events_processor.v  stdp_spike_addr <= {uram_waddr[0], 4'd0}
    external_events_processor    axon_addr_limit = num_inputs[16:4]

The last of these divides the neuron count by sixteen to obtain a row count,
which is only consistent with the group occupying the low bits. The host
readout agrees: neuron C1.9.104 reads back as index 8204, which is row 512
group 12, and 8204 = 512*16 + 12.

The relay decode reads the same address the other way round:

    noc_ng          = noc_fifo_dout[16:13]     group taken from the HIGH bits
    noc_neuron_addr = noc_fifo_dout[12:0]      row taken from the LOW bits

and those two values drive the axon memory directly, as the write address and
the one-hot group mask. Every spike relayed from another core therefore
activates the wrong axon. Address 8204 should reach row 512 group 12; it
reaches row 8204 group 1 instead.

The signal carrying the address is the same one the host reads back:
single_core assigns noc_spike_out_addr = spk2ci_in.din, so the format cannot
differ between the two consumers.

WHY IT SURVIVED
---------------
Nothing exercises this path. The sixteen-core regression is forty-two tests run
on each core independently with host-injected input; the NoC testbenches cover
the routers and the two bus levels but do not instantiate the events processor;
and no bitstream containing the NoC has yet been validated for cross-core
delivery. The defect sits in the gap between two separately verified halves.

  python3 fix_noc_relay_decode.py --check <external_events_processor_simple.v>
  python3 fix_noc_relay_decode.py         <external_events_processor_simple.v>
"""

import sys, os

OLD = """wire [3:0]  noc_ng = noc_fifo_dout[16:13];           // Neuron group (0-15)
wire [12:0] noc_neuron_addr = noc_fifo_dout[12:0];   // Neuron address"""

NEW = """// A spike address is {row[12:0], group[3:0]} with the group in the LOW four
// bits. This matches the internal events processor, which forms an address as
// {uram_waddr[i], i[3:0]}, and it matches axon_addr_limit above, which divides
// the neuron count by sixteen to obtain a row count. It also matches the host
// readout: neuron index 8204 is row 512 group 12, and 8204 = 512*16 + 12.
//
// The decode below previously took the group from bits [16:13] and the row
// from [12:0], which is the same seventeen bits read in the opposite order, so
// every relayed spike reached the wrong axon.
wire [3:0]  noc_ng = noc_fifo_dout[3:0];             // Neuron group (0-15)
wire [12:0] noc_neuron_addr = noc_fifo_dout[16:4];   // Row address"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_noc_relay_decode.py [--check] <eep.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "noc_fifo_dout[16:4]" in s:
    fail("already patched")

n = s.count(OLD)
if n != 1:
    fail("anchor matched %d times, expected 1" % n)
print("  ok  relay decode found (line %d)" % (s[:s.index(OLD)].count("\n") + 1))

# the file's own convention must be the one we are matching
if "num_inputs[16:4]" not in s:
    fail("axon_addr_limit does not use num_inputs[16:4]; check the convention "
         "before applying")
print("  ok  axon_addr_limit uses num_inputs[16:4], group in the low bits")

for sig in ("bramFuture_waddr_mux = noc_neuron_addr",
            "bramFuture_wdata_mux = noc_ng_onehot"):
    if sig not in s:
        fail("expected %r; the decoded fields may drive something else" % sig)
print("  ok  decoded fields drive the axon memory directly")

if check:
    print("""
--check: nothing written.

AFTER APPLYING, run the relay testbench. It drives a spike address whose row
and group differ, so it fails on the current file and passes on the corrected
one. A testbench that passes on both would prove nothing.
""")
    sys.exit(0)

out = s.replace(OLD, NEW, 1)
bak = p + ".before_relaydecode"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
