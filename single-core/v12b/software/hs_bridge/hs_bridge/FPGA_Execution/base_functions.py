import os
import subprocess
from collections import defaultdict
import re
import numpy as np

def execute(coreID):
    """This function runs a single time step of the network

    """
    coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
    coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)

    subprocess.run('sudo adxdma_dmadump wb 0 0x0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0x0 0x0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 '+coreByte+' 6', shell = True, check = True)


def flush(nums):
    """Untested
    """
    result = []
    for i in range(nums):
        result.append(
            (subprocess.run(['sudo', 'adxdma_dmadump', 'rb', '0', '0', '64'], stdout=subprocess.PIPE)).stdout.decode(
                'utf-8'))
    # print(result,type(result))

    output = re.findall("INFO:.*:([\s0-9A-F]*)", result[0])
    output = [i.strip() for i in output]
    spikes = defaultdict(list)
    for i in range(len(output)):
        data = output[i].split()
        # Get the timestep information
        while data:
            if (data[0] == 'EF' and data[1] == 'CD' and data[2] == 'AB' and data[3] == '89') or (
                    data[0] == 'EE' and data[1] == 'EE'):
                pass
            else:
                # working solution for now
                timestep = int(data[3], 16)
                spike = data[2] + data[1] + data[0]
                spike = int(spike, 16)
                if spike not in spikes[timestep]:
                    spikes[timestep].append(spike)
            del data[0:4]

    #print(spikes)
