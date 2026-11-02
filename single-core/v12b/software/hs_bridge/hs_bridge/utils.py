import copy
import logging

class synapse:
    #postsynapticNeuron = None
    #weight = None
    #synapseType = None
    def __init__(self,presynapticNeuron, postsynapticNeuron, weight):
        self.presynapticNeuron = presynapticNeuron
        self.postsynapticNeuron = postsynapticNeuron
        self.weight = weight
        self.synapseType = None
        self.colIndex = None
        self.rowIndex = None
    def get_presynapticNeuron(self):
        return self.presynapticNeuron
    def get_postsynapticNeuron(self):
        return self.postsynapticNeuron
    def set_synapseType(self):
        #TODO: check for None
        if (self.postsynapticNeuron and self.presynapticNeuron):
            if(self.postsynapticNeuron.get_core() != self.presynapticNeuron.get_core()):
                self.synapseType = "hetero"
            else:
                self.synapseType = "homo"
        else:
            raise Exception("core is None")
    def get_weight(self):
        return self.weight
    def set_weight(self, newWeight):
        self.weight = newWeight
    def set_index(self, newRowIndex, newColIndex):
        self.rowIndex = newRowIndex
        self.colIndex = newColIndex
    def get_index(self):
        return self.rowIndex, self.colIndex
    def __repr__(self):
        return self.obj2string()
    def __str__(self):
        return self.obj2string()
    def obj2string(self):
        return "("+str(self.postsynapticNeuron.get_user_key())+", "+str(self.weight)+", "+str(self.synapseType)+")"

class neuron:
    globalAxonCount = 0 #STATIC total number of axons
    globalNeuronCount = 0 #STATIC total number of nonAxon neurons
    globalCount = 0 #STATIC total number of both axons and neurons

    #globalIdx = None #Index unique among all neurons/axons
    #globalTypeIdx = None #Index unique among neurons of the same type
    #userKey = None
    #coreIdx = None ##Index unique among all neurons/axons in local core
    #coreTypeIdx = None #Index unique among neurons of the same type in local core
    #core = None
    #neuronType = None
    #synapses = None
    def __init__(self, userKey, neuronType, output = False):
        self.userKey = userKey
        self.neuronType = neuronType
        if (neuronType == 'axon'):
            self.output = False
            self.globalTypeIdx = copy.deepcopy(neuron.globalAxonCount)
            neuron.globalAxonCount += 1
        if (neuronType == 'neuron'):
            self.output = output
            self.globalTypeIdx = copy.deepcopy(neuron.globalNeuronCount)
            neuron.globalNeuronCount += 1
            self.output = output
        self.globalIdx = copy.deepcopy(neuron.globalCount)
        neuron.globalCount += 1
        self.core = 0
        self.coreTypeIdx = self.globalTypeIdx
        self.coreIdx = self.globalIdx
        self.synapses = []
    @classmethod
    def reset_count(cls):
        #resets counting variables for neuron class
        #breakpoint()
        cls.globalAxonCount = 0
        cls.globalNeuronCount = 0
        cls.globalCount = 0
    def addSynapse(self,postsynapticNeuron,weight):
        newSynapse = synapse(self,postsynapticNeuron,weight)
        self.synapses.append(newSynapse)
    def get_output(self):
        return self.output
    def get_user_key(self):
        return self.userKey
    def get_synapses(self):
        return self.synapses
    def get_neuron_type(self):
        return self.neuronType
    def set_core(self,core):
        self.core = core
    def get_core(self):
        return self.core
    def set_coreIdx(self,coreIdx):
        self.coreIdx = coreIdx
    def get_coreIdx(self):
        return self.coreIdx
    def set_coreTypeIdx(self,coreTypeIdx):
        self.coreTypeIdx = coreTypeIdx
    def get_coreTypeIdx(self):
        return self.coreTypeIdx
    def set_globalIdx(self,globalIdx):
        self.globalIdx = globalIdx
    def get_globalIdx(self):
        return self.globalIdx
    def get_synapse(self, postsynapticKey):
        canidateSynapses = [currSynapse for currSynapse in self.synapses if currSynapse.get_postsynapticNeuron().get_user_key()==postsynapticKey]
        if (len(canidateSynapses) == 0):
            logging.error("Neuron has no synapse to specified postsynaptic neuron")
        else:
            if (len(canidateSynapses) != 1):
                logging.error("Neuron has two synapses to the same postsynaptic neuron")
            else:
                return canidateSynapses[0]
    def set_synapseTypes(self):
        for synapse in self.synapses:
            synapse.set_synapseType()
    def __repr__(self):
        return self.obj2string()
    def __str__(self):
        return self.obj2string()
    def obj2string(self):
        string =  "userID: "+str(self.userKey)+", GlobalID: "+str(self.globalIdx)+", Core Assignment: "+str(self.core)+", Synapses: "
        for currSynapse in self.synapses:
            string = string + str(currSynapse)
        return string
    def get_output(self):
        return self.output

class connectome:
    #connectomeDict = None
    def __init__(self):
        self.connectomeDict = {}
        self.axons = {}
        self.neurons = {}
        self.mergedNeurons = {}
    def addNeuron(self, neuron):
        self.connectomeDict[neuron.get_user_key()] = neuron
    def __repr__(self):
        return self.obj2string()
    def __str__(self):
        return self.obj2string()
    def get_neuron_by_key(self, neuronKey):
        return self.connectomeDict[neuronKey]
    def get_neuron_by_idx(self, idx):
        for key in self.connectomeDict:
            # axons and 
            if (self.connectomeDict[key].get_neuron_type() == 'neuron' and self.connectomeDict[key].get_coreTypeIdx() == idx):
                return self.connectomeDict[key]
    def get_axon_by_idx(self, idx):
        for key in self.connectomeDict:
            if (self.connectomeDict[key].get_neuron_type() == 'axon' and self.connectomeDict[key].get_coreTypeIdx() == idx):
                return self.connectomeDict[key]   
    def obj2string(self):
        string = ""
        for key in self.connectomeDict:
            string = string + str(self.connectomeDict[key])+"\n"
        return string
    def get_axons(self):
        # Update Axons dictionary
        for key in self.connectomeDict:
            if (self.connectomeDict[key].get_neuron_type() == 'axon'):
                self.axons[key] = self.connectomeDict[key]
            elif (key in self.axons):
                self.axons.pop(key)
        return self.axons
    def get_neurons(self):
        # Update Neurons dictionary
        for key in self.connectomeDict:
            if (self.connectomeDict[key].get_neuron_type() == 'neuron'):
                self.neurons[key] = self.connectomeDict[key]
            elif (key in self.neurons):
                self.neurons.pop(key)
        return self.neurons
    def get_merged_neurons(self):
        # Update get_merge_neurons dictionary
        for key in self.connectomeDict:
            self.mergedNeurons[self.connectomeDict[key].get_globalIdx()] = self.connectomeDict[key]
        return self.mergedNeurons
    def get_part_format(self):
        mergedNeurons = self.get_merged_neurons()
        networkConnectivity = []
        for key in mergedNeurons.keys(): #Nishant's partitioning code expects a specific format so we convert to that format
            networkConnectivity.append([copy.deepcopy(synapse.get_postsynapticNeuron().get_globalIdx()) for synapse in mergedNeurons[key].get_synapses()])
        return networkConnectivity
    def get_core_outputs_idx(self, core):
         outputs = []
         for key in self.connectomeDict:
            currNeuron = self.connectomeDict[key]
            if (currNeuron.get_output() == True and currNeuron.get_neuron_type() == 'neuron' and currNeuron.get_core() == core) :
                outputs.append(currNeuron.get_coreTypeIdx())
         return outputs
    def get_outputs_idx(self):
         outputs = []
         for key in self.connectomeDict:
            currNeuron = self.connectomeDict[key]
            if (currNeuron.get_output() == True and currNeuron.get_neuron_type() == 'neuron') :
                outputs.append(currNeuron.get_coreTypeIdx())
         return outputs
    def apply_partition(self,membership):
        #breakpoint()
        mergedNeurons = self.get_merged_neurons()
        for key in membership.keys():
            mergedNeurons[key].set_core(membership[key])
        #breakpoint()
        for neuronKey in self.connectomeDict.keys():
            self.connectomeDict[neuronKey].set_synapseTypes()
       

        

