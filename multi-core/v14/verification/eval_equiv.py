#!/usr/bin/env python3
"""eval_equiv.py REF_PLAN REF_PREFIX PLAN PREFIX [LABEL] -- option B's decisive test: the same network in another placement
must give exactly the reference's spikes (every neuron, every step) and final membranes.  Parsing is eval_noc.py's:
a spike's step = its core's step-done count so far, its neuron = plan host_map[core][address]; membranes via neuron_idx."""
import sys, json, collections
def parse(planf, pre):
    plan = json.load(open(planf))
    idx_key = {int(c): {i: k for k, i in d.items()} for c, d in plan["neuron_idx"].items()}
    host = {int(c): {int(a): v for a, v in d.items()} for c, d in plan["host_map"].items()}
    abcd = collections.Counter(); spikes = collections.defaultdict(list); unknown = []; mem = {}
    seen = collections.Counter()
    for l in open(pre + "_tx.txt"):
        t, c, h = l.split(); c = int(c); b = bytes.fromhex(h); v = int.from_bytes(b, "little")
        if (b[63], b[62]) in ((0xEE, 0xEE), (0xAB, 0xCD)):
            for k in range(14):
                w = (v >> (32 + 32 * k)) & 0xFFFFFFFF
                if (w >> 23) & 1:
                    step, addr, tag = seen[c], w & 0x7FFFF, (w >> 19) & 0xF
                    hm = host.get(tag, {}).get(addr)
                    if hm is None: unknown.append((tag, addr))
                    elif hm[1]: spikes[hm[0]].append(step)
        if (b[63], b[62]) == (0xAB, 0xCD): abcd[c] += 1; seen[c] += 1
        if (b[63], b[62]) == (0xCC, 0xCC):
            col, row, mp = (v >> 49) & 0xF, (v >> 36) & 0x1FFF, v & 0xFFFFFFFF
            k = idx_key.get(c, {}).get(16 * row + col)
            if k is not None: mem[k] = mp - (1 << 32) if mp >> 31 else mp
    ex = {int(c): n for c, n in plan["executes"].items() if n}
    return plan, {k: sorted(v) for k, v in spikes.items()}, mem, abcd, ex, unknown
rp, rs, rm, ra, rex, ru = parse(sys.argv[1], sys.argv[2])
xp, xs, xm, xa, xex, xu = parse(sys.argv[3], sys.argv[4])
label = sys.argv[5] if len(sys.argv) > 5 else xp["name"]
keys = [k for k in rp["reads"] if k != "D0"]; steps = rp["steps"]
per_step = [sum(1 for k in keys for s in rs.get(k, []) if s == t) for t in range(steps)]
R = []
def check(n, ok, d=""): R.append(ok); print("  %-4s %-58s %s" % ("ok" if ok else "FAIL", n, d))
print("== %s vs reference %s  (%d neurons, %d steps; reference spikes per step %s)" % (label, rp["name"], len(keys), steps, per_step))
check("step-done from every executed core, every step (reference)", all(ra[c] == n for c, n in rex.items()), str(dict(ra)))
check("step-done from every executed core, every step", all(xa[c] == n for c, n in xex.items()), str(dict(xa)))
check("every spike maps to a neuron (no unknown addresses)", not ru and not xu, "unknown %d / %d" % (len(ru), len(xu)))
check("the reference is active (spikes in at least half the steps)", sum(1 for n in per_step if n) >= steps // 2, "%d of %d steps" % (sum(1 for n in per_step if n), steps))
diff = [k for k in keys if rs.get(k, []) != xs.get(k, [])]
check("identical spikes: every neuron, every step", not diff,
      "; ".join("%s ref %s got %s" % (k, rs.get(k, [])[:8], xs.get(k, [])[:8]) for k in diff[:4]) + ("" if not diff else "  (%d neurons differ)" % len(diff)))
mdiff = [k for k in keys if rm.get(k) != xm.get(k)]
check("identical final membranes (every neuron read)", not mdiff and len(xm) >= len(keys),
      "; ".join("%s ref %s got %s" % (k, rm.get(k), xm.get(k)) for k in mdiff[:4]) + ("" if not mdiff else "  (%d differ)" % len(mdiff)))
print("%s %s: %d of %d checks" % ("PASS" if all(R) else "FAIL", label, sum(R), len(R)))
