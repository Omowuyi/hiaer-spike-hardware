from hs_bridge.compile_network import compileNetwork
from hs_bridge.FPGA_Execution.fpga_compiler import fpga_compiler
import subprocess
import numpy as np
import time
import functools
import operator
import logging
from hs_bridge.config import *
from hs_bridge.FPGA_Execution.fpga_controller import readSelect, write_parameters_simple, write_neuron_type, clear, step_input, read, execute, write_synapse_row, input_user, flush_spikes, clear_read_buffer, cont_execute, cont_execute_sim_overide

class network:
    """A class for creating networks to be run on the CRI hardware

    Attributes
    ----------
    inputs : dict
        Dictionary specifying inputs to the network. Key, Time Step Value, TODO are these axons or neurons
    hbmRecord : dict
        Dictionary specifying the hbm structure for each core. Key: core number Value: tuple of (pointer,data) where pointer is a numpy array and data is a list of lists of tuples.
    outputs : dict
        Dictionary specifying output neurons of the network. 
    axonLength : int
        number of axons specified in the network
    self.numNeuron : int
        number of neurons specified in the network
    """

    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0,
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

    def get_uram_addr(cutoff):
        pass


    #def program_neuron_models(models):
    #    #TODO: this function seems to be unused
    #    for cutoff,model in zip(self.cutoffs,models):
    #        startAddr,stopAddr = get_uram_addr(cutoff) #TODO: implement
    #        write_neuron_type(startAddr, stopAddr, model.get_thershold(),model.get_neuron_model(),model.get_shift(),mode.get(leak),sramAddr)

    def initalize_network(self):
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

    def set_perturbMag(self,perturbMag):
        if self.simDump:
                #breakpoint()
                param_cmd = write_parameters(2, self.voltageThresh, n_outputs=self.num_outputs, n_inputs=self.num_inputs, simDump = True, leak=self.leak, shift=perturbMag, coreID = self.coreOveride)
                self.cmdDump.append(param_cmd)

        else:
                write_parameters(3, self.voltageThresh, n_outputs=self.num_outputs, n_inputs=self.num_inputs, simDump = False, leak=self.leak, shift=perturbMag, coreID = self.coreOveride)

    def run_step(self,inputs,membranePotential=False):
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
                # flush_spikes returns (spikeOutput, latency, hbmAcc) per
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
                self.stepNum = self.stepNum +1
                if membranePotential:
                    result = []
                    for core in self.cores:
                        core_result = read(self.core_num_outputs[core],coreID = self.core_target[core])  # TODO make read return the values instead of just printing to terminal
                        if core_result:
                            result = result + [tuple(r) + (core,) for r in core_result]
                    return result, spike_results
                else: 
                    return spike_results
        else:
            logging.warning("run_step did nothing, network has already finished all timesteps")

    def run_cont(self,inputs):
            if self.simDump:
                dump = cont_execute_sim_overide(inputs, numAxons = self.num_inputs)
                for element in dump:
                    self.cmdDump.append(element)
            else:
                result = cont_execute(inputs, numAxons = self.num_inputs, steps = len(inputs)-1, coreID = self.coreOveride)
                #print(read(self.numNeurons,coreID = self.coreOveride))

                return result

    def readMP(self,neuronList,core=None):
        #neuronList holds per-core indices, so the read has to be addressed to
        #the core that owns them
        if core is None:
            core = self.primary_core
        result = readSelect(neuronList, coreID = self.core_target.get(core, core))
        #take neuron list and compute neuron indicies
        #call selectRead with potentials
        #return
        return result


    def read_synapse(self,preIndex, postIndex, axonFlag = False):
        if self.simDump:
            logging.error("read_synapse commands not added to simDump")
        else:
            #TODO: it optionally might be nice to be able to read from the actual hardware
            if axonFlag:
                pntrs = self.hbm[0][0]
                neuron_type = 0
            else:
                pntrs = self.hbm[0][1]
                neuron_type = 1
    
            synapseRange = pntrs.flatten()[preIndex]
            synapses = self.hbm[0][2][synapseRange[0]:synapseRange[1]+1]
            
            rowIdx = (postIndex[0]*2 + 1) if (postIndex[1]//DATA_PER_ROW == 0) else postIndex[0]*2
            columnIdx = postIndex[1]%DATA_PER_ROW
            synapseIdx = [rowIdx,columnIdx]
            return synapses[synapseIdx[0]][synapseIdx[1]]

    def sim_flush(self, file):
        dmpStr = ""
        #breakpoint()
        if self.simDump:
            cmdDump = functools.reduce(operator.concat, self.cmdDump)
            with open(file, 'w') as f:
                for item in cmdDump:
                    f.write("%s\n" % item)
                    dmpStr = dmpStr + item + "\n"
            return dmpStr
        else:
            raise Exception("simdump was not set to True at object creation. No commands to flush")

    def write_synapse(self,preIndex, postIndex, weight, axonFlag = False):
#TODO: combine read and write synapse to avoid duplicating code
        if self.simDump:
            logging.warning("write_synapse commands not added to simDump, not implemented yet")
        else:
            if axonFlag:
                pntrs = self.hbm[0][0]
                neuron_type = 0
            else:
                pntrs = self.hbm[0][1]
                neuron_type = 1

            synapseRange = pntrs.flatten()[preIndex]
            synapses = self.hbm[0][2][synapseRange[0]:synapseRange[1]+1]
            rowIdx = (postIndex[0]*2 + 1) if (postIndex[1]//DATA_PER_ROW == 0) else postIndex[0]*2
            columnIdx = postIndex[1]%DATA_PER_ROW

            synapseIdx = [rowIdx,columnIdx]
            oldSynapse = synapses[synapseIdx[0]][synapseIdx[1]]
            row = synapses[synapseIdx[0]]
            row[columnIdx] = (oldSynapse[0],oldSynapse[1],weight)
            write_synapse_row(synapseRange[0]+synapseIdx[0], row, simDump = False, coreID = self.coreOveride)
            
           #This appears to actually update the values in hbm
                
