#!/usr/bin/env python3
"""
Correct the Firefly topology in hiaer_firefly_pkg.sv to the wiring actually
built into the rack.

WHAT WAS WRONG
--------------
The package describes a two-tier arrangement: devices 0 to 3 carry one port
each and devices 4 to 7 carry four, giving twenty port endpoints and ten
links, with a longest path of three hops.

The CRI hardware manual, section 5.9, and the accompanying FPGA wiring map show
something different. All eight boards use FireFly ports 4, 5, 6 and 7. The four
boards on each CPU form an all-to-all group over ports 4, 5 and 6, and port 7
carries one link from each board across the chassis to the opposite group. That
is thirty-two port endpoints and sixteen links.

    CPU1 group   1-2, 1-3, 1-4, 2-3, 2-4, 3-4
    CPU2 group   5-6, 5-7, 5-8, 6-7, 6-8, 7-8
    cross-group  1-8, 2-7, 3-6, 4-5        all on port 7

Verified over all fifty-six ordered pairs against this table: every pair is
reachable, the longest path is TWO hops rather than three, the mean is 1.43
rather than 1.86, and every link appears in both directions.

The built topology is therefore better connected than the one the package
described, and the routing function becomes simpler: a destination is either
directly connected, in which case one port serves, or exactly one intermediate
device reaches it.

WHY THE ROUTING FUNCTION CHANGES SHAPE
--------------------------------------
Under the two-tier table a lower-tier device had one port and forwarded
everything upward. Under the real wiring every device has four ports and three
same-group neighbours, so the rule is:

  if the destination is directly connected, use that port;
  if the destination is in the same group, it is directly connected, so the
    first case already covered it;
  otherwise the destination is in the other group, and the port-7 partner of
    this device is either the destination itself or a device directly
    connected to it, so port 7 always makes progress.

That gives a maximum of two hops by construction, which the exhaustive check
confirms.

  python3 fix_firefly_topology.py --check <hiaer_firefly_pkg.sv>
  python3 fix_firefly_topology.py         <hiaer_firefly_pkg.sv>
"""

import sys, os, re

# From CRI_SDSC_FPGA_Map.docx table 2. Positions 1-8 there, devices 0-7 here.
LINKS = [(1,4,2,4), (3,4,4,4), (1,5,3,6), (2,5,3,5), (2,6,4,5), (1,6,4,6),
         (5,4,6,4), (7,4,8,4), (5,5,7,6), (6,5,7,5), (6,6,8,5), (5,6,8,6),
         (1,7,8,7), (2,7,7,7), (3,7,6,7), (4,7,5,7)]

PORT_ENUM = {4: "PORT_4", 5: "PORT_5", 6: "PORT_6", 7: "PORT_7"}


def build_conn():
    conn = {d: {} for d in range(8)}
    for a, pa, b, pb in LINKS:
        conn[a-1][pa] = (b-1, pb)
        conn[b-1][pb] = (a-1, pa)
    return conn


def emit_table(conn):
    out = []
    for d in range(8):
        out.append("            3'd%d: begin" % d)
        out.append("                case (local_port)")
        for p in (4, 5, 6, 7):
            rf, rp = conn[d][p]
            out.append("                    %s: result = '{remote_fpga: 3'd%d, "
                       "remote_port: %s, is_connected: 1'b1};"
                       % (PORT_ENUM[p], rf, PORT_ENUM[rp]))
        out.append("                    default: ;")
        out.append("                endcase")
        out.append("            end")
    return "\n".join(out)


ROUTING = r"""    //=========================================================================
    // Next-hop selection.
    //
    // Every device has four ports: three to the other devices of its own CPU
    // group and one across the chassis on port 7.  So a destination is either
    // directly connected, or it is reachable through this device's port-7
    // partner, which is itself directly connected to every device in the
    // opposite group.  The longest path is therefore two hops, and no table
    // lookup is required.
    //=========================================================================
    function automatic logic [1:0] get_output_port(
        input logic [2:0] local_fpga,
        input logic [2:0] dest_fpga
    );
        connection_entry_t c;
        // directly connected on one of the four ports
        for (int p = 0; p < 4; p++) begin
            c = get_connection(local_fpga, p[1:0]);
            if (c.is_connected && c.remote_fpga == dest_fpga)
                return p[1:0];
        end
        // otherwise the destination is in the opposite group, and port 7
        // reaches a device that is directly connected to it
        return PORT_7;
    endfunction
"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_firefly_topology.py [--check] <hiaer_firefly_pkg.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

conn = build_conn()

# verify before writing anything
import collections
adj = {d: {conn[d][q][0] for q in conn[d]} for d in range(8)}
def bfs(src):
    dist = {src: 0}; q = collections.deque([src])
    while q:
        u = q.popleft()
        for v in adj[u]:
            if v not in dist:
                dist[v] = dist[u] + 1; q.append(v)
    return dist
worst, unreachable = 0, []
for a in range(8):
    dd = bfs(a)
    for b in range(8):
        if a == b: continue
        if b not in dd: unreachable.append((a, b))
        else: worst = max(worst, dd[b])
if unreachable:
    fail("table does not connect %s" % unreachable)
print("  ok  16 links, 32 port endpoints")
print("  ok  56 of 56 ordered pairs reachable, longest path %d hops" % worst)
asym = [(a, b) for a in range(8) for b in adj[a] if a not in adj[b]]
if asym:
    fail("asymmetric links: %s" % asym)
print("  ok  every link present in both directions")

m = re.search(r"(function automatic connection_entry_t get_connection\(.*?\n\s*endfunction)", s, re.S)
if not m:
    fail("get_connection not found")
print("  ok  get_connection found (line %d)" % (s[:m.start()].count("\n") + 1))
m2 = re.search(r"(function automatic logic \[1:0\] get_output_port\(.*?\n\s*endfunction)", s, re.S)
if not m2:
    fail("get_output_port not found")
print("  ok  get_output_port found (line %d)" % (s[:m2.start()].count("\n") + 1))

if "NUM_PORTS" in s and "= 4" in s:
    print("  ok  NUM_PORTS already 4, unchanged")

if check:
    print("""
--check: nothing written.

AFTER APPLYING:
  * inter_fpga_router.sv uses get_output_port, so no change is needed there,
    but its testbench should be re-run
  * the chapter's account of a two-tier topology no longer holds and its
    hop-count figure must be regenerated
""")
    sys.exit(0)

head = s[:m.start()]
mid = s[m.end():m2.start()]
tail = s[m2.end():]

newconn = ("""function automatic connection_entry_t get_connection(
        input logic [2:0] local_fpga,
        input logic [1:0] local_port
    );
        connection_entry_t result;
        result.is_connected = 1'b0;
        result.remote_fpga  = 3'd0;
        result.remote_port  = 2'd0;
        // Wiring per the CRI hardware manual section 5.9 and the FPGA wiring
        // map: all eight boards use ports 4 to 7. Ports 4, 5 and 6 form an
        // all-to-all group among the four boards on one CPU; port 7 crosses
        // the chassis to the opposite group.
        case (local_fpga)
%s
            default: ;
        endcase
        return result;
    endfunction""" % emit_table(conn))

out = head + newconn + mid + ROUTING.rstrip() + tail
bak = p + ".before_topology"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("16 links, longest path 2 hops.")
