#!/usr/bin/env python3
"""
coreID field width in write_parameters_simple and write_neuron_type.

THE BUG

switch_1_32.sv:9 is the only thing that decides which core a 512-bit host
command reaches:

    assign m.tdest = s.tdata[503:499];

FIVE bits, [503:499] -- the top five bits of byte 62.  command_interpreter.v
never reads a coreID from the packet at all; CORE_ID there is a compile-time
parameter used only to tag outgoing spikes.

Eight functions in fpga_controller.py encode that correctly:

    coreBits = np.binary_repr(coreID,5)+3*'0'      byte 62 = coreID << 3

Two do not.  write_parameters_simple (CMD 4) and write_neuron_type (CMD 8)
write an EIGHT bit field across [503:496]:

    command[8:16] = list(np.binary_repr(coreID,8)) byte 62 = coreID

so tdest sees coreID >> 3.  Core 1 is steered to core 0, cores 1-7 all land on
core 0, and core 8 lands on core 1.

WHY IT HAS NEVER SHOWN UP

At coreID 0 both encodings are 0x00, and every test to date has run on core 0.
It becomes load-bearing the moment initalize_network programs each core with
its own target -- the per-core parameters and neuron models would all be
written to core 0, leaving cores 1-15 running on reset defaults.

THE FIX

Use the same 5-bit field the other eight sites use.  Behaviour at coreID 0 is
unchanged, so the single-core regression is unaffected.

  python3 fix_coreid_width.py --check <fpga_controller.py>
  python3 fix_coreid_width.py         <fpga_controller.py>
"""

import sys
import os
import shutil
import io

BACKUP_SUFFIX = ".before_coreidfix"

OLD_PARAMS = '''    command[:8] = list(np.binary_repr(4,8)) #511-504: command ID (0x04)
    command[8:16] = list(np.binary_repr(coreID,8)) #503-496: CoreID
'''

NEW_PARAMS = '''    command[:8] = list(np.binary_repr(4,8)) #511-504: command ID (0x04)
    #switch_1_32 takes tdest from tdata[503:499] -- FIVE bits.  An 8-bit field
    #here would be read as coreID >> 3 and steer the command to the wrong core.
    command[8:13] = list(np.binary_repr(coreID,5)) #503-499: CoreID (tdest)
    command[13:16] = list('000')                   #498-496: unused
'''

OLD_NTYPE = '''    command[:8] = list(np.binary_repr(8,8)) #511-504: command ID (0x08)
    command[8:16] = list(np.binary_repr(coreID,8)) #503-496: CoreID
'''

NEW_NTYPE = '''    command[:8] = list(np.binary_repr(8,8)) #511-504: command ID (0x08)
    #see write_parameters_simple: tdest is tdata[503:499], five bits
    command[8:13] = list(np.binary_repr(coreID,5)) #503-499: CoreID (tdest)
    command[13:16] = list('000')                   #498-496: unused
'''

EDITS = [
    ("write_parameters_simple (CMD 4)", OLD_PARAMS, NEW_PARAMS),
    ("write_neuron_type (CMD 8)", OLD_NTYPE, NEW_NTYPE),
]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv

    if not args:
        print("usage: fix_coreid_width.py [--check] <fpga_controller.py>")
        return 2
    path = args[0]

    if not os.path.isfile(path):
        print("FAIL  no such file: %s" % path)
        return 2

    src = io.open(path, encoding="utf-8").read()

    if "503-499: CoreID (tdest)" in src:
        print("ALREADY APPLIED  %s" % path)
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

    remaining = src.count("np.binary_repr(coreID,8)")
    print("  8-bit coreID sites found: %d (expected 2)" % remaining)

    if not ok:
        print("\nFAIL  anchors do not match -- nothing written.")
        return 1

    if check_only:
        print("\nCHECK PASSED  re-run without --check to apply.")
        return 0

    out = src
    for name, old, new in EDITS:
        out = out.replace(old, new, 1)

    backup = path + BACKUP_SUFFIX
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
        print("\nbackup   %s" % backup)
    io.open(path, "w", encoding="utf-8").write(out)
    print("applied  2/2 edits to %s" % path)

    left = out.count("np.binary_repr(coreID,8)")
    print("8-bit coreID sites remaining: %d  %s"
          % (left, "OK" if left == 0 else "STILL PRESENT"))

    import py_compile
    try:
        py_compile.compile(path, doraise=True)
        print("syntax   OK")
    except py_compile.PyCompileError as e:
        print("SYNTAX ERROR: %s" % e)
        print("restore with: cp %s %s" % (backup, path))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
