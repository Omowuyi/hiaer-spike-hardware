#!/usr/bin/env python3
"""
Give Aurora ports 4, 5 and 6 the instantiation that works for port 7.

WHY
---
Ports 4, 5 and 6 were instantiated against an IP configured as one lane at
10.3125 Gb/s with its shared logic outside the core. Their connections
reflected that: gt_rxp and gt_txp rather than rxp and txp, and four QPLL inputs
that a core owning its own shared logic does not have.

All four IPs are now configured identically, which was verified by comparing
their instantiation templates:

    C_AURORA_LANES        4
    C_LINE_RATE           25.78125
    C_REFCLK_FREQUENCY    161.1328125
    SupportLevel          1            shared logic inside the core
    interface_mode        Streaming
    TransceiverControl    true
    C_INIT_CLK            100
    drp_mode              AXI4_LITE

    diff of port4.veo, port5.veo, port6.veo against port7_logic.veo: empty

So the three instantiations become copies of port 7's, which elaborates and
synthesises today, with only the module name differing.

SupportLevel 1 is required rather than preferred. The four ports occupy four
separate transceiver quads, each with its own reference clock:

    ff4  T13 / L7    quad 234   common X1Y10   channels X1Y40..43
    ff5  P13 / G7    quad 235   common X1Y11   channels X1Y44..47
    ff6  P42 / G48   quad 135   common X0Y11   channels X0Y44..47
    ff7  T42 / L48   quad 134   common X0Y10   channels X0Y40..43

Four quads mean four independent QPLLs, so every core must contain its own.

  python3 fix_aurora_ports456.py --check <aurora_channel_wrapper.sv>
  python3 fix_aurora_ports456.py         <aurora_channel_wrapper.sv>
"""

import sys, os, re


def body(port, module):
    return """        %s (PORT_NUM == %d) begin : gen_aurora_port%d
            // Same shape as port 7: the IP owns its shared logic, so the
            // reference clock arrives differentially and there are no QPLL
            // inputs to drive.
            %s u_aurora (
                .rxp                    (gt_rxp),
                .rxn                    (gt_rxn),
                .txp                    (gt_txp),
                .txn                    (gt_txn),
                .gt_refclk1_p           (gt_refclk_p),
                .gt_refclk1_n           (gt_refclk_n),
                .user_clk_out           (user_clk),
                .reset_pb               (~aresetn),
                .power_down             (1'b0),
                .pma_init               (~aresetn),
                .init_clk               (init_clk),
                .s_axi_tx_tdata         (aurora_tx_tdata),
                .s_axi_tx_tvalid        (aurora_tx_tvalid),
                .s_axi_tx_tready        (aurora_tx_tready),
                .m_axi_rx_tdata         (aurora_rx_tdata),
                .m_axi_rx_tvalid        (aurora_rx_tvalid),
                .channel_up             (channel_up),
                .lane_up                (lane_up),
                .hard_err               (hard_err),
                .soft_err               (soft_err),
                .sys_reset_out          (sys_reset_out),
                .link_reset_out         (link_reset_out),
                .loopback               (loopback)
            );
""" % ("if" if port == 4 else "end else if", port, port, module)


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_aurora_ports456.py [--check] <aurora_channel_wrapper.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if ".rxp                    (gt_rxp)" in s and s.count(".rxp                    (gt_rxp)") >= 4:
    fail("already patched")

start = s.find("        if (PORT_NUM == 4) begin : gen_aurora_port4")
end = s.find("        end else begin : gen_aurora_port7")
if start < 0 or end < 0 or end <= start:
    fail("could not locate the port 4 to 6 generate arms")
print("  ok  ports 4 to 6 span lines %d to %d"
      % (s[:start].count("\n") + 1, s[:end].count("\n") + 1))

if "aurora_64b66b_port7_logic u_aurora" not in s:
    fail("port 7 does not instantiate aurora_64b66b_port7_logic; the template "
         "this patch copies is not present")
print("  ok  port 7 template present")

for n in (4, 5, 6):
    if "aurora_64b66b_port%d u_aurora" % n not in s:
        fail("port %d instantiation not found" % n)
print("  ok  all three instantiations found")

if check:
    print("""
--check: nothing written.

AFTER APPLYING, elaborate before synthesising:

  synth_design -rtl -name chk -top sixteen_core_noc_firefly_top \\
               -part xcvu37p-fsvh2892-2-e

Seven minutes there is worth more than a full run: every Aurora port mismatch
so far has been found this way.
""")
    sys.exit(0)

new = (body(4, "aurora_64b66b_port4")
       + body(5, "aurora_64b66b_port5")
       + body(6, "aurora_64b66b_port6"))
out = s[:start] + new + s[end:]

bak = p + ".before_ports456"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("All four ports now instantiate a 4-lane core owning its shared logic.")
