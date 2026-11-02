#!/usr/bin/env python3
"""fix_round21.py SRC_DIR -- fix 22: beat pairing in the HBM processor.
hbm_count pairs 256-bit beats into 512-bit words for the neuron processor; it toggled on every accepted beat and was never
reset.  A CMD 2 read response is a single beat (fixes 8-9), taken by the same handshake, so every CMD 2 read flipped the
pairing for good: after an odd number of them every later word was built from the wrong two beats -- pointers paired
with the next row's spike mask (reports = captures - 8) and synapse words mis-delivered (round 20, plasticity network:
the controller's Phase-4 CMD 2 reads after step 1).  Any host CMD 2 read between steps did the same.
hbm_count is now held at 0 while the receive side is IDLE or taking a CMD 2 response (READ_HBM_RESP): single beats
never shift the pairing, every step's stream starts at its first beat, and a CMD 2 beat can no longer reach the neuron
processor as half a word.  In normal operation hbm_count is already 0 there, so nothing else changes."""
import sys, os
F = os.path.join(sys.argv[1], "hbm_processor.v"); s = open(F).read()
if "fix 22" in s: print("fix 22 already applied"); sys.exit(0)
a = "    else if (hbm_rvalid && hbm_rready) begin\n        hbm_count <= ~hbm_count;\n"
if s.count(a) != 1: sys.exit("ANCHOR hbm_processor.v: %d matches" % s.count(a))
s = s.replace(a, "    else if (rx_curr_state == RX_STATE_IDLE || rx_curr_state == RX_STATE_READ_HBM_RESP) begin\n"
                 "        hbm_count <= 1'b0;   // fix 22: single-beat CMD 2 responses must not shift the beat pairing\n    end\n" + a)
if not os.path.exists(F + ".before_round21"): open(F + ".before_round21", "w").write(open(F).read())
open(F, "w").write(s); print("fix 22 applied: hbm_count held at 0 in IDLE and READ_HBM_RESP")
