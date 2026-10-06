#!/usr/bin/env python3
"""
Fix the per-core flush_spikes merge in network.run_step.

THE BUG

flush_spikes returns (spikeOutput, latency, hbmAcc), not a list.  The layer-3
run_step concatenated that tuple onto a list, which raised

    TypeError: can only concatenate list (not "tuple") to list

The single-core code assigned the result straight through, so the shape never
had to be handled.  Accumulating across cores means taking it apart.

HOW THE THREE FIELDS COMBINE

  spikeOutput  concatenated -- every core's spikes belong to this timestep
  latency      MAX -- the timestep is over when the SLOWEST core finishes, so
                the longest per-core latency is the one that describes it
  hbmAcc       SUM -- each core accesses its own HBM channel independently

  python3 fix_flush_merge.py --check <network.py>
  python3 fix_flush_merge.py         <network.py>
"""

import sys
import os
import shutil
import io

BACKUP_SUFFIX = ".before_flushfix"

OLD = '''                spike_results = []
                for core in self.cores:
                    spike_results = spike_results + flush_spikes(coreID = self.core_target[core])
'''

NEW = '''                # flush_spikes returns (spikeOutput, latency, hbmAcc) per
                # core.  Spikes concatenate; latency is the MAX because the
                # timestep ends when the slowest core finishes; hbmAcc sums
                # because each core drives its own HBM channel.
                merged_spikes = []
                merged_latency = 0
                merged_hbmAcc = 0
                for core in self.cores:
                    coreSpikes, coreLatency, coreHbmAcc = flush_spikes(coreID = self.core_target[core])
                    merged_spikes = merged_spikes + list(coreSpikes)
                    if coreLatency > merged_latency:
                        merged_latency = coreLatency
                    merged_hbmAcc = merged_hbmAcc + coreHbmAcc
                spike_results = (merged_spikes, merged_latency, merged_hbmAcc)
'''


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv

    if not args:
        print("usage: fix_flush_merge.py [--check] <network.py>")
        return 2
    path = args[0]

    if not os.path.isfile(path):
        print("FAIL  no such file: %s" % path)
        return 2

    src = io.open(path, encoding="utf-8").read()

    if "merged_hbmAcc" in src:
        print("ALREADY APPLIED  %s" % path)
        return 0

    if "def _core_inputs" not in src:
        print("FAIL  layer 3 is not applied to this file -- nothing to fix.")
        return 1

    n = src.count(OLD)
    if n != 1:
        print("  ANCHOR %s  flush_spikes merge (found %d, need exactly 1)"
              % ("MISSING" if n == 0 else "AMBIGUOUS", n))
        return 1
    print("  anchor OK        flush_spikes merge")

    if check_only:
        print("\nCHECK PASSED  re-run without --check to apply.")
        return 0

    backup = path + BACKUP_SUFFIX
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
        print("\nbackup   %s" % backup)
    io.open(path, "w", encoding="utf-8").write(src.replace(OLD, NEW, 1))
    print("applied  1/1 edit to %s" % path)

    import py_compile
    try:
        py_compile.compile(path, doraise=True)
        print("syntax   OK")
    except py_compile.PyCompileError as e:
        print("SYNTAX ERROR: %s" % e)
        print("restore with: cp %s %s" % (backup, path))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
