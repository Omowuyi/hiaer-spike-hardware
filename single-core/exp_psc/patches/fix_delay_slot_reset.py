#!/usr/bin/env python3
"""
FIX U -- delayed entries are re-delivered forever.

delay_buffer.v line ~176:

    end else if (write_en) begin
        slot_wr_ptr[target_slot] <= slot_wr_ptr[target_slot] + 10'd1;
    end else if (drain_state == DRAIN_DONE) begin
        slot_wr_ptr[current_slot] <= 10'd0;
    end

The `else if` makes the two mutually exclusive.  They are not: a push targets
`current_slot + delay` while the drain clears `current_slot`, so except when
delay wraps to exactly 0 they are different slots and both must happen.

When they coincide the drained slot's write pointer is NEVER cleared.  Its
entries stay live, and 64 timesteps later the slot comes round again and
delivers them a second time -- then a third, indefinitely.  Every push that
lands on a DRAIN_DONE cycle leaves permanent residue in the buffer.

This matches the hardware signature: a drive appearing EVERY timestep instead
of once, and delay=2 / delay=3 / all axon-delay cases producing byte-identical
traces because they are all draining residue left by earlier runs rather than
their own entries.

The fix splits the two into independent branches.  The one genuine conflict --
a push to the same slot being drained, which only happens if delay wraps to 0
and cannot occur since delay==0 takes the immediate path -- resolves in favour
of the increment, preserving the entry.

  python3 fix_delay_slot_reset.py --check <delay_buffer.v>
  python3 fix_delay_slot_reset.py         <delay_buffer.v>
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_delay_slot_reset.py [--check] <delay_buffer.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
s = open(p).read()

if "FIX U" in s:
    fail("%s already patched." % p)

old = """        end else if (write_en) begin
            slot_wr_ptr[target_slot] <= slot_wr_ptr[target_slot] + 10'd1;
        end else if (drain_state == DRAIN_DONE) begin
            // After draining current_slot, reset its write pointer for reuse
            slot_wr_ptr[current_slot] <= 10'd0;
        end"""

new = """        end else begin
            //=================================================================
            // FIX U: these were chained with `else if`, which made them
            // mutually exclusive.  A push targets current_slot + delay while
            // the drain clears current_slot -- different slots, so both must
            // be able to happen in the same cycle.  When they collided the
            // drained slot's pointer was never cleared, so its entries stayed
            // live and were re-delivered every 64 timesteps, forever.
            //
            // Order matters: the increment is applied last so that if both
            // ever did target the same slot, the entry is preserved rather
            // than silently dropped.
            //=================================================================
            if (drain_state == DRAIN_DONE)
                slot_wr_ptr[current_slot] <= 10'd0;
            if (write_en)
                slot_wr_ptr[target_slot] <= slot_wr_ptr[target_slot] + 10'd1;
        end"""

if s.count(old) != 1:
    fail("slot_wr_ptr update block not found exactly once in %s (%d).\n"
         "       Send me lines 170-185 and I'll rebase." % (p, s.count(old)))

print("edit site verified:")
print("  ok  slot_wr_ptr update: write and drain-reset made independent")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bak = p + ".before_fixu"
if not os.path.exists(bak):
    open(bak, "w").write(s)
open(p, "w").write(s.replace(old, new))
print("patched %s (backup %s)" % (p, bak))
print("""
Apply after delay_buffer_v2.patch.py and fix_delay_offset.py.
This is an RTL change -- it needs a rebuild.
""")
