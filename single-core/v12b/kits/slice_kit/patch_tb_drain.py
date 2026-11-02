#!/usr/bin/env python3
"""patch_tb_drain.py TB -- testbench option DRAIN_US: how long to keep recording responses after the last command
(default 20 us, as before).  CMD 2 reads are pushed without waiting for their replies, so a run that ends with many
row reads needs a longer drain (round 16b: 140 reads, 117 replies recorded before the fixed 20 us ran out)."""
import sys
p = sys.argv[1]; s = open(p).read()
if "DRAIN_US" in s: print("already patched"); sys.exit(0)
a = '        #20_000_000;\n        $fwrite(flog, "%t  replay end:'
if s.count(a) != 1: sys.exit("ANCHOR %s: %d matches" % (p, s.count(a)))
b = ('        begin int drain_us; if (!$value$plusargs("DRAIN_US=%d", drain_us)) drain_us = 20;\n'
     '              #(drain_us * 1_000_000); end                     // DRAIN_US: response window after the last command\n'
     '        $fwrite(flog, "%t  replay end:')
open(p, "w").write(s.replace(a, b)); print("testbench: DRAIN_US option (default 20 us)")
