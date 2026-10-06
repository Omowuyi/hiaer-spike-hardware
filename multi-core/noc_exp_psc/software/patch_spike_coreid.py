#!/usr/bin/env python3
"""
CORE_ID in the spike decode  --  layer 2a of multi-core placement.

WHAT THIS CHANGES

The v3 spike word, assembled at command_interpreter.v:995 as
    {execRun_ctr[7:0], 1'b1, CORE_ID[3:0], spk2ciFIFO_dout[18:0]}
carries the emitting core at bits [22:19].  processSpikePacket reads the
address and throws the core away, so with a real partition all sixteen cores
report into one index range and a spike cannot be resolved to a neuron.

After this patch each spike is (counter, address, coreID).  The core is
APPENDED as a third element rather than inserted, so every existing consumer
that reads spike[1] as the address is unaffected -- inside this file the five
read_spikes callers only concatenate lists, and in api.py the three
get_neuron_by_hbmIdx(spike[1]) sites keep working until they are made
core-aware.

The 19-bit address width is assumed already applied.  The script reports if it
is not, since decoding 19 bits is what makes the core field meaningful.

  python3 patch_spike_coreid.py --check <path to fpga_controller.py>
  python3 patch_spike_coreid.py         <path to fpga_controller.py>
"""

import sys
import os
import shutil
import io

BACKUP_SUFFIX = ".before_coreid"

OLD_READ_LOOP = '''        subexecutionRun_counter, address = processSpikePacket(spikePacket)
        if (subexecutionRun_counter != None and address != None):
            spikeList.append((subexecutionRun_counter,address))
'''

NEW_READ_LOOP = '''        subexecutionRun_counter, address, coreID = processSpikePacket(spikePacket)
        if (subexecutionRun_counter != None and address != None):
            #core is APPENDED as a third element, so callers reading spike[1]
            #as the address are unaffected
            spikeList.append((subexecutionRun_counter, address, coreID))
'''

OLD_PROCESS = '''    valid = bool(int(spikePacket[8])) #check if it's a valid spike packet
    if valid:
        subexecutionRun_counter = int(spikePacket[0:8], 2)
        address = int(spikePacket[-19:],2)
        #breakpoint()
        return subexecutionRun_counter, address
    else:
        return None, None
'''

NEW_PROCESS = '''    valid = bool(int(spikePacket[8])) #check if it's a valid spike packet
    if valid:
        #v3 spike word, MSB first (command_interpreter.v:995):
        #  [0:8]    execRun_ctr[7:0]
        #  [8]      valid
        #  [9:13]   CORE_ID[3:0]    core that emitted the spike
        #  [13:32]  address[18:0]   per-core neuron index, row * 16 + group
        subexecutionRun_counter = int(spikePacket[0:8], 2)
        coreID = int(spikePacket[9:13], 2)
        address = int(spikePacket[-19:],2)
        #breakpoint()
        return subexecutionRun_counter, address, coreID
    else:
        return None, None, None
'''

EDITS = [
    ("read_spikes loop", OLD_READ_LOOP, NEW_READ_LOOP),
    ("processSpikePacket", OLD_PROCESS, NEW_PROCESS),
]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv

    if not args:
        print("usage: patch_spike_coreid.py [--check] <path to fpga_controller.py>")
        return 2
    path = args[0]

    if not os.path.isfile(path):
        print("FAIL  no such file: %s" % path)
        return 2

    src = io.open(path, encoding="utf-8").read()

    if "coreID = int(spikePacket[9:13], 2)" in src:
        print("ALREADY APPLIED  %s decodes CORE_ID" % path)
        return 0

    if "spikePacket[-17:]" in src:
        print("FAIL  this file still decodes a 17-bit address.")
        print("      Apply the 19-bit widening first, then re-run this patch.")
        return 1

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
        print("\nCHECK PASSED  2/2 anchors match.  Re-run without --check to apply.")
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
    print("applied  2/2 edits to %s" % path)

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
