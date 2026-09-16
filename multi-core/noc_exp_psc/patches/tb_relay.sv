// Decode check for the NoC relay address in external_events_processor_simple.
//
// The decode is combinational and drives the axon memory directly, so it is
// exercised by reproducing the two expressions against the file's own
// convention rather than by elaborating the whole processor. Addresses are
// chosen so that row and group differ; an address whose group is zero would
// pass under either decode and prove nothing.
`timescale 1ns/1ps
module tb_relay;
  integer pass = 0, fail = 0;

  task chk(input [31:0] got, input [31:0] exp, input [200*8-1:0] name);
    begin
      if (got === exp) begin pass = pass + 1;
        $display("  PASS  %0s  got %0d", name, got);
      end else begin fail = fail + 1;
        $display("  FAIL  %0s  got %0d, expected %0d", name, got, exp);
      end
    end
  endtask

  reg [16:0] addr;
  wire [3:0]  ng   = `NG_EXPR;
  wire [12:0] nrow = `ROW_EXPR;

  initial begin
    // 8204 is the address the host reads back for neuron C1.9.104, which the
    // spike-loss investigation established as row 512 group 12.
    addr = 17'd8204;  #1;
    chk(nrow, 13'd512, "8204 -> row 512");
    chk(ng,   4'd12,   "8204 -> group 12");

    // a low address whose group is non-zero
    addr = 17'd100;   #1;
    chk(nrow, 13'd6,   "100 -> row 6");
    chk(ng,   4'd4,    "100 -> group 4");

    // the top of the space
    addr = 17'd131071; #1;
    chk(nrow, 13'd8191, "131071 -> row 8191");
    chk(ng,   4'd15,    "131071 -> group 15");

    $display("\n=== %0d passed, %0d failed ===", pass, fail);
    if (fail == 0) $display("ALL PASS"); else $display("FAILURES PRESENT");
    $finish;
  end
endmodule
