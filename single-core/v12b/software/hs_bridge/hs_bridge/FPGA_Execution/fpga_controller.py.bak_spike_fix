import click
import os
import yaml
import pickle
import io
import numpy as np
import math
import subprocess
import time
import re
import logging
from collections import defaultdict
#import .FPGA_Execution.base_functions as base_functions
from hs_bridge.config import *
import hs_bridge.FPGA_Execution.base_functions as base_functions
from hs_bridge.FPGA_Execution.fpga_compiler import text2script
import hs_bridge.wrapped_dmadump.dmadump as dmadump
import concurrent.futures
from multiprocessing import Process, Queue, Pipe
#n_internal = None
#n_inputs = None
#inputs = None
ng_num = 16
debug_prints = False

def to_binary(number,width):
    stringRep = np.array(list(np.binary_repr(number,width))).astype(np.int8)

def to_dump_format(binArr):
    #TODO: check len(binArr is divisible by 8)
    #breakpoint()
    binArr = binArr.astype(np.int8)
    splitArr = np.split(binArr.astype(str), len(binArr)/8)
    result = np.flip (np.array([int(''.join(element),2) for element in splitArr],dtype=np.uint64))
    return result


def twos_comp(val, bits):
    """compute the 2's complement of int value val

    Takes the int casting of a two's compliment binary string and the number
    of bytes in the binary string and returns the value of the two's compliment
    representation correspondin to the original binary string.

    Parameters
    ----------
    val : int
        the binary stirng to compute the two's compliment of casted to an int
    bits : int
        the number of bits corresponding to the original binary representation of val

    Return
    ------
    val : int
        the value of the original two's compliment binary string
         
    """
    if (val & (1 << (bits - 1))) != 0: # if sign bit is set e.g., 8bit: 128-255
        val = val - (1 << bits)        # compute negative value
    return val                         # return positive value as is

def get_packet_type(string):
    """Caluclates and prints the membrane potentials corresponding to a PCIe packet from
       the FPGA

    Given the packet returned by a PCIe read from URAM this function calculates the neuron index
    and membrane potential of the neruon represented by the PCIe packet and prints those values
    to terminal

    Parameters
    ----------
    string : str
        The string returned by the PCIe command to read URAM

    """
    if debug_prints:
        print(string)
    #breakpoint()
    string = string.split('\n')[3]
    string = string.replace('INFO', '')
    new = ''
    for i in string:
    
        if i not in [':', '?', '.', '@']:
            new += i

    new = new.strip().split(' ')
    new = [i for i in list(filter(None, new)) if len(i) < 3]
    #breakpoint()
    tag = new[15]+new[14]
    return tag
    #print(new)
    #


def read_spikes(data):
    """Caluclates and prints the incoming spikes corresponding to a PCIe packet from
       the FPGA

    Given a spike packet this function decodes the spike packet

    Parameters
    ----------
    string : str
        The string returned by the PCIe command to read spikes

    """
#   #breakpoint()
    data = np.flip(data) #put list with MSB as smallest element
    binData = [np.binary_repr(i,width = 8) for i in data]
    binData = ''.join(binData) #tag in dec format
    tag = int(binData[:-480],2)
    #extract the executionRun_counter
    executionRun_counter = binData[-32:]
    #extract the region containing spike data
    spikeData = binData[-480:-32]
    #breakpoint
    spikePacketLength = 32 #4 bytes per spike packet
    spikeList = []
    for spikePacket in [spikeData[i:i+spikePacketLength] for i in range(0, len(spikeData), spikePacketLength)]:
        subexecutionRun_counter, address = processSpikePacket(spikePacket)
        if (subexecutionRun_counter != None and address != None):
            spikeList.append((subexecutionRun_counter,address))
    #breakpoint()
    #print('spikeList: ' + str(spikeList))
    return executionRun_counter, spikeList

def processSpikePacket(spikePacket):
    """Processes an incoming binary string representing a single spike event
    """
    #breakpoint()
    valid = bool(int(spikePacket[8])) #check if it's a valid spike packet
    if valid:
        subexecutionRun_counter = int(spikePacket[0:8], 2)
        address = int(spikePacket[-17:],2)
        #breakpoint()
        return subexecutionRun_counter, address
    else:
        return None, None

def read_membranes(data):
    """Caluclates and prints the membrane potentials corresponding to a PCIe packet from
       the FPGA

    Given the packet returned by a PCIe read from URAM this function calculates the neuron index
    and membrane potential of the neruon represented by the PCIe packet and prints those values
    to terminal

    Parameters
    ----------
    string : str
        The string returned by the PCIe command to read URAM

    """
    #breakpoint()
    #if debug_prints:
    data = np.flip(data)
    binData = [np.binary_repr(i,width=8) for i in data]
    binData = ''.join(binData)
    col = int(binData[-53:-49],2)
    row = int(binData[-49:-36],2)
    # L6c: URAM [35:0] = [35]spike [34:32]refractory_ctr [31:0]MP
    mp = binData[-32:]
    mp = twos_comp(int(mp,2), 32)
    return(ng_num * row+ col, row, col, mp)

@click.group()
def interface():
    """Untested
    """
    pass

def clear_address_packet(row,col,simDump=False):
    rowBin = np.binary_repr(row,13)
    colBin = np.binary_repr(col,4)
    byte4 = rowBin[-4:]+'0'*4
    byte5 = rowBin[-12:-4]
    byte6 = '0'*2+'1'+np.binary_repr(col,4)+rowBin[0]

   

    #if simDump:
    #    byte4_hex = '{:0{width}x}'.format(int(byte4, 2), width=2)
    #    byte5_hex = '{:0{width}x}'.format(int(byte5, 2), width=2)
    #    byte6_hex = '{:0{width}x}'.format(int(byte6, 2), width=2)
    #    packet = '00 00 00 00' + ' ' + byte4_hex + ' ' +  byte5_hex + ' ' + byte6_hex 
    #else:
    packet = np.array([0,0,0,0,int(byte4,2),int(byte5,2),int(byte6,2)], dtype = np.uint64 )
    return packet

#@interface.command()
def clear(n_internal, simDump = False, coreID = 0):
    """This function clears the membrane potentials on the fpga.
    """
    #updated Feb11
    #load()#is this even needed
    coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
    coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)
    
    if simDump:
        dump = []
    for i in range(int(np.ceil(n_internal / ng_num))):
        #if simDump:
        #    commandTail = ' 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ' + coreByte + ' 03'
        #    numCol = 16
        #      
        #    for column in range(numCol):
        #        #command = "03" + "00"*56 + byte + "00" + '{:0{width}x}'.format(i, width=2) + "00"*4
        #        command = clear_address_packet(row=i,col=column,simDump=True) + commandTail
        #        command = command.split(sep=' ')
        #        command.reverse()
        #        command = ''.join(command)
        #        dump.append(command)

            #0 0 0 0 $(($i * 16)) 0x00 0x20 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0x0 0x0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3

        #else:
        #command = 'sudo adxdma_dmadump wb 0 0x0 '
        commandTail = np.array([0]*55+[int(coreBits,2),3], dtype=np.uint64)
        numCol = 16
        clearCommandList = []
        for column in range(numCol):
            clearCommandList.append(np.concatenate([clear_address_packet(row=i,col=column),commandTail]))
        clearCommand = np.concatenate(clearCommandList)
        if simDump:
            #breakpoint()
            dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in clearCommand]
            dumpCmd.reverse()
            dumpCmd = [[''.join(list(x))] for x in list(np.split(np.array(dumpCmd),column+1))]
            #dumpCmd = ''.join(dumpCmd)
            dump= dump+dumpCmd
        else:
            #breakpoint()
            exitCode = dmadump.dma_dump_write(clearCommand, len(clearCommand), 1, 0, 0, 0, dmadump.DmaMethodNormal)

    if simDump:
        return dump

#@interface.command()

def clear_read_buffer(coreID = 0):
    while(True):
        exitCode, currentRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64)
        if(currentRead[62] == 255 and currentRead[63] == 255):
            #breakpoint()
            break

def flush_spikes_old(coreID = 0):
#Note, if you read out multiple spike packets the "older" spike packets will be in the MSB side of the packet and "newer" spike packets will be toward the LSB side."
#You may want to wait a constant amount of time, then read all spikes out at once
#I
    spikeOutput = []
    n=0
    while(True):
        exitCode, currentRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 128)
        #breakpoint()
        if((currentRead[62] == 255) and (currentRead[63] == 255)):
            #FIFO Empty
            n += 1
            if (n == 50):
                break
        elif(currentRead[62] == 238 and currentRead[63] == 238): #TODO: this is just here for debugging
            executionRun_counter, spikeList = read_spikes(currentRead)
            spikeOutput = spikeOutput + spikeList
            n = 0
        else:
            logging.error("non-spike packet encountered during spike flush: "+str(currentRead))
            n = 0
            

    return spikeOutput


def flush_spikes(coreID = 0):
#Note, if you read out multiple spike packets the "older" spike packets will be in the MSB side of the packet and "newer" spike packets will be toward the LSB side.
#You may want to wait a constant amount of time, then read all spikes out at once
#We also will want to check for some special non-spike packets.
    packetNum = 1
    spikeOutput = []
    n=0
    time.sleep(800/1000000.0) #wait fourty microseconds for processing of spikes to complete
    while(True):
        exitCode, batchRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64*packetNum)
        #breakpoint()
        latancy = None
        hbmAccess = None
        splitRead = np.array_split(batchRead,packetNum)
        splitRead.reverse()
        flushed = False
        for currentRead in splitRead:
            #do something
            #apple = "apple"
            if((currentRead[62] == 255) and (currentRead[63] == 255)):
                #FIFO Empty
                #print("hit empty")
                #print(n)
                n += 1
                if (n == 50):
                    flushed = True
                    break
            elif(currentRead[62] == 238 and currentRead[63] == 238):
                #breakpoint()
                executionRun_counter, spikeList = read_spikes(currentRead)
                spikeOutput = spikeOutput + spikeList
                n = 0
            elif(currentRead[62] == 205 and currentRead[63] == 171):
                #latency
                executionRun_counter, spikeList = read_spikes(currentRead)
                spikeOutput = spikeOutput + spikeList
                flushed = True
                break

            else:
                logging.error("non-spike packet encountered during spike flush: "+str(currentRead))
                #n = 0
        if flushed:
           break
            
    exitCode, batchRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64*packetNum)
    #splitRead = np.array_split(batchRead,packetNum) TODO: currently we only read one packet at a time
    #addtionaly logic would be required to handle splitting if we use more than one packet
    splitRead = batchRead
    np.flip(splitRead)
    flushed = False
    #breakpoint()
    #latency
    latencyBytes = ['{:0{width}x}'.format(int(byte), width=2) for byte in splitRead[:4]]
    latencyBytes.reverse()
    latency = int(''.join(latencyBytes),16)

    #breakpoint()
    #print('latency'+str(latency))

    exitCode, batchRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64*packetNum)
    #splitRead = np.array_split(batchRead,packetNum)
    splitRead = batchRead
    np.flip(splitRead)

    #hbm accesses
    hbmAccBytes = ['{:0{width}x}'.format(byte, width=2) for byte in splitRead[:4]]
    hbmAccBytes.reverse()
    hbmAcc = int(''.join(hbmAccBytes),16)

    return (spikeOutput,latency,hbmAcc)

def read_address_packet(row,col, simDump=False):
    rowBin = np.binary_repr(row,13)
    colBin = np.binary_repr(col,4)
    byte4 = rowBin[-4:]+'0'*4
    byte5 = rowBin[-12:-4]
    byte6 = '0'*3+np.binary_repr(col,4)+rowBin[0]

    if simDump:
        byte4_hex = '{:0{width}x}'.format(int(byte4, 2), width=2)
        byte5_hex = '{:0{width}x}'.format(int(byte5, 2), width=2)
        byte6_hex = '{:0{width}x}'.format(int(byte6, 2), width=2)
        packet = '00 00 00 00' + ' ' + byte4_hex + ' ' +  byte5_hex + ' ' + byte6_hex
    else:
        packet = np.array([0, 0, 0, 0, int(byte4,2), int(byte5,2), int(byte6,2)], dtype = np.uint64)
    return packet

def read(n_internal, simDump = False, coreID = 0):
    """This function reads in the membrane potentials from the fpga.
    """
    above_thresh = []
    #updated Feb11
    #load()#is this even needen
    coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
    coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)
    
    if simDump:
        dump = []
    formated_results = [] #holds the formated output
    for i in range(int(np.ceil(n_internal/ng_num))):
        if simDump:
            commandTail = ' 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ' + coreByte + ' 03'
            numCol = 16
            for column in range(numCol):
                #command = "03" + "00"*56 + byte + "00" + '{:0{width}x}'.format(i, width=2) + "00"*4
                command = read_address_packet(row=i,col=column,simDump=True) + commandTail
                command = command.split(sep=' ')
                command.reverse()
                command = ''.join(command)
                dump.append(command)
        #breakpoint()
            #for i in range(ng_num):
            #    dump.append("40")
        #else:
        dump = []
        commandTail = np.array([0]*55+[int(coreBits,2),3], dtype=np.uint64)
        numCol = 16
        requestDataList = []
        for column in range(numCol):
            #we'll split the command into lines to make it a little easier to read if we choose to print it
            requestDataList.append(np.concatenate([read_address_packet(row=i,col=column),commandTail]))
        requestData = np.concatenate(requestDataList)

        #subprocess.run(command, shell=True, check=True)
        if simDump:
            dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in requestData]
            dumpCmd.reverse()
            dumpCmd = ''.join(dumpCmd)
            #breakpoint()
            dump.append(dumpCmd)
        else:
            #breakpoint()
            exitCode = dmadump.dma_dump_write(requestData, len(requestData), 1, 0, 0, 0, dmadump.DmaMethodNormal)
            #print([hex(elem) for elem in requestData])
        #time.sleep(.005)
        result = [] #holds the raw pcie output
        #breakpoint()
        for i in range(ng_num):
            #print("NEURON GROUP NUMBER: "+str(i))
            if not simDump:
                while True: #look for the next membrane potential in the fifo

                    exitCode, readData = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64)
                    #print([hex(elem) for elem in readData])
                    #breakpoint()
                    #breakpoint()
                    #breakpoint()
                    #breakpoint()
                    #time.sleep(.005)
                    if(readData[62] == 204 and readData[63] == 204): #MSB's are CC and CC
                        #breakpoint()
                        break
                    else:
                       #breakpoint()
                       logging.error("an errant packet was detected during membrane potential readout: " + str(readData))
                       #breakpoint()
                       #exitCode = dmadump.dma_dump_write(requestData, len(requestData), 1, 0, 0, 0, dmadump.DmaMethodNormal)

                result.append(readData)                
                #w
                #breakpoint()
                #time.sleep(1)
                #print(result[i])
                formated_results.append(read_membranes(readData))
        #print(command)
            
    if simDump:
        return dump
    else:
        #breakpoint()
        return formated_results

def readSelect(neuronList, simDump = False, coreID = 0):
    """This function reads in the membrane potentials from the fpga.
    """
    #get the row column pairs?
    above_thresh = []
    coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
    coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)

    if simDump:
        dump = []
    formated_results = [] #holds the formated output
    for neuronIdx in neuronList:
        if simDump:
            commandTail = ' 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ' + coreByte + ' 03'
            numCol = 16
            for column in range(numCol):
                command = read_address_packet(row=i,col=column,simDump=True) + commandTail
                command = command.split(sep=' ')
                command.reverse()
                command = ''.join(command)
                dump.append(command)
        dump = []
        commandTail = np.array([0]*55+[int(coreBits,2),3], dtype=np.uint64)
        numCol = 16
        requestDataList = []
        rowVal = int(np.floor(neuronIdx/ng_num))
        colVal = int(neuronIdx % ng_num) #adjust for indexing
        #we'll split the command into lines to make it a little easier to read if we choose to print it
        requestDataList.append(np.concatenate([read_address_packet(row=rowVal,col=colVal),commandTail]))
        requestData = np.concatenate(requestDataList)

        if simDump:
            dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in requestData]
            dumpCmd.reverse()
            dumpCmd = ''.join(dumpCmd)
            dump.append(dumpCmd)
        else:
            exitCode = dmadump.dma_dump_write(requestData, len(requestData), 1, 0, 0, 0, dmadump.DmaMethodNormal)
        result = [] #holds the raw pcie output

        if not simDump:
            while True: #look for the next membrane potential in the fifo

                exitCode, readData = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64)
                #breakpoint()
                if(readData[62] == 204 and readData[63] == 204): #MSB's are CC and CC
                    break
                else:
                    logging.error("an errant packet was detected during membrane potential readout: " + str(readData))
            result.append(readData)
            formated_results.append(read_membranes(readData))

    if simDump:
        return dump
    else:
        return formated_results



def cont_read(conn,result_conn, coreID):
    #continuousaly reads spikes from FPGA
    global writeDone #signal to stop reading once we're done writing stuff
    packetNum = 1 #number of packets to read simultaneously
    spikeOutput = []
    #time.sleep(800/1000000.0) #wait fourty microseconds for processing of spikes to complete
    #while not conn.poll():
    readFlag = True
    while readFlag:
        #time.sleep(.1)
        exitCode, batchRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64*packetNum)
        #print(exitCode)
        #print(batchRead)
        #breakpoint()
        splitRead = np.array_split(batchRead,packetNum)
        splitRead.reverse()
        flushed = False
        #print(splitRead)
        #breakpoint()
        for currentRead in splitRead:
            if(currentRead[62] == 238 and currentRead[63] == 238):
                #breakpoint()
                executionRun_counter, spikeList = read_spikes(currentRead)
                spikeOutput = spikeOutput + spikeList
            elif(currentRead[62] == 205 and currentRead[63] == 171):
                #latency
                executionRun_counter, spikeList = read_spikes(currentRead)
                spikeOutput = spikeOutput + spikeList
                readFlag = False
            else:
                breakpoint()
    #now we read the final two packets
    exitCode, batchRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64*packetNum)
    splitRead = np.array_split(batchRead,packetNum)
    splitRead.reverse()
    flushed = False

    #latency
    latencyBytes = ['{:0{width}x}'.format(byte, width=2) for byte in currentRead[:4]]
    latencyBytes.reverse()
    latency = int(''.join(latencyBytes),16)

    exitCode, batchRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64*packetNum)
    splitRead = np.array_split(batchRead,packetNum)
    splitRead.reverse()

    #hbm accesses
    hbmAccBytes = ['{:0{width}x}'.format(byte, width=2) for byte in currentRead[:4]]
    hbmAccBytes.reverse()
    hbmAcc = int(''.join(hbmAccBytes),16)
                    #hbm access

    result = (spikeOutput,latency,hbmAcc)
    #result_conn.send(result)
    #breakpoint()
    return result



def cont_write(inputs, numAxons, conn, coreID):
    #Writes all available inputs to FPGA
    global writeDone
    #print(inputs)
    #print(np.shape(inputs))
    for currInput in inputs:
    #    for i in range(3):
        #time.sleep(.3)
        #print("we wrote an input :)")
        input_user(currInput, numAxons, cont_flag = True, coreID = coreID)
    #conn.send('writeDone')
    return

def init_cont_run(steps = 1, coreID = 0, simDump = False):
    #breakpoint()
    #initializes the FPGA to run in continuous execution
    coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
    coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)
    binSteps = np.binary_repr(steps,32)
    stepByte =  '{:0{width}x}'.format(int(binSteps, 2), width=8)
    stepByte = np.split(np.array(list(stepByte)),4)
    stepHeader = [int(''.join(byte),16) for byte in stepByte ]
    stepHeader.reverse()
    #breakpoint()
    runCommand = np.array(stepHeader+[0]*58+[int(coreBits,2),7], dtype=np.uint64)
    #print(runCommand)
    #breakpoint()
    if simDump:
        dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in runCommand]
        dumpCmd.reverse()
        dumpCmd = ''.join(dumpCmd)
        return [dumpCmd]
    else:
        exitCode = dmadump.dma_dump_write(runCommand, len(runCommand), 1, 0, 0, 0, dmadump.DmaMethodNormal)

    return

def cont_execute_old(inputs, numAxons):
#takes in inputs, then will set FPGA to run in continous execution mode, spawn two processes, one to continously write to the FPGA, one to continuously read
    global writeDone
    writeDone = False
    init_cont_run()
    with concurrent.futures.ProcessPoolExecutor(max_workers = 8) as executor:
        fs = [] #list to hold future objects
        fs.append(executor.submit(cont_read))
        fs.append(executor.submit(cont_write, inputs,numAxons))
        print("submitted jobs")
        concurrent.futures.wait(fs, timeout=None, return_when=concurrent.futures.ALL_COMPLETED) #this might be unecessary
        #breakpoint()
        return fs[0].result()

def cont_execute_sim_overide(inputs, numAxons, coreID=0):
    #breakpoint()
    dump = []
    initCmd = init_cont_run(steps=1, coreID=coreID, simDump=True)
    dump.append(initCmd)
    for currInput in inputs:
       dump.append(input_user(currInput, numAxons, simDump = True))
    return dump

def cont_execute(inputs, numAxons, steps, coreID=0):
#takes in inputs, then will set FPGA to run in continous execution mode, spawn two processes, one to continously write to the FPGA, one to continuously read
    #breakpoint()
    writeDone = False
    init_cont_run(steps, coreID)
    write_conn, read_conn = Pipe()
    result_parent, result_child = Pipe()
    pread = Process(target = cont_read, args=(read_conn, result_child, coreID))
    pwrite = Process(target = cont_write, args=(inputs, numAxons, write_conn, coreID))
#    pread.start()
#    pwrite.start()
    print("core ID: ", coreID)
    cont_write(inputs, numAxons, write_conn, coreID)
    #breakpoint()
    result = cont_read(read_conn, result_child, coreID)
    #pread.start()
    #pwrite.join()
    #pread.join()
    #pread.start()
    #spikes = result_parent.recv()
    #pread.join()
    #breakpoint()
    print(result)
    #breakpoint()
    return result

@interface.command()
@click.option('--filename',default=None, help='Pickled Network Configuration file')
@click.option('--n_inputs', default=None, help='Number of axons')
@click.option('--n_internal',default=None, help='Number of Neurons')
def init(filename,n_inputs,n_internal):
    """Untested
    """
    if filename is None or n_inputs is None or n_internal is None:
        raise ValueError('Command Line Arguments must be specified')


    with open(filename, 'rb' ) as f:
        file = pickle.load(f)

    inp = file[0]

    try:
        n_inputs = int(n_inputs)
        n_internal = int(n_internal)
    except ValueError:
        print('Failed! Make sure the number of inputs and internal values are numbers')

    data = {'inputs' : inp, 'n_inputs': n_inputs, 'n_internal': n_internal}
    with io.open('config.yaml', 'w', encoding='utf8') as outfile:
        yaml.dump(data, outfile, default_flow_style=False, allow_unicode=True)

#PCIe commands for setting network parameters
# [511:504] --> 0x4
# [71:70] --> exec_neuron_model
# [69:34] --> 36-bit threshold
# [33:17] --> NUM OUTPUTs in the network
# [16:0] --> NUM INPUTs in the network

def write_parameters_simple(n_outputs, n_inputs, coreID=0, simDump = False):
    """Writes the network parameters to the FPGA
    Parameters
    ----------
    neuron_model : int
        The type of neuron model to use (1: incremental I&F, 2: leaky I&F, 3: non-leaky I&F)
    threshold : int
        Neuron spike threshold
    n_outputs : int
        The number of neurons in the network
    n_inputs : int
        The number of axons in the network

    Notes
    -----
    Command Format
    511-504: command ID (0x04)
    503-496: CoreID
    495-34: 0
    33-17: number of outputs
    16-0: number of inputs
    """
    #breakpoint()
    #np.binary_repr(value, number of bits)
    command = np.zeros(512)
    command[:8] = list(np.binary_repr(4,8)) #511-504: command ID (0x04)
    command[8:16] = list(np.binary_repr(coreID,8)) #503-496: CoreID
    command[-17:] = list(np.binary_repr(n_inputs,17)) #15-0: number of inputs
    command[-34:-17] = list(np.binary_repr(n_outputs,17)) #32-16: number of outputs
    command = to_dump_format(command)
    print(command)
    logging.info("programminng network parameters")
    if simDump:
        dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in command]
        dumpCmd.reverse()
        dumpCmd = ''.join(dumpCmd)
        return [dumpCmd]
    else:
        exitCode = dmadump.dma_dump_write(command, len(command), 1, 0, 0, 0, dmadump.DmaMethodNormal)


def write_neuron_type(stopAddr, Threshold, neuronModel, shift, leak, refractory_max=0, dual_synapse_en=0, delay_value=0, shadow_uram_offset=0, legacy_noise_en=0, coreID=0, simDump=False):
    print(f"[DEBUG write_neuron_type] stopAddr={stopAddr} boundary={(stopAddr+15)//16} Threshold={Threshold} model={neuronModel} shift={shift} leak={leak} refr={refractory_max} delay={delay_value} dual_syn={dual_synapse_en}")
    """Writes the network parameters to the FPGA
    Parameters
    ----------
    neuron_model : int
        The type of neuron model to use (1: incremental I&F, 2: leaky I&F, 3: non-leaky I&F)
    threshold : int
        Neuron spike threshold
    n_outputs : int
        The number of neurons in the network
    n_inputs : int
        The number of axons in the network

    Notes
    -----
    Command Format
    511-504: command ID (0x08)
    503-496: CoreID
    495-83: 0
    82-77: leak
    76-71: shift
    70-69: neuron model
    68-33: threshold
    33-17: stop address (total number of neurons)
    16-0: 0
    """
    #breakpoint()
    if type(Threshold) != int:
        Threshold = int(Threshold)
    command = np.zeros(512)
    command[:8] = list(np.binary_repr(8,8)) #511-504: command ID (0x08)
    command[8:16] = list(np.binary_repr(coreID,8)) #503-496: CoreID
    #
    #command[-17:] = list(np.binary_repr(startAddr,16)) #15-0: start address
    command[-34:-21] = list(np.binary_repr((stopAddr + 15) // 16, 13)) #33-21: boundary (URAM addr, confirmed IEP line 1090)
    command[-21:-17] = list(np.binary_repr(delay_value, 4)) #20-17: delay_value
    command[-17:-14] = list(np.binary_repr(refractory_max, 3)) #16-14: refractory_max
    command[-14:-13] = list(np.binary_repr(int(dual_synapse_en), 1)) #13: dual_synapse_en
    command[-13:-9] = list(np.binary_repr(shadow_uram_offset, 4)) #12-9: shadow_uram_offset
    command[-8:-7] = list(np.binary_repr(int(legacy_noise_en), 1)) #7: legacy_noise_en
    #
    command[-70:-34] = list(np.binary_repr(Threshold,36)) #68-33: threshold
    #breakpoint()
    command[-72:-70] = list(np.binary_repr(neuronModel,2)) #70-69: neuron model
    command[-78:-72] = list(np.binary_repr(shift,6)) #76-71: shift
    command[-84:-78] = list(np.binary_repr(leak,6)) #82-77: leak
    #command[-87:-83] = list(np.binary_repr(sramAddr,35))
    command = to_dump_format(command)
    print(command)
    logging.info("programminng network parameters")
    if simDump:
        dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in command]
        dumpCmd.reverse()
        dumpCmd = ''.join(dumpCmd)
        return [dumpCmd]
    else:
        exitCode = dmadump.dma_dump_write(command, len(command), 1, 0, 0, 0, dmadump.DmaMethodNormal)


'''
def write_parameters(neron_model, threshold, n_outputs, n_inputs, shift, leak, coreID=0, simDump = False):
    """Writes the network parameters to the FPGA
    Parameters
    ----------
    neuron_model : int
        The type of neuron model to use (1: incremental I&F, 2: leaky I&F, 3: non-leaky I&F)
    threshold : int
        Neuron spike threshold
    n_outputs : int
        The number of neurons in the network
    n_inputs : int
        The number of axons in the network
    """
    #breakpoint()
    n_inputs_bin = np.binary_repr(n_inputs,17)
    a_bin = n_inputs_bin[9:17]
    b_bin = n_inputs_bin[1:9]
    c_bin = ["0"] * 8
    c_bin[7] = n_inputs_bin[0] #set lsb of c_bin
    n_outputs_bin = np.binary_repr(n_outputs,17)
    c_bin[:7] = n_outputs_bin[10:17] #set msb of cbit as lsb of outputs
    c_bin = "".join(c_bin)
    d_bin = n_outputs_bin[2:10]
    e_bin = ["0"] * 8
    e_bin[6:8] = n_outputs_bin[:2]
    threshold_bin = np.binary_repr(threshold,36)
    e_bin[:6] = threshold_bin[30:]
    e_bin = "".join(e_bin)
    f_bin = threshold_bin[22:30]
    g_bin = threshold_bin[14:22]
    h_bin = threshold_bin[6:14]
    i_bin = ["0"] * 8
    i_bin[2:] = threshold_bin[:6]
    n_model_bin = np.binary_repr(neron_model,2)
    i_bin[:2] = n_model_bin
    i_bin = "".join(i_bin)
    shift_bin = np.binary_repr(shift, 2)
    leak_bin = np.binary_repr(leak, 2)
    j_bin = ["0"] * 8
    j_bin[2:] = shift_bin
    j_bin[:2] = leak_bin[6:]
    j_bin = "".join(j_bin)
    k_bin = ["0"] * 8
    k_bin[2:] = leak_bin[2:6]
    k_bin = "".join(k_bin)
    a = int(a_bin, 2)
    b = int(b_bin, 2)
    c = int(c_bin, 2)
    d = int(d_bin, 2)
    e = int(e_bin, 2)
    f = int(f_bin, 2)
    g = int(g_bin, 2)
    h = int(h_bin, 2)
    i = int(i_bin, 2)
    j = int(j_bin, 2)
    k = int(k_bin, 2)
    #print(a_hex)
    #print(c_hex)
    ##
    #print(threshold_bin)

    coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
    #print("coreBits:",coreBits)
    coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)
    #if simDump:
    #    h_hex = "0x04"
    #    a_hex = '{:0{width}x}'.format(int(a_bin, 2), width=2)
    #    b_hex = '{:0{width}x}'.format(int(b_bin, 2), width=2)
    #    c_hex = '{:0{width}x}'.format(int(c_bin, 2), width=2)
    #    d_hex = '{:0{width}x}'.format(int(d_bin, 2), width=2)
    #    e_hex = '{:0{width}x}'.format(int(e_bin, 2), width=2)
    #    f_hex = '{:0{width}x}'.format(int(f_bin, 2), width=2)
    #    g_hex = '{:0{width}x}'.format(int(g_bin, 2), width=2)
    #    h_hex = '{:0{width}x}'.format(int(h_bin, 2), width=2)
    #    i_hex = '{:0{width}x}'.format(int(i_bin, 2), width=2)

    #    foo =  ["04"+coreByte+"00"*53+i_hex+h_hex+g_hex+f_hex+e_hex+d_hex+c_hex+b_hex+a_hex]
    #    breakpoint()
    #else:
    #breakpoint()
    command = np.array([a, b, c, d, e, f, g, h, i, j, k] + [0]*51 +[int(coreBits, 2), 4], dtype=np.uint64)
    print(command)
    logging.info("programminng network parameters")
    if simDump:
        dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in command]
        dumpCmd.reverse()
        dumpCmd = ''.join(dumpCmd)
        return [dumpCmd]
    else:
        exitCode = dmadump.dma_dump_write(command, len(command), 1, 0, 0, 0, dmadump.DmaMethodNormal)
'''

#@interface.command()
def execute(simDump=False, coreID = 0):
    """ Runs a single step of the network and prints "executing a Timestep: " to the terminal
    """
    # Implement Running the Command for one timestep
    coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
    
    #if simDump:
    #    coreByte = '{:0{width}x}'.format(int(coreBits, 2), width=2)
    #    command = ["06"+coreByte+"00"*62]
    #    return command
    #else:
    #click.echo('Executing a Timestep: ')
    command = np.array([0]*62 + [int(coreBits,2), 6], dtype=np.uint64)
    #print(command)
    if simDump:
        dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in command]
        dumpCmd.reverse()
        dumpCmd = ''.join(dumpCmd)
        return [dumpCmd]
    else:
        exitCode = dmadump.dma_dump_write(command, len(command), 1, 0, 0, 0, dmadump.DmaMethodNormal)

def step_input(command):
    """This just runs a command formated to be run with bash
    """
    os.system(command)

def input_user(inputs, numAxons, simDump = False, coreID=0, reserve=True,cont_flag = False):
    """Generates the input command for a given time step
    Generates the necesary bash command to run to provide inputs to the network for a given timestep
    Parameters
    ----------
    inputs : list of int
        The currently spiking axons
    Returns
    -------
    command : str
        The bash command to run to send the input to the FPGA

    Notes
    -----
    Command Format
    An older deprecated format exists and a newer format

    New Format

    Init Packet:
    511-504: command ID (0x01)
    503-496: CoreID
    495-0: 0

    Data Packet:
    511-504: command ID (0x00)
    503-496: Core ID
    495-256: 0
    255-0: onehot encoded inputs

    Old Format



    """
    reserve = True
    #breakpoint()
    #if (reserve): #new format upper 256 bits are reserved TODO: this functionality is untested
    if (reserve):
        currInput = inputs
        currInput.sort()
        coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
        coreByte = int(coreBits,2)
        if cont_flag:
            commandList = []
        else:
            commandList = [0]*62+[coreByte]+[1]
        for count in range(math.ceil(numAxons/256)):
            one_hot_bin = ["0"] * 256
            inputSegment = [i for i in currInput if (256*count) <= i and i < (256*count+256) ]
            for axon in inputSegment:
                one_hot_bin[axon%256] = "1"
           
            while one_hot_bin:
               curr_byte = one_hot_bin[:8][::-1]
               curr_byte = "".join(curr_byte)
               commandList = commandList + [int(curr_byte, 2)]
               one_hot_bin = one_hot_bin[8:]
            tail = 30*[0]
            commandList = commandList+tail+[coreByte,0]
        #Justin: jul13 fixed the indent

        command = np.array(commandList, dtype=np.uint64)
        if simDump:
            #breakpoint()
            dump_list = []
            command_list = np.split(command, len(command)/64)
            for subcommand in command_list:
                dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in subcommand]
                dumpCmd.reverse()
                #breakpoint()
                #dumpCmd = [[''.join(list(x))] for x in list(np.split(np.array(dumpCmd),count+2))]
            #breakpoint()
            #dumpCmd = ''.join(dumpCmd)
                dumpCmd = ''.join(dumpCmd)
                dump_list.append(dumpCmd)
            return dump_list
        else:
            #breakpoint()
            #command_list = np.split(command, len(command)/64)
            #for subcommand in command_list:
            exitCode = dmadump.dma_dump_write(command, len(command), 1, 0, 0, 0, dmadump.DmaMethodNormal)
    else:
        #breakpoint()
            #hex_list = []
            
            #print(self.input)
        currInput = inputs
        currInput.sort()
        ##Overwriting coreID into axon packets so they can go the correct core
        coreBits = np.binary_repr(coreID,5)+3*'0'#5 bits for coreID
        coreByte = int(coreBits,2)
        k = 0
        if cont_flag:
            commandList = []
        else:
            commandList = [0]*63+[1]
            commandList[64*k+62] = coreByte
            k = k+1
        for count in range(math.ceil(numAxons/512)):
                
            one_hot_bin = ["0"] * 512
            inputSegment = [i for i in currInput if (512*count) <= i and i < (512*count+512) ]
            for axon in inputSegment:
               one_hot_bin[axon%512] = "1"
            #one_hot_bin = one_hot_bin[::-1]
            while one_hot_bin:
                curr_byte = one_hot_bin[:8][::-1]
                curr_byte = "".join(curr_byte)
                commandList = commandList + [int(curr_byte, 2)]
                one_hot_bin = one_hot_bin[8:]
            commandList[64*k+62] = coreByte
            k = k+1
        #breakpoint()
        #print(coreByte)
        command = np.array(commandList, dtype=np.uint64)
        #print(command)
        if simDump:
            #breakpoint()
            splitcmd = np.split(command,len(command)/64)
            for idx,element in enumerate(splitcmd):
                splitcmd[idx] = ['{:0{width}x}'.format(i, width=2) for i in splitcmd[idx]]
                splitcmd[idx].reverse()
            dumpCmd = np.concatenate(splitcmd)
            #dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in splitcmd]
            #dumpCmd.reverse()
            dumpCmd = [[''.join(list(x))] for x in list(np.split(np.array(dumpCmd),count+2))] #add two since we're zero indexed and always have 1 extra packet
            #dumpCmd = ''.join(dumpCmd)
            return dumpCmd
        else:
            #breakpoint()
            exitCode = dmadump.dma_dump_write(command, len(command), 1, 0, 0, 0, dmadump.DmaMethodNormal)

        #exitCode = dmadump.dma_dump_write(command, len(command), 1, 0, 0, 0, dmadump.DmaMethodNormal)


'''
@interface.command()
def fullrun():
   """Untested
   """
   os.system('sudo ./hyddenn2_new.sh 0')
   base_functions.execute()
   base_functions.flush()
'''

def execute_step():
   """Duplicate of execute() without printing to terminal
   """
   base_functions.execute()

@interface.command()
@click.option('--nums',default=1,help='The number of the commands to flush')
def flush(nums):
    """Untested
    """
    base_functions.flush(nums)

def write_synapse_row(r, row, simDump = False, coreID = 0):
    '''
    Creates the necessary adxdma_dump commands to program the synapses into HBM
    Returns
    -------
    script : str
        The bash commands to run to program the synapses in HBM
    '''
    #breakpoint()
    #oldCommandPrefix = '02' + '{:0{width}x}'.format(coreID, width=2) + '000000000000000000000000000000000000000000000000000000'
    commandPrefix = [2, coreID] + [0]*27
    if simDump:
        dump = []
    #oldCmd = ''
    cmd = []
    for w in row:
        if w[0] == 0:
            # [31] = 0 for internal connections and 1 for external connections, [30:29] = unused for single core
            # TODO: how do I know if a given synapse is an internal or external connection?
            #oldCmd += '{:0{width}x}'.format(int(np.binary_repr( 0, SYN_OP_BITS) + np.binary_repr(int(w[1]), SYN_ADDR_BITS) + np.binary_repr(int(w[2]),SYN_WEIGHT_BITS), 2),width=8)
            binCmd = np.binary_repr( 0, SYN_OP_BITS) + np.binary_repr(int(w[1]), SYN_ADDR_BITS) +np.binary_repr(int(w[2]), SYN_WEIGHT_BITS)
            cmd = cmd + [int(binCmd[:8],2), int(binCmd[8:16],2), int(binCmd[16:24],2), int(binCmd[24:],2)]
        #TODO: looks like this format is out of date, it should be the same as the above format. It may not be hyper critical
        elif w[0] == 1:
            addr = np.binary_repr(w[1], SYN_ADDR_BITS)
            #oldCmd += '{:0{width}x}'.format(int(np.binary_repr( 4, SYN_OP_BITS) + 12*'0' + np.binary_repr(w[1],17), 2),width=8)
            binCmd = np.binary_repr( 4, SYN_OP_BITS) + 12*'0' + np.binary_repr(w[1],17)
            cmd = cmd + [int(binCmd[:8],2), int(binCmd[8:16],2), int(binCmd[16:24],2), int(binCmd[24:],2)]


    breakpoint()
    # append HBM write opcode and address
    rowAddress = '1'+np.binary_repr(SYN_BASE_ADDR+r,23) #rowAddress plus the leading one should be 24 bits
    #oldCmd = oldCommandPrefix + '{:0{width}x}'.format(0x800000 + SYN_BASE_ADDR + r, width=6) + oldCmd
    cmd = commandPrefix + [int(rowAddress[:8],2),int(rowAddress[8:16],2),int(rowAddress[16:],2)] + cmd
    #hexString = text2script(oldCmd)
    #oldFinalCmd = HBM_WRITE_CMD + hexString[:-1]
    finalCmd = np.flip(np.array(cmd,dtype=np.uint64))
    #n = n + 1

    # write to text file
    if simDump:
        dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in clearCommand]
        dumpCmd.reverse()
        dumpCmd = ''.join(dumpCmd)
        dump.append(dumpCmd)
        return dump
    else:
        #os.system(finalCmd)
        breakpoint()
        exitCode = dmadump.dma_dump_write(finalCmd, len(finalCmd), 1, 0, 0, 0, dmadump.DmaMethodNormal)

def HBM_decode(data):
    # 256bits data, 240 bit 0, 16 bit BBBB

    #translate data to binary
    data = np.flip(data)
    binData = [np.binary_repr(i,width=8) for i in data]
    binData = ''.join(binData)
    code = binData[:16]
    data = binData[-256:]
    for synapseIdx in range(8):
        start=32*synapseIdx
        stop = 32*(1+synapseIdx)
        synData = data[start:stop]
        op = synData[:3]
        address = synData[3:16]
        weight = synData[16:]
        print(op)

    #breakpoint()
    pass

def Read_synapse_row(r, simDump = False, coreID = 0):
    '''
    Creates the necessary adxdma_dump commands to Read the synapses from HBM
    Returns
    -------
    script : str
        The bash commands to run to program the synapses in HBM
    '''
    #breakpoint()
    #oldCommandPrefix = '02' + '{:0{width}x}'.format(coreID, width=2) + '000000000000000000000000000000000000000000000000000000'
    commandPrefix = [2, coreID] + [0]*27
    if simDump:
        dump = []
    #oldCmd = ''
    cmd = []
    rowAddress = '0'+np.binary_repr(SYN_BASE_ADDR+r,23) #rowAddress plus the leading zero should be 24 bits
    cmd = commandPrefix + [int(rowAddress[:8],2),int(rowAddress[8:16],2),int(rowAddress[16:],2)] + [0]*32
    finalCmd = np.flip(np.array(cmd,dtype=np.uint64))
    # write to text file
    if simDump:
        dumpCmd = ['{:0{width}x}'.format(i, width=2) for i in clearCommand]
        dumpCmd.reverse()
        dumpCmd = ''.join(dumpCmd)
        dump.append(dumpCmd)
        return dump
    else:
        #os.system(finalCmd)
        exitCode = dmadump.dma_dump_write(finalCmd, len(finalCmd), 1, 0, 0, 0, dmadump.DmaMethodNormal)
        print([hex(elem) for elem in finalCmd])


    exitCode, batchRead = dmadump.dma_dump_read(1, 0, 0, 0, dmadump.DmaMethodNormal, 64)
    print([hex(elem) for elem in batchRead])
    formatted = HBM_decode(batchRead)
    return batchRead


if __name__ == '__main__':
    interface()
