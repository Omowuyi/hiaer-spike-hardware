#!/usr/bin/env python3
"""patch_stim_slots.py IN OUT CORE -- replay copy of a recording as the fixed compiler would have written it: in every
64-bit synapse row (opcode-2 packets for CORE at rows >= 2^15) each placeholder entry -- op 0, dest 0, weight 0, no
source and no rule, whatever its delay -- becomes all zero.  Entry {op[63:61], dest[60:48], weight[47:32], delay[31:26],
type[25:22], tag[21:18], src[17:0]}, 4 per packet, entry e at bytes [24-8e : 32-8e] little-endian."""
import sys
src, dst, core = sys.argv[1], sys.argv[2], int(sys.argv[3]); n = rows = 0; out = []
for l in open(src):
    h = l.strip()
    if len(h) == 128:
        b = bytearray.fromhex(h)
        if b[63] == 2 and b[62] == (core & 0x1F) << 3 and (((b[34] & 0x7F) << 16) | (b[33] << 8) | b[32]) >= 2 ** 15:
            ch = False
            for e in range(4):
                v = int.from_bytes(b[24 - 8 * e:32 - 8 * e], "little")
                if v and (v >> 32) == 0 and (v & 0x3FFFFF) == 0:   # op, dest, weight = 0; type, tag, src = 0; only a delay left
                    b[24 - 8 * e:32 - 8 * e] = bytes(8); n += 1; ch = True
            rows += ch; h = b.hex()
    out.append(h)
open(dst, "w").write("\n".join(out) + "\n"); print("placeholder entries zeroed: %d in %d rows" % (n, rows)); sys.exit(0)
