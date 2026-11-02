#!/usr/bin/env python3
# Reads the debug-hook-captured bits that IEP received at group0's position in Phase 2.
# Requires the bitstream built with the fixed debug hook (dbg_g0_top / dbg_g0_wt, SET_ROW 257/258).
#
# It writes n0's synapse in the PROVEN 32-bit delta format (col0 - reads correctly in delta mode),
# runs ONE delta_mode=0 step so IEP latches the fetched HBM word, then reads back:
#   SET_ROW=257 -> raw exec_hbm_rdata[511:476] (36 bits: op+dest+weight region for group0)
#   SET_ROW=258 -> the 16-bit weight IEP extracted from [495:480]
#
# Interpretation:
#   weight == 1000 at [495:480]  -> word delivered correctly; bug is downstream (accumulate/halfsel)
#   weight != 1000               -> raw bits show where the weight actually landed -> exact packing fix
#
# Run on crisdsc0 after flashing the hook bitstream:
#   cd /home/omowuyi/testing/hs_api && source .venv/bin/activate
#   export PYTHONPATH=/home/omowuyi/testing/hs_bridge
#   python3 read_dbg.py

import sys, numpy as np
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_bridge.FPGA_Execution.fpga_controller import (
    SYN_BASE_ADDR, SYN_OP_BITS, SYN_ADDR_BITS, SYN_WEIGHT_BITS, read_address_packet
)
from hs_api.single_core_conductance_STDP import build_cmd13_packet


def wr_delta_row(r, entries, c=0):
    """Write a synapse row in the proven 32-bit delta format."""
    cmd = []
    for w in entries:
        b = (np.binary_repr(0, SYN_OP_BITS)
             + np.binary_repr(int(w[1]), SYN_ADDR_BITS)
             + np.binary_repr(int(w[2]) & 0xFFFF, SYN_WEIGHT_BITS))
        cmd += [int(b[:8], 2), int(b[8:16], 2), int(b[16:24], 2), int(b[24:], 2)]
    a = '1' + np.binary_repr(SYN_BASE_ADDR + r, 23)
    full = [2, c] + [0]*27 + [int(a[:8], 2), int(a[8:16], 2), int(a[16:], 2)] + cmd
    return dmadump.dma_dump_write(np.flip(np.array(full, dtype=np.uint64)),
                                  len(full), 1, 0, 0, 0, dmadump.DmaMethodNormal)


def read_dbg(set_row, c=0, tries=6000):
    """Issue a debug read at SET_GROUP=15, SET_ROW=set_row; return the 36-bit payload."""
    coreBits = np.binary_repr(c, 5) + '000'
    tail = np.array([0]*55 + [int(coreBits, 2), 3], dtype=np.uint64)
    req = np.concatenate([read_address_packet(row=set_row, col=15), tail])
    dmadump.dma_dump_write(req, len(req), 1, 0, 0, 0, dmadump.DmaMethodNormal)
    for _ in range(tries):
        ec, d = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64)
        if int(d[62]) == 204 and int(d[63]) == 204:
            b = np.flip(np.array([int(x) for x in d], dtype=np.uint64))
            bits = ''.join(np.binary_repr(int(i), 8) for i in b)
            return int(bits[-36:], 2)
    return None


def main():
    model = ANN_neuron(threshold=1000000, shift=-17, leak=0)
    net = CRI_network(axons={'a0': [('n0', 1000)]},
                      connections={'n0': ([], model)},
                      outputs=['n0'], target='CRI')
    net.step(['a0'])
    print("control ok")

    # Write n0 in the proven 32-bit delta format (col0), clear its pair row.
    wr_delta_row(1, [(0, 0, 1000)] + [(0, 0, 0)]*7)
    wr_delta_row(0, [(0, 0, 0)]*8)

    # One delta_mode=0 step so IEP latches the fetched HBM word into the debug regs.
    dmadump.dma_dump_write(
        build_cmd13_packet(delta_mode=0, decay_ex=3900, decay_in=3900,
                           coba_mode=0, stdp_enable=0, coreID=0),
        64, 1, 0, 0, 0, dmadump.DmaMethodNormal)
    net.step(['a0'])

    raw = read_dbg(257)
    wt = read_dbg(258)

    print("raw exec_hbm_rdata[511:476] =", hex(raw) if raw is not None else None)
    if raw is not None:
        # 36-bit field = bits [511:476]. Within it (bit0 = 476):
        #   weight [495:480] = field bits [19:4]
        #   dest   [508:496] = field bits [32:20]
        w_in_raw = (raw >> 4) & 0xFFFF
        d_in_raw = (raw >> 20) & 0x1FFF
        print("  -> weight bits [495:480] within raw =", w_in_raw, "(want 1000)")
        print("  -> dest   bits [508:496] within raw =", d_in_raw, "(want 0)")
    print("extracted group0 weight (IEP read of [495:480]) =", wt, "(want 1000)")

    # restore delta mode
    dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                           64, 1, 0, 0, 0, dmadump.DmaMethodNormal)


if __name__ == "__main__":
    main()
