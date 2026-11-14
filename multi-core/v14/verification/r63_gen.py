#!/usr/bin/env python3
"""r63_gen.py OUT_DIR -- round 63: full-load spike readout.  One core (D0 on core 15, as rounds 44/59), 10,000 neurons (two
microphases), each driven by its own axon every step, ALL of them outputs, 3 driven steps + 1 empty.  Expected spikes per step from
large2's exact model."""
import sys, json, os, collections
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
src = open("/tmp/ws/r47_kit/gen_equiv.py").read(); g = {"__name__": "r63"}; sys.argv = ["x", out]
exec(src[:src.index("out = sys.argv[1]")], g)
LIF = g["LIF_neuron"]; m = LIF(threshold=5, shift=-17, leak=63); n = 10000
conns = {"N%d" % i: ([], m) for i in range(n)}; axons = {"A%d" % i: [("N%d" % i, 10)] for i in range(n)}
conns["D0"] = ([], LIF(threshold=10**6, shift=-17, leak=63))
mem = {k: 0 for k in conns}; mem.update({a: 0 for a in axons}); mem["D0"] = 15
keys = ["N%d" % i for i in range(n)]; drive = [list(axons)] * 3 + [[]]
b = (axons, conns, mem, keys, drive)
l2 = open("/tmp/large2_kit/large2.py").read(); h = {"collections": collections}; exec(l2[l2.index("def th(m)"):l2.index("def run(name, built)")], h)
sp, V = h["model"](b)
json.dump({"spikes": [sorted(s) for s in sp], "mem": {k: V[k] for k in keys}}, open(os.path.join(out, "model_r63.json"), "w"))
print("model: spikes per step %s" % [len(s) for s in sp])
info = g["rec_net"]("r63", b)
with open(os.path.join(out, "stim_r63.hex"), "w") as f:
    for p in g["REC"]: f.write(bytes(int(x) for x in p).hex() + "\n")
json.dump(info, open(os.path.join(out, "plan_r63.json"), "w"), indent=1)
print("r63: %d commands (%d loading), %d steps, %d outputs" % (info["commands"], info["load_commands"], info["steps"], len(keys)))
