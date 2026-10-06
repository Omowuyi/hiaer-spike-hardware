#!/usr/bin/env python3
"""
Per-core runtime  --  layer 3, the last software piece of multi-core placement.

Patches TWO files; pass both paths, in either order:
    network.py   one fpga_compiler, output list, axon count and cutoff set
                 per core, and per-core input / execute / readback
    api.py       apply the partition BEFORE pad_models, route inputs to the
                 core that owns each axon, resolve spikes by (core, index)

THE ORDERING BUG THIS FIXES

api.py calls pad_models() during CRI_network.__init__, while partitioning ran
much later inside network.__init__ -> compileNetwork -> partition().  So
padding and cutoffs were computed with every neuron still on the default core
0.  Padding is per (core, model) to a multiple of 32 and cutoffs are per core,
so both are wrong unless the partition is applied first.  The source already
carried the note: "neurons are default to core ID 0, need to be fixed in the
connectome to assign correct coreIdx to neurons".

WHAT BECOMES PER CORE

  fpga_compiler          one per core, built from that core's HBM, that core's
                         output list, and coreID = that core.  The class
                         already took all three; nothing in it changes.
  num_outputs/num_inputs  counted within the core, not across the network
  cutoffs                 connectome.core_cutoffs[core]
  input_user/execute/     issued per core
  flush_spikes
  readMP                  reads are grouped by the core owning each neuron

SINGLE-CORE BEHAVIOUR

With one core in use every loop runs once and every command goes out with
coreOveride, exactly as before -- including the debugging case of running a
single-core network on a core other than 0.

  python3 patch_percore_runtime.py --check <network.py> <api.py>
  python3 patch_percore_runtime.py         <network.py> <api.py>
"""

import sys
import os
import shutil
import io

BACKUP_SUFFIX = ".before_percore_rt"

# ============================================================== network.py
OLD_NET_INIT = '''    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0,
                 syn_64bit = False, syn_delay = 0):
        self.coreOveride = coreOveride #TODO:this is for debugging
        # 64-bit Phase-2 synapse entries: doubles HBM footprint, needed for
        # per-synapse delay and STDP.  Must match syn_64bit_en in CMD 13.
        self.syn_64bit = syn_64bit
        # Network-wide synapse delay in timesteps, applied at compile time
        # so it is present the first time the rows are written.
        self.syn_delay = syn_delay
        self.hbm, self.numAxon = compileNetwork(
            loadFile=False,
            connectome = connectome,
            outputs=outputs  
        )
        self.outputs = outputs
        # TODO: this will need to be generalized for multiple networks
        axon_ptrs, ptrs, data = self.hbm[0] #This starts at 1 for whatever reason TODO: fix this so it's zero indexed
        self.num_inputs = len(connectome.get_axons()) #number of axons in the network
        self.num_outputs = len(connectome.get_neurons())
        self.outputs = outputs
        self.numNeurons=len(connectome.get_neurons())
        self.compiledNetwork = fpga_compiler(
            (axon_ptrs, ptrs, data), self.numNeurons, self.outputs, coreID = self.coreOveride
        )
        self.models = connectome.get_models()
        #TODO: program model start/stop in URAM -> do it in initialize network function
        self.stepNum = None
        self.simDump = simDump
        self.cutoffs = connectome.cutoffs
        if simDump:
            self.cmdDump = []
'''

NEW_NET_INIT = '''    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0,
                 syn_64bit = False, syn_delay = 0, membership = None,
                 n_cores = None):
        self.coreOveride = coreOveride #TODO:this is for debugging
        # 64-bit Phase-2 synapse entries: doubles HBM footprint, needed for
        # per-synapse delay and STDP.  Must match syn_64bit_en in CMD 13.
        self.syn_64bit = syn_64bit
        # Network-wide synapse delay in timesteps, applied at compile time
        # so it is present the first time the rows are written.
        self.syn_delay = syn_delay
        self.hbm, self.numAxon = compileNetwork(
            loadFile=False,
            connectome = connectome,
            outputs=outputs,
            n_cores = n_cores,
            membership = membership
        )
        self.outputs = outputs
        self.connectome = connectome
        # compileNetwork returns one HBM image per core that holds neurons.
        self.cores = sorted(self.hbm.keys())

        # Which coreID each core's commands are addressed to.  With a single
        # core that is coreOveride, so running one network on core N for
        # debugging behaves exactly as before; with several it is the core
        # itself.
        single = (len(self.cores) == 1)
        self.core_target = {c: (self.coreOveride if single else c)
                            for c in self.cores}

        allNeurons = connectome.get_neurons()
        self.compiledNetworks = {}
        self.core_num_outputs = {}
        self.core_num_inputs = {}
        for core in self.cores:
            axon_ptrs, ptrs, data = self.hbm[core]
            core_outputs = connectome.get_core_outputs_idx(core)
            # counted WITHIN the core -- num_outputs is the per-core neuron
            # ceiling the RTL compares spike addresses against, not a network
            # total
            n_neurons = len([n for n in allNeurons.values()
                             if n.get_core() == core])
            n_axons = len(connectome.get_core_axons(core))
            self.core_num_outputs[core] = n_neurons
            self.core_num_inputs[core] = n_axons
            self.compiledNetworks[core] = fpga_compiler(
                (axon_ptrs, ptrs, data), n_neurons, core_outputs,
                coreID = self.core_target[core]
            )

        # Aliases for the single-core callers that predate this change.
        primary = self.cores[0] if self.cores else 0
        self.primary_core     = primary
        self.compiledNetwork  = self.compiledNetworks[primary]
        self.num_inputs       = self.core_num_inputs[primary]
        self.num_outputs      = self.core_num_outputs[primary]
        self.numNeurons       = self.core_num_outputs[primary]
        self.models = connectome.get_models()
        self.stepNum = None
        self.simDump = simDump
        self.core_cutoffs = getattr(connectome, "core_cutoffs",
                                    {primary: connectome.cutoffs})
        self.cutoffs = connectome.cutoffs
        if simDump:
            self.cmdDump = []

    def _core_inputs(self, inputs):
        """Accept either a flat list (single core) or {core: [axon index]}."""
        if isinstance(inputs, dict):
            return inputs
        return {self.primary_core: inputs}
'''

OLD_NET_INIT_NETWORK = '''    def initalize_network(self):
        #breakpoint()
        if self.simDump:
            axon_ptrs, neuron_ptrs, synapses = self.compiledNetwork.create_script("test_config", simDump = True, syn_64bit = self.syn_64bit, syn_delay = self.syn_delay)
            self.cmdDump.append(axon_ptrs)
            self.cmdDump.append(neuron_ptrs)
            self.cmdDump.append(synapses)
            #breakpoint()
            global_cmd = write_parameters_simple(n_outputs=self.num_outputs, n_inputs=self.num_inputs, coreID=self.coreOveride, simDump = True)
            #breakpoint()
            self.cmdDump.append(global_cmd)
            for neuronModel, cutoff in zip(self.models, self.cutoffs):
                nt_cmd = write_neuron_type(cutoff, neuronModel.get_threshold(), neuronModel.get_neuronModel(), neuronModel.get_shift(), neuronModel.get_leak(), refractory_max=neuronModel.get_refractory_max(), dual_synapse_en=neuronModel.get_dual_synapse_en(), delay_value=neuronModel.get_delay_value(), shadow_uram_offset=neuronModel.get_shadow_uram_offset(), legacy_noise_en=neuronModel.get_legacy_noise_en(), soft_reset_en=neuronModel.get_soft_reset_en(), coreID=self.coreOveride, simDump = True)
                self.cmdDump.append(nt_cmd)
            clear_cmd = clear(self.numNeurons, simDump = True, coreID = self.coreOveride)
            self.cmdDump=self.cmdDump+clear_cmd
            self.stepNum = 0
        else:

            self.compiledNetwork.create_script("test_config", syn_64bit = self.syn_64bit, syn_delay = self.syn_delay)
            write_parameters_simple(n_outputs=self.num_outputs, n_inputs=self.num_inputs, coreID=self.coreOveride)
            for neuronModel, cutoff in zip(self.models, self.cutoffs):
            #TODO: write_neuron_type is missing core ID
                write_neuron_type(cutoff, neuronModel.get_threshold(), neuronModel.get_neuronModel(), neuronModel.get_shift(), neuronModel.get_leak(), refractory_max=neuronModel.get_refractory_max(), dual_synapse_en=neuronModel.get_dual_synapse_en(), delay_value=neuronModel.get_delay_value(), shadow_uram_offset=neuronModel.get_shadow_uram_offset(), legacy_noise_en=neuronModel.get_legacy_noise_en(), soft_reset_en=neuronModel.get_soft_reset_en(), coreID=self.coreOveride)
            clear(self.numNeurons, coreID = self.coreOveride)
            self.stepNum = 0
            #clear_read_buffer(coreID = self.coreOveride) #make sure no old data is still in the read buffer
'''

NEW_NET_INIT_NETWORK = '''    def initalize_network(self):
        #breakpoint()
        # Every core is programmed independently: its own synapse rows, its own
        # neuron count, its own model cutoffs.
        for core in self.cores:
            tgt      = self.core_target[core]
            compiler = self.compiledNetworks[core]
            cutoffs  = self.core_cutoffs.get(core, self.cutoffs)
            if self.simDump:
                axon_ptrs, neuron_ptrs, synapses = compiler.create_script("test_config", simDump = True, syn_64bit = self.syn_64bit, syn_delay = self.syn_delay)
                self.cmdDump.append(axon_ptrs)
                self.cmdDump.append(neuron_ptrs)
                self.cmdDump.append(synapses)
                global_cmd = write_parameters_simple(n_outputs=self.core_num_outputs[core], n_inputs=self.core_num_inputs[core], coreID=tgt, simDump = True)
                self.cmdDump.append(global_cmd)
                for neuronModel, cutoff in zip(self.models, cutoffs):
                    nt_cmd = write_neuron_type(cutoff, neuronModel.get_threshold(), neuronModel.get_neuronModel(), neuronModel.get_shift(), neuronModel.get_leak(), refractory_max=neuronModel.get_refractory_max(), dual_synapse_en=neuronModel.get_dual_synapse_en(), delay_value=neuronModel.get_delay_value(), shadow_uram_offset=neuronModel.get_shadow_uram_offset(), legacy_noise_en=neuronModel.get_legacy_noise_en(), soft_reset_en=neuronModel.get_soft_reset_en(), coreID=tgt, simDump = True)
                    self.cmdDump.append(nt_cmd)
                clear_cmd = clear(self.core_num_outputs[core], simDump = True, coreID = tgt)
                self.cmdDump=self.cmdDump+clear_cmd
            else:
                compiler.create_script("test_config", syn_64bit = self.syn_64bit, syn_delay = self.syn_delay)
                write_parameters_simple(n_outputs=self.core_num_outputs[core], n_inputs=self.core_num_inputs[core], coreID=tgt)
                for neuronModel, cutoff in zip(self.models, cutoffs):
                    write_neuron_type(cutoff, neuronModel.get_threshold(), neuronModel.get_neuronModel(), neuronModel.get_shift(), neuronModel.get_leak(), refractory_max=neuronModel.get_refractory_max(), dual_synapse_en=neuronModel.get_dual_synapse_en(), delay_value=neuronModel.get_delay_value(), shadow_uram_offset=neuronModel.get_shadow_uram_offset(), legacy_noise_en=neuronModel.get_legacy_noise_en(), soft_reset_en=neuronModel.get_soft_reset_en(), coreID=tgt)
                clear(self.core_num_outputs[core], coreID = tgt)
        self.stepNum = 0
'''

OLD_RUN_STEP = '''    def run_step(self,inputs,membranePotential=False):
        #breakpoint()
        if True: #self.stepNum <= self.maxTimeStep:
            if self.simDump:
                input_cmd = input_user(inputs, numAxons = self.num_inputs,  simDump = True,coreID = self.coreOveride)
                self.cmdDump.append(input_cmd)
                execute_cmd = execute(simDump = True,coreID = self.coreOveride)
                self.cmdDump.append(execute_cmd)
                if membranePotential:
                    read_cmd = read(self.numNeurons, simDump = True,coreID = self.coreOveride)
                    self.cmdDump.append(read_cmd)
                self.stepNum = self.stepNum +1
            else:
                #breakpoint()
                input_user(inputs, numAxons = self.num_inputs, coreID = self.coreOveride)
                #breakpoint()
                execute(coreID = self.coreOveride)
                spike_results = flush_spikes(coreID = self.coreOveride)
                #time.sleep(.2)
                self.stepNum = self.stepNum +1
                if membranePotential:
                    result = read(self.numNeurons,coreID = self.coreOveride)  # TODO make read return the values instead of just printing to terminal
                    return result, spike_results
'''

NEW_RUN_STEP = '''    def run_step(self,inputs,membranePotential=False):
        #breakpoint()
        # `inputs` is either a flat list of axon indices (single core) or
        # {core: [axon index]} -- an axon index is per core, so with several
        # cores the caller has to say which core each one belongs to.
        core_inputs = self._core_inputs(inputs)
        if True: #self.stepNum <= self.maxTimeStep:
            if self.simDump:
                for core in self.cores:
                    tgt = self.core_target[core]
                    input_cmd = input_user(core_inputs.get(core, []), numAxons = self.core_num_inputs[core],  simDump = True,coreID = tgt)
                    self.cmdDump.append(input_cmd)
                    execute_cmd = execute(simDump = True,coreID = tgt)
                    self.cmdDump.append(execute_cmd)
                    if membranePotential:
                        read_cmd = read(self.core_num_outputs[core], simDump = True,coreID = tgt)
                        self.cmdDump.append(read_cmd)
                self.stepNum = self.stepNum +1
            else:
                # Load every core's inputs and start them all before draining
                # any of them: a spike carries the timestep it was emitted in,
                # so the cores must advance together, not one after another.
                for core in self.cores:
                    input_user(core_inputs.get(core, []), numAxons = self.core_num_inputs[core], coreID = self.core_target[core])
                for core in self.cores:
                    execute(coreID = self.core_target[core])
                spike_results = []
                for core in self.cores:
                    spike_results = spike_results + flush_spikes(coreID = self.core_target[core])
                self.stepNum = self.stepNum +1
                if membranePotential:
                    result = []
                    for core in self.cores:
                        core_result = read(self.core_num_outputs[core],coreID = self.core_target[core])  # TODO make read return the values instead of just printing to terminal
                        if core_result:
                            result = result + [tuple(r) + (core,) for r in core_result]
                    return result, spike_results
'''

OLD_READMP = '''    def readMP(self,neuronList):
        result = readSelect(neuronList)
'''

NEW_READMP = '''    def readMP(self,neuronList,core=None):
        #neuronList holds per-core indices, so the read has to be addressed to
        #the core that owns them
        if core is None:
            core = self.primary_core
        result = readSelect(neuronList, coreID = self.core_target.get(core, core))
'''

NET_EDITS = [
    ("network.__init__", OLD_NET_INIT, NEW_NET_INIT),
    ("initalize_network", OLD_NET_INIT_NETWORK, NEW_NET_INIT_NETWORK),
    ("run_step", OLD_RUN_STEP, NEW_RUN_STEP),
    ("readMP", OLD_READMP, NEW_READMP),
]

# ================================================================== api.py
OLD_API_SIG = '''    def __init__(
            self, axons, connections, outputs, target=None, simDump=False, coreID=0,
            syn_64bit=False, syn_delay=0
    ):
'''

NEW_API_SIG = '''    def __init__(
            self, axons, connections, outputs, target=None, simDump=False, coreID=0,
            syn_64bit=False, syn_delay=0, membership=None, n_cores=None
    ):
'''

OLD_API_PAD = '''        if self.target == "CRI":
            logging.info("Initilizing to run on hardware")
            self.connectome.pad_models()
            ##neurons are default to core ID 0, need to be fixed in the connectome to assign correct coreIdx to neurons
            # formatedOutputs = self.connectome.get_core_outputs_idx(coreID)
            formatedOutputs = self.connectome.get_outputs_idx()
            print("formatedOutputs:", formatedOutputs)
            self.CRI = network(
                self.connectome,
                formatedOutputs,
                simDump=simDump,
                coreOveride=coreID,
                syn_64bit=syn_64bit,
                syn_delay=syn_delay,
            )
'''

NEW_API_PAD = '''        if self.target == "CRI":
            logging.info("Initilizing to run on hardware")
            # The partition has to be applied BEFORE pad_models: padding is per
            # (core, model) to a multiple of 32 and cutoffs are per core, so
            # both are wrong if every neuron is still on the default core 0
            # when the padding runs.
            self.membership = membership
            self.n_cores = n_cores
            if membership is not None:
                self.connectome.apply_partition(membership)
            self.connectome.pad_models()
            formatedOutputs = self.connectome.get_outputs_idx()
            print("formatedOutputs:", formatedOutputs)
            self.CRI = network(
                self.connectome,
                formatedOutputs,
                simDump=simDump,
                coreOveride=coreID,
                syn_64bit=syn_64bit,
                syn_delay=syn_delay,
                membership=membership,
                n_cores=n_cores,
            )
'''

OLD_API_INPUTS = '''        formated_inputs = [
            self.connectome.get_neuron_by_key(symbol).get_coreTypeIdx()
            for symbol in inputs
        ]  # convert symbols to internal indicies
'''

NEW_API_INPUTS = '''        # An axon index is per core, so inputs are grouped by the core that
        # owns the axon.  With one core this is a single-entry dict and the
        # order within it is the order the flat list had.
        formated_inputs = {}
        for symbol in inputs:
            axonObj = self.connectome.get_neuron_by_key(symbol)
            formated_inputs.setdefault(axonObj.get_core(), []).append(
                axonObj.get_coreTypeIdx())
        if self.target != "CRI":
            formated_inputs = [i for core in sorted(formated_inputs)
                               for i in formated_inputs[core]]
'''

OLD_API_SPIKE_MP = '''                    spikeList = spikeResult[0]
                    # we currently ignore the run execution counter
                    spikeList = [
                        self.connectome.get_neuron_by_hbmIdx(spike[1]).get_user_key()
                        for spike in spikeList
                    ]
'''

NEW_API_SPIKE_MP = '''                    spikeList = spikeResult[0]
                    # we currently ignore the run execution counter.  A spike is
                    # (counter, per-core index, core); the pair identifies the
                    # neuron, the index alone does not.
                    spikeList = [
                        self.connectome.get_neuron_by_core_idx(
                            spike[2] if len(spike) > 2 else 0,
                            spike[1]).get_user_key()
                        for spike in spikeList
                    ]
'''

OLD_API_SPIKE_PLAIN = '''                    spikeResult = self.CRI.run_step(formated_inputs, membranePotential)
                    # breakpoint()
                    spikeList = spikeResult[0]
                    spikeList = [
                        self.connectome.get_neuron_by_hbmIdx(spike[1]).get_user_key()
                        for spike in spikeList
                    ]
'''

NEW_API_SPIKE_PLAIN = '''                    spikeResult = self.CRI.run_step(formated_inputs, membranePotential)
                    # breakpoint()
                    spikeList = spikeResult[0]
                    spikeList = [
                        self.connectome.get_neuron_by_core_idx(
                            spike[2] if len(spike) > 2 else 0,
                            spike[1]).get_user_key()
                        for spike in spikeList
                    ]
'''

OLD_API_READMP = '''        if self.target == "CRI":
            formated_inputs = [
                self.connectome.get_neuron_by_key(symbol).get_hbmIdx()
                for symbol in neuronList
            ]
            results = self.CRI.readMP(formated_inputs)
            formatedResults = [(self.connectome.get_neuron_by_hbmIdx(element[0]).get_user_key(),element[3]) for element in results] #each membrane potential contains (membraneIdx, row, column, potential)
            return formatedResults
'''

NEW_API_READMP = '''        if self.target == "CRI":
            # Group the requested neurons by core: an index is only meaningful
            # alongside the core it belongs to, and each core is read
            # separately.
            byCore = {}
            for symbol in neuronList:
                neuronObj = self.connectome.get_neuron_by_key(symbol)
                byCore.setdefault(neuronObj.get_core(), []).append(
                    neuronObj.get_hbmIdx())
            formatedResults = []
            for core in sorted(byCore):
                results = self.CRI.readMP(byCore[core], core=core)
                #each membrane potential contains (membraneIdx, row, column, potential)
                formatedResults = formatedResults + [
                    (self.connectome.get_neuron_by_core_idx(core, element[0]).get_user_key(),
                     element[3]) for element in results]
            return formatedResults
'''

API_EDITS = [
    ("CRI_network signature", OLD_API_SIG, NEW_API_SIG),
    ("partition before pad_models", OLD_API_PAD, NEW_API_PAD),
    ("per-core input routing", OLD_API_INPUTS, NEW_API_INPUTS),
    ("spike resolution (membrane path)", OLD_API_SPIKE_MP, NEW_API_SPIKE_MP),
    ("spike resolution (plain path)", OLD_API_SPIKE_PLAIN, NEW_API_SPIKE_PLAIN),
    ("readMP per core", OLD_API_READMP, NEW_API_READMP),
]

SENTINELS = {
    "network.py": "def _core_inputs",
    "api.py": "get_neuron_by_core_idx",
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
            print("  anchor OK        %-36s %s" % (name, label))
        else:
            print("  ANCHOR %s  %-36s %s (found %d)"
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
        print("usage: patch_percore_runtime.py [--check] <network.py> <api.py>")
        return 2

    paths = {}
    for p in args:
        if not os.path.isfile(p):
            print("FAIL  no such file: %s" % p)
            return 2
        base = os.path.basename(p)
        if base in ("network.py", "api.py"):
            paths[base] = p
        else:
            print("FAIL  unexpected file: %s (need network.py and api.py)" % base)
            return 2

    if len(paths) != 2:
        print("FAIL  need one network.py and one api.py")
        return 2

    rc = 0
    rc |= patch_one(paths["network.py"], NET_EDITS, SENTINELS["network.py"], check_only)
    rc |= patch_one(paths["api.py"], API_EDITS, SENTINELS["api.py"], check_only)

    if rc:
        print("\nFAIL  nothing written for any file that reported an anchor problem.")
        return 1
    if check_only:
        print("\nCHECK PASSED  re-run without --check to apply.")
    else:
        print("""
DONE.  The software path now supports a real partition end to end.

Single core is unchanged: membership=None puts every neuron on core 0, every
loop runs once, and commands go out with coreOveride as before.  Run the 42
hardware tests to confirm that before going further.

Multi core:
    from noc_partition import partition, Topology
    asg = partition(edges, num_neurons, Topology(cores=16))
    net = CRI_network(axons, connections, outputs,
                      membership=asg.neuron_to_core, n_cores=16)
and the same neuron_to_core feeds noc_routing.build_tables, so placement and
routing come from one assignment.""")
    return 0


if __name__ == "__main__":
    sys.exit(main())
