// Checks the spike packing added to aurora_channel_wrapper.
//
// The wrapper cannot be elaborated here because it instantiates the Aurora
// core, so the logic under test is reproduced exactly as patched, together
// with a behavioural model of the asymmetric XPM queue. The model writes and
// reads least-significant word first, which is XPM's convention; the
// end-to-end ordering check below holds whichever convention is used, provided
// both queues agree, and that is the property that matters on hardware.
`timescale 1ns/1ps
module tb_pack;

  localparam [2:0] OP_NOP   = 3'b111;
  localparam [2:0] OP_SPIKE = 3'b000;
  localparam int   FLUSH    = 8;        // shortened from 256 for simulation

  logic aclk = 0, aresetn = 0;
  always #5 aclk = ~aclk;

  integer pass = 0, fail = 0;
  task chk(input logic cond, input [400*8-1:0] nm);
    begin
      if (cond) begin pass++; $display("  PASS  %0s", nm); end
      else      begin fail++; $display("  FAIL  %0s", nm); end
    end
  endtask

  //--------------------------------------------------------------- transmit
  logic [63:0] s_tdata; logic s_tvalid, s_tready;
  logic        tx_fifo_full = 0;

  logic [1:0]  tx_pack_count;
  logic [9:0]  tx_idle_count;
  logic [63:0] tx_fifo_din;
  logic        tx_fifo_wr;

  wire tx_user_wr  = s_tvalid && s_tready;
  wire tx_need_pad = (tx_pack_count != 2'd0)
                  && (tx_idle_count >= FLUSH[9:0])
                  && !tx_fifo_full;

  assign tx_fifo_wr  = tx_user_wr || tx_need_pad;
  assign tx_fifo_din = tx_user_wr ? s_tdata : {OP_NOP, 61'd0};
  assign s_tready    = !tx_fifo_full;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      tx_pack_count <= 2'd0;
      tx_idle_count <= 10'd0;
    end else begin
      if (tx_fifo_wr) tx_pack_count <= tx_pack_count + 2'd1;
      if (tx_user_wr) tx_idle_count <= 10'd0;
      else if (tx_pack_count != 2'd0) tx_idle_count <= tx_idle_count + 10'd1;
    end
  end

  // behavioural 64-in / 256-out queue
  logic [63:0] txq [0:255];
  int          txq_wr = 0, txq_rd = 0;
  always_ff @(posedge aclk)
    if (aresetn && tx_fifo_wr) begin txq[txq_wr] = tx_fifo_din; txq_wr++; end
  wire        beat_ready = (txq_wr - txq_rd) >= 4;
  wire [255:0] beat = {txq[txq_rd+3], txq[txq_rd+2], txq[txq_rd+1], txq[txq_rd]};

  //---------------------------------------------------------------- receive
  logic [255:0] rx_beat;  logic rx_beat_valid = 0;
  logic [63:0]  rxq [0:255];
  int           rxq_wr = 0, rxq_rd = 0;
  always_ff @(posedge aclk)
    if (aresetn && rx_beat_valid) begin
      rxq[rxq_wr]   = rx_beat[63:0];
      rxq[rxq_wr+1] = rx_beat[127:64];
      rxq[rxq_wr+2] = rx_beat[191:128];
      rxq[rxq_wr+3] = rx_beat[255:192];
      rxq_wr += 4;
    end

  logic [63:0] rx_dout_raw;  logic rx_dvalid_raw;
  assign rx_dout_raw   = rxq[rxq_rd];
  assign rx_dvalid_raw = (rxq_rd < rxq_wr);
  wire rx_slot_is_nop  = (rx_dout_raw[63:61] == OP_NOP);
  wire m_tvalid        = rx_dvalid_raw && !rx_slot_is_nop;
  wire [63:0] m_tdata  = rx_dout_raw;

  task send(input [63:0] d);
    begin @(negedge aclk); s_tdata = d; s_tvalid = 1; @(negedge aclk); s_tvalid = 0; end
  endtask
  function [63:0] mk(input [16:0] n); mk = {OP_SPIKE, 3'd0, 3'd1, 4'd0, n, 30'd0}; endfunction

  int got; logic [63:0] seen [0:15];
  logic [63:0] s1, s2, s3;

  initial begin
    s_tvalid = 0; s_tdata = 0;
    repeat (4) @(negedge aclk); aresetn = 1;

    // --- a full group of four needs no padding -------------------------
    send(mk(17'd11)); send(mk(17'd22)); send(mk(17'd33)); send(mk(17'd44));
    @(negedge aclk);
    chk(beat_ready, "four spikes form a beat with no wait");
    chk(beat[ 63:  0] == mk(17'd11), "slot 0 holds the first spike");
    chk(beat[127: 64] == mk(17'd22), "slot 1 holds the second");
    chk(beat[191:128] == mk(17'd33), "slot 2 holds the third");
    chk(beat[255:192] == mk(17'd44), "slot 3 holds the fourth");
    chk(tx_pack_count == 2'd0,       "count returns to zero after four");
    txq_rd += 4;

    // --- one spike alone must be flushed with three pads ---------------
    send(mk(17'd55));
    chk(!beat_ready, "one spike alone does not form a beat");
    repeat (FLUSH + 6) @(negedge aclk);
    chk(beat_ready, "the group is completed after the flush interval");
    chk(beat[ 63:  0] == mk(17'd55),  "the spike keeps slot 0");
    s1 = beat[127: 64]; s2 = beat[191:128]; s3 = beat[255:192];
    chk(s1[63:61] == OP_NOP, "slot 1 is padding");
    chk(s2[63:61] == OP_NOP, "slot 2 is padding");
    chk(s3[63:61] == OP_NOP, "slot 3 is padding");
    txq_rd += 4;

    // --- two and three behave the same way -----------------------------
    send(mk(17'd66)); send(mk(17'd77));
    repeat (FLUSH + 6) @(negedge aclk);
    s2 = beat[191:128]; s3 = beat[255:192];
    chk(beat_ready && beat[63:0] == mk(17'd66) && beat[127:64] == mk(17'd77)
        && s2[63:61] == OP_NOP && s3[63:61] == OP_NOP,
        "two spikes flush with two pads, in order");
    txq_rd += 4;

    send(mk(17'd88)); send(mk(17'd99)); send(mk(17'd100));
    repeat (FLUSH + 6) @(negedge aclk);
    s3 = beat[255:192];
    chk(beat_ready && beat[63:0] == mk(17'd88) && beat[127:64] == mk(17'd99)
        && beat[191:128] == mk(17'd100) && s3[63:61] == OP_NOP,
        "three spikes flush with one pad, in order");

    // --- the receiver drops padding and preserves order ----------------
    @(negedge aclk); rx_beat = beat; rx_beat_valid = 1;
    @(negedge aclk); rx_beat_valid = 0;
    got = 0;
    while (rxq_rd < rxq_wr) begin
      if (m_tvalid) begin seen[got] = m_tdata; got++; end
      rxq_rd++; @(negedge aclk);
    end
    chk(got == 3, "three spikes emerge from a beat carrying one pad");
    chk(seen[0] == mk(17'd88) && seen[1] == mk(17'd99) && seen[2] == mk(17'd100),
        "they emerge in the order they were sent");

    // --- a beat of pure padding yields nothing -------------------------
    @(negedge aclk);
    rx_beat = {4{{OP_NOP, 61'd0}}}; rx_beat_valid = 1;
    @(negedge aclk); rx_beat_valid = 0;
    got = 0;
    while (rxq_rd < rxq_wr) begin
      if (m_tvalid) got++;
      rxq_rd++; @(negedge aclk);
    end
    chk(got == 0, "a beat of padding alone produces no spikes");

    $display("\n=== %0d passed, %0d failed ===", pass, fail);
    if (fail == 0) $display("ALL PASS"); else $display("FAILURES PRESENT");
    $finish;
  end
endmodule
