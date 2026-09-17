#!/usr/bin/env python3
"""FIX F: widen the delay_buffer entry to carry the 4-bit URAM group index.

  54 bits: {3'b0, dest[12:0], weight[15:0], src[17:0], stdp_tag[3:0]}
  58 bits: {3'b0, group[3:0], dest[12:0], weight[15:0], src[17:0], stdp_tag[3:0]}

Without the group a drained entry has a row but no bank, so it cannot be
routed back into URAM.  usage: python3 delay_buffer_v2.patch.py <delay_buffer.v>
"""
import sys, os
p = sys.argv[1]
s = open(p).read()
E = [
 ("    parameter ENTRY_WIDTH       = 54     // {3'b0, dest_addr[12:0], weight[15:0], src_addr[17:0], stdp_tag[3:0]}",
  "    parameter ENTRY_WIDTH       = 58     // {3'b0, group[3:0], dest_addr[12:0], weight[15:0], src_addr[17:0], stdp_tag[3:0]}"),
 ("    input  wire [3:0]  syn_stdp_tag,    // STDP rule index",
  "    input  wire [3:0]  syn_stdp_tag,    // STDP rule index\n    input  wire [3:0]  syn_group,       // FIX F: target URAM bank (0-15)"),
 ("    output wire [3:0]  immediate_stdp_tag,",
  "    output wire [3:0]  immediate_stdp_tag,\n    output wire [3:0]  immediate_group,"),
 ("    output reg  [3:0]  delayed_stdp_tag,",
  "    output reg  [3:0]  delayed_stdp_tag,\n    output reg  [3:0]  delayed_group,"),
 ("    assign immediate_stdp_tag  = syn_stdp_tag;",
  "    assign immediate_stdp_tag  = syn_stdp_tag;\n    assign immediate_group     = syn_group;"),
 ("            bram_dina  <= {3'b0, syn_dest_addr, syn_weight, syn_src_addr, syn_stdp_tag};",
  "            bram_dina  <= {3'b0, syn_group, syn_dest_addr, syn_weight, syn_src_addr, syn_stdp_tag};"),
 ("                    delayed_dest_addr <= bram_doutb[50:38];   // [50:38] = dest_addr[12:0]\n"
  "                    delayed_weight    <= bram_doutb[37:22];   // [37:22] = weight[15:0]\n"
  "                    delayed_src_addr  <= bram_doutb[21:4];    // [21:4]  = src_addr[17:0]\n"
  "                    delayed_stdp_tag  <= bram_doutb[3:0];     // [3:0]   = stdp_tag[3:0]",
  "                    delayed_group     <= bram_doutb[54:51];   // [54:51] = group[3:0]\n"
  "                    delayed_dest_addr <= bram_doutb[50:38];   // [50:38] = dest_addr[12:0]\n"
  "                    delayed_weight    <= bram_doutb[37:22];   // [37:22] = weight[15:0]\n"
  "                    delayed_src_addr  <= bram_doutb[21:4];    // [21:4]  = src_addr[17:0]\n"
  "                    delayed_stdp_tag  <= bram_doutb[3:0];     // [3:0]   = stdp_tag[3:0]"),
 ("            delayed_stdp_tag <= 4'd0;",
  "            delayed_stdp_tag <= 4'd0;\n            delayed_group    <= 4'd0;"),
]
for old, new in E:
    c = s.count(old)
    if c != 1:
        sys.stderr.write("ABORT: anchor matched %d times (expected 1):\n%s\n" % (c, old[:110]))
        sys.exit(1)
    s = s.replace(old, new)
bak = p + ".before_group"
if not os.path.exists(bak):
    open(bak, "w").write(open(p).read())
open(p, "w").write(s)
print("patched %s -- ENTRY_WIDTH 54 -> 58, group carried through" % p)
print("BRAM cost unchanged in practice: 64*1024*58 bits still fits the same")
print("URAM/BRAM tiling as 54 (both round to the same 36Kb count).")
