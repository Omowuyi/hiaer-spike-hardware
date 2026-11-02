#!/usr/bin/env python3
"""fix_round20.py SRC_DIR -- fix 21: 64-bit synaptic delivery in delta mode.
A 64-bit Phase-2 FIFO word carries 8 entries for groups 0-7 or 8-15 (phase2_halfsel), the words alternating, and every
64-bit destination row is exactly two words.  The toggle was gated by !delta_mode (the 'new paths gated by !delta_mode'
convention of the exp-PSC work), so in delta mode it never toggled: every word was decoded as groups 0-7 and the input
for groups 8-15 landed 8 lower (round 19: neuron 8+k spiked as k).  64-bit exp-PSC already toggled; 32-bit mode does
not use phase2_halfsel.  Only 64-bit delta mode changes."""
import sys, os
F = os.path.join(sys.argv[1], "internal_events_processor.v"); s = open(F).read()
if "fix 21" in s: print("fix 21 already applied"); sys.exit(0)
a = "        if (!delta_mode && syn_64bit_en) phase2_halfsel <= ~phase2_halfsel;\n"
if s.count(a) != 1: sys.exit("ANCHOR internal_events_processor.v: %d matches" % s.count(a))
s = s.replace(a, "        if (syn_64bit_en) phase2_halfsel <= ~phase2_halfsel;   // fix 21: both modes (delta mode never toggled)\n")
if not os.path.exists(F + ".before_round20"): open(F + ".before_round20", "w").write(open(F).read())
open(F, "w").write(s); print("fix 21 applied: phase2_halfsel toggles in 64-bit mode in both delta and exp-PSC modes")
