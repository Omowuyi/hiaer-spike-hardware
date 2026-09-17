`timescale 1ns / 1ps

module dummy_core(
    input aclk,
    input async_resetn,
    input [16:0] num_outputs,
    input [16:0] num_inputs,
    input [15:0] threshold,
    input [1:0] exec_neuron_model,
    
    input [4:0] core_number,
    
    AXI4.Master hbm
    
    //FIFO_input.Sink rxFIFO_in,
    //FIFO_output.Source txFIFO_out
    );
    
    assign hbm.araddr = 33'b0;
    assign hbm.arburst = 2'b0;
    assign hbm.arid = 6'b0;
    assign hbm.arlen = 4'b0;
    assign hbm.arsize = 3'b0;
    assign hbm.arvalid = 1'b0;
    // Write address
    assign hbm.awaddr = 33'b0;
    assign hbm.awburst = 2'b0;
    assign hbm.awid = 6'b0;
    assign hbm.awlen = 4'b0;
    assign hbm.awsize = 3'b0;
    assign hbm.awvalid = 1'b0;
    // Write response
    assign hbm.bready = 1'b1;
    assign hbm.rready = 1'b1;
    // Write data
    assign hbm.wdata = 256'b0;
    assign hbm.wlast = 1'b0;
    assign hbm.wstrb = 32'b0;
    assign hbm.wvalid = 1'b0;
    
    //assign rxFIFO_in.full = 1'b0;
   // assign txFIFO_out.dout = 512'b0;
    //assign txFIFO_out.empty = 1'b0;
endmodule