#!/usr/bin/env python3
"""
FIX V -- spikes silently dropped when a per-group FIFO fills.

MEASURED
Driving all 10000 neurons of a 10016-neuron network to spike in one timestep,
only 8189 were reported.  Losses by row band: 0-255 clean, then progressively
worse, ending with entire bands lost.  504 of those losses were in microphase
0, so this is not the microphase bug -- it is the readout filling up.

THE CAUSE
hbm_processor.v line 152:

    assign spk0_wren = !spk0_full & exec_hbm_rx_phase1_done
                     & exec_hbm_rvalidready_2x & hbm_rdata[031];

When the FIFO is full the write enable simply drops.  The AXI beat is still
consumed, so the spike is gone -- no backpressure, no counter, no flag.  All
eight groups do this.

The wire to fix it ALREADY EXISTS at line 163, declared with the comment
"Backpressure: stall HBM reads if ANY spike FIFO is full" -- and is never
referenced anywhere in the file.  Someone wrote the signal and never wired it.

THE FIX
Deassert hbm_rready while a spike FIFO is full during the phase-1 spike read.
AXI then holds the beat until the FIFO drains and it is captured on a later
cycle.  This is ordinary AXI backpressure, not new mechanism.

TIMING
hbm_rready lives in the 450 MHz HBM domain, and an 8-input OR feeding it is a
real risk there.  So any_spk_full is REGISTERED before use: the stall arrives
one cycle late, and the existing !spk*_full gate still protects the FIFO, so
the worst case is losing the single beat in that shadow rather than thousands.
Registering is the difference between a fix that closes timing and one that
does not.

WHY IT MATTERS BEFORE THE NoC
Sixteen cores feed the same readout path.  A defect that loses 18% of spikes
at one core will be worse, not better, at sixteen.

  python3 fix_spike_backpressure.py --check <hbm_processor.v>
  python3 fix_spike_backpressure.py         <hbm_processor.v>
"""

import sys, os, re


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_spike_backpressure.py [--check] <hbm_processor.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX V" in s:
    fail("%s already patched." % p)
if "any_spk_full" not in s:
    fail("%s has no any_spk_full wire -- wrong file?" % p)

edits = []

# 1. hbm_rready becomes a gated output; the FSM drives an internal register.
o = "    output reg                  hbm_rready,"
if s.count(o) != 1:
    fail("hbm_rready port declaration not found exactly once in %s (%d)"
         % (p, s.count(o)))
edits.append((o, "    output wire                 hbm_rready,", "rready port -> wire"))

# 2. Registered fullness + the gate itself, placed right after any_spk_full.
o = """wire any_spk_full = spk0_full | spk1_full | spk2_full | spk3_full |
                    spk4_full | spk5_full | spk6_full | spk7_full;"""
if s.count(o) != 1:
    fail("any_spk_full declaration not found exactly once in %s" % p)
edits.append((o, o + """

//=========================================================================
// FIX V: the wire above was declared for backpressure and never used, so a
// full spike FIFO silently dropped the spike instead of stalling the read.
// Measured: 8189 of 10000 spikes reported in a single timestep.
//
// Registered before use.  hbm_rready is in the 450 MHz HBM domain and an
// 8-input OR feeding it directly is a timing risk there.  One cycle of
// latency means the beat already in flight can still be dropped by the
// existing !spk*_full gate, but the stream stalls immediately after, so the
// loss goes from thousands of spikes to at most one per fill event.
//=========================================================================
reg any_spk_full_r;
always @(posedge clk) begin
    if (~resetn) any_spk_full_r <= 1'b0;
    else         any_spk_full_r <= any_spk_full;
end

// hbm_rready is driven combinationally by the RX FSM below; that driver now
// targets hbm_rready_r and the gated result leaves the module.
reg  hbm_rready_r;
assign hbm_rready = hbm_rready_r & ~(any_spk_full_r & exec_hbm_rx_phase1_done);""",
               "backpressure gate"))

# 3. Every FSM assignment drives the internal register instead.
n = len(re.findall(r"\bhbm_rready\s*<=", s))
if n < 4:
    fail("expected at least 4 'hbm_rready <=' assignments in %s, found %d" % (p, n))
edits.append(("__RENAME__", "__RENAME__", "FSM assignments -> hbm_rready_r (%d)" % n))

print("edit sites verified:")
for _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

for old, new, label in edits:
    if old == "__RENAME__":
        s = re.sub(r"\bhbm_rready(\s*<=)", r"hbm_rready_r\1", s)
        continue
    if s.count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    s = s.replace(old, new)

bak = p + ".before_fixv"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s (backup %s)" % (p, bak))
print("""
Verify on hardware with the same test that measured the loss: drive every
neuron to spike in one timestep and count how many are reported.  Before the
fix: 8189 of 10000.
""")
