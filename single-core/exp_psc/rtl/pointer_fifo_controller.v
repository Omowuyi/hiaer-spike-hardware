`timescale 1ns / 1ps

module pointer_fifo_controller(

    input resetn,
    input clk,

    input exec_run,

    // from external events processor
    input [15:0] exec_bram_spiked, //Previously [7:0]
    input       exec_bram_phase1_done,
    input       exec_bram_phase1_ready,
    
    // from internal events processor
    input [15:0] exec_uram_spiked, //Previously [7:0]
    input       exec_uram_phase1_ready,
    input       exec_uram_phase0_done,
    input       exec_uram_phase1_done,
    
    // from HBM processor
    input         exec_hbm_rvalidready, 
    input [511:0] exec_hbm_rdata, //Previously [255:0]
    
    output wire                 hbm2pfc_rden, //rden for 512b HBMFIFO. 
    //hbm2pfc_dout is already assigned into exec_hbm_radata at top wrapper.
    //hbm2pfc_empty is already assigned to ~exec_hbm_rvalid_rready at top wrapper.
    
    // pointer FIFOs
    input         ptr0_full,
    output [31:0] ptr0_din,
    output        ptr0_wren,
    input         ptr0_empty,
    input  [31:0] ptr0_dout,
    output reg    ptr0_rden,
    
    input         ptr1_full,
    output [31:0] ptr1_din,
    output        ptr1_wren,
    input         ptr1_empty,
    input  [31:0] ptr1_dout,
    output reg    ptr1_rden,
    
    input         ptr2_full,
    output [31:0] ptr2_din,
    output        ptr2_wren,
    input         ptr2_empty,
    input  [31:0] ptr2_dout,
    output reg    ptr2_rden,
    
    input         ptr3_full,
    output [31:0] ptr3_din,
    output        ptr3_wren,
    input         ptr3_empty,
    input  [31:0] ptr3_dout,
    output reg    ptr3_rden,
    
    input         ptr4_full,
    output [31:0] ptr4_din,
    output        ptr4_wren,
    input         ptr4_empty,
    input  [31:0] ptr4_dout,
    output reg    ptr4_rden,
    
    input         ptr5_full,
    output [31:0] ptr5_din,
    output        ptr5_wren,
    input         ptr5_empty,
    input  [31:0] ptr5_dout,
    output reg    ptr5_rden,
    
    input         ptr6_full,
    output [31:0] ptr6_din,
    output        ptr6_wren,
    input         ptr6_empty,
    input  [31:0] ptr6_dout,
    output reg    ptr6_rden,
    
    input         ptr7_full,
    output [31:0] ptr7_din,
    output        ptr7_wren,
    input         ptr7_empty,
    input  [31:0] ptr7_dout,
    output reg    ptr7_rden,
    
    input         ptr8_full,
    output [31:0] ptr8_din,
    output        ptr8_wren,
    input         ptr8_empty,
    input  [31:0] ptr8_dout,
    output reg    ptr8_rden,
    
    input         ptr9_full,
    output [31:0] ptr9_din,
    output        ptr9_wren,
    input         ptr9_empty,
    input  [31:0] ptr9_dout,
    output reg    ptr9_rden,
    
    input         ptr10_full,
    output [31:0] ptr10_din,
    output        ptr10_wren,
    input         ptr10_empty,
    input  [31:0] ptr10_dout,
    output reg    ptr10_rden,
    
    input         ptr11_full,
    output [31:0] ptr11_din,
    output        ptr11_wren,
    input         ptr11_empty,
    input  [31:0] ptr11_dout,
    output reg    ptr11_rden,
    
    input         ptr12_full,
    output [31:0] ptr12_din,
    output        ptr12_wren,
    input         ptr12_empty,
    input  [31:0] ptr12_dout,
    output reg    ptr12_rden,
    
    input         ptr13_full,
    output [31:0] ptr13_din,
    output        ptr13_wren,
    input         ptr13_empty,
    input  [31:0] ptr13_dout,
    output reg    ptr13_rden,
    
    input         ptr14_full,
    output [31:0] ptr14_din,
    output        ptr14_wren,
    input         ptr14_empty,
    input  [31:0] ptr14_dout,
    output reg    ptr14_rden,
    
    input         ptr15_full,
    output [31:0] ptr15_din,
    output        ptr15_wren,
    input         ptr15_empty,
    input  [31:0] ptr15_dout,
    output reg    ptr15_rden,
    
    // to HBM processor
    input             ptrFIFO_full,
    output reg [31:0] ptrFIFO_din,
    output reg        ptrFIFO_wren
);

reg bram_reading, uram_reading;
reg exec_hbm_rvalidready_reg;
always @(posedge clk) begin
    if (!resetn) begin
        bram_reading <= 1'b0;
        uram_reading <= 1'b0;
        exec_hbm_rvalidready_reg <= 1'b0;
    //end else if (exec_run | (exec_bram_phase1_ready & !bram_reading & !uram_reading)) begin
    //To support microphase we should use phase1_ready signal to setbram_reading and uram_reading flag independently not necessarily one after another as use to be.
    //still, bram_reading has higher priority if both iep and eep are involved in the current microphase.
    end else if (exec_run | exec_bram_phase1_ready) begin
        bram_reading <= 1'b1;
        exec_hbm_rvalidready_reg <= exec_hbm_rvalidready;
    //end else if (exec_bram_phase1_done & bram_reading & !uram_reading) begin
    end else if (exec_uram_phase1_ready) begin
        bram_reading <= 1'b0;
        uram_reading <= 1'b1;
        exec_hbm_rvalidready_reg <= exec_hbm_rvalidready;
     end else if (exec_uram_phase1_done) begin
        uram_reading <= 1'b0;
        exec_hbm_rvalidready_reg <= exec_hbm_rvalidready;
     end
end
/*
always @(posedge clk) begin
   //Don't delay the rden in Phase 1 by 1 clock as asumption is read data from FILLED PIPE and one-hot encodied spikes are already there.
   //Delay the rden by 1 clock in Phase 2 so that uram addr (post-synaptic) can be read correctly.
   if ((bram_reading || uram_reading) && exec_hbm_rvalidready) hbm2pfc_rden <= 1'b1; //Don't delay the rden in Phase 1 by 1 clock as asumption is read data from FILLED PIPE and one-hot encodied spikes are already there.
   else hbm2pfc_rden <= 1'b0;
end
*/
assign hbm2pfc_rden = exec_hbm_rvalidready; //send rden to HBMFIFO after each readout (First-word fall-through)

assign ptr0_din  = exec_hbm_rdata[031:000];
assign ptr1_din  = exec_hbm_rdata[063:032];
assign ptr2_din  = exec_hbm_rdata[095:064];
assign ptr3_din  = exec_hbm_rdata[127:096];
assign ptr4_din  = exec_hbm_rdata[159:128];
assign ptr5_din  = exec_hbm_rdata[191:160];
assign ptr6_din  = exec_hbm_rdata[223:192];
assign ptr7_din  = exec_hbm_rdata[255:224];
assign ptr8_din  = exec_hbm_rdata[287:256];
assign ptr9_din  = exec_hbm_rdata[319:288];
assign ptr10_din  = exec_hbm_rdata[351:320];
assign ptr11_din  = exec_hbm_rdata[383:352];
assign ptr12_din  = exec_hbm_rdata[415:384];
assign ptr13_din  = exec_hbm_rdata[447:416];
assign ptr14_din  = exec_hbm_rdata[479:448];
assign ptr15_din  = exec_hbm_rdata[511:480];

assign ptr0_wren = !ptr0_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[0]) | (uram_reading & exec_uram_spiked[0]));
assign ptr1_wren = !ptr1_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[1]) | (uram_reading & exec_uram_spiked[1]));
assign ptr2_wren = !ptr2_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[2]) | (uram_reading & exec_uram_spiked[2]));
assign ptr3_wren = !ptr3_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[3]) | (uram_reading & exec_uram_spiked[3]));
assign ptr4_wren = !ptr4_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[4]) | (uram_reading & exec_uram_spiked[4]));
assign ptr5_wren = !ptr5_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[5]) | (uram_reading & exec_uram_spiked[5]));
assign ptr6_wren = !ptr6_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[6]) | (uram_reading & exec_uram_spiked[6]));
assign ptr7_wren = !ptr7_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[7]) | (uram_reading & exec_uram_spiked[7]));
assign ptr8_wren = !ptr8_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[8]) | (uram_reading & exec_uram_spiked[8]));
assign ptr9_wren = !ptr9_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[9]) | (uram_reading & exec_uram_spiked[9]));
assign ptr10_wren = !ptr10_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[10]) | (uram_reading & exec_uram_spiked[10]));
assign ptr11_wren = !ptr11_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[11]) | (uram_reading & exec_uram_spiked[11]));
assign ptr12_wren = !ptr12_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[12]) | (uram_reading & exec_uram_spiked[12]));
assign ptr13_wren = !ptr13_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[13]) | (uram_reading & exec_uram_spiked[13]));
assign ptr14_wren = !ptr14_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[14]) | (uram_reading & exec_uram_spiked[14]));
assign ptr15_wren = !ptr15_full & exec_hbm_rvalidready & ((bram_reading & exec_bram_spiked[15]) | (uram_reading & exec_uram_spiked[15]));

// Round-Robin arbitration
reg [3:0] addr; //Previously [2:0] 8 pointer FIFOs, now 16 pointer FIFOs
always @(posedge clk) begin
    if (~resetn) addr <= 4'd0;
    else         addr <= addr + 1'b1;
end

//wire [7:0] ptrs_empty = {ptr7_empty,ptr6_empty,ptr5_empty,ptr4_empty,ptr3_empty,ptr2_empty,ptr1_empty,ptr0_empty};
wire [15:0] ptrs_empty = {ptr15_empty,ptr14_empty,ptr13_empty,ptr12_empty,ptr11_empty,ptr10_empty,ptr9_empty,ptr8_empty,ptr7_empty,ptr6_empty,ptr5_empty,ptr4_empty,ptr3_empty,ptr2_empty,ptr1_empty,ptr0_empty};
//wire [31:0] ptrs_dout [7:0];
wire [31:0] ptrs_dout [15:0];
always @(*) begin
    ptr0_rden    <= 1'b0;
    ptr1_rden    <= 1'b0;
    ptr2_rden    <= 1'b0;
    ptr3_rden    <= 1'b0;
    ptr4_rden    <= 1'b0;
    ptr5_rden    <= 1'b0;
    ptr6_rden    <= 1'b0;
    ptr7_rden    <= 1'b0;
    ptr8_rden    <= 1'b0;
    ptr9_rden    <= 1'b0;
    ptr10_rden    <= 1'b0;
    ptr11_rden    <= 1'b0;
    ptr12_rden    <= 1'b0;
    ptr13_rden    <= 1'b0;
    ptr14_rden    <= 1'b0;
    ptr15_rden    <= 1'b0;
    ptrFIFO_din  <= 32'dX;
    ptrFIFO_wren <= 1'b0;
    
    case (addr)
        4'd0: begin
            if (~ptr0_empty & ~ptrFIFO_full) begin
                ptr0_rden    <= 1'b1;
                ptrFIFO_din  <= ptr0_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd1: begin
            if (~ptr1_empty & ~ptrFIFO_full) begin
                ptr1_rden    <= 1'b1;
                ptrFIFO_din  <= ptr1_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd2: begin
            if (~ptr2_empty & ~ptrFIFO_full) begin
                ptr2_rden    <= 1'b1;
                ptrFIFO_din  <= ptr2_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd3: begin
            if (~ptr3_empty & ~ptrFIFO_full) begin
                ptr3_rden    <= 1'b1;
                ptrFIFO_din  <= ptr3_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd4: begin
            if (~ptr4_empty & ~ptrFIFO_full) begin
                ptr4_rden    <= 1'b1;
                ptrFIFO_din  <= ptr4_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd5: begin
            if (~ptr5_empty & ~ptrFIFO_full) begin
                ptr5_rden    <= 1'b1;
                ptrFIFO_din  <= ptr5_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd6: begin
            if (~ptr6_empty & ~ptrFIFO_full) begin
                ptr6_rden    <= 1'b1;
                ptrFIFO_din  <= ptr6_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd7: begin
            if (~ptr7_empty & ~ptrFIFO_full) begin
                ptr7_rden    <= 1'b1;
                ptrFIFO_din  <= ptr7_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd8: begin
            if (~ptr8_empty & ~ptrFIFO_full) begin
                ptr8_rden    <= 1'b1;
                ptrFIFO_din  <= ptr8_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd9: begin
            if (~ptr9_empty & ~ptrFIFO_full) begin
                ptr9_rden    <= 1'b1;
                ptrFIFO_din  <= ptr9_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd10: begin
            if (~ptr10_empty & ~ptrFIFO_full) begin
                ptr10_rden    <= 1'b1;
                ptrFIFO_din  <= ptr10_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd11: begin
            if (~ptr11_empty & ~ptrFIFO_full) begin
                ptr11_rden    <= 1'b1;
                ptrFIFO_din  <= ptr11_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd12: begin
            if (~ptr12_empty & ~ptrFIFO_full) begin
                ptr12_rden    <= 1'b1;
                ptrFIFO_din  <= ptr12_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd13: begin
            if (~ptr13_empty & ~ptrFIFO_full) begin
                ptr13_rden    <= 1'b1;
                ptrFIFO_din  <= ptr13_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd14: begin
            if (~ptr14_empty & ~ptrFIFO_full) begin
                ptr14_rden    <= 1'b1;
                ptrFIFO_din  <= ptr14_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        4'd15: begin
            if (~ptr15_empty & ~ptrFIFO_full) begin
                ptr15_rden    <= 1'b1;
                ptrFIFO_din  <= ptr15_dout;
                ptrFIFO_wren <= 1'b1;
            end
        end
        default: begin
            ptr0_rden    <= 1'b0;
            ptr1_rden    <= 1'b0;
            ptr2_rden    <= 1'b0;
            ptr3_rden    <= 1'b0;
            ptr4_rden    <= 1'b0;
            ptr5_rden    <= 1'b0;
            ptr6_rden    <= 1'b0;
            ptr7_rden    <= 1'b0;
            ptr8_rden    <= 1'b0;
            ptr9_rden    <= 1'b0;
            ptr10_rden    <= 1'b0;
            ptr11_rden    <= 1'b0;
            ptr12_rden    <= 1'b0;
            ptr13_rden    <= 1'b0;
            ptr14_rden    <= 1'b0;
            ptr15_rden    <= 1'b0;
            
            ptrFIFO_din  <= 32'dX;
            ptrFIFO_wren <= 1'b0;
        end
    endcase
end

endmodule
