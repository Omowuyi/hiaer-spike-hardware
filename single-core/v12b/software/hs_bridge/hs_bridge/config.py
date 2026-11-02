import confuse
import os

__all__ = [
    'ARCH',
    'N_NG',
    'PTRS_PER_ROW',
    'DATA_PER_ROW',
    'HBM_OP_RW',
    'PTR_ADDR_BITS',
    'PTR_LEN_BITS',
    'AXN_BASE_ADDR',
    'NRN_BASE_ADDR',
    'SYN_BASE_ADDR',
    'SYN_ADDR_BITS',
    'SYN_WEIGHT_BITS',
    'SYN_OP_BITS',
    'HBM_WRITE_CMD',
    'WRITE',
]

config = confuse.Configuration('cri_simulations', __name__)
config.set_file(os.path.join(os.path.dirname(__file__), 'config.yaml'))

ARCH = config['FPGA_cluster'].get()
N_NG = config['n_ng'].get(int)
PTRS_PER_ROW = config['ptrs_per_row'].get(int)
DATA_PER_ROW = config['data_per_row'].get(int)
HBM_OP_RW = '02' + 28 * '00'

PTR_ADDR_BITS = 23  # HBM row address
PTR_LEN_BITS = 9  # (8 connections/row x 2^9 rows = 2^12 = 4K connections max)
AXN_BASE_ADDR = 0  # axon pointer start address
NRN_BASE_ADDR = 2 ** 14  # neuron pointer start address (2^17 axons / 8 axon pointers/row = 2^14 rows max)
SYN_BASE_ADDR = 2 ** 15  # (2^17 neurons / 8 neuron pointers/row = 2^14 rows max -> 2^14+2^14=2^15)

SYN_ADDR_BITS = 13  # each synapse: [31:29]=OpCode  [28:16]=address, [15:0]=weight (1 sign + 15 value, fixed-point)
SYN_WEIGHT_BITS = 16
SYN_OP_BITS = 3

HBM_WRITE_CMD = 'sudo adxdma_dmadump wb 0 0 '

WRITE = '01' + 63 * '00'
