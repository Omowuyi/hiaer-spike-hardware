#!/usr/bin/env python3
"""
Stop the receiver destroying the neuron address of every inter-device spike.

THE DEFECT
----------
A spike leaving a device carries the full neuron index. The classifier sets it
directly:

    spike_classifier.sv:321
        m_firefly_spike.dst_neuron = spike_addr[spike_idx];

which is the flat seventeen-bit index of a neuron within the device, sixteen
cores of 8,192.

The receiver reassembles it as though the index were three bits of device,
four of core and ten of neuron:

    remote_spike_injector.sv:97-99
        result[16:14] = spike.dst_fpga;
        result[13:10] = spike.dst_core;
        result[9:0]   = spike.dst_neuron[9:0];

That layout holds only if a core has 1,024 neurons. A core has 8,192, which
needs thirteen bits, so the low ten bits of the address are kept and the upper
seven are overwritten with device and core numbers. A spike addressed to neuron
5,000 arrives at neuron 904.

This is the same misreading of the address that was found and corrected in the
classifier's get_dest_fpga, surviving here in a second module. Nothing has
caught it because no optical link has yet carried a spike.

THE CORRECT LAYOUT
------------------
The command interpreter builds every spike word in the design, and it is the
reference:

    command_interpreter.v:994
        {execRun_ctr[7:0], 1'b1, 2'b00, CORE_ID[3:0], spk2ciFIFO_dout, ...}
         [31:24] timestamp  [23] valid  [22:21] fpga  [20:17] core  [16:0] neuron

The core number occupies [20:17], above the address, and the seventeen bits of
[16:0] are the neuron index entire. The receiving side agrees: the events
processor splits an incoming address as {row[16:4], group[3:0]}, a flat index
with no device or core embedded in it.

WHAT THIS WRITES
----------------
The neuron index passes through whole, and the core number is placed in the
field the rest of the design uses for it.

  python3 fix_convert_spike.py --check <remote_spike_injector.sv>
  python3 fix_convert_spike.py         <remote_spike_injector.sv>
"""

import sys, os

OLD = """        // [22:17] = flags/reserved
        result[22:17] = 6'b0;
        // [16:0] = destination neuron (encode core + neuron)
        result[16:14] = spike.dst_fpga;      // Should be LOCAL_FPGA_ID for received spikes
        result[13:10] = spike.dst_core;
        result[9:0] = spike.dst_neuron[9:0]; // Lower 10 bits of neuron ID"""

NEW = """        // [22:21] = device, reserved, and [20:17] = core, matching the word
        // the command interpreter builds at line 994. The core sits ABOVE the
        // address; it is not folded into it.
        result[22:21] = 2'b00;
        result[20:17] = spike.dst_core;
        // [16:0] = the neuron index entire. A core holds 8,192 neurons and the
        // device 131,072, so all seventeen bits are index: taking only the low
        // ten and overwriting the rest, as this function previously did,
        // delivered every arriving spike to the wrong neuron.
        result[16:0] = spike.dst_neuron;"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_convert_spike.py [--check] <remote_spike_injector.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "result[16:0] = spike.dst_neuron;" in s:
    fail("already patched")

n = s.count(OLD)
if n != 1:
    fail("anchor matched %d times, expected 1" % n)
print("  ok  convert_spike body found (line %d)"
      % (s[:s.index(OLD)].count("\n") + 1))

for tag, needle in (("result is 32 bits", "logic [31:0] result;"),
                    ("timestamp at [31:24]", "result[31:24] = spike.timestamp;"),
                    ("valid at [23]", "result[23] = 1'b1;"),
                    ("dst_core exists", "spike.dst_core"),
                    ("dst_neuron exists", "spike.dst_neuron")):
    if needle not in s:
        fail("expected %s; the packet or the function differs from what this "
             "patch assumes" % tag)
    print("  ok  %s" % tag)

if check:
    print("""
--check: nothing written.

AFTER APPLYING, run tb_convert_spike. It drives neuron indices that exercise
bits above the low ten and checks that each arrives whole, which the current
function cannot do. A test using only small indices would pass either way and
prove nothing.
""")
    sys.exit(0)

out = s.replace(OLD, NEW, 1)
bak = p + ".before_convertspike"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Arriving spikes now keep their full neuron index.")
