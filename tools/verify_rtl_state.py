#!/usr/bin/env python3
"""
Verify every RTL file is in the expected state before launching a build.

Copy-pasting through the Vivado editor has silently failed three times in this
project: a file that differed only in whitespace, a file that needed a hash
check to trust, and a file that did not get replaced at all.  This checks all
seven files and says exactly what is missing.

Content hashes ignore comments and whitespace, so Vivado reformatting or
line-ending changes do not cause false alarms -- only real code differences do.

  python3 verify_rtl_state.py /data/omowuyi/single_core_exp_psc/project/multi_core.srcs/sources_1/imports
"""

import sys, os, re, hashlib

if len(sys.argv) != 2:
    sys.exit("usage: verify_rtl_state.py <imports_dir>")
D = sys.argv[1]
if not os.path.isdir(D):
    sys.exit("no such directory: %s" % D)


def norm(path):
    """md5 and length of the file with comments and whitespace removed."""
    s = open(path, 'rb').read().decode('utf-8', 'replace').replace('\r\n', '\n')
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'\s+', '', s)
    return hashlib.md5(s.encode()).hexdigest(), len(s)


def body(path):
    return open(path, 'rb').read().decode('utf-8', 'replace')


ok_all = True
notes = []


def check(label, cond, detail=""):
    global ok_all
    mark = "PASS" if cond else "FAIL"
    if not cond:
        ok_all = False
    print("    %-46s %s" % (label, mark))
    if detail and not cond:
        notes.append("  %s: %s" % (label, detail))


# ---------------------------------------------------------------- IEP ------
print("\ninternal_events_processor.v")
p = os.path.join(D, "internal_events_processor.v")
if not os.path.isfile(p):
    check("file present", False, "missing")
else:
    h, n = norm(p)
    print("    content hash: %s  (%d chars)" % (h, n))
    V6 = ("2cc062c7a7807f202fb2f3e859f630a3", 67540)
    V7 = ("817bf43407247ccaddfa4a0d8ad4641d", 67548)
    V11 = ("15665e4dc212f4a376e464d7d7572bed", 67719)   # v6 + microphase diagnostics
    if (h, n) == V7:
        print("    -> v7: FIX K applied. Correct for this build.")
        check("FIX K present", True)
    elif (h, n) == V11:
        print("    -> v11: v6 + microphase diagnostics (FIX K/T reverted). Correct for this build.")
        check("FIX K present", True)
    elif (h, n) == V6:
        print("    -> v6: FIX K NOT applied.")
        check("FIX K present", False,
              "run fix_microphase_skip.py on this file")
    else:
        print("    -> UNRECOGNISED. Expected v6 %s or v7 %s." % (V6[0], V7[0]))
        check("recognised version", False,
              "this file is neither v6 nor v7 -- do not build until resolved")
    check("has FIX G (Phase-2 flow control)", "FIX G" in body(p))
    check("has FIX I (delay drain)", "FIX I" in body(p))
    check("has syn_64bit_en port", "syn_64bit_en" in body(p))

# ------------------------------------------------------------ stdp ---------
print("\nstdp_controller.v")
p = os.path.join(D, "stdp_controller.v")
if not os.path.isfile(p):
    check("file present", False, "missing")
else:
    h, n = norm(p)
    print("    content hash: %s  (%d chars)" % (h, n))
    check("matches stdp_controller_fixed",
          (h, n) == ("c2154dc1fc9cd213d838f0c9a74930e8", 5864),
          "expected c2154dc1fc9cd213d838f0c9a74930e8 / 5864")
    b = body(p)
    check("P4_PTR_READ state added", "P4_PTR_READ" in b)
    check("syn_entry_count assigned", b.count("syn_entry_count <=") >= 1)

# --------------------------------------------------------- delay buffers ---
print("\ndelay_buffer.v")
p = os.path.join(D, "delay_buffer.v")
if not os.path.isfile(p):
    check("file present", False, "missing")
else:
    b = body(p)
    check("group widening (syn_group port)", "syn_group" in b,
          "run delay_buffer_v2.patch.py")
    check("ENTRY_WIDTH = 58", re.search(r"ENTRY_WIDTH\s*=\s*58", b) is not None)
    check("FIX J present", b.count("FIX J") >= 1, "run fix_delay_offset.py")
    adv = re.findall(r"\n[ \t]*current_slot\s*<=\s*current_slot \+ 6'd1;", b)
    check("exactly one slot advance (in DRAIN_IDLE)", len(adv) == 1,
          "found %d" % len(adv))

print("\naxon_delay_buffer.v")
p = os.path.join(D, "axon_delay_buffer.v")
if not os.path.isfile(p):
    check("file present", False, "missing")
else:
    b = body(p)
    check("FIX J present", b.count("FIX J") >= 1, "run fix_delay_offset.py")
    adv = re.findall(r"\n[ \t]*current_slot\s*<=\s*current_slot \+ 6'd1;", b)
    check("exactly one slot advance (in DRAIN_IDLE)", len(adv) == 1,
          "found %d" % len(adv))

# ------------------------------------------------------------- CI ----------
print("\ncommand_interpreter.v")
p = os.path.join(D, "command_interpreter.v")
if not os.path.isfile(p):
    check("file present", False, "missing")
else:
    b = body(p)
    check("syn_64bit_en (CMD 13 bit 131)", b.count("syn_64bit_en") >= 3,
          "run wire_syn64.py")
    check("CMD 14 axon delay table", "CMD_AXON_DELAY_W" in b,
          "run enable_axon_delay.py")
    check("spk_dropped -> error_status[11]", "error_status[11]" in b,
          "run detect_spike_drop.py")

# --------------------------------------------------------- single_core -----
print("\nsingle_core.sv")
p = os.path.join(D, "single_core.sv")
if not os.path.isfile(p):
    check("file present", False, "missing")
else:
    b = body(p)
    check("syn_64bit_en wired (driven + consumed)", b.count("syn_64bit_en") >= 3,
          "run wire_syn64.py")
    check("dbuf group wired", "dbuf_delayed_group" in b, "run wire_syn64.py")
    check("delay table untied", "w_delay_table_wr    = 1'b0" not in b,
          "run enable_axon_delay.py")
    check("spk_dropped wired", "w_spk_dropped" in b, "run detect_spike_drop.py")

# --------------------------------------------------------- hbm_processor ---
print("\nhbm_processor.v")
p = os.path.join(D, "hbm_processor.v")
if not os.path.isfile(p):
    check("file present", False, "missing")
else:
    b = body(p)
    check("spk_dropped detector", "spk_dropped" in b, "run detect_spike_drop.py")
    check("spk*_wren unchanged (detection only)",
          b.count("!spk0_full & exec_hbm_rx_phase1_done") == 1,
          "the write enables should NOT have been modified")

print("\n" + "=" * 60)
if ok_all:
    print("ALL CHECKS PASS -- safe to build.")
else:
    print("NOT READY. Outstanding:")
    for n in notes:
        print(n)
print("=" * 60)
