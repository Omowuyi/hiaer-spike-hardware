#!/usr/bin/env python3
"""
Make the board identifier a run-time value and remove the two-tier gating.

WHY
---
The optical topology was corrected to the sixteen-link arrangement the machine
is cabled with, in which all eight boards use ports 4 through 7. The Aurora
instantiation was opened up to match. Three places in the router were not, and
on any board numbered below four they hold ports 4, 5 and 6 permanently
inactive, never build their transmit queues, and send every outbound spike to
port 7 whatever its destination. Four transceivers are present and three are
unreachable.

Separately, the identifier is a compile-time parameter, so eight bitstreams
would be needed, differing in one constant, with the attendant risk of loading
one board's image into another's slot.

Both follow from the same cause and are fixed together: once the gating is gone,
the identifier no longer selects what is built, only what is routed, and it can
be supplied by the host.

WHAT WAS VERIFIED FIRST
-----------------------
The topology table in the package was read and checked: sixteen bidirectional
links, no asymmetry, all fifty-six ordered board pairs reachable, thirty-two
directly and twenty-four through one intermediate board, none exceeding two
hops.

The routing function get_output_port was simulated over the same fifty-six
pairs: every pair is delivered, no path loops, and the maximum is two hops. The
routing logic was therefore already correct; the router was not calling it.

Every use of the identifier in the six modules that receive it was inspected and
found to be a comparison or a field assignment, never a selection of structure.
That is what makes the conversion from parameter to port safe.

A shorter route was considered and rejected. Reusing the existing remote
destination command would have needed a reserved table address, but that table
is 256 entries indexed by the upper eight bits of the neuron address, so every
address is a live routing entry and reserving one would silently misroute the
last 512 neurons of the last core.

THE EIGHT FILES
---------------
  inter_fpga_router.sv        three gates removed, parameter becomes a port
  firefly_subsystem_top.sv    parameter becomes a port and is passed on
  spike_classifier.sv         parameter becomes a port
  remote_spike_injector.sv    parameter becomes a port
  command_interpreter.v       new command, following the existing one at 16
  single_core.sv              two signals threaded out
  core_wrapper.sv             two signals threaded out
  sixteen_core_noc_firefly_top.sv   register, and the three connections

ORDER OF CONFIGURATION
----------------------
The classifier initialises its destination table from the identifier at reset,
so the host must set the identifier before loading the routing tables. Setting
it afterwards leaves the table holding the value from reset.

  python3 fix_runtime_fpga_id.py --check <directory of imports>
  python3 fix_runtime_fpga_id.py         <directory of imports>
"""

import sys, os

CMD_ID = 17          # the next opcode after the destination-table command at 16


def fail(m):
    sys.stderr.write("\nABORT: %s\nNothing was written to any file.\n" % m)
    sys.exit(1)


def load(d, name):
    p = os.path.join(d, name)
    if not os.path.isfile(p):
        fail("missing file: %s" % p)
    raw = open(p, errors="replace").read()
    return p, raw, ("\r\n" in raw), raw.replace("\r\n", "\n")


# every edit is (file, description, exact old text, new text)
def build_edits():
    E = []

    # ---------------------------------------------------------------- router
    # Each parameter removal and its matching port insertion is ONE edit, so
    # the two cannot become separated: removing the parameter without adding
    # the port leaves the identifier undeclared at every use.
    E.append(("inter_fpga_router.sv", "parameter to port", """#(
    parameter logic [2:0] LOCAL_FPGA_ID = 3'd0,  // This FPGA's ID (0-7)
    parameter int TX_FIFO_DEPTH = 64,            // TX buffer depth per port
    parameter int RX_FIFO_DEPTH = 64             // RX buffer depth
)(""", """#(
    parameter int TX_FIFO_DEPTH = 64,            // TX buffer depth per port
    parameter int RX_FIFO_DEPTH = 64             // RX buffer depth
)(
    // Board identifier, 0 to 7, from the host. It selects routes, not logic,
    // so it no longer has to be fixed when the bitstream is built.
    input  logic [2:0]      LOCAL_FPGA_ID,"""))
    E.append(("inter_fpga_router.sv", "port_active gate", """        port_active[0] = (LOCAL_FPGA_ID >= 3'd4) && port4_channel_up;  // Port 4
        port_active[1] = (LOCAL_FPGA_ID >= 3'd4) && port5_channel_up;  // Port 5
        port_active[2] = (LOCAL_FPGA_ID >= 3'd4) && port6_channel_up;  // Port 6""",
              """        // Every board uses all four ports under the cabled topology, so a
        // port is active exactly when its link is up.
        port_active[0] = port4_channel_up;
        port_active[1] = port5_channel_up;
        port_active[2] = port6_channel_up;"""))
    E.append(("inter_fpga_router.sv", "routing gate", """                if (LOCAL_FPGA_ID <= 3'd3) begin
                    // Lower tier FPGA: always route through Port 7 to upper tier
                    tx_output_port = PORT_7;
                end else begin
                    // Upper tier FPGA: complex routing through mesh
                    tx_output_port = compute_mesh_route(LOCAL_FPGA_ID, dest_fpga);
                end""",
              """                // The package holds the routing for the cabled topology. It was
                // checked over all fifty-six ordered pairs: thirty-two direct,
                // twenty-four through one board, none longer and none looping.
                tx_output_port = get_output_port(LOCAL_FPGA_ID, dest_fpga);"""))
    E.append(("inter_fpga_router.sv", "fifo gate",
              "            if (p == 3 || LOCAL_FPGA_ID >= 3'd4) begin : fifo_inst\n",
              "            // All four ports carry traffic on every board, and the\n"
              "            // identifier is no longer known at elaboration.\n"
              "            if (1) begin : fifo_inst\n"))

    # ------------------------------------------------------------- subsystem
    E.append(("firefly_subsystem_top.sv", "parameter block", """#(
    parameter logic [2:0] FPGA_ID = 3'd0    // Set for each FPGA (0-7)
)(""", """(
    // Board identifier, from the host, passed through to the router.
    input  logic [2:0] FPGA_ID,"""))
    E.append(("firefly_subsystem_top.sv", "router connection",
              "        .LOCAL_FPGA_ID      (FPGA_ID),\n        .TX_FIFO_DEPTH      (64),",
              "        .TX_FIFO_DEPTH      (64),"))
    E.append(("firefly_subsystem_top.sv", "router port", "    ) u_router (",
              "    ) u_router (\n        .LOCAL_FPGA_ID      (FPGA_ID),"))
    # Port 7 sits at twelve spaces; ports 6, 5 and 4 are nested one level
    # deeper inside the generate and sit at sixteen. Verified with cat -A.
    E.append(("firefly_subsystem_top.sv", "wrapper 7 parameter",
              "            .PORT_NUM           (7),\n"
              "            .FPGA_ID            (FPGA_ID),\n",
              "            .PORT_NUM           (7),\n"))
    for n in (6, 5, 4):
        E.append(("firefly_subsystem_top.sv", "wrapper %d parameter" % n,
                  "                .PORT_NUM           (%d),\n"
                  "                .FPGA_ID            (FPGA_ID),\n" % n,
                  "                .PORT_NUM           (%d),\n" % n))

    # ------------------------------------------------- classifier / injector
    E.append(("spike_classifier.sv", "parameter to port", """#(
    parameter logic [2:0] LOCAL_FPGA_ID = 3'd0,
    parameter int         BLOCK_BITS    = 8      // addr[16:9] -> 256 blocks
)(""", """#(
    parameter int         BLOCK_BITS    = 8      // addr[16:9] -> 256 blocks
)(
    // Board identifier, from the host. Note that the destination table is
    // seeded from this at reset, so it must be set before the tables load.
    input  logic [2:0]      LOCAL_FPGA_ID,"""))
    E.append(("remote_spike_injector.sv", "parameter to port", """#(
    parameter logic [2:0] LOCAL_FPGA_ID = 3'd0,
    parameter int BATCH_SIZE = 14,
    parameter int TIMEOUT_CYCLES = 256
)(""", """#(
    parameter int BATCH_SIZE = 14,
    parameter int TIMEOUT_CYCLES = 256
)(
    // Board identifier, from the host.
    input  logic [2:0]      LOCAL_FPGA_ID,"""))

    # --------------------------------------------------- command interpreter
    E.append(("command_interpreter.v", "opcode",
              "localparam [7:0] CMD_REMOTE_DST_W = 8'd16;",
              "localparam [7:0] CMD_REMOTE_DST_W = 8'd16;\n"
              "// Board identifier, so one bitstream serves every chassis position.\n"
              "localparam [7:0] CMD_FPGA_ID_W    = 8'd%d;" % CMD_ID))
    E.append(("command_interpreter.v", "outputs",
              "   output reg        remote_cfg_valid,",
              "   output reg        fpga_id_valid,\n"
              "   output reg  [2:0] fpga_id_data,\n"
              "   output reg        remote_cfg_valid,"))
    E.append(("command_interpreter.v", "defaults",
              "   remote_cfg_valid = 1'b0;",
              "   fpga_id_valid    = 1'b0;\n"
              "   fpga_id_data     = rxFIFO_dout[2:0];\n"
              "   remote_cfg_valid = 1'b0;"))
    E.append(("command_interpreter.v", "decode", """               CMD_REMOTE_DST_W: begin
                  remote_cfg_valid = 1'b1;""",
              """               CMD_FPGA_ID_W: begin
                  fpga_id_valid = 1'b1;
                  rxFIFO_rden   = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               CMD_REMOTE_DST_W: begin
                  remote_cfg_valid = 1'b1;"""))

    # ------------------------------------------------------------- threading
    for f, w in (("single_core.sv", "    output wire [5:0]  remote_cfg_data\n"),
                 ("core_wrapper.sv", "    output wire [5:0]  remote_cfg_data\n")):
        E.append((f, "port list",
                  w,
                  "    output wire [5:0]  remote_cfg_data,\n"
                  "    output wire        fpga_id_valid,\n"
                  "    output wire [2:0]  fpga_id_data\n"))
        E.append((f, "connection",
                  "        .remote_cfg_data(remote_cfg_data),\n",
                  "        .remote_cfg_data(remote_cfg_data),\n"
                  "        .fpga_id_valid(fpga_id_valid),\n"
                  "        .fpga_id_data(fpga_id_data),\n"))

    # ------------------------------------------------------------- top level
    E.append(("sixteen_core_noc_firefly_top.sv", "identifier register",
              "    localparam logic [2:0] THIS_FPGA_ID = 3'd0;   // set per device before build",
              """    // The board identifier arrives from the host, so one bitstream serves
    // every position. It must be set before the routing tables are loaded:
    // the classifier seeds its destination table from it at reset.
    wire        core_fpga_id_valid [0:15];
    wire [2:0]  core_fpga_id_data  [0:15];
    reg  [2:0]  THIS_FPGA_ID = 3'd0;
    always @(posedge aclk)
        if (core_fpga_id_valid[0]) THIS_FPGA_ID <= core_fpga_id_data[0];"""))
    # Each is a parameter block today. Remove it and pass the identifier as a
    # port instead, anchored on the module and instance names together so the
    # edit cannot land on a different instantiation.
    E.append(("sixteen_core_noc_firefly_top.sv", "classifier connection",
              """    spike_classifier #(
        .LOCAL_FPGA_ID (THIS_FPGA_ID)
    ) ff_classifier (""",
              """    spike_classifier ff_classifier (
        .LOCAL_FPGA_ID   (THIS_FPGA_ID),"""))
    E.append(("sixteen_core_noc_firefly_top.sv", "subsystem connection",
              """    firefly_subsystem_top #(
        .FPGA_ID (THIS_FPGA_ID)
    ) ff_subsys (""",
              """    firefly_subsystem_top ff_subsys (
        .FPGA_ID       (THIS_FPGA_ID),"""))
    E.append(("sixteen_core_noc_firefly_top.sv", "injector connection",
              """    remote_spike_injector #(
        .LOCAL_FPGA_ID (THIS_FPGA_ID)
    ) ff_injector (""",
              """    remote_spike_injector ff_injector (
        .LOCAL_FPGA_ID (THIS_FPGA_ID),"""))
    # The live core generate block, indexed by j. The commented-out block at
    # lines 576 to 634 is dead and must not be touched; the classifier's own
    # remote_cfg connections use [0] and are a different site entirely.
    E.append(("sixteen_core_noc_firefly_top.sv", "core identifier wires",
              """                    .remote_cfg_valid(core_remote_cfg_valid[j]),
                    .remote_cfg_addr(core_remote_cfg_addr[j]),
                    .remote_cfg_data(core_remote_cfg_data[j]),""",
              """                    .remote_cfg_valid(core_remote_cfg_valid[j]),
                    .remote_cfg_addr(core_remote_cfg_addr[j]),
                    .remote_cfg_data(core_remote_cfg_data[j]),
                    .fpga_id_valid(core_fpga_id_valid[j]),
                    .fpga_id_data(core_fpga_id_data[j]),"""))
    return E


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_runtime_fpga_id.py [--check] <imports directory>")
D = args[0]
if not os.path.isdir(D):
    fail("not a directory: %s" % D)

edits = build_edits()
files = {}
for f, _, _, _ in edits:
    if f not in files:
        files[f] = load(D, f)

print("Verifying %d edits across %d files.\n" % (len(edits), len(files)))
ok = bad = 0
for f, desc, old, new in edits:
    s = files[f][3]
    n = s.count(old)
    if n == 1:
        print("  ok    %-34s %s" % (f, desc)); ok += 1
    else:
        print("  MISS  %-34s %s   (matched %d)" % (f, desc, n)); bad += 1

print("\n%d verified, %d not found." % (ok, bad))
if bad:
    fail("%d anchors did not match exactly once. Nothing written. Send the "
         "MISS lines and the surrounding source so the anchors can be "
         "corrected." % bad)

if check:
    print("""
--check: nothing written. Every anchor matches exactly once.

Applying will change eight files. Elaborate before synthesising:

  synth_design -rtl -name idchk -top sixteen_core_noc_firefly_top \\
               -part xcvu37p-fsvh2892-2-e

A missed connection here does not fail loudly. It misroutes spikes.
""")
    sys.exit(0)

# compute_mesh_route encoded the earlier two-tier next-hop table and nothing
# calls it once the routing gate is gone. Removing it prevents a future reader
# from mistaking it for the live routing.
def strip_mesh_route(text):
    i = text.find("    function automatic logic [1:0] compute_mesh_route(")
    if i < 0:
        return text
    j = text.find("endfunction", i)
    if j < 0:
        return text
    j = text.find("\n", j) + 1
    return text[:i] + ("    // compute_mesh_route removed with the two-tier gating: the package\n"
                       "    // function get_output_port supplies routing for the cabled topology.\n") + text[j:]


for f in files:
    p, raw, crlf, s = files[f]
    for ef, desc, old, new in edits:
        if ef == f:
            s = s.replace(old, new, 1)
    if f == "inter_fpga_router.sv":
        s = strip_mesh_route(s)
    bak = p + ".before_runtimeid"
    if not os.path.exists(bak):
        open(bak, "w").write(raw)
    open(p, "w").write(s.replace("\n", "\r\n") if crlf else s)
    print("  patched %s" % f)

print("\nAll eight files patched. Backups end .before_runtimeid")
print("The host sets the identifier with command %d before loading routing tables." % CMD_ID)
