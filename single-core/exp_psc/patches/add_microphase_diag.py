#!/usr/bin/env python3
"""
Isolate WHICH STAGE loses microphase-1 spikes -- error_status bits 12-15.

CONFIRMED SYMPTOM
At low spike load (14 probes, no FIFO overflow possible): microphase 0 lost
0 of 7, microphase 1 lost 7 of 7.  Everything from neuron 8192 up is silent.
~1808 neurons in a 10016-neuron network; ~92% of the large DVS model.

WHY INSTRUMENT INSTEAD OF PATCHING
A microphase-1 spike passes through four stages:

    1. IEP Phase 1 detects it and pushes a neuron pointer
    2. TX fetches that neuron's pointer from HBM (with the microphase offset)
    3. RX completes Phase 1 for that microphase
    4. Phase 2 reads the synapse rows; the spike entry sets spk*_wren

Nine fix attempts failed because they guessed at the stage.  These four bits
name it in one run, and they are mutually exclusive:

    bit 12 SET   the IEP DID detect a spike at a row >= 512
    bit 13 SET   a spike with address >= 8192 reached a spike FIFO
    bit 14 SET   TX issued an output-pointer read for a microphase != 0
    bit 15 SET   RX completed Phase 1 with rx_output_microphase_ctr != 0

    12=1, 13=0  -> detected then lost between the IEP and the FIFO
    12=0        -> the IEP never detects it; the bug is in Phase 1 itself
    14=0        -> microphase 1's pointers are never fetched
    15=0        -> RX never completes Phase 1 for microphase 1

All four are single comparisons feeding sticky registers.  No high-fanout net
is preserved, unlike the mark_debug attempt that cost 828 ps of WNS.

  python3 add_microphase_diag.py --check <internal_events_processor.v> <hbm_processor.v> <single_core.sv> <command_interpreter.v>
  python3 add_microphase_diag.py         <same four files>

Apply to the REVERTED IEP (normalized 2cc062c7a7807f202fb2f3e859f630a3) and
alongside FIX V.  Read with CMD 10 after a test that spans two microphases.
"""

import sys, os


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 4:
    fail("usage: add_microphase_diag.py [--check] <internal_events_processor.v> "
         "<hbm_processor.v> <single_core.sv> <command_interpreter.v>")
iep_p, hp_p, sc_p, ci_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

iep = open(iep_p).read()
hp = open(hp_p).read()
sc = open(sc_p).read()
ci = open(ci_p).read()
for p, s in ((iep_p, iep), (hp_p, hp), (sc_p, sc), (ci_p, ci)):
    if "dbg_mp1" in s or "dbg_spike_hi" in s:
        fail("%s already patched." % p)

edits = []

# ---------------- IEP: bit 12 ----------------
o = "    input  wire [3:0]  dbuf_delayed_group,   // FIX I: bank for the drained entry\n"
if iep.count(o) != 1:
    fail("dbuf_delayed_group port not found exactly once in %s.\n"
         "       Is this the reverted IEP with wire_syn64 applied?" % iep_p)
edits.append((iep_p, o,
  "    // DIAG: Phase 1 detected a spike at a URAM row >= 512, i.e. a neuron\n"
  "    // at or above 8192.  Sticky, cleared only by reset.\n"
  "    output reg         dbg_spike_hi,\n" + o, "IEP port"))

o = ("always @(posedge clk) begin\n"
     "    if (~resetn) curr_state <= STATE_RESET;\n"
     "    else         curr_state <= next_state;\n"
     "end")
if iep.count(o) != 1:
    fail("FSM state register block not found exactly once in %s (%d)"
         % (iep_p, iep.count(o)))
edits.append((iep_p, o,
  "// DIAG bit 12: did Phase 1 ever detect a spike above the first microphase?\n"
  "always @(posedge clk) begin\n"
  "    if (~resetn)\n"
  "        dbg_spike_hi <= 1'b0;\n"
  "    else if (curr_state == STATE_PUSH_PTR_FIFO && (|exec_uram_spiked) &&\n"
  "             uram_raddr >= 13'd512)\n"
  "        dbg_spike_hi <= 1'b1;\n"
  "end\n\n" + o, "IEP sticky flag"))

# ---------------- hbm_processor: bits 13, 14, 15 ----------------
o = "    output          spk_dropped,\n"
if hp.count(o) != 1:
    fail("spk_dropped output not found exactly once in %s -- run "
         "detect_spike_drop.py first." % hp_p)
edits.append((hp_p, o,
  "    // DIAG: a spike with address >= 8192 reached a spike FIFO\n"
  "    output reg      dbg_mp1_spike,\n"
  "    // DIAG: TX issued an output-pointer read for a microphase other than 0\n"
  "    output reg      dbg_mp1_tx,\n"
  "    // DIAG: RX completed Phase 1 with a nonzero output microphase counter\n"
  "    output reg      dbg_mp1_rx,\n" + o, "HBM ports"))

o = "wire spk_attempt = exec_hbm_rx_phase1_done & exec_hbm_rvalidready_2x;\n"
if hp.count(o) != 1:
    fail("spk_attempt wire not found exactly once in %s -- run "
         "detect_spike_drop.py first." % hp_p)
edits.append((hp_p, o, o +
  """
//=========================================================================
// DIAG bits 13-15.  Each is one comparison into a sticky register; nothing
// high-fanout is preserved, so the timing cost is negligible.
//=========================================================================
wire dbg_any_hi_spike =
    (spk0_wren & (spk0_din >= 17'd8192)) | (spk1_wren & (spk1_din >= 17'd8192)) |
    (spk2_wren & (spk2_din >= 17'd8192)) | (spk3_wren & (spk3_din >= 17'd8192)) |
    (spk4_wren & (spk4_din >= 17'd8192)) | (spk5_wren & (spk5_din >= 17'd8192)) |
    (spk6_wren & (spk6_din >= 17'd8192)) | (spk7_wren & (spk7_din >= 17'd8192));

always @(posedge clk) begin
    if (~resetn) begin
        dbg_mp1_spike <= 1'b0;
        dbg_mp1_tx    <= 1'b0;
        dbg_mp1_rx    <= 1'b0;
    end else begin
        if (dbg_any_hi_spike)
            dbg_mp1_spike <= 1'b1;
        if (tx_curr_state == TX_STATE_SEND_OUTPUT_READ_COMMANDS &&
            tx_output_microphase_ctr != 4'd0)
            dbg_mp1_tx <= 1'b1;
        if (rx_curr_state == RX_STATE_PHASE1_DONE &&
            rx_output_microphase_ctr != 4'd0)
            dbg_mp1_rx <= 1'b1;
    end
end
""", "HBM sticky flags"))

# ---------------- single_core ----------------
o = "    wire        w_spk_dropped;   // spike discarded, FIFO full\n"
if sc.count(o) != 1:
    fail("w_spk_dropped declaration not found exactly once in %s" % sc_p)
edits.append((sc_p, o, o +
  "    wire        w_dbg_spike_hi;  // DIAG bit 12\n"
  "    wire        w_dbg_mp1_spike; // DIAG bit 13\n"
  "    wire        w_dbg_mp1_tx;    // DIAG bit 14\n"
  "    wire        w_dbg_mp1_rx;    // DIAG bit 15\n", "SC wires"))

o = "        .dbuf_delayed_group(w_dbuf_delayed_group),\n"
if sc.count(o) != 1:
    fail("IEP dbuf_delayed_group hookup not found exactly once in %s" % sc_p)
edits.append((sc_p, o, "        .dbg_spike_hi(w_dbg_spike_hi),\n" + o, "SC IEP hookup"))

o = "        .spk_dropped(w_spk_dropped),\n        .hbm_curr_state(hbm_curr_state)"
if sc.count(o) != 1:
    fail("hbm_processor spk_dropped/hbm_curr_state hookup not found exactly once "
         "in %s (%d)" % (sc_p, sc.count(o)))
edits.append((sc_p, o,
  "        .dbg_mp1_spike(w_dbg_mp1_spike),\n"
  "        .dbg_mp1_tx(w_dbg_mp1_tx),\n"
  "        .dbg_mp1_rx(w_dbg_mp1_rx),\n" + o, "SC HBM hookup"))

o = ("        .spk_dropped(w_spk_dropped),\n"
     "        .delay_table_waddr(w_delay_table_waddr),")
if sc.count(o) != 1:
    fail("CI spk_dropped/delay_table hookup not found exactly once in %s" % sc_p)
edits.append((sc_p, o,
  "        .spk_dropped(w_spk_dropped),\n"
  "        .dbg_spike_hi(w_dbg_spike_hi),\n"
  "        .dbg_mp1_spike(w_dbg_mp1_spike),\n"
  "        .dbg_mp1_tx(w_dbg_mp1_tx),\n"
  "        .dbg_mp1_rx(w_dbg_mp1_rx),\n"
  "        .delay_table_waddr(w_delay_table_waddr),", "SC CI hookup"))

# ---------------- command_interpreter ----------------
o = "   input        spk_dropped,\n"
if ci.count(o) != 1:
    fail("spk_dropped input not found exactly once in %s" % ci_p)
edits.append((ci_p, o, o +
  "\n   // DIAG: which stage loses microphase-1 spikes\n"
  "   input        dbg_spike_hi,   // 12: IEP detected a spike above row 512\n"
  "   input        dbg_mp1_spike,  // 13: a spike >= 8192 reached a FIFO\n"
  "   input        dbg_mp1_tx,     // 14: TX read microphase-1 output pointers\n"
  "   input        dbg_mp1_rx,     // 15: RX finished Phase 1 in microphase 1\n",
  "CI ports"))

o = "            error_status[11] <= 1'b1; // spike discarded, per-group FIFO full\n"
if ci.count(o) != 1:
    fail("error_status[11] assignment not found exactly once in %s" % ci_p)
edits.append((ci_p, o, o +
  "        if (dbg_spike_hi)  error_status[12] <= 1'b1;\n"
  "        if (dbg_mp1_spike) error_status[13] <= 1'b1;\n"
  "        if (dbg_mp1_tx)    error_status[14] <= 1'b1;\n"
  "        if (dbg_mp1_rx)    error_status[15] <= 1'b1;\n", "CI sticky bits"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {iep_p: iep, hp_p: hp, sc_p: sc, ci_p: ci}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_diag"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))

print("""
Run a test spanning two microphases (test_microphase_lowload.py does), then
read CMD 10.  The bit pattern names the stage; no further guessing needed.
""")
