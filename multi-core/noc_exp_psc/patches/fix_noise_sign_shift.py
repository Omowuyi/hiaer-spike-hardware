#!/usr/bin/env python3
"""
Stop the sign bit leaking into the noise magnitude on right shifts.

THE DEFECT
----------
The noise sample is held in sign-magnitude form:

    prbs_regularized[i] = 2*prbs_ng[i]+1;   // 17 bits
        bit 16   sign, read at line 1482 to build the two's complement value
        [15:0]   magnitude, always odd so it is never zero

The left-shift arm uses the magnitude alone, which is right:

    prbs_shift[i] = prbs_regularized[i][15:0] << shift_abs;

The right-shift arm uses all seventeen bits:

    prbs_shift[i] = {18'd0, prbs_regularized[i]} >> shift_abs;

so whenever the sign bit is set the shift operates on 65536 + magnitude rather
than on the magnitude. Positive samples are unaffected, because their bit 16 is
zero, and negative samples are inflated by 2^(16-n).

WHAT THAT DOES TO THE NOISE
---------------------------
Measured over two hundred thousand samples:

    shift -1   before  pos max 32767 mean 16348 | neg max 65535 mean 49207
               after   pos max 32767 mean 16348 | neg max 32767 mean 16439
    shift -8   before  pos max   255 mean   127 | neg max   511 mean   383
               after   pos max   255 mean   127 | neg max   255 mean   127

The distribution is asymmetric, with a standing negative offset of about half
the peak amplitude at every negative shift: -16353 at shift -1, -128 at shift
-8. That is a systematic inhibitory bias on every neuron, not noise of the
wrong size.

It presents as "one shift too few" because the negative peak at shift -1,
65535, is what shift 0 should produce, so measuring amplitude alone gives that
impression.

A CONSEQUENCE TO BE AWARE OF
----------------------------
The comment on the faulty line records why the sign bit was included: to keep
shift -16 non-zero. With the magnitude alone, magnitude >> 16 is always zero,
so shift -16 now produces no noise and matches the disabled setting at -17.

That trade is worth making. Avoiding zero at one setting cost a direct-current
bias at all fifteen. If shift -16 must stay non-zero, floor the magnitude at
one instead, by appending "| 35'd1" to the corrected expression; the sign is
applied afterwards and stays correct.

  python3 fix_noise_sign_shift.py --check <internal_events_processor.v>
  python3 fix_noise_sign_shift.py         <internal_events_processor.v>
"""

import sys, os

OLD = """            // Negative shift (but > -17): Right shift (smaller noise)
            // Use full 17-bit prbs_regularized so shift=-16 still yields nonzero
            prbs_shift[i] = {18'd0, prbs_regularized[i]} >> shift_abs;"""

NEW = """            // Negative shift (but > -17): Right shift (smaller noise).
            // Shift the MAGNITUDE only. Bit 16 is the sign, read below to form
            // the two's complement value, and including it here made every
            // negative sample 65536/2^n too large while leaving positive ones
            // exact. The result was asymmetric noise carrying a standing
            // negative offset of about half the peak amplitude at every shift.
            // Consequence: magnitude >> 16 is zero, so shift=-16 now yields no
            // noise, matching the disabled setting at -17. To keep it non-zero
            // instead, append " | 35'd1" to floor the magnitude at one.
            prbs_shift[i] = {19'd0, prbs_regularized[i][15:0]} >> shift_abs;"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_noise_sign_shift.py [--check] <internal_events_processor.v>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "{19'd0, prbs_regularized[i][15:0]} >> shift_abs" in s:
    fail("already patched")

n = s.count(OLD)
if n != 1:
    fail("anchor matched %d times, expected 1" % n)
print("  ok  right-shift arm found (line %d)" % (s[:s.index(OLD)].count("\n") + 1))

# the assumptions this fix rests on, each checked against the file
for tag, needle in (
        ("prbs_regularized is 17 bits", "reg [16:0] prbs_regularized"),
        ("prbs_shift is 35 bits", "reg [34:0] prbs_shift"),
        ("bit 16 is used as the sign", "if (prbs_regularized[i][16])"),
        ("the left-shift arm uses [15:0]",
         "prbs_shift[i] = prbs_regularized[i][15:0] << shift_abs;")):
    if needle not in s:
        fail("expected %s; the fix assumes it, so stopping" % tag)
    print("  ok  %s" % tag)

if check:
    print("""
--check: nothing written.

The replacement keeps the width at 35 bits: 19 + 16 matches the 18 + 17 it
replaces, so prbs_shift is driven exactly as before and no truncation or
extension changes.

AFTER APPLYING, the sign path at line 1482 is untouched, so a negative sample
is still negated into two's complement; only its magnitude changes.
""")
    sys.exit(0)

out = s.replace(OLD, NEW, 1)
bak = p + ".before_noisesign"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Right shifts now use the magnitude alone; positive samples are unchanged.")
