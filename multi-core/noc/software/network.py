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

    def __init__(self, connectome, outputs, simDump = False, coreOveride = 0):
        self.coreOveride = coreOveride #TODO:this is for debugging
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

    def get_uram_addr(cutoff):
        pass


    #def program_neuron_models(models):
    #    #TODO: this function seems to be unused
    #    for cutoff,model in zip(self.cutoffs,models):
    #        startAddr,stopAddr = get_uram_addr(cutoff) #TODO: implement
    #        write_neuron_type(startAddr, stopAddr, model.get_thershold(),model.get_neuron_model(),model.get_shift(),mode.get(leak),sramAddr)

    def initalize_network(self):
        #breakpoint()
        if self.simDump:
            axon_ptrs, neuron_ptrs, synapses = self.compiledNetwork.create_script("test_config", simDump = True)
            self.cmdDump.append(axon_ptrs)
            self.cmdDump.append(neuron_ptrs)
            self.cmdDump.append(synapses)
            #breakpoint()
            global_cmd = write_parameters_simple(n_outputs=self.num_outputs, n_inputs=self.num_inputs, coreID=self.coreOveride, simDump = True)
            #breakpoint()
            self.cmdDump.append(global_cmd)
            for neuronModel, cutoff in zip(self.models, self.cutoffs):
                nt_cmd = write_neuron_type(cutoff, neuronModel.get_threshold(), neuronModel.get_neuronModel(), neuronModel.get_shift(), neuronModel.get_leak(), refractory_max=neuronModel.get_refractory_max(), dual_synapse_en=neuronModel.get_dual_synapse_en(), delay_value=neuronModel.get_delay_value(), shadow_uram_offset=neuronModel.get_shadow_uram_offset(), legacy_noise_en=neuronModel.get_legacy_noise_en(), coreID=self.coreOveride, simDump = True)
                self.cmdDump.append(nt_cmd)
            clear_cmd = clear(self.numNeurons, simDump = True, coreID = self.coreOveride)
            self.cmdDump=self.cmdDump+clear_cmd
            self.stepNum = 0
        else:

            self.compiledNetwork.create_script("test_config")
            write_parameters_simple(n_outputs=self.num_outputs, n_inputs=self.num_inputs, coreID=self.coreOveride)
            for neuronModel, cutoff in zip(self.models, self.cutoffs):
            #TODO: write_neuron_type is missing core ID
                write_neuron_type(cutoff, neuronModel.get_threshold(), neuronModel.get_neuronModel(), neuronModel.get_shift(), neuronModel.get_leak(), refractory_max=neuronModel.get_refractory_max(), dual_synapse_en=neuronModel.get_dual_synapse_en(), delay_value=neuronModel.get_delay_value(), shadow_uram_offset=neuronModel.get_shadow_uram_offset(), legacy_noise_en=neuronModel.get_legacy_noise_en(), coreID=self.coreOveride)
            clear(self.numNeurons, coreID = self.coreOveride)
            self.stepNum = 0
            #clear_read_buffer(coreID = self.coreOveride) #make sure no old data is still in the read buffer

    def set_perturbMag(self,perturbMag):
        if self.simDump:
                #breakpoint()
                param_cmd = write_parameters(2, self.voltageThresh, n_outputs=self.num_outputs, n_inputs=self.num_inputs, simDump = True, leak=self.leak, shift=perturbMag, coreID = self.coreOveride)
                self.cmdDump.append(param_cmd)

        else:
                write_parameters(3, self.voltageThresh, n_outputs=self.num_outputs, n_inputs=self.num_inputs, simDump = False, leak=self.leak, shift=perturbMag, coreID = self.coreOveride)

    def run_step(self,inputs,membranePotential=False):
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

    def readMP(self,neuronList):
        result = readSelect(neuronList)
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
                
