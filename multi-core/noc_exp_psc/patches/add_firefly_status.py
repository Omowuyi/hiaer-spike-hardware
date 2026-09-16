#!/usr/bin/env python3
"""
Make Firefly link status observable.

THE GAP
-------
wire_firefly_top.py connected the Firefly datapath and left the subsystem's
four status outputs dangling:

    ff_channel_up   [3:0]    per-port link established
    ff_hard_err     [3:0]    per-port hard error
    ff_spikes_routed  [31:0]
    ff_spikes_dropped [31:0]

They are driven by firefly_subsystem_top and connected to nothing, so after
flashing there is no way to tell whether the optical link came up.  That is the
first question anyone asks of a new transceiver design, and this build could
not answer it.  My omission.

TWO OBSERVATION PATHS
---------------------
1. THE CARD LEDs.  src/user_led.xdc documents four green LEDs at BF53, BG48,
   BG49 and BE54, all commented out and absent from the top.  Driving one from
   channel_up gives a physical indication that needs no host software, no VIO
   and no debug hub -- which matters during first bring-up, when nothing else
   is trustworthy yet.  The LEDs are active low, hence the inversion.

       LED 0   port 7 channel up
       LED 1   port 7 hard error
       LED 2   any spike routed off-device
       LED 3   any spike dropped

   Bits 2 and 3 latch, so a single dropped spike stays visible rather than
   flashing past.

2. THE VIO, for detail.  The existing top_vio ends at probe_in29 and its probe
   count is fixed at generation, so four more probes require regenerating that
   IP:

       set_property -dict [list CONFIG.C_NUM_PROBE_IN {34} \\
           CONFIG.C_PROBE_IN30_WIDTH {4}  CONFIG.C_PROBE_IN31_WIDTH {4} \\
           CONFIG.C_PROBE_IN32_WIDTH {32} CONFIG.C_PROBE_IN33_WIDTH {32}] \\
           [get_ips top_vio]
       generate_target all [get_ips top_vio]

   This patch adds the four connections; run the property command above before
   synthesising or the instantiation will name probes that do not exist.

  python3 add_firefly_status.py --check <top.sv>
  python3 add_firefly_status.py         <top.sv>
"""

import sys, os

A_PORT = "    input sys_rst_n,"
N_PORT = """    input sys_rst_n,

    // Card LEDs, active low.  Pins are in src/user_led.xdc, commented out
    // there; uncomment BF53, BG48, BG49 and BE54 before building.
    output wire user_led_g0_l,   // port 7 channel up
    output wire user_led_g1_l,   // port 7 hard error
    output wire user_led_g2_l,   // a spike has left this device
    output wire user_led_g3_l,   // a spike has been dropped
"""

A_STATUS = """        .channel_up      (ff_channel_up),
        .hard_err        (ff_hard_err),
        .spikes_routed   (ff_spikes_routed),
        .spikes_dropped  (ff_spikes_dropped)
    );"""

N_STATUS = """        .channel_up      (ff_channel_up),
        .hard_err        (ff_hard_err),
        .spikes_routed   (ff_spikes_routed),
        .spikes_dropped  (ff_spikes_dropped)
    );

    //=========================================================================
    // Firefly status on the card LEDs.
    //
    // A physical indication that needs no host software and no debug hub.
    // During first bring-up nothing else is trustworthy yet, and "is the link
    // up" is the question every other measurement depends on.
    //
    // Bit 3 of the subsystem's status vectors is port 7, the only port a
    // lower-tier device populates.  The LEDs are active low.
    //
    // Routed and dropped LATCH, so a single dropped spike stays lit rather
    // than flashing past unseen.
    //=========================================================================
    reg ff_any_routed, ff_any_dropped;
    always @(posedge aclk) begin
        if (~aresetn) begin
            ff_any_routed  <= 1'b0;
            ff_any_dropped <= 1'b0;
        end else begin
            if (|ff_spikes_routed)  ff_any_routed  <= 1'b1;
            if (|ff_spikes_dropped) ff_any_dropped <= 1'b1;
        end
    end

    assign user_led_g0_l = ~ff_channel_up[3];
    assign user_led_g1_l = ~ff_hard_err[3];
    assign user_led_g2_l = ~ff_any_routed;
    assign user_led_g3_l = ~ff_any_dropped;
"""

A_VIO = "        .probe_in29(from_txFIFO.tvalid)\n    );"
N_VIO = """        .probe_in29(from_txFIFO.tvalid),
        // Firefly detail.  Requires top_vio regenerated with 34 probes --
        // see the header of this script for the property command.
        .probe_in30(ff_channel_up),
        .probe_in31(ff_hard_err),
        .probe_in32(ff_spikes_routed),
        .probe_in33(ff_spikes_dropped)
    );"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
no_vio = "--no-vio" in sys.argv[1:]
if len(args) != 1:
    fail("usage: add_firefly_status.py [--check] [--no-vio] <top.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "user_led_g0_l" in s:
    fail("already patched")
if "ff_channel_up" not in s:
    fail("the Firefly patch is not applied to this file")

plan = [("port", A_PORT, N_PORT), ("status", A_STATUS, N_STATUS)]
if not no_vio:
    plan.append(("vio", A_VIO, N_VIO))

for tag, a, _ in plan:
    n = s.count(a)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  anchor %-7s verified (line %d)" % (tag, s[:s.index(a)].count("\n") + 1))

if check:
    print("""
--check: nothing written.

BEFORE SYNTHESISING, two things:

  1. Uncomment the four LED pins in src/user_led.xdc -- BF53, BG48, BG49,
     BE54 -- or the new ports are unconstrained and implementation fails.

  2. Regenerate top_vio with 34 probes, or pass --no-vio to add only the LEDs.
     A probe that does not exist on the IP is an elaboration error.

The LEDs alone are enough for first bring-up.  --no-vio is the lower-risk
choice if you would rather not touch the VIO in the same build.
""")
    sys.exit(0)

out = s
for _, a, n in plan:
    out = out.replace(a, n, 1)

bak = p + ".before_ffstatus"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("LEDs: g0 channel up, g1 hard error, g2 routed, g3 dropped -- active low")
