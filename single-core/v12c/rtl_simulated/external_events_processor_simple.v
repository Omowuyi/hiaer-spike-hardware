`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////////////
// EXTERNAL EVENTS PROCESSOR (with NoC Support)
//  Interfaces with two BRAMs (present + future)
//  BRAM read advances synchronously with HBM read commands
//
// Flow control for present inputs
//  1. State machine sweeps through all inputs, reading input states and clearing values after reading
//  2. Before the read cycle, the 3-stage pipeline must be filled
//  3. The BRAM rden signal is used in conjunction with HBM rvalid+rready signals to advance BRAM outputs 
//
// NoC Support:
//  - NoC Relay Event FIFO (512 x 19-bit) for incoming inter-core spikes
//
// v10: next-step (future) bank writes reworked
//  - Every write into the next-step bank ORs into its row (read, OR, write back); two inputs to the
//    same 16-axon row in one step both survive, and host rows of zeros no longer erase other inputs.
//  - Relayed spikes are written whenever the relay FIFO holds one (the old Phase 3 was reachable only
//    between microphases, so for networks below 8192 axons relays were never written).
//  - Each relay is written to its own row and bit (the old write used the FIFO head one cycle after
//    the pop, i.e. the next entry), and no axon event is dropped when a relay is written.
//  - At exec_run the banks swap only after the relays already queued (they belong to the step that
//    just ended) are written; bank_swap_tick then advances the per-axon delay buffer, so delayed
//    inputs keep their exact delay.  Every relay of step t is applied at step t+1.
//  - pending_clear (opcode 18) zeroes both banks and empties the relay FIFO.
//
////////////////////////////////////////////////////////////////////////////////////////

module external_events_processor_simple #(

   parameter PIPE_DEPTH = 3,
   parameter NOC_FIFO_DEPTH = 512   // Depth of NoC Relay Event FIFO
   
   )(

   input resetn,
   input clk,
    
   // Global core parameters
   input [16:0]            num_inputs,          // number of inputs/axons
   

   //////////////////////////////////////
   // from Command Interpreter         //
   //  Write axon event to future BRAM //
   //////////////////////////////////////
   
   input            axonEvent_set,
   input     [12:0] axonEvent_addr,             // [12:0]=row address
   input      [15:0] axonEvent_data,            // [15:0]=data mask (one-hot for 16 NGs)
       
   output wire                 hbm2eep_rden, //rden for 512b HBMFIFO.  
   
   ///////////////////////
   // Network execution //
   ///////////////////////
   
   input            exec_run,                   // algorithm time step execution
   output reg       exec_eep_phase1_ready,      // output to HBM indicating pipeline has been filled
   input            exec_hbm_rvalidready,       // input from HBM indicating address has been ready
   output     [15:0] exec_eep_spiked,
   output reg       exec_eep_phase1_done,       // output to URAM processor
   input            exec_uram_phase0_done, 
   input            delta_mode,
   
   input            exec_uram_phase1_done, 
   input            exec_uram_phase2_done, 
   
   // =========================================================================
   // NoC Relay Event Interface (NEW)
   // =========================================================================
   input  wire [18:0] noc_relay_din,           // 19-bit spike address from NoC
   input  wire        noc_relay_wren,          // Write enable from NoC spike injector
   output wire        noc_relay_full,          // FIFO full signal to NoC
   output reg         exec_eep_phase3_done,    // v10: 1 when the previous step's relays are in the bank

   // v10: clear of every pending input, and the bank-swap tick for the per-axon delay buffer
   input  wire        pending_clear,           // opcode 18: zero both banks, empty the relay FIFO
   output wire        pending_clear_busy,      // high until both banks are zero
   output reg         bank_swap_tick,          // one-cycle pulse when the banks swap
    
   ////////////////////////////////////////////
   // Axon event memories                    //
   //  Present/current and next/future BRAMs //
   ////////////////////////////////////////////
    output   [12:0] bram0_waddr,
    output    [15:0] bram0_wdata,
    output          bram0_wren,
    output   [12:0] bram0_raddr,
    output          bram0_rden,
    input     [15:0] bram0_rdata,
    
    output   [12:0] bram1_waddr,
    output    [15:0] bram1_wdata,
    output          bram1_wren,
    output   [12:0] bram1_raddr,
    output          bram1_rden,
    input     [15:0] bram1_rdata,
    
    output [2:0]  eep_curr_state,
    // Asserts on the cycle bramPresent_rdata is valid for bramPresent_waddr,
    // so {curr_bram_waddr, exec_eep_spiked} name a fired axon row.
    output        axon_row_valid,
    output [12:0] curr_bram_waddr,
    output        reading_inputs     // fix 28: consuming pointer pairs (READ_INPUTS) -- the neuron processor pops for it
);


//////////////////
// Declarations //
//////////////////

// Old 8 axons per axon row address -> ignore lower 3 bits of number of inputs
// Now 16 axons per axon row address -> ignore lower 4 bits of number of inputs
wire [12:0] axon_addr_limit = num_inputs[16:4];
wire [3:0] MICROPHASE_LIMIT = axon_addr_limit[12:9];
wire [8:0] MICROPHASE_MOD = axon_addr_limit[8:0];
wire [8:0] axon_microphase_addr_limit;
reg [3:0] microphase_ctr;

assign axon_microphase_addr_limit = (microphase_ctr==MICROPHASE_LIMIT)?MICROPHASE_MOD:9'd511;

// Toggle between BRAMs for future/next and present/current selection
//  bram_select=0: bram0=present; bram1=future
//  bram_select=1: bram0=future ; bram1=present
reg bram_select;

// Present/current BRAM
reg [12:0] bramPresent_raddr, bramPresent_waddr;
reg        bramPresent_addr_rst, bramPresent_addr_inc;
reg        bramPresent_rden;
reg        bramPresent_wren;
wire [15:0] bramPresent_rdata, bramPresent_wdata;


// Future/next BRAM
wire [12:0] bramFuture_raddr;
wire [12:0] bramFuture_waddr_mux;
wire [15:0] bramFuture_rdata;
wire [15:0] bramFuture_wdata_mux;
wire        bramFuture_rden;
wire        bramFuture_wren_mux;

reg exec_hbm_rvalidready_reg;

// =========================================================================
// NoC Relay Event FIFO (NEW)
// =========================================================================
wire        noc_fifo_empty;
wire        noc_fifo_full;
wire [18:0] noc_fifo_dout;
wire        noc_fifo_rden;
reg         clearing;       // v10: zeroing both banks after opcode 18
reg  [12:0] clr_addr;
reg  [9:0]  noc_fifo_count;  // Track FIFO occupancy

// Simple synchronous FIFO for NoC relay events
reg [18:0] noc_fifo_mem [NOC_FIFO_DEPTH-1:0];
reg [8:0]  noc_fifo_wr_ptr;
reg [8:0]  noc_fifo_rd_ptr;
reg [9:0]  noc_fifo_level;

// FIFO write logic
always @(posedge clk) begin
    if (~resetn) begin
        noc_fifo_wr_ptr <= 9'd0;
    end else if (noc_relay_wren && !noc_relay_full) begin
        noc_fifo_mem[noc_fifo_wr_ptr] <= noc_relay_din;
        noc_fifo_wr_ptr <= noc_fifo_wr_ptr + 1'b1;
    end
end

// FIFO read logic
always @(posedge clk) begin
    if (~resetn) begin
        noc_fifo_rd_ptr <= 9'd0;
    end else if (pending_clear) begin
        noc_fifo_rd_ptr <= noc_fifo_wr_ptr;            // v10: opcode 18 empties the FIFO
    end else if (noc_fifo_rden && !noc_fifo_empty) begin
        noc_fifo_rd_ptr <= noc_fifo_rd_ptr + 1'b1;
    end
end

// FIFO level tracking
always @(posedge clk) begin
    if (~resetn) begin
        noc_fifo_level <= 10'd0;
    end else if (pending_clear) begin
        noc_fifo_level <= 10'd0;
    end else begin
        case ({noc_relay_wren && !noc_relay_full, noc_fifo_rden && !noc_fifo_empty})
            2'b10: noc_fifo_level <= noc_fifo_level + 1'b1;  // Write only
            2'b01: noc_fifo_level <= noc_fifo_level - 1'b1;  // Read only
            default: noc_fifo_level <= noc_fifo_level;       // Both or neither
        endcase
    end
end

assign noc_fifo_dout = noc_fifo_mem[noc_fifo_rd_ptr];
assign noc_fifo_empty = (noc_fifo_level == 10'd0);
assign noc_fifo_full = (noc_fifo_level >= NOC_FIFO_DEPTH);
assign noc_relay_full = noc_fifo_full | clearing | pending_clear;   // v10: no relay accepted while clearing

// NoC spike address decoding
// A spike address is {row[12:0], group[3:0]} with the group in the LOW four
// bits. This matches the internal events processor, which forms an address as
// {uram_waddr[i], i[3:0]}, and it matches axon_addr_limit above, which divides
// the neuron count by sixteen to obtain a row count. It also matches the host
// readout: neuron index 8204 is row 512 group 12, and 8204 = 512*16 + 12.
//
// The decode below previously took the group from bits [16:13] and the row
// from [12:0], which is the same seventeen bits read in the opposite order, so
// every relayed spike reached the wrong axon.
wire [3:0]  noc_ng = noc_fifo_dout[3:0];             // Neuron group (0-15)
wire [12:0] noc_neuron_addr = noc_fifo_dout[16:4];   // Row address (13-bit axon row)
wire [15:0] noc_ng_onehot = (16'd1 << noc_ng);       // One-hot encoding

// =========================================================================
// No-fire bypass: timeout counter for STATE_READ_INPUTS
// When Phase 0 is done and no HBM data arrives, bypass to avoid deadlock
reg [10:0] read_inputs_timeout;
always @(posedge clk) begin
    if (~resetn || curr_state != STATE_READ_INPUTS)
        read_inputs_timeout <= 11'd0;
    else if (!delta_mode && (curr_state == STATE_READ_INPUTS) && !exec_hbm_rvalidready)
        read_inputs_timeout <= (read_inputs_timeout < 11'd2047) ? read_inputs_timeout + 11'd1 : read_inputs_timeout;
    else if (!delta_mode && (curr_state == STATE_READ_INPUTS) && exec_hbm_rvalidready)
        read_inputs_timeout <= 11'd0;
end

// State machine declaration 
// =========================================================================
reg [2:0] curr_state, next_state;

localparam [2:0] STATE_RESET           = 3'd0;
localparam [2:0] STATE_IDLE            = 3'd1;
localparam [2:0] STATE_WAIT_IEP_PHASE0 = 3'd2;
localparam [2:0] STATE_FILL_PIPE       = 3'd3;
localparam [2:0] STATE_READ_INPUTS     = 3'd4;
localparam [2:0] STATE_WAIT_IEP_PHASE1 = 3'd5;
localparam [2:0] STATE_WAIT_IEP_PHASE2 = 3'd6;
localparam [2:0] STATE_PHASE3_NOC      = 3'd7;  // NEW: Phase 3 - Process NoC relay events
assign reading_inputs = (curr_state == STATE_READ_INPUTS);   // fix 28

assign eep_curr_state = curr_state;

assign curr_bram_waddr = bramPresent_waddr;
assign axon_row_valid  = bramPresent_wren;

always @(posedge clk)
    if (~resetn) curr_state <= STATE_RESET;
    else         curr_state <= next_state;

////////////////////////////
// Block RAM multiplexing //
////////////////////////////

assign bram0_raddr = !bram_select ? bramPresent_raddr : bramFuture_raddr; 
assign bram0_rden  = !bram_select ? bramPresent_rden  : bramFuture_rden;
assign bram0_waddr = clearing ? clr_addr : (!bram_select ? bramPresent_waddr : bramFuture_waddr_mux);
assign bram0_wdata = clearing ? 16'd0    : (!bram_select ? bramPresent_wdata : bramFuture_wdata_mux);
assign bram0_wren  = clearing ? 1'b1     : (!bram_select ? bramPresent_wren  : bramFuture_wren_mux);

assign bram1_raddr =  bram_select ? bramPresent_raddr : bramFuture_raddr; 
assign bram1_rden  =  bram_select ? bramPresent_rden  : bramFuture_rden;
assign bram1_waddr = clearing ? clr_addr : ( bram_select ? bramPresent_waddr : bramFuture_waddr_mux);
assign bram1_wdata = clearing ? 16'd0    : ( bram_select ? bramPresent_wdata : bramFuture_wdata_mux);
assign bram1_wren  = clearing ? 1'b1     : ( bram_select ? bramPresent_wren  : bramFuture_wren_mux);

assign bramPresent_rdata = !bram_select ? bram0_rdata : bram1_rdata;
assign bramFuture_rdata  =  bram_select ? bram0_rdata : bram1_rdata;

// Toggle between BRAMs 0 and 1 at each new time step
//  bram_select=0: bram0=present; bram1=future
//  bram_select=1: bram0=future;  bram1=present
// v10: at exec_run the swap is made pending; it happens once the relays already queued at exec_run
// (they belong to the step that just ended) and every in-flight write are in the bank.
reg        swap_pending;
reg  [9:0] relays_before_swap;
wire       engine_idle;
wire       host_req, relay_req;
wire       do_swap = swap_pending && (relays_before_swap == 10'd0) && engine_idle && !host_req;
always @(posedge clk) begin
    bank_swap_tick <= 1'b0;
    if (!resetn)   begin
        bram_select <= 1'b0; 
        exec_hbm_rvalidready_reg <= 1'b0;
        swap_pending <= 1'b0;
        relays_before_swap <= 10'd0;
    end
    else if (clearing || pending_clear) begin
        swap_pending <= 1'b0;
        relays_before_swap <= 10'd0;
    end
    else begin
        if (exec_run) begin
            swap_pending <= 1'b1;
            relays_before_swap <= noc_fifo_level - (relay_req ? 10'd1 : 10'd0);
        end else if (swap_pending && relay_req && relays_before_swap != 10'd0)
            relays_before_swap <= relays_before_swap - 10'd1;
        if (do_swap) begin
            bram_select <= ~bram_select; 
            exec_hbm_rvalidready_reg <= exec_hbm_rvalidready;
            swap_pending <= 1'b0;
            bank_swap_tick <= 1'b1;
        end
    end
end


///////////////////////////////////////////////////
// Control logic for present/current BRAM        //
//  - Fill read pipeline                         //
//  - Clear axon event memory for next time step //
///////////////////////////////////////////////////

//  Register read and write addresses
//   raddr: leading address
//   waddr: lagging address
always @(posedge clk) begin
    if (~resetn | exec_run)    bramPresent_raddr <= 13'd0;
    else if (bramPresent_rden) bramPresent_raddr <= bramPresent_raddr + 1'b1;
    
    if (~resetn | exec_run)    bramPresent_waddr <= 13'd0;
    else if (bramPresent_wren) bramPresent_waddr <= bramPresent_waddr + 1'b1;
end

//  Clear the input axon events after they have been read
assign bramPresent_wdata = 16'd0;

// Send axon event information to Pointer FIFO
assign exec_eep_spiked = bramPresent_rdata;

// Register status flags
reg phase1_done_set;
always @(posedge clk) begin
    if (~resetn) begin
        exec_eep_phase1_ready <= 1'b0;
        exec_eep_phase1_done  <= 1'b0;
        microphase_ctr <= 4'b0;
    end else if (next_state == STATE_IDLE) begin
        microphase_ctr <= 4'b0;
        exec_eep_phase1_ready <= 1'b0;
        exec_eep_phase1_done  <= 1'b1;
    end else if (next_state == STATE_WAIT_IEP_PHASE0) begin
        exec_eep_phase1_ready <= 1'b0;
        exec_eep_phase1_done  <= 1'b0;
    end else if (next_state == STATE_FILL_PIPE) begin
        exec_eep_phase1_ready <= 1'b0;
        exec_eep_phase1_done  <= 1'b0;
        microphase_ctr <= 4'b0;
    end else if (next_state == STATE_READ_INPUTS)
        exec_eep_phase1_ready <= 1'b1;
    else if (next_state == STATE_WAIT_IEP_PHASE2) begin
        exec_eep_phase1_ready <= 1'b0;
        exec_eep_phase1_done  <= 1'b0;
    end else if (phase1_done_set) begin
        exec_eep_phase1_done  <= 1'b1;
        exec_eep_phase1_ready <= 1'b0;
        if(microphase_ctr != MICROPHASE_LIMIT) microphase_ctr <= microphase_ctr+1'b1;
    end
end


// =========================================================================
// Main State Machine (Updated with Phase 3)
// =========================================================================

always @(*) begin
   bramPresent_rden = 1'b0;
   bramPresent_wren = 1'b0;
    
   phase1_done_set = 1'b0;
    
   next_state = curr_state;
   case (curr_state)
    
      STATE_RESET: begin
         next_state = STATE_IDLE;
      end
        
      // Wait for new algorithm time step
      STATE_IDLE: begin
         if (exec_run)
            next_state = STATE_WAIT_IEP_PHASE0;
      end
      
      // Wait for IEP Phase 0 to be done
      STATE_WAIT_IEP_PHASE0: begin
          if(exec_uram_phase0_done && !swap_pending)   // v10: banks swapped first
            next_state = STATE_FILL_PIPE;
      end
      
      // Fill present/current BRAM pipeline
      //  the depth of the pipe depends on the number of stages configured for the BRAM
      STATE_FILL_PIPE: begin
         if (bramPresent_raddr < PIPE_DEPTH)
            bramPresent_rden = 1'b1;
         else
         next_state = STATE_READ_INPUTS;
      end
        
      // Read present/current BRAM values (used by Pointer FIFO)
      //  read/write addresses evolve at each new HBM read data ready+valid signal
      //  if reached axon address limit -> done
      STATE_READ_INPUTS: begin
         if (exec_hbm_rvalidready) begin
            bramPresent_rden = 1'b1;
            bramPresent_wren = 1'b1;
            if (bramPresent_waddr == microphase_ctr * 512+axon_microphase_addr_limit) begin
               phase1_done_set = 1'b1;
               if((microphase_ctr==MICROPHASE_LIMIT)) next_state = STATE_IDLE;
               else next_state = STATE_WAIT_IEP_PHASE1;
            end
         end else if (read_inputs_timeout == 11'd2047) begin
            // No HBM data for 2048 cycles: no neurons fired, bypass to done
            phase1_done_set = 1'b1;
            if((microphase_ctr==MICROPHASE_LIMIT)) next_state = STATE_IDLE;
            else next_state = STATE_WAIT_IEP_PHASE1;
         end
      end
      
      STATE_WAIT_IEP_PHASE1: begin
          if(exec_uram_phase1_done) begin
            next_state = STATE_WAIT_IEP_PHASE2;
          end
      end
      
      STATE_WAIT_IEP_PHASE2: begin
          if(exec_uram_phase2_done)
            next_state = STATE_READ_INPUTS;   // v10: relays are written continuously, no phase 3
      end
      
      default: begin
         next_state = curr_state;
      end
   endcase
end


//////////////////////////////////////////////////////////////////////////////////////////////
// Control logic for future/next BRAM                                                       //
//  Multi-core -> flow control with merging of PCIe events and NoC events                   //
//////////////////////////////////////////////////////////////////////////////////////////////


// Register incoming axon events for better place-and-route
reg [12:0] axonEvent_addr_reg;
reg  [15:0] axonEvent_data_reg;
reg        axonEvent_set_reg;

always @(posedge clk) begin
   if (~resetn) begin
      axonEvent_set_reg  <= 1'b0;
      axonEvent_addr_reg <= 13'd0;
      axonEvent_data_reg <= 16'd0;
   end else begin
      axonEvent_set_reg  <= axonEvent_set;
      axonEvent_addr_reg <= axonEvent_addr;
      axonEvent_data_reg <= axonEvent_data;
   end
end

// =========================================================================
// v10: next-step (future) bank write engine
// =========================================================================
// Every write ORs into its row: the row is read, the new bits are ORed in, the row is written back.
// eep_bram returns port-B data 3 cycles after the read (both output registers enabled), and port B
// is enabled every cycle, so a request issued in cycle c is written in cycle c+3 (stage s3).
// Requests, one per cycle:
//   - axon events from the command interpreter / per-axon delay buffer (no back-pressure; a row of
//     zeros changes nothing and is skipped);
//   - relayed spikes from the relay FIFO, taken only in a cycle with no axon event.
// A request for a row already in flight merges its bits into that entry, so no bits are lost and a
// row is never read before an earlier write to it has landed.
reg        s1_v, s2_v, s3_v;
reg [12:0] s1_r, s2_r, s3_r;
reg [15:0] s1_m, s2_m, s3_m;

assign host_req  = axonEvent_set_reg && (axonEvent_data_reg != 16'd0) && !clearing;
wire   relay_avail = !noc_fifo_empty && !clearing && !pending_clear &&
                     (!swap_pending || relays_before_swap != 10'd0);
assign relay_req = !host_req && relay_avail;
assign noc_fifo_rden = relay_req;                  // the relay taken is the FIFO head this cycle

wire        req_v = host_req | relay_req;
wire [12:0] req_r = host_req ? axonEvent_addr_reg : noc_neuron_addr;
wire [15:0] req_m = host_req ? axonEvent_data_reg : noc_ng_onehot;
wire hit1 = req_v && s1_v && (s1_r == req_r);
wire hit2 = req_v && s2_v && (s2_r == req_r);
wire hit3 = req_v && s3_v && (s3_r == req_r);
wire new_entry = req_v && !hit1 && !hit2 && !hit3;
assign engine_idle = !s1_v && !s2_v && !s3_v;

assign bramFuture_raddr = req_r;                   // read for a new entry (unused otherwise)
assign bramFuture_rden  = 1'b1;
assign bramFuture_waddr_mux = s3_r;
assign bramFuture_wdata_mux = bramFuture_rdata | s3_m | (hit3 ? req_m : 16'd0);
assign bramFuture_wren_mux  = s3_v;

always @(posedge clk) begin
    if (~resetn || clearing || pending_clear) begin
        s1_v <= 1'b0; s2_v <= 1'b0; s3_v <= 1'b0;
        s1_r <= 13'd0; s2_r <= 13'd0; s3_r <= 13'd0;
        s1_m <= 16'd0; s2_m <= 16'd0; s3_m <= 16'd0;
    end else begin
        s3_v <= s2_v; s3_r <= s2_r; s3_m <= s2_m | (hit2 ? req_m : 16'd0);
        s2_v <= s1_v; s2_r <= s1_r; s2_m <= s1_m | (hit1 ? req_m : 16'd0);
        s1_v <= new_entry; s1_r <= req_r; s1_m <= req_m;
    end
end

// opcode 18: zero both banks (8192 rows, one per cycle, both banks at once); the command interpreter
// waits on pending_clear_busy before taking its next command
always @(posedge clk) begin
    if (~resetn) begin
        clearing <= 1'b0;
        clr_addr <= 13'd0;
    end else if (pending_clear) begin
        clearing <= 1'b1;
        clr_addr <= 13'd0;
    end else if (clearing) begin
        if (clr_addr == 13'h1FFF) clearing <= 1'b0;
        clr_addr <= clr_addr + 13'd1;
    end
end
assign pending_clear_busy = clearing | pending_clear;

always @(posedge clk)
    exec_eep_phase3_done <= resetn & ~swap_pending & ~clearing;


/////////////////////
// Module outputs  //
/////////////////////

assign hbm2eep_rden = exec_hbm_rvalidready;

endmodule




