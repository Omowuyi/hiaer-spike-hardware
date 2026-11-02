import numpy as np
import pickle
import os
import math
import sys
import warnings
import logging
import time
import hs_bridge.wrapped_dmadump.dmadump as dmadump
from hs_bridge.config import *
from hs_bridge.FPGA_Execution.fpga_controller import drain_acks, ACKError

USE_BYPASS_FOR_HBM = False    # Disabled: xdma m_axib bypass broken
USE_BURST_FOR_HBM = True      # NEW: Use CMD_DMA_HBM_W_BURST (opcode 13)


def text2script(cmd_str):
    """Converts a string of hex characters into the correct format to suppyl to the adxdma dump command.

    Given a string of hex characters with the left most character containing the MSB create a string of pairs of hex characters representing bytes
    with the leftmost byte contanining the LSB in the format expected by the adxdma_dmadump binary for the data argument.

    Parameters
    ----------
    cmd_str : str
        The string of hexidecimal characters to format. The first character represents the hex character containing the MSB

    Returns
    -------
    script_txt : str
        The formated string of bytes
    """
    cmd = cmd_str
    script_txt = ''
    while cmd:
        script_txt += '0x' + cmd[-2:] + ' '
        cmd = cmd[0:-2]
    return script_txt


class fpga_compiler:
    """Produces the needed adxdma dump scripts of a given network to program HBM

    Attributes
    ----------
    input : dict
        The inputs to the network for each timestep. Key, timestep value, list of axons
    axon_ptrs : numpy array
        Array of tuples pointing to the rows containing the synapses for the corresponding Axon.
    Each tuple is (start row, end row).
    neuron_ptrs : numpy array
        Array of tuples pointing to the rows containing the synapses for the corresponding Axon.
    Each tuple is (start row, end row).
    synapses : list
        List of tuples corresponding to synapses. Each tuple is (oncore/offcore bit, synapse address (row index of destination neuron pointer in HBM calculated as floor(destination neuron index / number of neuron groups)), weight)
    HBM_WRITE_CMD : str

    HBM_OP_RW  : str
        OP code to read/write to hbm vie PCie
    NRN_BASE_ADDR : int
        Starting address of neuron pointers in HBM
    SYN_BASE_ADDR : int
        Starting address of synapses in HBM
    PTR_ADDR_BITS : int
        Number of bits used to represent pointer starting adderess
    PTR_LEN_BITS :
        Number of bits used to represent the number of rows of synapses a pointer corresponds to
    SYN_OP_BITS :
        Number of bits used to represent synapse opcode
    SYN_ADDR_BITS :
        Number of bits used to represent synapse address
    SYN_WEIGHT_BITS :
        Number of bits used to represent synapse weight

    """

    def __init__(self, data, N_neurons,  outputs, coreID = 0):
        '''
        Creates the FPGA Compiler object. Populates spike packets in synapses.

        Paramaters
        ----------
        data: list
            Takes the following format: [0]=input data, [1]=axon pointers, [2]=neuron pointers, [3]=synapses
        N_neurons : int
            Number of neurons in network
        CoreID : int
            Index of core in FPGA to write to
        '''
        coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
        coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)
        self.HBM_OP_RW = '02' + coreByte + 27 * '00'
        self.HBM_OP_RW_LIST = [2,int(coreBits,2)] + [0]*27
        #self.input = data[0]
        self.axon_ptrs = data[0]
        self.neuron_ptrs = data[1]
        self.synapses = data[2]

        n = 0
        errors = 0
        #This works because of how python handles references but it would be much clearer
        #to directly work with self.neuron_ptrs and self.synapses
        #Find space to insert spike packets and insert them in the numpy array representing synapses
        #only assign spike entries in HBM for neurons in the outputs list
        #for row in range(len(data[1])):
            #for col in range(len(data[1][row]))
        rowLength = len(data[1][0])
        for neuronIdx in outputs:
            row = int(np.floor(neuronIdx / rowLength))
            col = neuronIdx % rowLength
            start = data[1][row][col][0]
            end = data[1][row][col][1] + 1
            finished = False
            for r in data[2][start:end]:
                for i in range(len(r)):
                    if r[i] == (0, 0, 0) and n <= len(outputs):
                        r[i] = (1, neuronIdx)
                        #n += 1
                        finished = True
                        break

                if finished:
                    break
            if not finished:
                if n == len(outputs):
                    pass
                else:
                    
                    if n > N_neurons:
                        logging.info('neuron pointer index is greater than specified number of internal neurons, a spike entry will not be assigned to remaining neuron pointer')
                    else:

                         errors+=1
                         logging.error('neuron pointer index: '+ str(n) +' could not be assigned a spike entry')



        logging.info('spike entry assignment errors: %s', errors)




    def create_axon_ptrs_stream(self, simDump = False):
        '''
        Creates the necessary adxdma_dump commands to program the axon pointers into HBM

        Returns
        -------
        script : str
            The bash commands to run to program the axon pointers in HBM
        '''

        if simDump:
            dump = []
        axn_ptrs = np.fliplr(self.axon_ptrs)
        batchCmd = []
        for r, d in enumerate(axn_ptrs):

            oldCmd = ''
            cmd = []
            for p in d:
                binAddr = np.binary_repr(p[1] - p[0], PTR_LEN_BITS) + np.binary_repr(p[0] + SYN_BASE_ADDR,
                                                                                    PTR_ADDR_BITS)
                oldCmd += '{:0{width}x}'.format(int(binAddr,2), width=8)
                cmd = cmd + [int(binAddr[:8],2),int(binAddr[8:16],2),int(binAddr[16:24],2),int(binAddr[24:],2)]

            # append HBM write opcode and WRITE command
            oldCmd = self.HBM_OP_RW + '{:0{width}x}'.format(0x800000 + r, width=6) + oldCmd
            rowAddress = '1'+np.binary_repr(r+AXN_BASE_ADDR,23)
            cmd = self.HBM_OP_RW_LIST + [int(rowAddress[:8],2),int(rowAddress[8:16],2),int(rowAddress[16:],2)]  + cmd
            oldCmd = self.txt2script(oldCmd)
            cmd.reverse()
            if simDump:
                dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in cmd]
                dumpCmd.reverse()
                dumpCmd = ''.join(dumpCmd)
                dump.append(dumpCmd)
            else:
                batchCmd = batchCmd + cmd
                #print(cmd)
        if simDump:
            return dump
        else:
            #print(np.array(batchCmd))
            exitCode = dmadump.dma_dump_write(np.array(batchCmd), len(batchCmd), 1, 0, 0, 0, dmadump.DmaMethodNormal)
            # Each row is one CMD_HBM_RW (0x02) packet; drain one ACK per row
           # drain_acks(len(axn_ptrs), 0x02)

    def txt2script(self, cmd_str):
        """Converts a string of hex characters into the correct format to suppyl to the adxdma dump command.

        Given a string of hex characters with the left most character containing the MSB create a string of pairs of hex characters representing bytes
        with the leftmost byte contanining the LSB in the format expected by the adxdma_dmadump binary for the data argument.

        Parameters
        ----------
        cmd_str : str
            The string of hexidecimal characters to format. The first character represents the hex character containing the MSB

        Returns
        -------
        script_txt : str
            The formated string of bytes
        """
        cmd = cmd_str
        script_txt = ''
        while cmd:
            script_txt += '0x' + cmd[-2:] + ' '
            cmd = cmd[0:-2]
        return script_txt

    def create_neuron_ptrs_stream(self, simDump = False):
        '''
        Creates the necessary data arguments to pass to the adxdma_dump commands to program the neuron pointers into HBM.
        Data arguments for multiple adxdma_dump commands are seperated by new line characters

        Returns
        -------
        script : str
            The data arguments to provide to a series of adxdma_dump commands. Data arguments for successive adxdma_dump commands
        are seperated by newline characters
        '''
        if simDump:
            dump = []
        nrn_ptrs = np.fliplr(self.neuron_ptrs)
        batchCmd = []
        for r, d in enumerate(nrn_ptrs):
            oldCmd = ''
            cmd = []
            for p in d:

                binCmd = np.binary_repr(p[1] - p[0], PTR_LEN_BITS) + np.binary_repr(p[0] + SYN_BASE_ADDR, PTR_ADDR_BITS)
                cmd = cmd + [int(binCmd[:8],2),int(binCmd[8:16],2),int(binCmd[16:24],2),int(binCmd[24:],2)]
                oldCmd += '{:0{width}x}'.format(int(binCmd, 2), width=8)


            # append HBM write opcode and address
            oldCmd = self.HBM_OP_RW + '{:0{width}x}'.format(0x800000 + NRN_BASE_ADDR + r, width=6) + oldCmd
            rowAddress = '1'+np.binary_repr(r+NRN_BASE_ADDR,23)
            cmd = self.HBM_OP_RW_LIST + [int(rowAddress[:8],2),int(rowAddress[8:16],2),int(rowAddress[16:],2)]  + cmd
            oldCmd = self.txt2script(oldCmd) + '\n'
            cmd.reverse()
            if simDump:
                dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in cmd]
                dumpCmd.reverse()
                dumpCmd = ''.join(dumpCmd)
                dump.append(dumpCmd)
            else:
                batchCmd = batchCmd + cmd
                #print(cmd)
        #print(np.array(batchCmd))
        if simDump:
            return dump
        else:
            dmadump.dma_dump_write(np.array(batchCmd), len(batchCmd), 1, 0, 0, 0, dmadump.DmaMethodNormal)
            # Each row is one CMD_HBM_RW (0x02) packet; drain one ACK per row
            #drain_acks(len(nrn_ptrs), 0x02)

    def create_synapses_stream(self, simDump = False):
        '''
        Creates the necessary adxdma_dump commands to program the synapses into HBM

        Returns
        -------
        script : str
            The bash commands to run to program the synapses in HBM
        '''
        #breakpoint()
        if simDump:
            dump = []
        weights = self.synapses
        #script = ''
        n = 0
        #batchCmd = []
        bigCmdList = []
        for r, d in enumerate(weights):
            oldCmd = ''
            cmd = []
            for w in d:
                if w[0] == 0:
                    # [31] = 0 for internal connections and 1 for external connections, [30:29] = unused for single core
                    binCmd = np.binary_repr( 0, SYN_OP_BITS) + np.binary_repr(int(w[1]), SYN_ADDR_BITS) + np.binary_repr(int(w[2]),SYN_WEIGHT_BITS)
                    oldCmd += '{:0{width}x}'.format(int(binCmd, 2),width=8)
                    cmd = cmd + [int(binCmd[:8],2),int(binCmd[8:16],2),int(binCmd[16:24],2),int(binCmd[24:],2)]
                elif w[0] == 1:
                    spike = 16 * '0'
                    print(w[1])
                    binSpike = np.binary_repr( 4, SYN_OP_BITS) + 12*'0' + np.binary_repr(w[1],17)
                    oldCmd += '{:0{width}x}'.format(int(binSpike, 2),width=8)
                    cmd = cmd + [int(binSpike[:8],2),int(binSpike[8:16],2),int(binSpike[16:24],2),int(binSpike[24:],2)]



            # append HBM write opcode and address
            oldCmd = self.HBM_OP_RW + '{:0{width}x}'.format(0x800000 + SYN_BASE_ADDR + r, width=6) + oldCmd
            rowAddress = '1'+np.binary_repr(r+SYN_BASE_ADDR,23)
            cmd = self.HBM_OP_RW_LIST + [int(rowAddress[:8],2),int(rowAddress[8:16],2),int(rowAddress[16:],2)]  + cmd
            oldCmd = self.txt2script(oldCmd) + '\n'
            cmd = np.flip(np.array(cmd, dtype=np.uint8))  # FIX: uint8 ensures 1 byte per element
            #cmd.reverse()
            #
            if simDump:
                dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in cmd]
                dumpCmd.reverse()
                dumpCmd = ''.join(dumpCmd)
                dump.append(dumpCmd)
            else:
                bigCmdList.append(cmd)
                #print(cmd)
            #time.sleep(.005)
            #
            n = n + 1

        # write to text file
        if simDump:
            return dump
        else:
            split = np.concatenate(bigCmdList)
            n = 10

 
            loopBreak = False
            count = 0
            while loopBreak == False:
                count = count+1
                #print('begin: '+str(count))
                #breakpoint()
                try:
                    element = split[:n*64]
                    split = split[n*64:]
                except:
                    element = split
                    loopBreak = True
                if element.size == 0:
                    break
                #print(element)
                exitCode = dmadump.dma_dump_write(element, len(element), 1, 0, 0, 0, dmadump.DmaMethodNormal)
                if exitCode != 0:
                    breakpoint()
                # Each 64-byte chunk is one CMD_HBM_RW (0x02) packet; drain its ACK
                n_packets = len(element) // 64
               # drain_acks(n_packets, 0x02)
                #time.sleep(.4)
                #print('end: '+str(count))
                print('did one')




    def create_script(self, fname, simDump = False):
        """Generates the bash file to program HBM for the current network

        Generates the bash file needed to program the axon pointers, neuron pointers, and synapses into hbm

        Parameters
        ----------
        fname : int
            The filename to write the script to
        """
        axon_ptrs = self.create_axon_ptrs(simDump)
        neuron_ptrs = self.create_neuron_ptrs(simDump)
        synapses = self.create_synapses(simDump)

        if simDump:
            return axon_ptrs, neuron_ptrs, synapses


    @staticmethod
    def _hbm_byte_offset(row_address):
        return int(row_address) * 32

    def _pack_pointer_row(self, pointer_tuples):
        cmd_bytes = []
        for p in pointer_tuples:
            length = int(p[1] - p[0])
            addr = int(p[0]) + SYN_BASE_ADDR
            binAddr = (np.binary_repr(length, PTR_LEN_BITS) +
                       np.binary_repr(addr, PTR_ADDR_BITS))
            cmd_bytes += [int(binAddr[0:8],2), int(binAddr[8:16],2),
                          int(binAddr[16:24],2), int(binAddr[24:],2)]
        cmd_bytes = list(reversed(cmd_bytes))
        return bytes(cmd_bytes)

    def _pack_synapse_row(self, synapse_entries):
        cmd_bytes = []
        for w in synapse_entries:
            if w[0] == 0:
                binCmd = (np.binary_repr(0, SYN_OP_BITS) +
                          np.binary_repr(int(w[1]), SYN_ADDR_BITS) +
                          np.binary_repr(int(w[2]), SYN_WEIGHT_BITS))
            elif w[0] == 1:
                binCmd = (np.binary_repr(4, SYN_OP_BITS) +
                          '0'*12 + np.binary_repr(int(w[1]), 17))
            else:
                raise ValueError(f"Unknown opcode {w[0]}")
            cmd_bytes += [int(binCmd[0:8],2), int(binCmd[8:16],2),
                          int(binCmd[16:24],2), int(binCmd[24:],2)]
        cmd_bytes = list(reversed(cmd_bytes))
        return bytes(cmd_bytes)

    def create_axon_ptrs_bypass(self, simDump=False):
        if simDump: return self.create_axon_ptrs_stream(simDump=True)
        import time as _t; t0 = _t.time()
        buf = bytearray()
        for row in np.fliplr(self.axon_ptrs):
            buf += self._pack_pointer_row(row)
        offset = self._hbm_byte_offset(AXN_BASE_ADDR)
        ec = dmadump.dma_bypass_write(np.frombuffer(bytes(buf), dtype=np.uint8), offset)
        if ec != 0: raise RuntimeError(f"Axon ptr bypass write failed: {ec}")
        logging.info('Axon ptrs via bypass: %d bytes at 0x%X in %.2fs', len(buf), offset, _t.time()-t0)

    def create_neuron_ptrs_bypass(self, simDump=False):
        if simDump: return self.create_neuron_ptrs_stream(simDump=True)
        import time as _t; t0 = _t.time()
        buf = bytearray()
        for row in np.fliplr(self.neuron_ptrs):
            buf += self._pack_pointer_row(row)
        offset = self._hbm_byte_offset(NRN_BASE_ADDR)
        ec = dmadump.dma_bypass_write(np.frombuffer(bytes(buf), dtype=np.uint8), offset)
        if ec != 0: raise RuntimeError(f"Neuron ptr bypass write failed: {ec}")
        logging.info('Neuron ptrs via bypass: %d bytes at 0x%X in %.2fs', len(buf), offset, _t.time()-t0)

    def create_synapses_bypass(self, simDump=False):
        if simDump: return self.create_synapses_stream(simDump=True)
        import time as _t; t0 = _t.time()
        buf = bytearray()
        for row in self.synapses:
            buf += self._pack_synapse_row(row)
        offset = self._hbm_byte_offset(SYN_BASE_ADDR)
        total = len(buf)
        logging.info('Writing %d bytes synapse data via bypass at 0x%X...', total, offset)
        CHUNK = 16*1024*1024
        arr = np.frombuffer(bytes(buf), dtype=np.uint8)
        pos = 0
        while pos < total:
            end = min(pos+CHUNK, total)
            ec = dmadump.dma_bypass_write(arr[pos:end], offset+pos)
            if ec != 0: raise RuntimeError(f"Synapse bypass write failed at 0x{offset+pos:X}: {ec}")
            pos = end
        logging.info('Synapse bypass complete: %d bytes in %.2fs', total, _t.time()-t0)

    # ==================================================================
    # BURST MODE: CMD_DMA_HBM_W_BURST (opcode 13)
    # ==================================================================
    # Sends one header packet, then streams consecutive 256-bit row data
    # packets. The CI on the FPGA writes them to ci2hbm with burst_first
    # flag set every 16 beats. hbm_processor detects this and issues
    # awlen=15 AXI bursts to HBM.
    #
    # Header packet (64 bytes = 512 bits):
    #   byte[63]    = 0x0D (CMD_DMA_HBM_W_BURST = 13)
    #   byte[34:32] = start_row_addr[22:0] (3 bytes, little-endian within
    #                 the 512-bit word at bits [278:256])
    #   byte[3:0]   = total_rows as uint32 LE (bits [31:0])
    #
    # Data packets (64 bytes each):
    #   byte[31:0]  = 256-bit HBM row data (same as _pack_*_row output)
    #   byte[63:32] = unused (zeros)
    # ==================================================================

    def _send_burst_write(self, row_data_list, start_row_addr):
        """Send rows via CMD_DMA_HBM_W_BURST through AXI Stream DMA.

        Parameters
        ----------
        row_data_list : list of bytes
            Each entry is a 32-byte packed HBM row.
        start_row_addr : int
            HBM row address of the first row.
        """
        BURST_SIZE = 16  # rows per AXI burst — matches hbm_processor awlen=15
        total_rows = len(row_data_list)

        # Pad to multiple of 16 (extra rows are benign zero-writes)
        pad_count = (BURST_SIZE - (total_rows % BURST_SIZE)) % BURST_SIZE
        for _ in range(pad_count):
            row_data_list.append(b'\x00' * 32)
        total_rows_padded = len(row_data_list)

        # Build header packet (64 bytes = one 512-bit AXI Stream beat)
        header = bytearray(64)
        header[63] = 13  # CMD_DMA_HBM_W_BURST opcode at byte[63] = bits[511:504]

        # Start row address in bits [278:256] = bytes [32..34] of 512-bit word
        addr_val = start_row_addr & 0x7FFFFF
        header[32] = (addr_val >> 0) & 0xFF
        header[33] = (addr_val >> 8) & 0xFF
        header[34] = (addr_val >> 16) & 0x7F

        # Total rows in bits [31:0] = bytes [0..3] LE
        header[0] = (total_rows_padded >> 0) & 0xFF
        header[1] = (total_rows_padded >> 8) & 0xFF
        header[2] = (total_rows_padded >> 16) & 0xFF
        header[3] = (total_rows_padded >> 24) & 0xFF

        # Build full byte stream: header + all data packets (64 bytes each)
        all_packets = bytearray(header)
        for row_bytes in row_data_list:
            pkt = bytearray(64)
            pkt[0:32] = row_bytes  # data in lower 256 bits
            all_packets += pkt

        # Send via AXI Stream DMA
        arr = np.array(list(all_packets), dtype=np.uint8)
        t0 = time.time()
        ec = dmadump.dma_dump_write(arr, len(arr), 1, 0, 0, 0,
                                    dmadump.DmaMethodNormal)
        elapsed = time.time() - t0
        if ec != 0:
            raise RuntimeError(
                f"Burst write failed: ec={ec}, addr=0x{start_row_addr:X}, "
                f"rows={total_rows}")
        logging.info(
            'Burst write: %d rows at addr 0x%X in %.2fs (%.1f MB/s)',
            total_rows, start_row_addr, elapsed,
            (total_rows * 32) / (1024*1024) / max(elapsed, 0.001))

    def create_axon_ptrs_burst(self, simDump=False):
        if simDump:
            return self.create_axon_ptrs_stream(simDump=True)
        t0 = time.time()
        rows = []
        for row in np.fliplr(self.axon_ptrs):
            rows.append(self._pack_pointer_row(row))
        self._send_burst_write(rows, AXN_BASE_ADDR)
        logging.info('Axon ptrs via burst: %d rows in %.2fs',
                     len(rows), time.time() - t0)

    def create_neuron_ptrs_burst(self, simDump=False):
        if simDump:
            return self.create_neuron_ptrs_stream(simDump=True)
        t0 = time.time()
        rows = []
        for row in np.fliplr(self.neuron_ptrs):
            rows.append(self._pack_pointer_row(row))
        self._send_burst_write(rows, NRN_BASE_ADDR)
        logging.info('Neuron ptrs via burst: %d rows in %.2fs',
                     len(rows), time.time() - t0)

    def create_synapses_burst(self, simDump=False):
        if simDump:
            return self.create_synapses_stream(simDump=True)
        t0 = time.time()
        rows = []
        for row in self.synapses:
            rows.append(self._pack_synapse_row(row))
        self._send_burst_write(rows, SYN_BASE_ADDR)
        logging.info('Synapses via burst: %d rows in %.2fs',
                     len(rows), time.time() - t0)

    def create_axon_ptrs(self, simDump=False):
        if USE_BYPASS_FOR_HBM and not simDump:
            return self.create_axon_ptrs_bypass(simDump)
        if USE_BURST_FOR_HBM and not simDump:
            return self.create_axon_ptrs_burst(simDump)
        return self.create_axon_ptrs_stream(simDump)

    def create_neuron_ptrs(self, simDump=False):
        if USE_BYPASS_FOR_HBM and not simDump:
            return self.create_neuron_ptrs_bypass(simDump)
        if USE_BURST_FOR_HBM and not simDump:
            return self.create_neuron_ptrs_burst(simDump)
        return self.create_neuron_ptrs_stream(simDump)

    def create_synapses(self, simDump=False):
        if USE_BYPASS_FOR_HBM and not simDump:
            return self.create_synapses_bypass(simDump)
        if USE_BURST_FOR_HBM and not simDump:
            return self.create_synapses_burst(simDump)
        return self.create_synapses_stream(simDump)

def main():
    with open('test' + '.pkl', 'rb') as f:
        data = pickle.load(f)

    f = fpga_compiler(data, 6271)

    f.create_script('test_config')
    #TODO: these values should not be hardcoded
    f.create_input_script(num_timesteps=0,n_inputs=1,filename='test_input')
    #print(f.create_neuron_ptrs().split('\n'))


if __name__ == '__main__':
    main()
