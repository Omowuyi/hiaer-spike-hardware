#!/usr/bin/env python3
"""
FIX K -- spikes lost at every microphase boundary.

STATE_PUSH_PTR_FIFO advanced the URAM address unconditionally:

    if (exec_hbm_rvalidready) begin
        uram_addr_inc <= 1'b1;                    <-- always
        if (uram_waddr[0] == microphase_ctr*512 + uram_microphase_addr_limit)
            next_state <= STATE_PHASE1_DONE;      <-- exit, NO read issued
        else
            uram_rden <= 1'b1;
    end

On the exit cycle the address advances but no read is issued, so one row is
skipped.  At a microphase boundary that row belongs to the NEXT microphase:

    PUSH c511   waddr=510   read 511      raddr -> 512
    PUSH c512   waddr=511 == limit        exit: inc, no read, raddr -> 513
    mu1 c1      waddr=511                 reads 513

Row 512 is never read, its spike bits are never examined, and all 16 neurons
in it lose every spike they produce.  Same at rows 1024, 1536, ...

MEASURED ON HARDWARE (test_microphase_boundary.py, ch10conv2, 10912 neurons):
7 silent losses, ALL in row 512, ZERO in row 513.  Neurons crossed threshold,
V reset, no spike reported.

Affects any network above 8192 neurons -- 16 muted neurons per boundary.
Large DVS (109,632 neurons, 13 boundaries) has 208 permanently silent neurons.
Predates the exp_psc work entirely, so L6m and earlier bitstreams are affected.

  python3 fix_microphase_skip.py --check <internal_events_processor.v>
  python3 fix_microphase_skip.py         <internal_events_processor.v>

Equivalent to internal_events_processor_v7.v; applying this to a verified v6
(normalized 2cc062c7a7807f202fb2f3e859f630a3 / 67540) yields v7 (normalized
817bf43407247ccaddfa4a0d8ad4641d / 67548).
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_microphase_skip.py [--check] <internal_events_processor.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX K" in s:
    fail("%s already contains FIX K -- already patched?" % p)

old = """        STATE_PUSH_PTR_FIFO: begin
            if (exec_hbm_rvalidready) begin
                uram_addr_inc <= 1'b1;
                if (uram_waddr[0] == microphase_ctr * 512 + uram_microphase_addr_limit) begin
                    next_state <= STATE_PHASE1_DONE;
                end else
                    uram_rden <= 1'b1;
            end"""

new = """        STATE_PUSH_PTR_FIFO: begin
            if (exec_hbm_rvalidready) begin
                // FIX K: uram_addr_inc used to be unconditional, so the exit
                // cycle advanced uram_raddr WITHOUT issuing a read, skipping a
                // row.  At a microphase boundary that row belongs to the next
                // microphase: microphase 0 ended at row 511 with raddr already
                // stepped to 513, so row 512 was never read, its spike bits
                // never examined, and all 16 neurons in it lost every spike.
                // Measured: 7 losses, all row 512, none row 513.
                // Only advance the address when a read is actually issued.
                if (uram_waddr[0] == microphase_ctr * 512 + uram_microphase_addr_limit) begin
                    next_state <= STATE_PHASE1_DONE;
                end else begin
                    uram_addr_inc <= 1'b1;
                    uram_rden <= 1'b1;
                end
            end"""

if s.count(old) != 1:
    fail("STATE_PUSH_PTR_FIFO block not found exactly once in %s (%d).\n"
         "       Is this the right file, and is it v6?" % (p, s.count(old)))

print("edit site verified:")
print("  ok  STATE_PUSH_PTR_FIFO conditional address advance")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_fixk"
if not os.path.exists(bak):
    open(bak, "w").write(s)
open(p, "w").write(s.replace(old, new))
print("patched %s (backup %s)" % (p, bak))
print("""
Verify:  python3 /tmp/norm.py %s
Expect:  817bf43407247ccaddfa4a0d8ad4641d 67548
""" % p)
