#!/usr/bin/env python3
"""vs_model.py PLAN OUTPREFIX MODEL.json -- round 46: the simulation's spikes at every step and final membranes against the exact
model of the network (computed off line with the network builder; spike when V > threshold, reset to 0, input at the next update,
membrane read with the last step's input added -- the model that matched the card's correct 16-core CNN run exactly)."""
import sys, json, os, collections
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "eval_equiv.py")).read(); g = {}; exec(src[:src.index("rp, rs, rm")], g)
p, fired, mem, *_ = g["parse"](sys.argv[1], sys.argv[2]); ref = json.load(open(sys.argv[3]))
steps = collections.defaultdict(set)
for k, ts in fired.items():
    for t in ts: steps[int(t)].add(k)
bad = []
for t, r in enumerate(ref["spikes"]):
    r = set(r); s = steps.get(t, set())
    if r != s:
        bad.append(t); lay = lambda k: k.split("_")[0]
        print("  step %d: model %d spikes, simulation %d; missing %s; extra %s" % (t, len(r), len(s), dict(collections.Counter(lay(k) for k in r - s)), dict(collections.Counter(lay(k) for k in s - r))))
mb = [k for k, v in ref["mem"].items() if mem.get(k) != v]
print("%s ROUND46 vs EXACT MODEL: %d of %d steps identical, %d of %d membranes differ%s" % ("PASS" if not bad and not mb else "FAIL", len(ref["spikes"]) - len(bad), len(ref["spikes"]), len(mb), len(ref["mem"]), "" if not mb else " (e.g. %s)" % [(k, ref["mem"][k], mem.get(k)) for k in mb[:3]]))
