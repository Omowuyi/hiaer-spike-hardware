#!/usr/bin/env python3
"""patch_stim_stdp.py IN OUT CORE -- replay copy of a recording: set stdp_enable (CMD 13 bit 82) in every CMD 13 packet
for CORE (the card recorded with stdp_enable = 0).  Lines are 128 hex digits, byte k at [2k:2k+2], byte 63 = opcode."""
import sys
src, dst, core = sys.argv[1], sys.argv[2], int(sys.argv[3])
n = 0; out = []
for l in open(src):
    h = l.strip()
    if len(h) == 128 and int(h[126:128], 16) == 13 and int(h[124:126], 16) == (core & 0x1F) << 3:
        b = bytearray.fromhex(h); b[10] |= 0x04; h = b.hex(); n += 1
    out.append(h)
open(dst, "w").write("\n".join(out) + "\n")
print("stdp_enable set in %d CMD 13 packet(s) for core %d" % (n, core)); sys.exit(0 if n else 1)
