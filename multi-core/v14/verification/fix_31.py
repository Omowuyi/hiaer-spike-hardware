#!/usr/bin/env python3
"""fix_31.py [--check] COMMAND_INTERPRETER_V | SRC_DIR -- fix 31: the latency (0xBABA) and HBM-access (0xBACA) count packets were written
to the 32-deep transmit FIFO on the two cycles after step-done WITHOUT checking txFIFO_full (step-done itself waits for space).
With the FIFO full -- under heavy relay or host traffic -- both writes were silently dropped: the host saw step-done but never
the count packets (cores 9-11, 13-15 at 8,192 relays per step; core 14 in the large CNN).  Each now waits in its state until
the FIFO has space, exactly as step-done does.  No packet content changes."""
import sys
import os
p = [a for a in sys.argv[1:] if not a.startswith("--")][-1]
if os.path.isdir(p): p = os.path.join(p, "command_interpreter.v")   # called with the source folder, as fix_30.py is
s = open(p).read()
if "fix 31" in s: sys.exit("NOT APPLIED: already patched")
EDITS = [
 ("      TX_STATE_SEND_LATENCY_CNT: begin\n",
  "      TX_STATE_SEND_LATENCY_CNT: if (!txFIFO_full) begin   // fix 31: wait for transmit-FIFO space, as step-done does\n"),
 ("      TX_STATE_SEND_HBM_ACCESS_CNT: begin\n",
  "      TX_STATE_SEND_HBM_ACCESS_CNT: if (!txFIFO_full) begin   // fix 31: wait for transmit-FIFO space, as step-done does\n")]
for a, b in EDITS:
    n = s.count(a)
    if n != 1: sys.exit("NOT APPLIED: anchor %r found %d times" % (a.strip(), n))
    s = s.replace(a, b)
if "--check" in sys.argv: print("CHECK OK"); sys.exit(0)
open(p, "w").write(s); print("fix 31 applied to %s" % p)
