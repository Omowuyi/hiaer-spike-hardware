#!/usr/bin/env python3
"""
Per-synapse delay, specified at COMPILE time.

WHY THIS DIFFERS FROM test_delay_hw.py
The earlier test built a network, patched the synapse tuples to carry a delay,
and called create_synapses() again.  That re-emit never reached HBM -- reading
the rows back through the axon pointer showed the original delay=0 data still
in place.  So every delayed run measured the undelayed synapse, which is why
three different bitstreams produced byte-identical traces.

This supplies the delay when the network is COMPILED, so it is present the
first time the rows are written -- the same path that already works for
delay=0 and that check_64bit.py proved correct:

    CRI_network(..., syn_64bit=True, syn_delay=N)

EXPECTATION
weight 1000, decay_ex 3900 -> drive 952.  With syn_delay=0 the drive appears
one step after the axon fires.  With syn_delay=N it appears N steps later
than that.  FIX J made the delay buffers deliver at exactly N (measured in
simulation on both delay_buffer.v and axon_delay_buffer.v, delays 0-5).

SAFETY
Bounded reads, a wall-clock hard stop, and delta_mode restored on exit
including on exception.  Row B is cleared before each measurement -- without
that the drive lands on top of residual I_ex and nothing matches.

  cd /home/omowuyi/testing/hs_api
  source .venv/bin/activate
  export PYTHONPATH=/home/omowuyi/testing/hs_bridge
  python3 test_delay_construct.py
"""

import sys, signal
sys.path.insert(0, '/home/omowuyi/testing/hs_bridge')
import numpy as np
from hs_api.api import CRI_network
from hs_api.neuron_models import ANN_neuron
import hs_bridge.wrapped_dmadump.dmadump as d
from hs_api.single_core_conductance_STDP import build_cmd13_packet

DEC, W = 3900, 1000
DRIVE = (W * DEC) >> 12        # 952
STEPS = 10
results = {}


class Timeout(Exception):
    pass


signal.signal(signal.SIGALRM, lambda s, f: (_ for _ in ()).throw(Timeout()))


def cfg(**kw):
    p = dict(delta_mode=0, decay_ex=DEC, decay_in=DEC, decay_w=0, delta_w=0,
             coba_mode=0, E_ex=0, E_in=0, neuromod_excitability_bias=0,
             stdp_enable=0, syn_64bit_en=1, coreID=0)
    p.update(kw)
    d.dma_dump_write(build_cmd13_packet(**p), 64, 1, 0, 0, 0, d.DmaMethodNormal)


def sv(v):
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def step(net, ax=None):
    try:
        return net.step(ax if ax else [])
    except Exception:
        return None


def mknet(delay):
    """Construct with syn_delay set, then RE-EMIT the synapse rows.

    The emit that happens during CRI_network construction produces wrong
    synapse data in 64-bit mode -- with syn_delay=0 and no re-emit the drive
    reads -1935 instead of +952.  Calling create_synapses() again afterwards
    writes correct rows, which is why the earlier test's control passed: it
    re-emitted as a side effect of patching tuples.

    Because syn_delay is stored on the compiler at create_script time, the
    re-emit picks it up automatically -- no tuple patching needed."""
    m = ANN_neuron(threshold=50000, shift=-17, leak=0)
    net = CRI_network(axons={'a0': [('n0', W)]}, connections={'n0': ([], m)},
                      outputs=['n0'], target='CRI',
                      syn_64bit=True, syn_delay=delay)
    net.CRI.compiledNetwork.create_synapses(syn_64bit=True)
    return net


def reset_rowb(net):
    """Zero Row B.  Without this the drive lands on residual I_ex."""
    cfg(decay_ex=0, decay_in=0)
    for _ in range(8):
        step(net)
    cfg()


def trace(net):
    out = []
    for s in range(STEPS):
        step(net, ['a0'] if s == 0 else [])
        out.append(sv(net.CRI.readMP([0])[0][3]))
    return out


try:
    signal.alarm(900)

    print("weight %d, decay_ex %d -> drive %d" % (W, DEC, DRIVE))
    print("synapse rows re-emitted after construction\n")

    print("=" * 68)
    print("CONTROL -- syn_delay=0")
    print("=" * 68)
    net = mknet(0)
    reset_rowb(net)
    cfg()
    tr0 = trace(net)
    base = tr0.index(DRIVE) if DRIVE in tr0 else None
    print("  %s" % tr0)
    print("  drive first at step %s\n" % base)
    if base is None:
        print("  CONTROL FAILED -- the immediate path does not work here, so no")
        print("  delayed result would mean anything.  Stopping.")
        raise SystemExit(1)

    ok = True
    for delay in (1, 2, 3):
        print("=" * 68)
        print("syn_delay=%d" % delay)
        print("=" * 68)
        net = mknet(delay)
        reset_rowb(net)
        cfg()
        tr = trace(net)
        idx = tr.index(DRIVE) if DRIVE in tr else None
        shift = None if idx is None else idx - base
        good = (shift == delay)
        ok &= good
        print("  %s" % tr)
        print("  drive at step %-5s shift %-5s expect %d   %s\n"
              % (idx, shift, delay, "PASS" if good else "FAIL"))
        if tr == tr0:
            print("  NOTE: identical to the control trace -- the delay is not\n"
                  "  reaching the synapse data at all.\n")
    results["per-synapse delay"] = ok

except Timeout:
    print("\nABORTED: timed out")
except SystemExit:
    pass
except KeyboardInterrupt:
    print("\ninterrupted")
finally:
    signal.alarm(0)
    try:
        d.dma_dump_write(build_cmd13_packet(delta_mode=1, coreID=0),
                         64, 1, 0, 0, 0, d.DmaMethodNormal)
    except Exception:
        pass

print("=" * 68)
for k, v in results.items():
    print("  %-22s %s" % (k, "PASS" if v else "FAIL"))
if not results:
    print("  nothing completed")
print("=" * 68)
