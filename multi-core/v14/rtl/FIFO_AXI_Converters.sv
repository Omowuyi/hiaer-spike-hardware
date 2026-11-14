`timescale 1ns / 1ps

module AXIS_to_FIFO_input(
    AXIStream_simple.Slave a,
    FIFO_input.Source f
);
    assign f.wren = a.tvalid;
    assign f.din = a.tdata;
    assign a.tready = ~f.full;
endmodule

module AXIS_to_FIFO_output(
    AXIStream_simple.Slave a,
    FIFO_output.Source f
);
    assign a.tready = f.rden;
    assign f.dout = a.tdata;
    assign f.empty = ~a.tvalid;
endmodule

module FIFO_input_to_AXIS(
    AXIStream_simple.Master a,
    FIFO_input.Sink f
);
    assign a.tvalid = f.wren;
    assign a.tdata = f.din;
    assign f.full = ~a.tready;
endmodule

module FIFO_output_to_AXIS(
    AXIStream_simple.Master a,
    FIFO_output.Sink f
);
    assign a.tvalid = ~f.empty;
    assign a.tdata = f.dout;
    assign f.rden = a.tready;
endmodule