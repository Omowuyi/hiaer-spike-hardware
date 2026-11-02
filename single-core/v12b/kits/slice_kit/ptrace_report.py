#!/usr/bin/env python3
"""ptrace_report.py PTRACE PROTOCOL_JSON REPLAY_PREFIX -- what the plasticity controller saw and did, against the truth.
1. captures per step vs the real spikes: axons fired (protocol schedule) and neurons fired (replay spike reports)
2. every plastic weight after each controller row write vs the reference trajectory (stdp_ref.py at the hardware's
   step numbering); the first step where any weight diverges, with what the controller saw at that step."""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stdp_ref as R, plasticity as PL
from stdp_ref_v2 import NeuronStamps, AxonStamps
ptr, P = sys.argv[1], json.load(open(sys.argv[2])); pre = sys.argv[3]
hw = P["hw"]; STEPS = P["steps"]; g = P["g"]; PS, PE = P["bases"]["PLASTIC_START"], P["bases"]["PLASTIC_END"]
steps, cur = [], []
for l in open(pre + "_tx.txt"):
    b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
    if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
        cur += [((v >> (32 + 32 * k)) & 0x7FFFF) for k in range(14) if ((v >> (32 + 32 * k)) >> 23) & 1]
        if (b[63], b[62]) == (0xAB, 0xCD): steps.append(set(cur)); cur = []
axhw = {k: v for k, v in hw.items() if k[0] in "DP"}
AX = [{axhw[k] for k in P["schedule"][s]} for s in range(STEPS)]
# ---- trace
st = -1; ncap, acap, p4, rew, writes = {}, {}, {}, {}, []
UNITS = {"s", "ms", "us", "ns", "ps", "fs"}
for l in open(ptr):
    f = l.split()
    if len(f) > 1 and f[1] in UNITS: f = [f[0]] + f[2:]      # xsim writes '<time> <unit>'
    if len(f) < 2: continue
    k = f[1]; kv = dict(x.split("=", 1) for x in f[2:] if "=" in x)
    if k == "STEP": st += 1
    elif k in ("NCAP", "ACAP"):
        row, mask = int(kv["row"]), int(kv["mask"], 16)
        (ncap if k == "NCAP" else acap).setdefault(st, set()).update(16 * row + b for b in range(16) if mask >> b & 1)
    elif k == "P4START": p4[st] = (int(kv["ncount"]), int(kv["acount"]))
    elif k == "REWARD": rew[st] = int(kv["R"])
    elif k == "HREQ" and kv["we"] == "1" and PS <= int(kv["addr"]) < PE:
        writes.append((st, int(kv["addr"]), int(kv["data"], 16)))
print("trace: %d steps, %d Phase-4 runs, rewards after steps %s, %d writes to plastic synapse rows" % (st + 1, len(p4), sorted(rew), len(writes)))
# ---- 1. captures vs truth
def cmp(name, cap, truth, universe):
    bad = []
    for s in range(STEPS):
        c = cap.get(s, set()); t = truth[s] & universe
        if c != t: bad.append((s, sorted(t - c), sorted(c - t)))
    miss = sum(len(b[1]) for b in bad); extra = sum(len(b[2]) for b in bad)
    print("%s captures: %d of %d steps differ from the truth (%d missing, %d extra)" % (name, len(bad), STEPS, miss, extra))
    for s, m, e in bad[:8]: print("   step %2d: missing %s  extra %s" % (s, m[:10], e[:10]))
    return bad
cmp("axon  ", acap, AX, set(axhw.values()))
cmp("neuron", ncap, steps, {v for k, v in hw.items() if k.startswith("N1.")})
# ---- 2. weights
tabs = {int(t): (PL.trace_table(tau) if kk == "trace" else PL.decay_table(tau, sh)) for t, (kk, tau, sh) in P["tables"].items()}
luts = [tabs.get(i, [0] * 4096) for i in range(8)]
def rule(f): return R.Rule(f["A2p"], f["A3p"], f["A2m"], f["w_min"], f["w_max"], soft=f["soft"], A3m=f["A3m"], A0=f["A0"], s2p=f["s2p"], s3p=f["s3p"], s2m=f["s2m"], s3m=f["s3m"], s0=f["s0"], elig=f["elig"], eta=f["eta"], elig_reset=f["elig_reset"], e_shift=f["e_shift"], lut_p=f["lut_p"], lut_m=f["lut_m"], lut_y=f["lut_y"], lut_x=f["lut_x"], lut_e=f["lut_e"])
rules = {int(s_): rule(ff) for s_, ff in P["rules"].items()}
rewards = {int(k): v for k, v in P["rewards"].items()}
def traj(rl, w0, PRE, POST, axon):
    a = AxonStamps(1) if axon else NeuronStamps(1); q = NeuronStamps(1); a.clear(); q.clear(); w, e, te = w0, 0, 0; out = []
    for s in range(STEPS):
        a.advance(); q.advance(); t = q.t; fp, fq = s in PRE, s in POST
        if fp: a.spike(0)
        if fq: q.spike(0)
        for ltp, fired, d, isi in ((False, fp, q.d(0), a.isi[0]), (True, fq, a.d(0), q.isi[0])):
            if not fired: continue
            p = R.event_p(rl, luts, ltp, d, isi)
            if p is None: continue
            if rl.elig: e, te = R.elig_accumulate(rl, luts, e, te, t, p)
            else: w = R.apply_p(rl, p, w, g)
        if rl.elig and s in rewards: w, e, te = R.reward_apply(rl, luts, e, te, t, rewards[s], w)
        out.append(w)
    return out
syn = {}
for sy in P["synapses"]:
    ax = sy["pre"].startswith("P"); src = ((1 << 17) | hw[sy["pre"]]) if ax else hw[sy["pre"]]
    PRE = {s for s in range(STEPS) if sy["pre"] in P["schedule"][s]} if ax else {s for s in range(STEPS) if hw[sy["pre"]] in steps[s]}
    POST = {s for s in range(STEPS) if hw[sy["post"]] in steps[s]}
    syn[(src, hw[sy["post"]] // 16)] = dict(sy, ax=ax, PRE=PRE, POST=POST, ref=traj(rules[sy["rule"]], sy["w0"], PRE, POST, ax), hw=[None] * STEPS)
last = {k: v["w0"] for k, v in syn.items()}
for s, addr, data in writes:
    for sl in range(4):
        e = (data >> (64 * sl)) & ((1 << 64) - 1)
        if (e >> 61) == 0 and (e >> 18) & 0xF:
            key = (e & 0x3FFFF, (e >> 48) & 0x1FFF)
            if key in syn:
                w = (e >> 32) & 0xFFFF; syn[key]["hw"][s] = w - (1 << 16) if w >= 1 << 15 else w
for k, S in syn.items():
    w = S["w0"]
    for s in range(STEPS):
        if S["hw"][s] is not None: w = S["hw"][s]
        S["hw"][s] = w
div = [(next((s for s in range(STEPS) if S["hw"][s] != S["ref"][s]), None), k) for k, S in syn.items()]
div = sorted((s, k) for s, k in div if s is not None)
print("weights: %d of %d synapses diverge from the reference" % (len(div), len(syn)))
for s, k in div[:6]:
    S = syn[k]; pv = lambda arr: arr[s - 1] if s > 0 else S["w0"]
    print("   %-12s rule %d  first at step %2d: hardware %4d -> %4d, reference %4d -> %4d | pre fired %s (captured %s), post fired %s (captured %s)%s" % (
        S["pre"] + "->" + S["post"], S["rule"], s, pv(S["hw"]), S["hw"][s], pv(S["ref"]), S["ref"][s], s in S["PRE"],
        (hw[S["pre"]] in (acap if S["ax"] else ncap).get(s, set())), s in S["POST"], hw[S["post"]] in ncap.get(s, set()),
        ", reward %d" % rewards[s] if s in rewards else ""))
