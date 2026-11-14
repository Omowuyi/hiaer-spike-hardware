#!/usr/bin/env python3
"""
fix_ila.py -- add debug taps for the core-1 capture build.

Adds, at the end of each module, wires that copy existing signals and carry
(* mark_debug = "true" *).  They feed nothing but the ILA, so the design's behaviour is
unchanged; synthesis keeps them under exactly these names and produces each state machine's
binary value whatever encoding it chooses.  Each insertion point must be found exactly once,
otherwise NOTHING is written.  Backups: <file>.before_ila  (undo: copy them back).
Usage: python3 fix_ila.py <imports directory>
"""
import os, re, shutil, sys
D = sys.argv[1] if len(sys.argv) > 1 else "."
MD = '(* mark_debug = "true" *) '
TAPS = {
  ("hbm_processor.v", "hbm_processor"): [
    "wire [3:0]  dbg_tx_state           = tx_curr_state;",
    "wire [3:0]  dbg_rx_state           = rx_curr_state;",
    "wire [22:0] dbg_tx_ptr_ctr         = tx_ptr_ctr;",
    "wire [22:0] dbg_rx_ptr_ctr         = rx_ptr_ctr;",
    "wire [7:0]  dbg_wait_clks_cnt      = wait_clks_cnt;",
    "wire [4:0]  dbg_wait_clks_done_cnt = wait_clks_done_cnt;",
    "wire [5:0]  dbg_phase  = {tx_done_rst, tx_phase1_done, tx_phase2_done, rx_done_rst, rx_phase1_done, rx_phase2_done};",
    "wire [2:0]  dbg_in     = {exec_run, exec_bram_phase1_ready, exec_uram_phase1_ready};",
    "wire [3:0]  dbg_fifo   = {exec_hbm_rvalidready, hbmFIFO_full, ptrFIFO_empty, ptrFIFO_rden};",
    "wire [4:0]  dbg_axi    = {hbm_arvalid, hbm_arready, hbm_rvalid, hbm_rready, hbm_rlast};",
  ],
  ("internal_events_processor.v", "internal_events_processor"): [
    "wire [3:0]  dbg_iep_state   = curr_state;",
    "wire [10:0] dbg_iep_timeout = iep_phase1_timeout;",
    "wire [3:0]  dbg_iep_flags   = {exec_hbm_rvr_p2, exec_bram_phase1_done, exec_hbm_rvalidready, exec_hbm_rx_phase2_done};",
  ],
  ("external_events_processor_simple.v", "external_events_processor_simple"): [
    "wire [2:0]  dbg_eep_state = curr_state;",
    "wire [1:0]  dbg_eep_flags = {bram_select, axonEvent_set_reg};",
  ],
  ("pointer_fifo_controller.v", "pointer_fifo_controller"): [
    "wire        dbg_pfc_wren = ptrFIFO_wren;",
  ],
  ("command_interpreter.v", "command_interpreter"): [
    "wire [3:0]  dbg_ci_rx_state = rx_curr_state;",
    "wire [3:0]  dbg_ci_tx_state = tx_curr_state;",
    "wire [1:0]  dbg_ci_flags    = {exec_run, execRun_running};",
  ],
  ("single_core.sv", "core"): [
    "wire [15:0] dbg_bram_spiked = exec_bram_spiked;",
    "wire [15:0] dbg_uram_spiked = exec_uram_spiked;",
    "wire [1:0]  dbg_p2done      = {exec_hbm_rx_phase2_done_FF2_225M, iep_phase2_done_latched};",
  ],
}
texts = {}
for (f, mod), taps in TAPS.items():
    s = open(os.path.join(D, f)).read()
    if "dbg_" in s and "mark_debug" in s:
        sys.exit("ABORT: %s already has debug taps; no file changed" % f)
    starts = [m.start() for m in re.finditer(r"^\s*module\s+%s\b" % re.escape(mod), s, re.M)]
    if len(starts) != 1:
        sys.exit("ABORT: module %s found %d times in %s; no file changed" % (mod, len(starts), f))
    m = re.search(r"^\s*endmodule\b", s[starts[0]:], re.M)
    if not m:
        sys.exit("ABORT: no endmodule for %s in %s; no file changed" % (mod, f))
    at = starts[0] + m.start()
    block = ("\n// ---- debug taps for the core-1 capture build (copies only; feed nothing but the ILA)\n"
             + "".join(MD + t + "\n" for t in taps) + "\n")
    texts[f] = s[:at] + block + s[at:]
for f, s in texts.items():
    p = os.path.join(D, f); shutil.copy2(p, p + ".before_ila"); open(p, "w").write(s)
    print("patched %s (backup %s.before_ila)" % (f, f))
