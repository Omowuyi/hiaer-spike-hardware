#!/usr/bin/env python3
"""
Carry four spikes per Aurora beat instead of one.

THE DEFECT
----------
Each optical port is configured with four lanes. Aurora 64b/66b presents 64
bits of user interface per lane, so a four-lane core has a 256-bit interface.
The wrapper drives 64:

    logic [63:0] aurora_tx_tdata;   ->  .s_axi_tx_tdata (256 bits)
    logic [63:0] aurora_rx_tdata;   <-  .m_axi_rx_tdata (256 bits)

Three quarters of every beat is unwired: on transmit the upper 192 bits are
undriven, and on receive they are discarded. Synthesis reports this as a width
mismatch rather than an error, so it has been present in every build.

WHAT THIS CHANGES
-----------------
The spike itself stays 64 bits, which is what the packet format defines and
what the rest of the design carries. Four of them now travel in each beat.

The packing costs no logic. An XPM asynchronous FIFO accepts different write
and read widths, so the transmit queue is written 64 bits at a time and read
256, and the receive queue is written 256 and read 64. Four writes become one
beat; one beat becomes four reads.

Two pieces of logic are needed around that.

A flush timer on the transmit side. The queue only presents a beat once four
words are in it, so one to three spikes at the end of a burst would wait
indefinitely. After a period of inactivity the remaining slots are filled with
the no-operation opcode the packet format already defines. The timer follows
the pattern already used in remote_spike_injector.

A filter on the receive side. Slots carrying the no-operation opcode are read
from the queue and discarded without being presented downstream.

WHY PADDING IS UNAVOIDABLE
--------------------------
The cores are configured in streaming mode, which carries no tkeep or tlast, so
a partial beat cannot be marked at the interface. The padding is therefore
in band, in a field the packet already has.

  python3 fix_aurora_256bit.py --check <aurora_channel_wrapper.sv>
  python3 fix_aurora_256bit.py         <aurora_channel_wrapper.sv>
"""

import sys, os

OLD_DECL = """    logic [63:0]    aurora_tx_tdata;"""
NEW_DECL = """    // The four-lane cores present 256 bits per beat, four spikes' worth.
    logic [255:0]   aurora_tx_tdata;"""

OLD_RXDECL = """    logic [63:0]    aurora_rx_tdata;"""
NEW_RXDECL = """    logic [255:0]   aurora_rx_tdata;"""

OLD_TXW = """        .WRITE_DATA_WIDTH   (64),
        .READ_DATA_WIDTH    (64),
        .READ_MODE          ("fwft"),
        .FIFO_READ_LATENCY  (0),
        .CDC_SYNC_STAGES    (3),
        .FULL_RESET_VALUE   (1)
    ) u_tx_cdc_fifo ("""
NEW_TXW = """        .WRITE_DATA_WIDTH   (64),
        .READ_DATA_WIDTH    (256),   // four spikes gathered into one beat
        .READ_MODE          ("fwft"),
        .FIFO_READ_LATENCY  (0),
        .CDC_SYNC_STAGES    (3),
        .FULL_RESET_VALUE   (1)
    ) u_tx_cdc_fifo ("""

OLD_TXWR = """        .wr_en          (s_axis_tx_tvalid && s_axis_tx_tready),
        .din            (s_axis_tx_tdata),
        .full           (tx_fifo_full),"""
NEW_TXWR = """        .wr_en          (tx_fifo_wr),
        .din            (tx_fifo_din),
        .full           (tx_fifo_full),"""

# The two queues have identical parameter blocks, so the receive one is
# identified by the instance name that follows it.
OLD_RXW = """        .WRITE_DATA_WIDTH   (64),
        .READ_DATA_WIDTH    (64),
        .READ_MODE          ("fwft"),
        .FIFO_READ_LATENCY  (0),
        .CDC_SYNC_STAGES    (3),
        .FULL_RESET_VALUE   (1)
    ) u_rx_cdc_fifo ("""
NEW_RXW = """        .WRITE_DATA_WIDTH   (256),  // one beat in, four spikes out
        .READ_DATA_WIDTH    (64),
        .READ_MODE          ("fwft"),
        .FIFO_READ_LATENCY  (0),
        .CDC_SYNC_STAGES    (3),
        .FULL_RESET_VALUE   (1)
    ) u_rx_cdc_fifo ("""

OLD_RXRD = """        .rd_en          (m_axis_rx_tvalid && m_axis_rx_tready),
        .dout           (m_axis_rx_tdata),
        .empty          (rx_fifo_empty),"""
NEW_RXRD = """        .rd_en          (rx_dvalid_raw && (rx_slot_is_nop || m_axis_rx_tready)),
        .dout           (rx_dout_raw),
        .empty          (rx_fifo_empty),"""

OLD_RXDV = """        .data_valid     (m_axis_rx_tvalid),
        
        .sleep          (1'b0),"""
NEW_RXDV = """        .data_valid     (rx_dvalid_raw),
        
        .sleep          (1'b0),"""

PACK_LOGIC = """
    //=========================================================================
    // Spike packing
    //
    // The transmit queue is written one 64-bit spike at a time and read as a
    // 256-bit beat, so four spikes cross the link together. A group that stops
    // short is completed with no-operation words after a period of inactivity;
    // without that a lone spike would sit in the queue until three more
    // arrived. Streaming mode carries no tkeep, so the padding has to be in
    // band, and the packet format already defines the opcode for it.
    //=========================================================================
    localparam int TX_FLUSH_CYCLES = 256;

    logic [1:0]  tx_pack_count;    // words written so far, modulo four
    logic [9:0]  tx_idle_count;
    logic [63:0] tx_fifo_din;
    logic        tx_fifo_wr;

    wire tx_user_wr   = s_axis_tx_tvalid && s_axis_tx_tready;
    wire tx_need_pad  = (tx_pack_count != 2'd0)
                     && (tx_idle_count >= TX_FLUSH_CYCLES[9:0])
                     && !tx_fifo_full;

    assign tx_fifo_wr  = tx_user_wr || tx_need_pad;
    assign tx_fifo_din = tx_user_wr ? s_axis_tx_tdata
                                    : {OP_NOP, 61'd0};

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            tx_pack_count <= 2'd0;
            tx_idle_count <= 10'd0;
        end else begin
            if (tx_fifo_wr)
                tx_pack_count <= tx_pack_count + 2'd1;   // wraps at four
            if (tx_user_wr)
                tx_idle_count <= 10'd0;
            else if (tx_pack_count != 2'd0)
                tx_idle_count <= tx_idle_count + 10'd1;
        end
    end

    //=========================================================================
    // Received beats arrive as four 64-bit slots. Those carrying the
    // no-operation opcode were padding and are drained without being offered
    // downstream.
    //=========================================================================
    logic [63:0] rx_dout_raw;
    logic        rx_dvalid_raw;

    wire rx_slot_is_nop = (rx_dout_raw[63:61] == OP_NOP);

    assign m_axis_rx_tdata  = rx_dout_raw;
    assign m_axis_rx_tvalid = rx_dvalid_raw && !rx_slot_is_nop;

"""


def fail(m):
    sys.stderr.write("ABORT: %s\nNothing was written.\n" % m)
    sys.exit(1)


args = [a for a in sys.argv[1:] if not a.startswith("--")]
check = "--check" in sys.argv[1:]
if len(args) != 1:
    fail("usage: fix_aurora_256bit.py [--check] <aurora_channel_wrapper.sv>")
p = args[0]
if not os.path.isfile(p):
    fail("no such file: %s" % p)
raw = open(p, errors="replace").read()
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")

if "logic [255:0]   aurora_tx_tdata" in s:
    fail("already patched")

# The wrapper does not import the package today, so OP_NOP is not visible.
# Other modules in this design import it directly after the module name.
OLD_MOD = "module aurora_channel_wrapper #("
NEW_MOD = ("module aurora_channel_wrapper\n"
           "    import hiaer_firefly_pkg::*;   // for OP_NOP, used as beat padding\n"
           "#(")

edits = [("package import", OLD_MOD, NEW_MOD),
         ("tx data declaration", OLD_DECL, NEW_DECL),
         ("rx data declaration", OLD_RXDECL, NEW_RXDECL),
         ("tx fifo widths", OLD_TXW, NEW_TXW),
         ("tx fifo write port", OLD_TXWR, NEW_TXWR),
         ("rx fifo widths", OLD_RXW, NEW_RXW),
         ("rx fifo read port", OLD_RXRD, NEW_RXRD),
         ("rx data_valid", OLD_RXDV, NEW_RXDV)]

for tag, old, new in edits:
    n = s.count(old)
    if n != 1:
        fail("anchor '%s' matched %d times, expected 1" % (tag, n))
    print("  ok  %-22s (line %d)" % (tag, s[:s.index(old)].count("\n") + 1))

print("  ok  package import will be added for OP_NOP")

anchor = "    //=========================================================================\n    // TX CDC FIFO"
if s.count(anchor) != 1:
    fail("could not find the transmit queue section header")
print("  ok  insertion point for the packing logic")

if check:
    print("""
--check: nothing written.

AFTER APPLYING, run tb_aurora_pack. It drives one, two, three and four spikes
and checks that a beat carries them in order with the remainder padded, and
that the padding is dropped on receive. A partial group that never flushes, or
padding that reaches the router, are both silent faults on hardware.
""")
    sys.exit(0)

out = s
for _, old, new in edits:
    out = out.replace(old, new, 1)
out = out.replace(anchor, PACK_LOGIC + anchor, 1)

bak = p + ".before_256bit"
if not os.path.exists(bak):
    open(bak, "w").write(raw)
open(p, "w").write(out.replace("\n", "\r\n") if crlf else out)
print("\npatched %s (backup %s)" % (p, bak))
print("Four spikes now cross the link per beat; short groups pad with OP_NOP.")
