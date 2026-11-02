#!/usr/bin/env python3
"""
Two checks that must pass before any network runs 64-bit.

  python3 check_64bit.py headroom <network.pkl>     # offline, no hardware
  python3 check_64bit.py order                      # on hardware

HEADROOM
--------
Each HBM row is 256 bits = 32 bytes.  32-bit entries pack 8 per row; 64-bit
pack 4, so the synapse region DOUBLES.  The per-channel limit is 256 MB.
Reads self.synapses row count out of the pickled compiler data
([0]=axon_ptrs, [1]=neuron_ptrs, [2]=synapses) and reports both sizes.

ORDER
-----
The IEP reads two consecutive HBM rows as one 512-bit word and takes group 0
from the MSB end.  Which half of a row-pair carries groups 0-7 is decided by
the upstream partitioner, not by fpga_compiler.py, so it has to be measured.

Builds 16 neurons, one per URAM group, driven by one axon with weights
100,200,...,1600, compiled 64-bit, and reads V per group.  V is the
instantaneous drive (leak=0), so with decay_ex=4095 each group should read
its own weight minus rounding.

  groups ascending 100..1600  -> convention holds, nothing to change
  halves swapped              -> swap the `half` loop order in
                                 _create_synapses_64
  any other permutation       -> send me the exact list
"""

import sys, pickle, os

ROW_BYTES   = 32
CHANNEL_CAP = 256 * 1024 * 1024


def headroom(path):
    if not os.path.isfile(path):
        sys.exit("no such file: %s" % path)
    with open(path, 'rb') as f:
        data = pickle.load(f)
    rows32 = len(data[2])
    rows64 = rows32 * 2
    b32, b64 = rows32 * ROW_BYTES, rows64 * ROW_BYTES
    print("synapse rows (32-bit) : %d" % rows32)
    print("synapse rows (64-bit) : %d" % rows64)
    print()
    print("  32-bit : %8.1f MB   %s" % (b32 / 1e6, "fits" if b32 <= CHANNEL_CAP else "OVER LIMIT"))
    print("  64-bit : %8.1f MB   %s" % (b64 / 1e6, "fits" if b64 <= CHANNEL_CAP else "OVER LIMIT"))
    print("  limit  : %8.1f MB per HBM channel" % (CHANNEL_CAP / 1e6))
    print()
    if b64 > CHANNEL_CAP:
        print("This network CANNOT run 64-bit on one channel.  Keep it 32-bit")
        print("(syn_64bit_en=0) -- it only needs 64-bit for per-synapse delay")
        print("or STDP.  Otherwise partition it across more cores.")
    else:
        print("Headroom is fine for 64-bit.  Remember Phase 2 also does twice")
        print("the HBM reads, so expect roughly 2x the Phase-2 time.")


def order():
    sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
    from hs_api.api import CRI_network
    from hs_api.neuron_models import ANN_neuron
    import hs_bridge.wrapped_dmadump.dmadump as dmadump
    from hs_api.single_core_conductance_STDP import build_cmd13_packet

    NG, DEC = 16, 4095
    W = [100 * (g + 1) for g in range(NG)]

    model = ANN_neuron(threshold=50000, shift=-17, leak=0)
    import inspect as _i
    if 'syn_64bit' not in _i.signature(CRI_network.__init__).parameters:
        sys.exit(
            "\nPREREQUISITE MISSING: CRI_network has no syn_64bit argument.\n"
            "Run (WITHOUT --check):\n"
            "  python3 thread_syn64bit.py <api.py> <network.py>\n"
            "and make sure compiler_64bit.py has been applied to fpga_compiler.py.\n")
    net = CRI_network(axons={'a0': [('n%d' % g, W[g]) for g in range(NG)]},
                      connections={('n%d' % g): ([], model) for g in range(NG)},
                      outputs=['n%d' % g for g in range(NG)], target='CRI',
                      syn_64bit=True)

    import inspect
    if 'syn_64bit_en' not in inspect.signature(build_cmd13_packet).parameters:
        sys.exit(
            "\nPREREQUISITE MISSING: build_cmd13_packet has no syn_64bit_en argument.\n"
            "\n"
            "Run the wiring patch first -- it adds the argument and packs bit 131:\n"
            "  python3 wire_syn64.py <command_interpreter.v> <single_core.v> \\\n"
            "                        <single_core_conductance_STDP.py>\n"
            "\n"
            "And note this check ALSO needs:\n"
            "  * a REBUILD and reflash -- syn_64bit_en is a new RTL port, it does\n"
            "    not exist in the currently flashed bitstream\n"
            "  * the network compiled with syn_64bit=True, which means threading\n"
            "    that flag through CRI_network -> compile_network -> fpga_compiler\n")

    idx = [net.connectome.get_neuron_by_key('n%d' % g).get_hbmIdx() for g in range(NG)]
    print("hbmIdx:", idx)
    print("Requires: patches applied, bitstream rebuilt and flashed, and this")
    print("network compiled with syn_64bit=True.\n")

    dmadump.dma_dump_write(
        build_cmd13_packet(delta_mode=0, decay_ex=DEC, decay_in=DEC,
                           syn_64bit_en=1, coreID=0),
        64, 1, 0, 0, 0, dmadump.DmaMethodNormal)

    def sv(v):
        v = int(v) & 0xFFFFFFFF
        return v - 0x100000000 if v >= 0x80000000 else v

    # clear Row B: decay=0 zeroes I_ex/I_in in one Phase 0.  Without this the
    # previous test's residue shows up added to group 0.
    dmadump.dma_dump_write(
        build_cmd13_packet(delta_mode=0, decay_ex=0, decay_in=0,
                           syn_64bit_en=1, coreID=0),
        64, 1, 0, 0, 0, dmadump.DmaMethodNormal)
    for _ in range(8):
        try:
            net.step([])
        except Exception:
            pass
    dmadump.dma_dump_write(
        build_cmd13_packet(delta_mode=0, decay_ex=DEC, decay_in=DEC,
                           syn_64bit_en=1, coreID=0),
        64, 1, 0, 0, 0, dmadump.DmaMethodNormal)

    try:
        net.step(['a0'])
        net.step([])
    except Exception as e:
        print("(step raised %s -- continuing)" % type(e).__name__)

    got  = [sv(net.CRI.readMP([i])[0][3]) for i in idx]
    want = [(w * DEC) >> 12 for w in W]

    print("  group :", " ".join("%5d" % g for g in range(NG)))
    print("  got   :", " ".join("%5d" % v for v in got))
    print("  expect:", " ".join("%5d" % v for v in want))
    print()
    if got == want:
        print("PASS - group order holds.  64-bit layout is correct as emitted.")
    elif got == want[8:] + want[:8]:
        print("HALVES SWAPPED - groups 0-7 and 8-15 are exchanged.")
        print("Fix: reverse the `for half in (0, 1)` loop in")
        print("     _create_synapses_64 to `for half in (1, 0)`.")
    elif all(v == 0 for v in got[8:]) and got[1:8] == [want[2 * g] for g in range(1, 8)]:
        print("32-BIT DATA READ AT 64-BIT SPACING.")
        print("Group g is reading 32-bit slot 2g, and groups 8-15 are empty")
        print("because 32-bit entries fill only one 512-bit word.")
        print("The RTL is in 64-bit mode but HBM still holds 32-bit entries:")
        print("  * apply thread_syn64bit.py WITHOUT --check")
        print("  * apply compiler_64bit.py to fpga_compiler.py")
        print("  * recompile the network (CRI_network(..., syn_64bit=True))")
    else:
        print("PERMUTED - send me the 'got' line and I will derive the mapping.")
        print("Do not run any 64-bit network until this reads in order.")

    dmadump.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                           64, 1, 0, 0, 0, dmadump.DmaMethodNormal)


if len(sys.argv) < 2 or sys.argv[1] not in ("headroom", "order"):
    sys.exit(__doc__)
if sys.argv[1] == "headroom":
    if len(sys.argv) != 3:
        sys.exit("usage: check_64bit.py headroom <network.pkl>")
    headroom(sys.argv[2])
else:
    order()
