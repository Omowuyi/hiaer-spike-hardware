#!/usr/bin/env python3
"""tapcheck.py SIM_FILE TAPPED_FILE -- the tapped file must be the simulated file plus fix_ila.py's tap block only:
nothing removed or changed; every added line is the tap header, a mark_debug wire, or blank."""
import sys, difflib
a = open(sys.argv[1]).read().splitlines(); b = open(sys.argv[2]).read().splitlines()
d = list(difflib.unified_diff(a, b, lineterm="", n=0))
rem = [l for l in d if l.startswith("-") and not l.startswith("---")]
add = [l[1:] for l in d if l.startswith("+") and not l.startswith("+++")]
taps = [l for l in add if l.startswith('(* mark_debug = "true" *) wire')]
ok = not rem and taps and all(l.strip() == "" or l in taps or l.startswith("// ---- debug taps for the core-1 capture build") for l in add)
print("%-36s %s: %d tap wires added, %d lines removed" % (sys.argv[2].split("/")[-1], "OK" if ok else "NOT ONLY TAPS", len(taps), len(rem)))
sys.exit(0 if ok else 1)
