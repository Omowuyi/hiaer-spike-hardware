#!/usr/bin/env python3
"""
Thread the CMD 16 remote-destination signals out to the classifier.

Run add_cmd16_remote_cfg.py FIRST -- that adds the three ports to
command_interpreter.  This carries them the rest of the way:

    command_interpreter  ->  single_core  ->  core_wrapper  ->  top  ->  classifier

WHY CORE 0 ONLY
---------------
There is ONE spike_classifier for the device, sitting after switch_32_1, not
one per core.  So only one core's CMD 16 needs to reach it, and core 0 is the
natural choice.  The other fifteen cores still decode the command -- they share
the same command interpreter source -- but their outputs go nowhere, which
costs three unconnected signals per core and nothing else.

An alternative would be to OR the sixteen together, but that invites two cores
driving different entries in the same cycle.  Taking core 0 alone makes the
host's steering the single source of truth: a CMD 16 must be steered to core 0,
exactly as a CMD 15 must be steered to the core whose routing table it targets.

  python3 thread_cmd16.py --check <dir containing the three files>
  python3 thread_cmd16.py         <dir>
"""

import sys, os

EDITS = {
"single_core.sv": [
 ("port",
  "    output wire        iep_uram_out_of_range",
  """    output wire        iep_uram_out_of_range,

    // CMD 16: one entry of the classifier's remote destination table.
    // Only core 0's copy is used at the top -- there is one classifier per
    // device, not one per core.
    output wire        remote_cfg_valid,
    output wire [7:0]  remote_cfg_addr,
    output wire [5:0]  remote_cfg_data"""),
 ("ci_inst",
  "    ) ci (\n        .aclk(aclk),\n        .aresetn(aresetn),",
  """    ) ci (
        .remote_cfg_valid(remote_cfg_valid),
        .remote_cfg_addr(remote_cfg_addr),
        .remote_cfg_data(remote_cfg_data),
        .aclk(aclk),
        .aresetn(aresetn),"""),
],
"core_wrapper.sv": [
 ("port",
  "    output wire        iep_uram_out_of_range",
  """    output wire        iep_uram_out_of_range,

    // CMD 16, passed through from the command interpreter.
    output wire        remote_cfg_valid,
    output wire [7:0]  remote_cfg_addr,
    output wire [5:0]  remote_cfg_data"""),
 ("inner_inst",
  "    ) inst (\n        .aclk(aclk),\n        .aclk450(aclk450),",
  """    ) inst (
        .remote_cfg_valid(remote_cfg_valid),
        .remote_cfg_addr(remote_cfg_addr),
        .remote_cfg_data(remote_cfg_data),
        .aclk(aclk),
        .aclk450(aclk450),"""),
],
}


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: thread_cmd16.py [--check] <imports-dir>")
d = args[0]
if not os.path.isdir(d):
    fail("no such directory: %s" % d)

plan = []
for fname, edits in EDITS.items():
    p = os.path.join(d, fname)
    if not os.path.isfile(p):
        fail("missing: %s" % p)
    raw = open(p, errors="replace").read()
    s = raw.replace("\r\n", "\n")
    if "remote_cfg_valid" in s:
        fail("%s already has remote_cfg_valid" % fname)
    for tag, old, new in edits:
        n = s.count(old)
        if n != 1:
            fail("%s: anchor '%s' matched %d times, expected 1" % (fname, tag, n))
        plan.append((p, raw, fname, tag, old, new))
    print("  ok  %-20s %d anchor(s) verified" % (fname, len(edits)))

# the command interpreter must already carry the ports
ci = os.path.join(d, "command_interpreter.v")
if os.path.isfile(ci):
    if "remote_cfg_valid" not in open(ci, errors="replace").read():
        fail("command_interpreter.v has no remote_cfg_valid -- "
             "run add_cmd16_remote_cfg.py first")
    print("  ok  command_interpreter.v already carries the ports")

if check:
    print("""
--check: nothing written.

AFTER APPLYING, one edit left, in the top.  Core 0's signals drive the
classifier.  The cores are instantiated in a generate loop, so bring them out
into arrays and take index 0:

    wire        core_remote_cfg_valid [0:15];
    wire [7:0]  core_remote_cfg_addr  [0:15];
    wire [5:0]  core_remote_cfg_data  [0:15];

in the core_wrapper instantiation:

    .remote_cfg_valid (core_remote_cfg_valid[i]),
    .remote_cfg_addr  (core_remote_cfg_addr[i]),
    .remote_cfg_data  (core_remote_cfg_data[i]),

and in the spike_classifier instantiation:

    .remote_cfg_valid (core_remote_cfg_valid[0]),
    .remote_cfg_addr  (core_remote_cfg_addr[0]),
    .remote_cfg_data  (core_remote_cfg_data[0])

Send me the top's core_wrapper instantiation and I will write that as an
anchored patch too -- the generate loop's index name has to match exactly.

HOST SIDE

    cmd[63] = 16
    val     = (block << 6) | (server << 3) | fpga
    cmd[0]  = val & 0xFF
    cmd[1]  = (val >> 8) & 0xFF

steered to core 0 via HIAER_CORE_ID, the same way CMD 15 is steered.
""")
    sys.exit(0)

done = {}
for p, raw, fname, tag, old, new in plan:
    if p not in done:
        done[p] = raw
        bak = p + ".before_cmd16thread"
        if not os.path.exists(bak):
            open(bak, "w").write(raw)
    crlf = "\r\n" in done[p]
    s = open(p, errors="replace").read().replace("\r\n", "\n")
    s = s.replace(old, new, 1)
    open(p, "w").write(s.replace("\n", "\r\n") if crlf else s)

print("\npatched %d file(s)" % len(done))
print("The top still needs its edit -- see the --check notes.")
