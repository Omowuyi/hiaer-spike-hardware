#!/usr/bin/env python3
"""
Let the axon delay table cover every axon a core can hold.

THE LIMIT
---------
Each core holds an axon memory of 8,192 rows of sixteen groups, so 131,072
axons may reach it. The table that gives each incoming axon its conduction
delay holds 8,192 entries and is addressed by thirteen bits:

    axon_delay_buffer.v:31   parameter NUM_AXONS = 8192
                       :59   input wire [12:0] delay_table_waddr
    command_interpreter:197  output reg [12:0] delay_table_waddr
                       :544  delay_table_waddr <= rxFIFO_dout[18:6]

Thirteen bits reach 8,192 axons, and 8,191 is the axonal fan-in the regression
suite measures at its boundary. The table is therefore a sixteenth the size of
the memory it indexes, and it is the table rather than the memory that sets the
limit.

WHY IT WAS THIRTEEN BITS
------------------------
Not for want of room. The command that programs the table travels in the
512-bit host packet and occupies nineteen of those bits, thirteen of address
and six of delay. A seventeen-bit address takes bits [22:6], twenty-three of
512. The packet was never the constraint.

WHAT THIS CHANGES
-----------------
The table grows to 131,072 entries and the address to seventeen bits, matching
the axon memory exactly. Axonal fan-in rises from 8,191 to 131,072.

The table is declared with its depth as a parameter, so the storage follows the
parameter and no structure changes.

WHAT IT COSTS
-------------
131,072 entries of six bits is 786,432 bits a core, 12.6 Mb across sixteen,
about 342 RAMB36. The design uses 508 of 2,016 block RAMs, so this takes block
memory from a quarter of the device to about two fifths.

The risk is not the resource but the timing. The design closed with five
picoseconds of slack, and three hundred more block memories will place and route
differently. Elaborate, then build, and read the slack before trusting it.

  python3 fix_delay_table_width.py --check <imports directory>
  python3 fix_delay_table_width.py         <imports directory>
"""

import sys, os

EDITS = {
 "axon_delay_buffer.v": [
   ("depth parameter",
    "    parameter NUM_AXONS        = 8192",
    "    parameter NUM_AXONS        = 131072"),
   ("write address",
    "    input  wire [12:0] delay_table_waddr,",
    "    input  wire [16:0] delay_table_waddr,"),
   ("comment",
    "    // Delay lookup table: 8192 × 6-bit",
    "    // Delay lookup table: 131072 x 6-bit, one entry per axon the core"
    " can hold"),
 ],
 "command_interpreter.v": [
   ("write address port",
    "   output reg [12:0] delay_table_waddr,",
    "   output reg [16:0] delay_table_waddr,"),
   ("command payload",
    "        delay_table_waddr <= rxFIFO_dout[18:6];",
    "        delay_table_waddr <= rxFIFO_dout[22:6];"),
 ],
}

RESET = ("        delay_table_waddr <= 13'd0;",
         "        delay_table_waddr <= 17'd0;")


def fail(m):
    sys.stderr.write("\nABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_delay_table_width.py [--check] <imports directory>")
D = args[0]
if not os.path.isdir(D):
    fail("not a directory: %s" % D)

files = {}
for f in EDITS:
    p = os.path.join(D, f)
    if not os.path.isfile(p):
        fail("missing file: %s" % p)
    raw = open(p, errors="replace").read()
    files[f] = (p, raw, "\r\n" in raw, raw.replace("\r\n", "\n"))

# the reset assignment lives in command_interpreter and is optional in form
if RESET[0] in files["command_interpreter.v"][3]:
    EDITS["command_interpreter.v"].append(("reset value",) + RESET)

total = sum(len(v) for v in EDITS.values())
print("Verifying %d edits across %d files.\n" % (total, len(EDITS)))
ok = done = bad = 0
for f in sorted(EDITS):
    s = files[f][3]
    for tag, old, new in EDITS[f]:
        n = s.count(old)
        if n == 1:
            ok += 1
            print("  ok    %-24s %s" % (f, tag))
        elif n == 0 and new in s:
            done += 1
            print("  done  %-24s %s (already applied)" % (f, tag))
        else:
            bad += 1
            print("  MISS  %-24s %s (matched %d)" % (f, tag, n))

print("\n%d verified, %d already applied, %d not found." % (ok, done, bad))
if bad:
    fail("%d anchors did not match exactly once." % bad)

if check:
    print("""
--check: nothing written.

After applying, the delay table holds 131,072 entries of six bits in each core,
about 342 RAMB36 across the device, taking block memory from a quarter to about
two fifths. Elaborate, then build, and read the slack: the design closed with
five picoseconds and three hundred more block memories will place differently.

The host must also widen the address field of the command that programs the
table, from bits [18:6] to [22:6] of the 512-bit packet.
""")
    sys.exit(0)

for f in files:
    p, raw, crlf, s = files[f]
    for tag, old, new in EDITS[f]:
        s = s.replace(old, new, 1)
    bak = p + ".before_delaytable"
    if not os.path.exists(bak):
        open(bak, "w").write(raw)
    open(p, "w").write(s.replace("\n", "\r\n") if crlf else s)
    print("  patched %s" % f)

print("\nAxonal fan-in is now bounded by the axon memory rather than by the table.")
print("The host command field moves from [18:6] to [22:6].")
