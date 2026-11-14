`timescale 1ns / 1ps

module input_data_handler(

    input resetn,
    input clk,

    // Command interpreter: input FIFO (local)
    input                   ci2idp_empty,
    output reg              ci2idp_rden,
    input      [1+15+255:0] ci2idp_dout,
    
    // Command interpreter: output FIFO (remote)
    input                 idp2ci_full,
    output     [15+255:0] idp2ci_din,
    output reg            idp2ci_wren,
    
    // External events processor: input FIFO (local)
    input                 eep2idp_empty,
    output reg            eep2idp_rden,
    input          [14:0] eep2idp_dout,
    
    // External events processor: output FIFO (remote)
    input                 idp2eep_full,
    output     [15+255:0] idp2eep_din,
    output reg            idp2eep_wren,
    
    // BRAM (2^15 x 256)
    output reg     [14:0] bram_addr,
    output        [255:0] bram_din,
    output reg            bram_wren,
    input         [255:0] bram_dout
    
);

//////////////////
// DECLARATIONS //
//////////////////

wire command;
localparam CMD_READ  = 1'b0;
localparam CMD_WRITE = 1'b1;

reg [2:0] curr_state, next_state;
localparam [2:0] STATE_RESET                = 3'd0;
localparam [2:0] STATE_IDLE                 = 3'd1;
localparam [2:0] STATE_EEP_WAIT_BRAM_READ_0 = 3'd2;
localparam [2:0] STATE_EEP_WAIT_BRAM_READ_1 = 3'd3;
localparam [2:0] STATE_EEP_WAIT_BRAM_READ_2 = 3'd4;
localparam [2:0] STATE_CI_WAIT_BRAM_READ_0  = 3'd5;
localparam [2:0] STATE_CI_WAIT_BRAM_READ_1  = 3'd6;
localparam [2:0] STATE_CI_WAIT_BRAM_READ_2  = 3'd7;


/////////////////
// ASSIGNMENTS //
/////////////////

assign command = ci2idp_dout[1+15+255];

assign idp2eep_din = {bram_addr, bram_dout};
assign idp2ci_din  = {bram_addr, bram_dout};

assign bram_din = ci2idp_dout[255:0];


///////////
// LOGIC //
///////////

// State machine
always @(posedge clk) begin
    if (~resetn) curr_state <= STATE_RESET;
    else         curr_state <= next_state;
end

always @(*) begin
    bram_addr       = 15'dX;
    bram_wren       = 1'b0;
    idp2eep_wren    = 1'b0;
    eep2idp_rden    = 1'b0;
    idp2ci_wren     = 1'b0;
    ci2idp_rden     = 1'b0;
    next_state = curr_state;
    
    case (curr_state)
        STATE_RESET: begin
            next_state = STATE_IDLE;
        end
        STATE_IDLE: begin
            if (~eep2idp_empty) begin
                bram_addr  = eep2idp_dout;
                next_state = STATE_EEP_WAIT_BRAM_READ_0;

            end else if (~ci2idp_empty) begin
                bram_addr = ci2idp_dout[15+255:256];

                if (command==CMD_READ)
                    next_state = STATE_CI_WAIT_BRAM_READ_0;
                else begin
                    bram_wren   = 1'b1;
                    ci2idp_rden = 1'b1;
                    next_state  = STATE_IDLE;
                end
            end
        end
        
        STATE_EEP_WAIT_BRAM_READ_0: begin
            bram_addr  = eep2idp_dout;
            next_state = STATE_EEP_WAIT_BRAM_READ_1;
        end
        STATE_EEP_WAIT_BRAM_READ_1: begin
            bram_addr  = eep2idp_dout;
            next_state = STATE_EEP_WAIT_BRAM_READ_2;
        end
        STATE_EEP_WAIT_BRAM_READ_2: begin
            bram_addr = eep2idp_dout;
            if (~idp2eep_full) begin
                idp2eep_wren = 1'b1;
                eep2idp_rden = 1'b1;
                next_state = STATE_IDLE;
            end
        end
        
        STATE_CI_WAIT_BRAM_READ_0: begin
            bram_addr  = ci2idp_dout[15+255:256];
            next_state = STATE_CI_WAIT_BRAM_READ_1;
        end
        STATE_CI_WAIT_BRAM_READ_1: begin
            bram_addr  = ci2idp_dout[15+255:256];
            next_state = STATE_CI_WAIT_BRAM_READ_2;
        end
        STATE_CI_WAIT_BRAM_READ_2: begin
            bram_addr = ci2idp_dout[15+255:256];
            if (~idp2ci_full) begin
                idp2ci_wren = 1'b1;
                ci2idp_rden = 1'b1;
                next_state = STATE_IDLE;
            end
        end
        
        default: begin
            next_state = STATE_RESET;
        end
    endcase
end

endmodule
