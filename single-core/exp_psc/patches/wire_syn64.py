#!/usr/bin/env python3
"""
Wire syn_64bit_en and dbuf_delayed_group end to end (RTL side).

internal_events_processor_v6.v adds two ports nothing currently drives:
  input       syn_64bit_en        0 = 32-bit Phase-2 entries (default), 1 = 64-bit
  input [3:0] dbuf_delayed_group  URAM bank a drained delayed synapse targets

  python3 wire_syn64.py [--check] <command_interpreter.v> <single_core.v>

The CMD 13 packer half is done separately by patch_cmd13.py on crisdsc0, so
single_core_conductance_STDP.py never has to leave the test machine.

Apply delay_buffer_v2.patch.py to delay_buffer.v FIRST.  Bit 131 is the next
free CMD 13 bit (w_min occupies [130:115]).  Everything defaults to 0.
"""
import sys, os

def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 2:
    fail("usage: wire_syn64.py [--check] <command_interpreter.v> <single_core.v>")
ci_p, sc_p = args
for p in args:
    if not os.path.isfile(p):
        fail("no such file: %s" % p)

edits = []
ci = open(ci_p).read()
sc = open(sc_p).read()
if "syn_64bit_en" in ci:
    fail("%s already mentions syn_64bit_en -- already patched?" % ci_p)

o = ("   output reg signed [15:0] w_min                     "
     "// Weight saturation lower bound (16-bit signed)\n")
if ci.count(o) != 1:
    fail("w_min port line not found exactly once in %s (%d)" % (ci_p, ci.count(o)))
edits.append((ci_p, o,
  "   output reg signed [15:0] w_min,                    "
  "// Weight saturation lower bound (16-bit signed)\n\n"
  "   //=========================================================================\n"
  "   // Phase-2 synapse entry width.  0 = 32-bit (default, today's behaviour),\n"
  "   // 1 = 64-bit {op,dest,weight,delay,syn_type,stdp_tag,src}, which carries\n"
  "   // per-synapse delay and the STDP source address.\n"
  "   //=========================================================================\n"
  "   output reg        syn_64bit_en\n", "CI port"))

o = "        w_min <= 16'sd0;       // floor at 0 (no negative weights by default)\n"
if ci.count(o) != 1:
    fail("w_min reset line not found exactly once in %s" % ci_p)
edits.append((ci_p, o, o + "        syn_64bit_en <= 1'b0;  // default: 32-bit entries\n",
              "CI reset"))

o = "        w_min       <= rxFIFO_dout[130:115];\n"
if ci.count(o) != 1:
    fail("w_min CMD13 capture not found exactly once in %s" % ci_p)
edits.append((ci_p, o,
  o + "        syn_64bit_en <= rxFIFO_dout[131];   // [131] = 64-bit synapse format\n",
  "CI CMD13 bit 131"))

o = "    wire        w_dbuf_drain_done;\n"
if sc.count(o) != 1:
    fail("w_dbuf_drain_done declaration not found exactly once in %s" % sc_p)
edits.append((sc_p, o,
  o + "    wire [3:0]  w_dbuf_delayed_group;   // FIX I: bank for a drained entry\n"
      "    wire        w_syn_64bit_en;         // FIX E: Phase-2 entry width\n"
      "    wire [3:0]  w_dbuf_syn_group;       // FIX F: bank for a pushed entry\n",
  "SC wires"))

o = ("        .dbuf_delayed_weight(w_dbuf_delayed_weight),\n"
     "        .dbuf_drain_done(w_dbuf_drain_done),\n"
     "        .dbuf_delayed_ready(w_dbuf_delayed_ready)\n")
if sc.count(o) != 1:
    fail("IEP dbuf_delayed hookup not found exactly once in %s" % sc_p)
edits.append((sc_p, o,
  "        .dbuf_delayed_weight(w_dbuf_delayed_weight),\n"
  "        .dbuf_delayed_group(w_dbuf_delayed_group),\n"
  "        .dbuf_syn_group(w_dbuf_syn_group),\n"
  "        .syn_64bit_en(w_syn_64bit_en),\n"
  "        .dbuf_drain_done(w_dbuf_drain_done),\n"
  "        .dbuf_delayed_ready(w_dbuf_delayed_ready)\n", "IEP hookup"))

n_dm = sc.count("        .delta_mode(w_delta_mode),\n")
if n_dm != 3:
    fail("expected 3 '.delta_mode(w_delta_mode),' hookups in %s, found %d" % (sc_p, n_dm))

o = "        .w_min(w_w_min)\n    );\n"
if sc.count(o) != 1:
    fail("CI instance end not found exactly once in %s (%d)" % (sc_p, sc.count(o)))
edits.append((sc_p, o,
  "        .w_min(w_w_min),\n        .syn_64bit_en(w_syn_64bit_en)\n    );\n",
  "CI instance syn_64bit_en"))

o = "        .syn_stdp_tag(w_dbuf_syn_stdp_tag),\n"
if sc.count(o) != 1:
    fail("delay_buffer .syn_stdp_tag hookup not found exactly once in %s" % sc_p)
edits.append((sc_p, o, o + "        .syn_group(w_dbuf_syn_group),\n", "dbuf syn_group"))

o = "        .delayed_stdp_tag(w_dbuf_delayed_stdp_tag),\n"
if sc.count(o) != 1:
    fail("delay_buffer .delayed_stdp_tag hookup not found exactly once in %s" % sc_p)
edits.append((sc_p, o,
  o + "        .delayed_group(w_dbuf_delayed_group),\n"
      "        .immediate_group(),\n", "dbuf delayed_group"))

print("edit sites verified:")
for _, _, _, label in edits:
    print("  ok  %s" % label)
print("\nRemember: run patch_cmd13.py on crisdsc0 for the CMD 13 packer.")

if check:
    print("\n--check: nothing written.")
    sys.exit(0)

bufs = {ci_p: ci, sc_p: sc}
for path, old, new, label in edits:
    if bufs[path].count(old) != 1:
        fail("anchor for %s stopped being unique mid-apply." % label)
    bufs[path] = bufs[path].replace(old, new)
for path, text in bufs.items():
    bak = path + ".before_syn64"
    if not os.path.exists(bak):
        open(bak, "w").write(open(path).read())
    open(path, "w").write(text)
    print("patched %s (backup %s)" % (path, bak))
