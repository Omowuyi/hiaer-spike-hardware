#!/usr/bin/env python3
"""
Real partitioning + per-core HBM mapping  --  layer 2b of multi-core placement.

Patches TWO files; pass both paths, in either order:
    connectome.py       per-core AXON indexing
    compile_network.py  real partition, per-core filtering in map_to_hbm_fpga

WHAT IS WRONG TODAY

compile_network.partition() hardcodes `n_cores = 1` with the comment "get rid
of this, it's just for some quick and dirty debugging", so membership is all
zeros and every neuron lands on core 0.  map_to_hbm_fpga() then loops over
cores but calls connectome.get_axons() and get_class_ordered_list() inside the
loop with no core filter, so each core would be handed an identical copy of
the whole network.

Separately, layer 1 re-indexed NEURONS per core but not AXONS.  api.py turns
input symbols into axon indices with get_coreTypeIdx(), and map_to_hbm_fpga
lays axons out in get_axons() iteration order; unless both are per core and
agree, inputs address the wrong axon.

WHAT THIS CHANGES

  connectome.update_core_axon_idx()  new: axons indexed 0..N-1 within each
                                     core, in the same iteration order
                                     map_to_hbm_fpga uses, called from
                                     apply_partition once cores are known
  partition()                        membership comes from the caller; the
                                     n_cores=1 hardcode is gone
  map_to_hbm_fpga()                  axons and neurons filtered to the core
                                     being mapped; hbm is keyed by the cores
                                     actually in use
  compileNetwork()                   accepts n_cores and membership

SINGLE-CORE EQUIVALENCE

With membership=None and one core, every neuron and axon has core 0, the
filters are no-ops, and the result is what the current code produces.

  python3 patch_percore_partition.py --check <connectome.py> <compile_network.py>
  python3 patch_percore_partition.py         <connectome.py> <compile_network.py>
"""

import sys
import os
import shutil
import io

BACKUP_SUFFIX = ".before_percore_part"

# ============================================================ connectome.py
OLD_APPLY_PARTITION = '''    def apply_partition(self, membership): #apply a partition to the network
        mergedNeurons = self.get_merged_neurons()
        for key in membership.keys():
            mergedNeurons[key].set_core(membership[key]) #set core designation
        dictkeys = list(self.connectomeDict.keys()) #cast to list since we'll be modifying the dict
        for neuronKey in dictkeys:
            self.connectomeDict[neuronKey].set_synapseTypes() #update synapses and instantiate any relay neurons if needed
'''

NEW_APPLY_PARTITION = '''    def apply_partition(self, membership): #apply a partition to the network
        mergedNeurons = self.get_merged_neurons()
        for key in membership.keys():
            mergedNeurons[key].set_core(membership[key]) #set core designation
        dictkeys = list(self.connectomeDict.keys()) #cast to list since we'll be modifying the dict
        for neuronKey in dictkeys:
            self.connectomeDict[neuronKey].set_synapseTypes() #update synapses and instantiate any relay neurons if needed
        #relay axons are created by set_synapseTypes above and inherit their
        #neuron's core, so axon indexing has to run after it, not before
        self.update_core_axon_idx()

    def update_core_axon_idx(self): #assign each axon its per-core index
        #The host turns an input symbol into an axon index with
        #get_coreTypeIdx(), and map_to_hbm_fpga lays axons out in get_axons()
        #iteration order.  Both must be per core and must agree, so this walks
        #that same order and restarts the count on every core.
        self.get_axons()
        per_core = {}
        for key in self.axons:
            currAxon = self.axons[key]
            core = currAxon.get_core()
            idx = per_core.get(core, 0)
            currAxon.set_coreTypeIdx(idx)
            per_core[core] = idx + 1

    def get_core_axons(self, core): #axons on one core, in HBM order
        self.get_axons()
        return {k: a for k, a in self.axons.items() if a.get_core() == core}
'''

# ======================================================= compile_network.py
OLD_PARTITION = '''    networkConnectivity = connectome.get_part_format()

    #TODO: get rid of this, it's just for some quick and dirty debugging
    n_cores = 1
    # No partitioning
    if n_cores == 1:
        membership = {k: 0 for k in range(len(networkConnectivity))}
        #return {k: 0 for k, v in connectome.connectomeDict.items()}
         #return {k: 0 for k, v in axons.items()},{k: 0 for k, v in connections.items()}

    # Partition the network
    else:
        if (partLoad):
            membership = netPart(data = networkConnectivity,n_clusters = n_cores) #n_clusters is just the number of cores to partition the network across
        else:
            logging.error("partitioning library failed to load, multicore partitioning skipped")

    connectome.apply_partition(membership)
'''

NEW_PARTITION = '''    networkConnectivity = connectome.get_part_format()

    if membership is not None:
        #Supplied by the caller -- produced by noc_partition and reused as-is
        #by noc_routing.build_tables, so placement and routing come from one
        #assignment rather than two that have to be kept in step.
        pass
    elif n_cores == 1:
        membership = {k: 0 for k in range(len(networkConnectivity))}
    elif partLoad:
        membership = netPart(data = networkConnectivity, n_clusters = n_cores) #n_clusters is just the number of cores to partition the network across
    else:
        raise RuntimeError(
            "n_cores=%d was requested but no partition is available: the "
            "partitioning library did not import and no membership map was "
            "passed in.  Supply membership={neuron_key: core} (see "
            "noc_partition.partition) or use n_cores=1." % n_cores)

    connectome.apply_partition(membership)
'''

OLD_PARTITION_SIG = '''def partition(connectome, n_cores):
    """Creates adjacency list
'''

NEW_PARTITION_SIG = '''def partition(connectome, n_cores, membership=None):
    """Creates adjacency list
'''

OLD_MAP_LOOP = '''    hbm = {}

    rows_per_ptr = ceil(N_NG / DATA_PER_ROW) #the number of rows needed to represent one 'slot' in hbm for all neuron groups

    for core_idx in range(n_cores):
'''

NEW_MAP_LOOP = '''    hbm = {}

    rows_per_ptr = ceil(N_NG / DATA_PER_ROW) #the number of rows needed to represent one 'slot' in hbm for all neuron groups

    #Map only the cores that actually hold neurons.  Iterating range(n_cores)
    #would build empty structures for unused cores and, before the filters
    #below existed, gave every core a copy of the whole network.
    cores_used = connectome.get_cores_used()
    if len(cores_used) > n_cores:
        raise ValueError("partition uses %d cores but the topology has %d"
                         % (len(cores_used), n_cores))

    for core_idx in cores_used:
'''

OLD_AXON_FETCH = '''        axons = connectome.get_axons()
        #breakpoint()
        for axonKey in tqdm(axons): #iterate through all axons
'''

NEW_AXON_FETCH = '''        #only this core's axons -- their order here defines the per-core axon
        #index that update_core_axon_idx assigned
        axons = connectome.get_core_axons(core_idx)
        #breakpoint()
        for axonKey in tqdm(axons): #iterate through all axons
'''

OLD_NEURON_FETCH = '''        neurons = connectome.get_neurons()
        neurons = connectome.get_class_ordered_list()
        #indicies need to get reassigned to match the structure in HBM
'''

NEW_NEURON_FETCH = '''        #only this core's neurons, ordered by model, indices restarting at 0
        neurons = connectome.get_class_ordered_list(core=core_idx)
        #indicies need to get reassigned to match the structure in HBM
'''

OLD_COMPILE_SIG = '''def compileNetwork(
    loadFile=False, connectome=None, inputs=None, outputs=None):
'''

NEW_COMPILE_SIG = '''def compileNetwork(
    loadFile=False, connectome=None, inputs=None, outputs=None,
    n_cores=None, membership=None):
'''

OLD_COMPILE_BODY = '''        n_cores = get_cores()

    partition(connectome, n_cores)
'''

NEW_COMPILE_BODY = '''        if n_cores is None:
            n_cores = get_cores()

    partition(connectome, n_cores, membership=membership)
'''

CONNECTOME_EDITS = [
    ("apply_partition + per-core axon index", OLD_APPLY_PARTITION, NEW_APPLY_PARTITION),
]

COMPILE_EDITS = [
    ("partition() signature", OLD_PARTITION_SIG, NEW_PARTITION_SIG),
    ("partition() body", OLD_PARTITION, NEW_PARTITION),
    ("map_to_hbm_fpga core loop", OLD_MAP_LOOP, NEW_MAP_LOOP),
    ("map_to_hbm_fpga axon filter", OLD_AXON_FETCH, NEW_AXON_FETCH),
    ("map_to_hbm_fpga neuron filter", OLD_NEURON_FETCH, NEW_NEURON_FETCH),
    ("compileNetwork() signature", OLD_COMPILE_SIG, NEW_COMPILE_SIG),
    ("compileNetwork() body", OLD_COMPILE_BODY, NEW_COMPILE_BODY),
]

SENTINELS = {
    "connectome": "def update_core_axon_idx",
    "compile": "membership=membership",
}


def patch_one(path, edits, sentinel, check_only):
    src = io.open(path, encoding="utf-8").read()
    label = os.path.basename(path)

    if sentinel in src:
        print("ALREADY APPLIED  %s" % label)
        return 0

    ok = True
    for name, old, new in edits:
        n = src.count(old)
        if n == 1:
            print("  anchor OK        %-40s %s" % (name, label))
        else:
            print("  ANCHOR %s  %-40s %s (found %d)"
                  % ("MISSING" if n == 0 else "AMBIGUOUS", name, label, n))
            ok = False
    if not ok:
        return 1
    if check_only:
        return 0

    out = src
    for name, old, new in edits:
        out = out.replace(old, new, 1)

    backup = path + BACKUP_SUFFIX
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
        print("  backup   %s" % backup)
    io.open(path, "w", encoding="utf-8").write(out)
    print("  applied  %d/%d edits to %s" % (len(edits), len(edits), label))

    import py_compile
    try:
        py_compile.compile(path, doraise=True)
        print("  syntax   OK       %s" % label)
    except py_compile.PyCompileError as e:
        print("  SYNTAX ERROR      %s: %s" % (label, e))
        print("  restore with: cp %s %s" % (backup, path))
        return 1
    return 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv

    if len(args) != 2:
        print("usage: patch_percore_partition.py [--check] "
              "<connectome.py> <compile_network.py>")
        return 2

    paths = {}
    for p in args:
        if not os.path.isfile(p):
            print("FAIL  no such file: %s" % p)
            return 2
        base = os.path.basename(p)
        if base == "connectome.py":
            paths["connectome"] = p
        elif base == "compile_network.py":
            paths["compile"] = p
        else:
            print("FAIL  unexpected file: %s (need connectome.py and "
                  "compile_network.py)" % base)
            return 2

    if len(paths) != 2:
        print("FAIL  need one connectome.py and one compile_network.py")
        return 2

    rc = 0
    rc |= patch_one(paths["connectome"], CONNECTOME_EDITS,
                    SENTINELS["connectome"], check_only)
    rc |= patch_one(paths["compile"], COMPILE_EDITS,
                    SENTINELS["compile"], check_only)

    if rc:
        print("\nFAIL  nothing was written for any file that reported an anchor problem.")
        return 1
    if check_only:
        print("\nCHECK PASSED  re-run without --check to apply.")
    else:
        print("\nDONE.  Layer 3 (network.py, api.py) is still required before a "
              "partition reaches hardware:\n"
              "  - api.py must apply the partition BEFORE pad_models()\n"
              "  - network.py must build one fpga_compiler per core")
    return 0


if __name__ == "__main__":
    sys.exit(main())
