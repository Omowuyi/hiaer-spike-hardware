`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////////////
// EXTERNAL EVENTS PROCESSOR
//  Interfaces with two BRAMs (present + future)
//  BRAM read advances synchronously with HBM read commands
//
// Flow control for present inputs
//  1. State machine sweeps through all inputs, reading input states and clearing values 
//      after reading
//  2. Before the read cycle, the 3-stage pipeline must be filled: 
//      bramPresent_wren = bramPresent_rden;     // single-port RAM with "read first" option
//  3. The BRAM enable signal is used in conjunction with HBM rvalid+rready signals to 
//      advance BRAM outputs 
//
// Flow control for future inputs
//  1. Takes into account the 3-stage pipeline in the BRAM
//  2. The mask requires additional logic as not to lose any activations which occurred
//     in the same BRAM address during the pipeline filling
////////////////////////////////////////////////////////////////////////////////////////

module external_events_processor #(

    parameter PIPE_DEPTH = 3
)(
    input resetn,
    input clk,
    
    input [16:0] num_inputs,                // number of inputs to cycle through
    
    // set external input bit/array
    input        setArray_go,
    input [13:0] setArray_addr,
    input  [7:0] setArray_data,
    
    // Interface between blocks
    input        exec_run,                  // start processing (i.e. new algorithm time step)
    output reg   exec_bram_phase1_ready,    // output to HBM indicating pipeline has been filled
    input        exec_hbm_rvalidready,      // input from HBM indicating address has been read
    output [7:0] exec_bram_spiked,          // array indicating which inputs are presently active
    output reg   exec_bram_phase1_done,     // output to URAM processor
    
    // BRAMs: present and future
    output [13:0] bram0_waddr,
    output  [7:0] bram0_wdata,
    output        bram0_wren,
    output [13:0] bram0_raddr,
    output        bram0_rden,
    input   [7:0] bram0_rdata,
    
    output [13:0] bram1_waddr,
    output  [7:0] bram1_wdata,
    output        bram1_wren,
    output [13:0] bram1_raddr,
    output        bram1_rden,
    input   [7:0] bram1_rdata
);

//////////////////
// DECLARATIONS //
//////////////////

wire [13:0] BRAM_ADDR_LIMIT;    // # of inputs used (with 8 inputs per address)

reg bram_select;                // toggle between BRAMs

// Present BRAM
reg [13:0] bramPresent_raddr, bramPresent_waddr;
reg        bramPresent_addr_rst, bramPresent_addr_inc;
reg        bramPresent_rden;
wire       bramPresent_wren;
wire [7:0] bramPresent_rdata, bramPresent_wdata;

// Future BRAM
wire [13:0] bramFuture_raddr;
wire        bramFuture_rden;
wire  [7:0] bramFuture_rdata;
reg  [13:0] bramFuture_waddr [2:0];
reg         bramFuture_wren  [2:0];
reg   [7:0] bramFuture_wdata [2:0];

reg [7:0] setArray_data_pipe;


/////////////////
// ASSIGNMENTS //
/////////////////

assign BRAM_ADDR_LIMIT = num_inputs[16:3];

// BRAM 0
assign bram0_raddr = ~bram_select ? bramPresent_raddr : bramFuture_raddr; 
assign bram0_rden  = ~bram_select ? bramPresent_rden  : bramFuture_rden;
assign bram0_waddr = ~bram_select ? bramPresent_waddr : bramFuture_waddr[0];
//assign bram0_wdata = ~bram_select ? bramPresent_wdata : bramFuture_wdata[0] | bramFuture_rdata | setArray_data_pipe;
assign bram0_wdata = ~bram_select ? bramPresent_wdata : bramFuture_wdata[0]; // <- for debugging only 
assign bram0_wren  = ~bram_select ? bramPresent_wren  : bramFuture_wren[0];

// BRAM 1
assign bram1_raddr =  bram_select ? bramPresent_raddr : bramFuture_raddr; 
assign bram1_rden  =  bram_select ? bramPresent_rden  : bramFuture_rden;
assign bram1_waddr =  bram_select ? bramPresent_waddr : bramFuture_waddr[0];
//assign bram1_wdata =  bram_select ? bramPresent_wdata : bramFuture_wdata[0] | bramFuture_rdata | setArray_data_pipe;
assign bram1_wdata =  bram_select ? bramPresent_wdata : bramFuture_wdata[0]; //  <- for debugging only 
assign bram1_wren  =  bram_select ? bramPresent_wren  : bramFuture_wren[0];

assign bramPresent_wren = bramPresent_rden;

// outputs
assign exec_bram_spiked = bramPresent_rdata;



//////////////
// BEHAVIOR //
//////////////

always @(posedge clk) begin
    if (~resetn)
        bram_select <= 1'b0;
    else if (exec_run)
        bram_select <= ~bram_select;
end


// Flow control for present inputs
assign bramPresent_wdata = 8'd0;                                      // used for clearing the present inputs after being read
assign bramPresent_rdata = !bram_select ? bram0_rdata : bram1_rdata;

// raddr: leading address (end of pipeline)
// waddr: lagging address (front of pipeline)
always @(posedge clk) begin
    if (~resetn | exec_run | bramPresent_addr_rst) begin
        bramPresent_raddr <= 14'd0;
        bramPresent_waddr <= 14'd0;
    end else if (bramPresent_addr_inc) begin
        bramPresent_raddr <= bramPresent_raddr + 1'b1;
        if (exec_bram_phase1_ready)
            bramPresent_waddr <= bramPresent_waddr + 1'b1;
    end
end

reg [2:0] curr_state, next_state;
localparam [2:0] STATE_RESET        = 3'd0;
localparam [2:0] STATE_IDLE         = 3'd1;
localparam [2:0] STATE_FILL_PIPE    = 3'd2;
localparam [2:0] STATE_READ_INPUTS  = 3'd3;
localparam [2:0] STATE_PHASE1_DONE  = 3'd4;

always @(posedge clk) begin
    if (~resetn) curr_state <= STATE_RESET;
    else         curr_state <= next_state;
end

always @(*) begin
    bramPresent_rden     <= 1'b0;
    bramPresent_addr_rst <= 1'b0;
    bramPresent_addr_inc <= 1'b0;
    
    next_state <= curr_state;
    
    case (curr_state)
        STATE_RESET: begin
            bramPresent_addr_rst <= 1'b1;
            next_state <= STATE_IDLE;
        end
        STATE_IDLE: begin
            if (exec_run) begin
                bramPresent_addr_rst <= 1'b1;
                next_state <= STATE_FILL_PIPE;
            end
        end
        STATE_FILL_PIPE: begin
            if (bramPresent_raddr < PIPE_DEPTH) begin
                bramPresent_rden     <= 1'b1;
                bramPresent_addr_inc <= 1'b1;
            end else
                next_state <= STATE_READ_INPUTS;
        end
        STATE_READ_INPUTS: begin
            if (exec_hbm_rvalidready) begin
                bramPresent_rden     <= 1'b1;
                bramPresent_addr_inc <= 1'b1;
                if (bramPresent_waddr == BRAM_ADDR_LIMIT)
                    next_state <= STATE_PHASE1_DONE;
            end
        end
        STATE_PHASE1_DONE: begin
            next_state <= STATE_IDLE;
        end
        default: begin
            next_state <= STATE_RESET;
        end
    endcase
end

// Flow control for future inputs
assign bramFuture_raddr = setArray_addr;
assign bramFuture_rden  = 1'b1;
assign bramFuture_rdata = bram_select ? bram0_rdata : bram1_rdata;

always @(*) begin
    if (setArray_go) begin
        if (setArray_addr==bramFuture_waddr[0])
            setArray_data_pipe = setArray_data;
        else
            setArray_data_pipe = 8'd0;
    end else
        setArray_data_pipe = 8'd0;
end

always @(posedge clk) begin
    if (~resetn) begin
        bramFuture_wdata[2] <= 8'd0;
        bramFuture_wdata[1] <= 8'd0;
        bramFuture_wdata[0] <= 8'd0;
        bramFuture_waddr[2] <= 14'd0;
        bramFuture_waddr[1] <= 14'd0;
        bramFuture_waddr[0] <= 14'd0;
        bramFuture_wren[2]  <= 1'b0;
        bramFuture_wren[1]  <= 1'b0;
        bramFuture_wren[0]  <= 1'b0;
    end else if (setArray_go) begin
        if (setArray_addr==bramFuture_waddr[2]) begin
            bramFuture_wdata[2] <= 8'd0;
            bramFuture_wdata[1] <= bramFuture_wdata[2] | setArray_data;
            bramFuture_wdata[0] <= bramFuture_wdata[1];
            bramFuture_wren[2]  <= 1'b0;
        end else if (setArray_addr==bramFuture_waddr[1]) begin 
            bramFuture_wdata[2] <= 8'd0;
            bramFuture_wdata[1] <= bramFuture_wdata[2];
            bramFuture_wdata[0] <= bramFuture_wdata[1] | setArray_data;
            bramFuture_wren[2]  <= 1'b0;
        end else if (setArray_addr==bramFuture_waddr[0]) begin 
            bramFuture_wdata[2] <= 8'd0;
            bramFuture_wdata[1] <= bramFuture_wdata[2];
            bramFuture_wdata[0] <= bramFuture_wdata[1];
            bramFuture_wren[2]  <= 1'b0;
        end else begin
            bramFuture_wdata[2] <= setArray_data;
            bramFuture_wdata[1] <= bramFuture_wdata[2];
            bramFuture_wdata[0] <= bramFuture_wdata[1];
            bramFuture_wren[2]  <= 1'b1;
        end
        bramFuture_waddr[2] <= setArray_addr;
        bramFuture_waddr[1] <= bramFuture_waddr[2];
        bramFuture_waddr[0] <= bramFuture_waddr[1];
        bramFuture_wren[1]  <= bramFuture_wren[2];
        bramFuture_wren[0]  <= bramFuture_wren[1];
    end else begin
        bramFuture_wdata[2] <= 8'd0;
        bramFuture_wdata[1] <= bramFuture_wdata[2];
        bramFuture_wdata[0] <= bramFuture_wdata[1];
        bramFuture_waddr[2] <= 14'd0;
        bramFuture_waddr[1] <= bramFuture_waddr[2];
        bramFuture_waddr[0] <= bramFuture_waddr[1];
        bramFuture_wren[2]  <= 1'b0;
        bramFuture_wren[1]  <= bramFuture_wren[2];
        bramFuture_wren[0]  <= bramFuture_wren[1];
    end
end

always @(posedge clk) begin
    if (~resetn) begin
        exec_bram_phase1_ready <= 1'b0;
        exec_bram_phase1_done  <= 1'b0;
    end else if (next_state == STATE_FILL_PIPE) begin
        exec_bram_phase1_ready <= 1'b0;
        exec_bram_phase1_done  <= 1'b0;
    end else if (next_state == STATE_READ_INPUTS)
        exec_bram_phase1_ready <= 1'b1;
    else if (curr_state == STATE_PHASE1_DONE) begin
        exec_bram_phase1_done  <= 1'b1;
    end
end

endmodule
