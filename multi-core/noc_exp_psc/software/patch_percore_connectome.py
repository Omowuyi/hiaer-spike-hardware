#!/usr/bin/env python3
"""
Per-core indexing for connectome.py  --  layer 1 of multi-core placement.

WHAT THIS CHANGES

coreTypeIdx and hbmIdx are currently assigned by enumerate() over every neuron
in the connectome, sorted by neuron model, with no core term.  The compiler
turns coreTypeIdx into the hardware address (row = idx // N_NG, column =
idx % N_NG), so with a real partition every core would be handed indices from
one global sequence and neurons would land at the wrong URAM addresses.

After this patch both indices restart at 0 for each core, and pad_models
computes its model cutoffs per core instead of once for the whole network.

SINGLE-CORE EQUIVALENCE

With every neuron on core 0 -- which is what partition() forces today -- the
output is identical to the current code.  The sort key becomes
(core, neuronModel); with one core that is the old key, and Python's sort is
stable so ties keep insertion order exactly as before.  .cutoffs keeps its
current meaning (the core-0 list), so network.py is unaffected until it is
changed deliberately.

  python3 patch_percore_connectome.py --check   <path to connectome.py>
  python3 patch_percore_connectome.py           <path to connectome.py>
"""

import sys
import os
import shutil
import io

BACKUP_SUFFIX = ".before_percore"

# ---------------------------------------------------------------- edit 1
OLD_UPDATE_COREIDX = '''    def update_class_ordered_coreIdx(self):# return a list of neurons by order of their neuron model
        self.get_neurons() #update neurons dictionary
        dict_list=list(self.neurons.items())
        dict_list.sort(key=lambda x: x[1].neuronModel) #sort by neuron class
        #breakpoint()
        for idx, elem in enumerate(dict_list):
            elem[1].coreTypeIdx = idx
'''

NEW_UPDATE_COREIDX = '''    def update_class_ordered_coreIdx(self):# assign the per-core hardware index
        self.get_neurons() #update neurons dictionary
        dict_list=list(self.neurons.items())
        #sort by core first, then by neuron class.  Python's sort is stable, so
        #within one (core, model) group insertion order is preserved -- with a
        #single core this is the previous ordering unchanged.
        dict_list.sort(key=lambda x: (x[1].get_core(), x[1].neuronModel))
        #coreTypeIdx restarts at 0 on every core.  The compiler turns it into
        #row = idx // N_NG and column = idx % N_NG, so it must be the index
        #WITHIN a core, not a position in a global sequence.
        per_core = {}
        for elem in dict_list:
            core = elem[1].get_core()
            idx = per_core.get(core, 0)
            elem[1].coreTypeIdx = idx
            per_core[core] = idx + 1
'''

# ---------------------------------------------------------------- edit 2
OLD_CLASS_ORDERED = '''    def get_class_ordered_list(self):# return a list of neurons by order of their neuron model
        self.get_neurons() #update neurons dictionary
        dict_list=list(self.neurons.items())
        dict_list.sort(key=lambda x: x[1].neuronModel) #sort by neuron class
        #reassign index
        for idx,neuron in enumerate(dict_list):
            neuron[1].set_hbmIdx(idx)

        return dict_list
'''

NEW_CLASS_ORDERED = '''    def get_class_ordered_list(self, core=None):# neurons ordered by core then model
        self.get_neurons() #update neurons dictionary
        dict_list=list(self.neurons.items())
        dict_list.sort(key=lambda x: (x[1].get_core(), x[1].neuronModel))
        #reassign index -- hbmIdx restarts per core so that it matches
        #coreTypeIdx, which is the address the hardware reports in the spike
        #packet alongside CORE_ID.
        per_core = {}
        for neuronEntry in dict_list:
            c = neuronEntry[1].get_core()
            idx = per_core.get(c, 0)
            neuronEntry[1].set_hbmIdx(idx)
            per_core[c] = idx + 1

        self.build_hbm_index()
        if core is not None:
            return [elem for elem in dict_list if elem[1].get_core() == core]
        return dict_list
'''

# ---------------------------------------------------------------- edit 3
OLD_PAD_MODELS = '''    def pad_models(self): #add 'dummy' neurons to the connectome so that definitions of neurons for a model line up in HBM correctly
        #breakpoint()
        pad_idx = 0
        model_list = self.get_models()
        cutoffs = []
        cutoff = 0
        for model in model_list:
            currList = self.get_neuron_by_model(model)
            if len(currList)%32 != 0:
                remainder = 32-(len(currList)%32)
                for i in range(remainder):
                    padNeuron = neuron('pad'+str(pad_idx), neuronType="neuron", neuronModel=model, output=False, dummy=False)
                    pad_idx = pad_idx + 1
                    self.addNeuron(padNeuron)
                cutoff += len(currList)+remainder
            else:
                cutoff += len(currList)
            cutoffs.append(cutoff)
        self.update_class_ordered_coreIdx()
        self.cutoffs = cutoffs
'''

NEW_PAD_MODELS = '''    def pad_models(self): #add 'dummy' neurons so each model's region lines up in HBM
        #breakpoint()
        pad_idx = 0
        model_list = self.get_models()
        #Pad and compute cutoffs PER CORE.  The cutoffs are URAM model
        #boundaries written by write_neuron_type, and each core has its own
        #address space, so a single global cutoff list is only correct when
        #every neuron sits on one core.
        core_cutoffs = {}
        for core in self.get_cores_used():
            cutoffs = []
            cutoff = 0
            for model in model_list:
                currList = [n for n in self.get_neuron_by_model(model)
                            if n.get_core() == core]
                if len(currList)%32 != 0:
                    remainder = 32-(len(currList)%32)
                    for i in range(remainder):
                        padNeuron = neuron('pad'+str(pad_idx), neuronType="neuron", neuronModel=model, output=False, dummy=False)
                        padNeuron.set_core(core)
                        pad_idx = pad_idx + 1
                        self.addNeuron(padNeuron)
                    cutoff += len(currList)+remainder
                else:
                    cutoff += len(currList)
                cutoffs.append(cutoff)
            core_cutoffs[core] = cutoffs
        self.update_class_ordered_coreIdx()
        self.core_cutoffs = core_cutoffs
        #.cutoffs keeps its existing meaning -- the core-0 list -- so callers
        #that have not been made core-aware yet behave exactly as before.
        self.cutoffs = core_cutoffs.get(0, [])
'''

# ---------------------------------------------------------------- edit 4
OLD_LOOKUP_ANCHOR = '''    def get_neuron_by_hbmIdx(self, idx): #get neuron by coreTypeIdx
        for key in self.connectomeDict:
            # axons and
            if (
                self.connectomeDict[key].get_neuron_type() == "neuron"
                and self.connectomeDict[key].get_hbmIdx() == idx
            ):
                return self.connectomeDict[key]
'''

NEW_LOOKUP = OLD_LOOKUP_ANCHOR + '''
    def get_cores_used(self): #sorted list of cores holding at least one neuron
        self.get_neurons()
        return sorted({n.get_core() for n in self.neurons.values()})

    def build_hbm_index(self): #(core, hbmIdx) -> neuron, so readback is not a scan
        self._hbm_index = {}
        for key in self.connectomeDict:
            currNeuron = self.connectomeDict[key]
            if (currNeuron.get_neuron_type() == "neuron"
                    and currNeuron.get_hbmIdx() is not None):
                self._hbm_index[(currNeuron.get_core(),
                                 currNeuron.get_hbmIdx())] = currNeuron
        return self._hbm_index

    def get_neuron_by_core_idx(self, core, idx): #resolve a spike to its neuron
        #The spike packet carries CORE_ID and a per-core address; the pair is
        #what identifies a neuron once more than one core is in use.
        index = getattr(self, "_hbm_index", None)
        if index is None:
            index = self.build_hbm_index()
        currNeuron = index.get((core, idx))
        if currNeuron is None:
            #index may predate a re-assignment; rebuild once before giving up
            currNeuron = self.build_hbm_index().get((core, idx))
        return currNeuron
'''

EDITS = [
    ("update_class_ordered_coreIdx", OLD_UPDATE_COREIDX, NEW_UPDATE_COREIDX),
    ("get_class_ordered_list", OLD_CLASS_ORDERED, NEW_CLASS_ORDERED),
    ("pad_models", OLD_PAD_MODELS, NEW_PAD_MODELS),
    ("per-core lookup helpers", OLD_LOOKUP_ANCHOR, NEW_LOOKUP),
]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv

    if not args:
        print("usage: patch_percore_connectome.py [--check] <path to connectome.py>")
        return 2
    path = args[0]

    if not os.path.isfile(path):
        print("FAIL  no such file: %s" % path)
        return 2

    src = io.open(path, encoding="utf-8").read()

    # already applied?
    if "def get_neuron_by_core_idx" in src:
        print("ALREADY APPLIED  %s contains get_neuron_by_core_idx" % path)
        return 0

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
        print("\nFAIL  anchors do not match this file -- nothing written.")
        return 1

    if check_only:
        print("\nCHECK PASSED  4/4 anchors match.  Re-run without --check to apply.")
        return 0

    out = src
    for name, old, new in EDITS:
        out = out.replace(old, new, 1)

    backup = path + BACKUP_SUFFIX
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
        print("\nbackup   %s" % backup)
    else:
        print("\nbackup   %s already exists, left alone" % backup)

    io.open(path, "w", encoding="utf-8").write(out)
    print("applied  4/4 edits to %s" % path)

    import py_compile
    try:
        py_compile.compile(path, doraise=True)
        print("syntax   OK")
    except py_compile.PyCompileError as e:
        print("SYNTAX ERROR after patch: %s" % e)
        print("restore with: cp %s %s" % (backup, path))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
