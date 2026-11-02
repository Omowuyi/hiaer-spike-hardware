#!/usr/bin/env python3
"""iso_check.py JSON REPLAY_PREFIX [PTRACE] -- isolated firing: neuron n must spike exactly at step n+1 (its driver fires
only at step n).  Compares the expected spikes with the host-reported spikes, and with the plasticity controller's
neuron captures if a trace is given."""
import sys, json
J = json.load(open(sys.argv[1])); pre = sys.argv[2]; hw = J["hw"]; S = J["steps"]
exp = [set() for _ in range(S)]
for n in range(J["n"]):
    if n + 1 < S: exp[n + 1].add(hw["N1.%d" % n])
rep, cur = [], []
for l in open(pre + "_tx.txt"):
    b = bytes.fromhex(l.split()[1]); v = int.from_bytes(b, "little")
    if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
        cur += [((v >> (32 + 32 * k)) & 0x7FFFF) for k in range(14) if ((v >> (32 + 32 * k)) >> 23) & 1]
        if (b[63], b[62]) == (0xAB, 0xCD): rep.append(set(cur)); cur = []
def judge(name, got):
    bad = [(s, sorted(exp[s]), sorted(got[s] if s < len(got) else set())) for s in range(S) if (got[s] if s < len(got) else set()) != exp[s]]
    print("%s: %d steps, %d of %d steps differ from the expected spikes" % (name, len(got), len(bad), S))
    for s, e, g in bad[:12]: print("   step %2d  expected %-6s got %s" % (s, e, g))
    return not bad and len(got) >= S
ok = judge("%s-bit reported spikes" % (64 if J["syn64"] else 32), rep)
if len(sys.argv) > 3:
    cap = [set() for _ in range(S)]; st = -1
    for l in open(sys.argv[3]):
        f = l.split(); f = [f[0]] + f[2:] if len(f) > 1 and f[1] in ("ns", "ps", "us", "fs") else f
        if len(f) < 2: continue
        if f[1] == "STEP": st += 1
        elif f[1] == "NCAP" and 0 <= st < S:
            kv = dict(x.split("=") for x in f[2:]); r, m = int(kv["row"]), int(kv["mask"], 16)
            cap[st] |= {16 * r + b for b in range(16) if m >> b & 1}
    ok = judge("plasticity controller's neuron captures", cap) and ok
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
