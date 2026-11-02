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

module external_events_processor_v2 #(

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
    output [7:0] exec_bram_spiked,          // array indicating inputs which are presently active
    output reg   exec_bram_phase1_done,     // output to URAM processor
    
    // Interface with Command Interpreter
    input                 ci2eep_empty,
    input          [13:0] ci2eep_dout,
    output reg            ci2eep_rden,
    input                 eep2ci_full,
    output         [21:0] eep2ci_din,
    output reg            eep2ci_wren,
    
    // BRAMs: present and future
    output [13:0] bram0_raddr,
    output        bram0_rden,
    input   [7:0] bram0_rdata,
    output  [7:0] bram0_wdata,
    output        bram0_wren,
    
    output [13:0] bram1_raddr,
    output        bram1_rden,
    input   [7:0] bram1_rdata,
    output  [7:0] bram1_wdata,
    output        bram1_wren,
    
    // BRAMs: debug
    output [13:0] bram0_raddr_dbg,
    input   [7:0] bram0_rdata_dbg,
    output [13:0] bram1_raddr_dbg,
    input   [7:0] bram1_rdata_dbg
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
wire  [7:0] bramFuture_wdata;


/////////////////
// ASSIGNMENTS //
/////////////////

assign BRAM_ADDR_LIMIT = num_inputs[16:3];

// BRAM 0
assign bram0_raddr = ~bram_select ? bramPresent_raddr : bramFuture_raddr; 
assign bram0_rden  = ~bram_select ? bramPresent_rden  : bramFuture_rden;
assign bram0_wdata = ~bram_select ? bramPresent_wdata : bramFuture_wdata;
assign bram0_wren  = ~bram_select ? bramPresent_wren  : bramFuture_wren[0];

// BRAM 1
assign bram1_raddr =  bram_select ? bramPresent_raddr : bramFuture_raddr; 
assign bram1_rden  =  bram_select ? bramPresent_rden  : bramFuture_rden;
assign bram1_wdata =  bram_select ? bramPresent_wdata : bramFuture_wdata;
assign bram1_wren  =  bram_select ? bramPresent_wren  : bramFuture_wren[0];

assign bramPresent_wren = bramPresent_rden;     // single-port RAM with "read first" option

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
assign bramPresent_rdata = ~bram_select ? bram0_rdata : bram1_rdata;

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
assign bramFuture_raddr = setArray_addr[16:3];
assign bramFuture_rden  = ci2eep_rden | setArray_go | bramFuture_wren[2] | bramFuture_wren[1] | bramFuture_wren[0];
assign bramFuture_rdata = bram_select ? bram0_rdata : bram1_rdata;
assign bramFuture_wdata = bramFuture_rdata | setArray_data;

always @(posedge clk) begin
    if (~resetn) begin
        bramFuture_waddr[2] <= 14'd0;
        bramFuture_waddr[1] <= 14'd0;
        bramFuture_waddr[0] <= 14'd0;
        bramFuture_wren[2]  <= 1'b0;
        bramFuture_wren[1]  <= 1'b0;
        bramFuture_wren[0]  <= 1'b0;
    end else begin
        bramFuture_waddr[2] <= setArray_addr;
        bramFuture_waddr[1] <= bramFuture_waddr[2];
        bramFuture_waddr[0] <= bramFuture_waddr[1];
        bramFuture_wren[2]  <= setArray_go;
        bramFuture_wren[1]  <= bramFuture_wren[2];
        bramFuture_wren[0]  <= bramFuture_wren[1];
    end
end

always @(posedge clk) begin
    if (~resetn) begin
        exec_bram_phase1_ready <= 1'b0;
        exec_bram_phase1_done  <= 1'b0;
    end else if (next_state == STATE_READ_INPUTS)
        exec_bram_phase1_ready <= 1'b1;
    else if (curr_state == STATE_PHASE1_DONE) begin
        exec_bram_phase1_done  <= 1'b1;
        exec_bram_phase1_ready <= 1'b0;
    end else
        exec_bram_phase1_done  <= 1'b0;
end

// for debugging
reg [2:0] dbg_curr_state, dbg_next_state;
localparam [2:0] DBG_STATE_RESET   = 3'd0;
localparam [2:0] DBG_STATE_IDLE    = 3'd1;
localparam [2:0] DBG_STATE_WAIT_0  = 3'd2;
localparam [2:0] DBG_STATE_WAIT_1  = 3'd3;
localparam [2:0] DBG_STATE_WAIT_2  = 3'd4;
localparam [2:0] DBG_STATE_WAIT_3  = 3'd5;
localparam [2:0] DBG_STATE_DONE    = 3'd6;

always @(posedge clk) begin
    if (~resetn) dbg_curr_state <= DBG_STATE_RESET;
    else         dbg_curr_state <= dbg_next_state;
end

always @(*) begin
    ci2eep_rden = 1'b0;
    eep2ci_wren = 1'b0;
    dbg_next_state = dbg_curr_state;
    
    case (dbg_curr_state)
        DBG_STATE_RESET: begin
            dbg_next_state = DBG_STATE_IDLE;
        end
        DBG_STATE_IDLE: begin
            if (~ci2eep_empty)
                dbg_next_state = DBG_STATE_WAIT_0;
        end
        DBG_STATE_WAIT_0: begin
            if (~eep2ci_full)
                eep2ci_wren = 1'b1;
            dbg_next_state = DBG_STATE_WAIT_1;
        end
        DBG_STATE_WAIT_1: begin
            if (~eep2ci_full)
                eep2ci_wren = 1'b1;
            dbg_next_state = DBG_STATE_WAIT_2;
        end
        DBG_STATE_WAIT_2: begin
            if (~eep2ci_full)
                eep2ci_wren = 1'b1;
            dbg_next_state = DBG_STATE_WAIT_3;
        end
        DBG_STATE_WAIT_3: begin
            if (~eep2ci_full)
                eep2ci_wren = 1'b1;
            dbg_next_state = DBG_STATE_DONE;
        end
        DBG_STATE_DONE: begin
            ci2eep_rden = 1'b1;
            dbg_next_state = DBG_STATE_IDLE;
        end
        
        default: begin
            dbg_next_state = DBG_STATE_RESET;
        end
    endcase
end

assign eep2ci_din = bram_select ? {bram0_raddr_dbg, bram0_rdata_dbg} : {bram1_raddr_dbg, bram1_rdata_dbg};

assign bram0_raddr_dbg = ci2eep_dout;
assign bram1_raddr_dbg = ci2eep_dout;

endmodule
