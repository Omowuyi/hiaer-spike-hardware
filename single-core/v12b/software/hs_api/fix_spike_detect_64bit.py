#!/usr/bin/env python3
"""
FIX X -- in 64-bit mode the spike ADDRESS is read from the wrong bits.

MEASURED, NOT ASSUMED
The entry ordering was determined by running the compiler's own packing code
offline (four distinct entries, encoded, flipped, and decoded through the
measured readback layout).  Result:

    64-bit entry 0 -> row bits [255:192]  flag 255  address [208:192]
    64-bit entry 1 -> row bits [191:128]  flag 191  address [144:128]
    64-bit entry 2 -> row bits [127: 64]  flag 127  address [ 80: 64]
    64-bit entry 3 -> row bits [ 63:  0]  flag  63  address [ 16:  0]

hbm_processor tests one flag per 32-bit entry:

    spk0->31  spk1->63  spk2->95  spk3->127
    spk4->159 spk5->191 spk6->223 spk7->255

So in 64-bit mode the four flags land on spk7, spk5, spk3 and spk1.  The FLAG
is therefore detected -- but each channel reads its address from the 32-bit
offset, which is not where the 64-bit address sits:

    spk7_din reads [240:224], entry 0's address is at [208:192]
    spk5_din reads [176:160], entry 1's address is at [144:128]
    spk3_din reads [112:096], entry 2's address is at [ 80: 64]
    spk1_din reads [048:032], entry 3's address is at [ 16:  0]

The neuron that spikes is reported under the wrong address.

An earlier draft of this patch remapped spk0-3 and disabled spk4-7 -- exactly
backwards, and it would have disabled the channels that carry the flags.  That
draft was written from an assumed ordering; this one is written from a
measured one.

THE FIX
Leave the flag bits alone -- they already line up.  Select only the address
offsets by syn_64bit_en, on the four channels that carry 64-bit flags.

  python3 fix_spike_detect_64bit.py --check <hbm_processor.v> <single_core.sv>
  python3 fix_spike_detect_64bit.py         <hbm_processor.v> <single_core.sv>

Apply AFTER fix_spike_backpressure.py and add_microphase_diag.py, and pair
with fix_syn64_spike_entries.py on the compiler side.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 2:
    fail("usage: fix_spike_detect_64bit.py [--check] <hbm_processor.v> <single_core.sv>")
hp_p, sc_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

hp = open(hp_p).read()
sc = open(sc_p).read()
for p, s in ((hp_p, hp), (sc_p, sc)):
    if "FIX X" in s:
        fail("%s already patched." % p)

edits = []

o = "    output          spk_dropped,\n"
if hp.count(o) != 1:
    fail("spk_dropped output not found exactly once in %s -- run "
         "detect_spike_drop.py first." % hp_p)
edits.append((hp_p, o,
  "    // FIX X: selects the spike-entry address offset.  Flag bits already\n"
  "    // line up in both formats; only the addresses move.\n"
  "    input           syn_64bit_en,\n" + o, "HBM port"))

# channel -> (32-bit address slice, 64-bit address slice, which 64-bit entry)
CHAN = {
    1: ((48, 32),   (16, 0),     3),
    3: ((112, 96),  (80, 64),    2),
    5: ((176, 160), (144, 128),  1),
    7: ((240, 224), (208, 192),  0),
}
for ch, ((h32, l32), (h64, l64), ent) in sorted(CHAN.items()):
    o = "assign spk%d_din  = hbm_rdata[%03d:%03d];" % (ch, h32, l32)
    if hp.count(o) != 1:
        fail("spk%d_din assign not found exactly once in %s (looked for "
             "[%03d:%03d])" % (ch, hp_p, h32, l32))
    edits.append((hp_p, o,
      "// FIX X: in 64-bit mode this channel's flag comes from entry %d, whose\n"
      "// address sits at [%03d:%03d], not the 32-bit offset.\n"
      "assign spk%d_din  = syn_64bit_en ? hbm_rdata[%03d:%03d] : hbm_rdata[%03d:%03d];"
      % (ent, h64, l64, ch, h64, l64, h32, l32), "spk%d_din (entry %d)" % (ch, ent)))

o = "        .spk_dropped(w_spk_dropped),\n        .hbm_curr_state(hbm_curr_state)"
if sc.count(o) != 1:
    fail("hbm_processor spk_dropped/hbm_curr_state hookup not found exactly once "
         "in %s" % sc_p)
edits.append((sc_p, o, "        .syn_64bit_en(w_syn_64bit_en),\n" + o, "SC hookup"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {hp_p: hp, sc_p: sc}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_fixx"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Flag bits are untouched -- only the four address offsets change, and only when
syn_64bit_en is set.  32-bit behaviour is bit-identical.
""")
