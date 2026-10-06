#!/usr/bin/env python3
"""
Load the NoC routing tables during network construction.

WHY THIS IS NEEDED

Everything up to now places neurons on cores correctly and programs each core
independently, but nothing tells the NoC where a spike should go.  Each
router's table resets to {OP_LOCAL, 0000}, which keeps every spike on its own
core -- so a partitioned network runs with the cores mutually invisible.  The
symptom is not an error: it is a network that executes cleanly and silently
drops every inter-core connection.

WHAT THIS CHANGES

CRI_network builds the tables from the connectome it has just partitioned and
loads them right after initalize_network(), but ONLY when a membership map was
supplied.  A single-core network needs no table at all -- reset LOCAL is
already what it wants -- so nothing is sent and single-core behaviour is byte
identical.

The edges come from self.userConnections, the same connection dict the network
was built from, and the per-core index comes from the connectome itself, so
placement and routing are derived from one assignment rather than two that have
to be kept in step.

Table loading is best-effort: if it fails the network is still constructed and
the failure is logged with what it means, because a half-loaded table is worth
knowing about explicitly rather than discovering as missing spikes.

  python3 patch_load_routing.py --check <api.py>
  python3 patch_load_routing.py         <api.py>
"""

import sys
import os
import shutil
import io

BACKUP_SUFFIX = ".before_loadrouting"

OLD = '''                membership=membership,
                n_cores=n_cores,
            )
            self.CRI.initalize_network()
'''

NEW = '''                membership=membership,
                n_cores=n_cores,
            )
            self.CRI.initalize_network()
            self._load_noc_routing()
'''

# Inserted just before the readMP definition, which is a stable anchor inside
# the class body.
OLD_METHOD_ANCHOR = '''    def step(self, inputs, target="simpleSim", membranePotential=False):
'''

NEW_METHOD_ANCHOR = '''    def _load_noc_routing(self):
        """Program each core's NoC routing table.

        Only meaningful once neurons live on more than one core: an unwritten
        entry resets to LOCAL, which is exactly right for a single-core
        network, so nothing is sent in that case.
        """
        if getattr(self, "membership", None) is None:
            return
        try:
            import noc_routing
        except ImportError:
            logging.warning(
                "neurons are partitioned across cores but noc_routing is not "
                "importable -- routing tables were NOT loaded, so spikes will "
                "not cross cores")
            return
        try:
            edges = []
            for preKey in self.userConnections:
                entry = self.userConnections[preKey]
                if not entry:
                    continue
                for syn in entry[synapseIdx]:
                    edges.append((preKey, syn[0]))
            tables = noc_routing.from_connectome(self.connectome, edges)
            bad = noc_routing.check_alignment(
                {k: n.get_core() for k, n in self.connectome.get_neurons().items()},
                core_index={k: n.get_coreTypeIdx()
                            for k, n in self.connectome.get_neurons().items()})
            if bad:
                logging.warning(
                    "%d routing block(s) span more than one core; those blocks "
                    "multicast to every core holding part of them", len(bad))
            sent = noc_routing.load_tables(tables, verbose=False)
            logging.info("NoC routing: %d entries loaded across %d cores",
                         sent, len(tables))
        except Exception as e:
            logging.error("NoC routing tables were NOT loaded (%s) -- the "
                          "network will run with every core isolated", e)

    def step(self, inputs, target="simpleSim", membranePotential=False):
'''

EDITS = [
    ("call after initalize_network", OLD, NEW),
    ("_load_noc_routing method", OLD_METHOD_ANCHOR, NEW_METHOD_ANCHOR),
]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv

    if not args:
        print("usage: patch_load_routing.py [--check] <api.py>")
        return 2
    path = args[0]

    if not os.path.isfile(path):
        print("FAIL  no such file: %s" % path)
        return 2

    src = io.open(path, encoding="utf-8").read()

    if "_load_noc_routing" in src:
        print("ALREADY APPLIED  %s" % path)
        return 0

    if "membership=membership" not in src:
        print("FAIL  layer 3 is not applied to this file -- apply "
              "patch_percore_runtime.py first.")
        return 1

    ok = True
    for name, old, new in EDITS:
        n = src.count(old)
        if n == 1:
            print("  anchor OK        %s" % name)
        else:
            print("  ANCHOR %s  %s (found %d, need exactly 1)"
                  % ("MISSING" if n == 0 else "AMBIGUOUS", name, n))
            ok = False

    if not ok:
        print("\nFAIL  anchors do not match -- nothing written.")
        return 1

    if check_only:
        print("\nCHECK PASSED  re-run without --check to apply.")
        return 0

    out = src
    for name, old, new in EDITS:
        out = out.replace(old, new, 1)

    backup = path + BACKUP_SUFFIX
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
        print("\nbackup   %s" % backup)
    io.open(path, "w", encoding="utf-8").write(out)
    print("applied  2/2 edits to %s" % path)

    import py_compile
    try:
        py_compile.compile(path, doraise=True)
        print("syntax   OK")
    except py_compile.PyCompileError as e:
        print("SYNTAX ERROR: %s" % e)
        print("restore with: cp %s %s" % (backup, path))
        return 1

    print("""
noc_routing.py must be importable from the environment that runs the tests.
Put it on PYTHONPATH or beside hs_api; if it is missing the network still
builds and logs a warning rather than failing silently.""")
    return 0


if __name__ == "__main__":
    sys.exit(main())
