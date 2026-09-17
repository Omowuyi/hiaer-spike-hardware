#!/usr/bin/env python3
"""
FIX J -- delay buffers deliver N+2 timesteps late instead of N.

MEASURED IN SIMULATION (tbloop.v, real delay_buffer, delay swept 0..6):

    requested delay :  0  1  2  3  4  5
    delivered at    :  1  3  4  5  6  7      <- N+2 for N>=1

Both delay_buffer.v and axon_delay_buffer.v advance current_slot in
DRAIN_DONE.  DRAIN_DONE runs off timestep_tick (= exec_run), which fires at
the top of the timestep -- ahead of the Phase-2 push.  So:

  * a push during timestep T sees current_slot already advanced  (+1)
  * a slot is drained one timestep after current_slot reaches it (+1)

Moving the advance into DRAIN_IDLE, so the slot steps forward and is drained
in the same tick, makes delay N arrive at exactly N:

    requested delay :  0  1  2  3  4  5
    delivered at    :  1  2  3  4  5  6      <- correct

  python3 fix_delay_offset.py --check <delay_buffer.v> <axon_delay_buffer.v>
  python3 fix_delay_offset.py         <delay_buffer.v> <axon_delay_buffer.v>

Apply delay_buffer_v2.patch.py (the group-index widening) first.
"""

import sys, os, re


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 2:
    fail("usage: fix_delay_offset.py [--check] <delay_buffer.v> <axon_delay_buffer.v>")
db_p, adb_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

edits = []

NOTE = ("                        // FIX J: advance the slot HERE, before Phase 2\n"
        "                        // pushes.  Advancing at DRAIN_DONE meant a push\n"
        "                        // saw an already-advanced slot AND a slot was\n"
        "                        // drained a timestep after current_slot reached\n"
        "                        // it, so requested delay N arrived at N+2.\n")

# ---------------- delay_buffer.v ----------------
db = open(db_p).read()
if "FIX J" in db:
    fail("%s already patched." % db_p)

o = ("                        drain_rd_count <= slot_wr_ptr[current_slot];\n"
     "                        drain_rd_idx   <= 10'd0;\n"
     "                        if (slot_wr_ptr[current_slot] == 10'd0)")
if db.count(o) != 1:
    fail("delay_buffer DRAIN_IDLE snapshot not found exactly once in %s (%d)"
         % (db_p, db.count(o)))
edits.append((db_p, o,
  NOTE +
  "                        current_slot   <= current_slot + 6'd1;\n"
  "                        drain_rd_count <= slot_wr_ptr[current_slot + 6'd1];\n"
  "                        drain_rd_idx   <= 10'd0;\n"
  "                        if (slot_wr_ptr[current_slot + 6'd1] == 10'd0)",
  "delay_buffer advance"))

o = "                            bram_addrb <= {current_slot, 10'd0};"
if db.count(o) != 1:
    fail("delay_buffer first-read address not found exactly once in %s" % db_p)
edits.append((db_p, o,
  "                            bram_addrb <= {current_slot + 6'd1, 10'd0};",
  "delay_buffer first read"))

# Match the whole advance line whatever trailing comment it carries, and
# do not assume what follows it -- the real file has comments in between.
m = re.findall(r"\n([ \t]*)current_slot <= current_slot \+ 6'd1;[^\n]*\n", db)
if len(m) != 1:
    fail("delay_buffer: found %d 'current_slot <= current_slot + 1' lines, "
         "expected 1 (in DRAIN_DONE)" % len(m))
o = re.search(r"\n[ \t]*current_slot <= current_slot \+ 6'd1;[^\n]*\n", db).group(0)
edits.append((db_p, o,
  "\n%s// FIX J: advance moved to DRAIN_IDLE.\n" % m[0],
  "delay_buffer remove old advance"))

# ---------------- axon_delay_buffer.v ----------------
adb = open(adb_p).read()
if "FIX J" in adb:
    fail("%s already patched." % adb_p)

o = ("                        drain_count <= slot_wr_ptr[current_slot];\n"
     "                        drain_idx <= 10'd0;\n"
     "                        if (slot_wr_ptr[current_slot] == 10'd0) begin")
if adb.count(o) != 1:
    fail("axon_delay_buffer DRAIN_IDLE snapshot not found exactly once in %s (%d)"
         % (adb_p, adb.count(o)))
edits.append((adb_p, o,
  NOTE +
  "                        current_slot <= current_slot + 6'd1;\n"
  "                        drain_count <= slot_wr_ptr[current_slot + 6'd1];\n"
  "                        drain_idx <= 10'd0;\n"
  "                        if (slot_wr_ptr[current_slot + 6'd1] == 10'd0) begin",
  "axon_delay_buffer advance"))

o = "                            bram_rd_addr <= {current_slot, 10'd0};"
if adb.count(o) != 1:
    fail("axon_delay_buffer first-read address not found exactly once in %s" % adb_p)
edits.append((adb_p, o,
  "                            bram_rd_addr <= {current_slot + 6'd1, 10'd0};",
  "axon_delay_buffer first read"))

m = re.findall(r"\n([ \t]*)current_slot <= current_slot \+ 6'd1;[^\n]*\n", adb)
if len(m) != 1:
    fail("axon_delay_buffer: found %d 'current_slot <= current_slot + 1' lines, "
         "expected 1 (in DRAIN_DONE)" % len(m))
o = re.search(r"\n[ \t]*current_slot <= current_slot \+ 6'd1;[^\n]*\n", adb).group(0)
edits.append((adb_p, o,
  "\n%s// FIX J: advance moved to DRAIN_IDLE.\n" % m[0],
  "axon_delay_buffer remove old advance"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {db_p: db, adb_p: adb}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_delayoffset"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Verified in simulation for delay_buffer: delay N now delivers at timestep N
(0 immediate, 1 -> 2, 2 -> 3, ... 5 -> 6).  axon_delay_buffer has the same
structure and the same fix; it has NOT been simulated.
""")
