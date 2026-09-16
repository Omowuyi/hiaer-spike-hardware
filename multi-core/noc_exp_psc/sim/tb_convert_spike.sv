// Checks the reassembly of an arriving inter-device spike into the 32-bit word
// the network on chip carries.
//
// The reference layout is the one command_interpreter.v builds at line 994:
//   [31:24] timestamp   [23] valid   [22:21] device   [20:17] core
//   [16:0]  neuron index, entire
//
// Indices below deliberately exercise bits above the low ten. A test using only
// small indices would pass against the faulty function as well and prove
// nothing.
`timescale 1ns/1ps
module tb_convert_spike;

  integer pass = 0, fail = 0;
  task chk(input [31:0] got, input [31:0] exp, input [300*8-1:0] nm);
    begin
      if (got === exp) begin pass++; $display("  PASS  %0s", nm); end
      else begin fail++;
        $display("  FAIL  %0s", nm);
        $display("        got %08h  expected %08h", got, exp);
      end
    end
  endtask

  logic [7:0]  ts;
  logic [3:0]  core;
  logic [16:0] neuron;
  logic [2:0]  fpga;
  logic [31:0] result;

  always_comb begin
    result[31:24] = ts;
    result[23]    = 1'b1;
`ifdef BROKEN
    result[22:17] = 6'b0;
    result[16:14] = fpga;
    result[13:10] = core;
    result[9:0]   = neuron[9:0];
`else
    result[22:21] = 2'b00;
    result[20:17] = core;
    result[16:0]  = neuron;
`endif
  end

  function [31:0] expect_word(input [7:0] t, input [3:0] c, input [16:0] n);
    expect_word = {t, 1'b1, 2'b00, c, n};
  endfunction

  initial begin
    fpga = 3'd5;   // a received spike names this device; it must not enter the index

    ts = 8'd7; core = 4'd2; neuron = 17'd5000;  #1;
    chk(result, expect_word(ts,core,neuron), "neuron 5000 survives, core 2");

    ts = 8'd0; core = 4'd0; neuron = 17'd8191;  #1;
    chk(result, expect_word(ts,core,neuron), "neuron 8191, the last of a core");

    ts = 8'd3; core = 4'd15; neuron = 17'd131071; #1;
    chk(result, expect_word(ts,core,neuron), "neuron 131071, the last of a device");

    ts = 8'd1; core = 4'd9; neuron = 17'd1024;  #1;
    chk(result, expect_word(ts,core,neuron), "neuron 1024, first above ten bits");

    ts = 8'd0; core = 4'd0; neuron = 17'd0;     #1;
    chk(result, expect_word(ts,core,neuron), "neuron 0");

    ts = 8'd200; core = 4'd7; neuron = 17'd99999; #1;
    chk(result, expect_word(ts,core,neuron), "a large arbitrary index");

    $display("\n=== %0d passed, %0d failed ===", pass, fail);
    if (fail == 0) $display("ALL PASS"); else $display("FAILURES PRESENT");
    $finish;
  end
endmodule
