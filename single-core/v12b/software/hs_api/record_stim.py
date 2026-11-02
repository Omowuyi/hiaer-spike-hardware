# record_stim.py -- run pytest while recording every 64-byte command sent to the card.
# Usage: python record_stim.py <stimulus.hex> <pytest args...>   (byte 0 first on each line)
import sys
import hs_bridge.wrapped_dmadump.dmadump as d
out = open(sys.argv[1], "w", buffering=1)
_w = d.dma_dump_write
def _rec(data, n, *a, **k):
    b = [int(x) & 0xFF for x in list(data)[:int(n)]]
    for i in range(0, len(b) - len(b) % 64, 64):
        out.write("".join("%02x" % x for x in b[i:i + 64]) + "\n")
    out.flush()
    return _w(data, n, *a, **k)
d.dma_dump_write = _rec
import pytest
sys.exit(pytest.main(sys.argv[2:]))
