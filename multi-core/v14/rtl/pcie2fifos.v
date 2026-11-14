`timescale 1ns / 1ps

module pcie2fifos (
    input aclk,
    input aresetn,

    // AXI4 Read command -> Output FIFO pop
    //  Read address/command
    input  [63:0]   s_axi_araddr,
    input   [1:0]   s_axi_arburst,
    input   [3:0]   s_axi_arcache,
    input   [3:0]   s_axi_arid,
    input   [7:0]   s_axi_arlen,
    input           s_axi_arlock,
    input   [2:0]   s_axi_arprot,
    output reg      s_axi_arready,
    input   [2:0]   s_axi_arsize,
    input           s_axi_arvalid,

    // AXI4 Write command -> Input FIFO push
    //  Write address/command
    input  [63:0]   s_axi_awaddr,
    input   [1:0]   s_axi_awburst,
    input   [3:0]   s_axi_awcache,
    input   [3:0]   s_axi_awid,
    input   [7:0]   s_axi_awlen,
    input           s_axi_awlock,
    input   [2:0]   s_axi_awprot,
    output reg      s_axi_awready,
    input   [2:0]   s_axi_awsize,
    input           s_axi_awvalid,
    
    //  Write response
    output   [3:0]  s_axi_bid,
    input           s_axi_bready,
    output   [1:0]  s_axi_bresp,
    output reg      s_axi_bvalid,
    
    //  Read response
    output [511:0]  s_axi_rdata,
    output   [3:0]  s_axi_rid,
    output          s_axi_rlast,
    input           s_axi_rready,
    output   [1:0]  s_axi_rresp,
    output reg      s_axi_rvalid,
    
    //  Write data
    input  [511:0]  s_axi_wdata,
    input           s_axi_wlast,
    output reg      s_axi_wready,
    input   [63:0]  s_axi_wstrb,
    input           s_axi_wvalid,
    
    // Input FIFO: PC->FPGA
    input           inpFIFO_full,
    output [511:0]  inpFIFO_din,
    output          inpFIFO_wren,
    
    // Output FIFO: FPGA->PC
    input           outFIFO_empty,
    input  [511:0]  outFIFO_dout,
    output          outFIFO_rden
);


// Drive mandatory signals
assign s_axi_bid = 4'd0;
assign s_axi_rid = 4'd0;
assign s_axi_rresp = 2'd0;
assign s_axi_bresp = 2'd0;

// Input data
assign inpFIFO_din  = s_axi_wdata;
assign inpFIFO_wren = s_axi_wready & s_axi_wvalid;
 
// Output data (using FWFT FIFO for simplifying rden logic)
assign s_axi_rdata = ~outFIFO_empty ? outFIFO_dout : {16{32'h89ABCDEF}};
assign outFIFO_rden = ~outFIFO_empty & s_axi_rvalid & s_axi_rready;

// Write control logic: push FIFO
reg [1:0] rx_curr_state, rx_next_state;
localparam [1:0] STATE_RX_RESET = 2'd0;
localparam [1:0] STATE_RX_DATA  = 2'd1;
localparam [1:0] STATE_RX_DONE  = 2'd3;

always @(posedge aclk)
    if (!aresetn) rx_curr_state <= STATE_RX_RESET;
    else          rx_curr_state <= rx_next_state;

always @* begin
    s_axi_awready = 1'b0;
    s_axi_wready  = 1'b0;
    s_axi_bvalid  = 1'b0;
    rx_next_state = rx_curr_state;
    
    case (rx_curr_state)
        STATE_RX_RESET: begin
            s_axi_awready = 1'b1;
            if (s_axi_awvalid)                
                rx_next_state = STATE_RX_DATA;
        end
        STATE_RX_DATA: begin
            if (!inpFIFO_full) begin
                s_axi_wready = 1'b1;
                if (s_axi_wvalid & s_axi_wlast)
                    rx_next_state = STATE_RX_DONE;
            end
        end
        STATE_RX_DONE: begin
            s_axi_bvalid = 1'b1;
            if (s_axi_bready) begin
                s_axi_awready = 1'b1;
                if (s_axi_awvalid)
                    rx_next_state = STATE_RX_DATA;
                else
                    rx_next_state = STATE_RX_RESET;
            end
        end
        default: rx_next_state = STATE_RX_RESET;
    endcase
end

// Read control logic: pop FIFO
reg tx_curr_state, tx_next_state;
localparam STATE_TX_RESET = 1'b0;
localparam STATE_TX_DATA  = 1'b1;

always @(posedge aclk)
    if (!aresetn) tx_curr_state <= STATE_TX_RESET;
    else          tx_curr_state <= tx_next_state;

reg [7:0] s_axi_arlen_reg;
always @(posedge aclk)
    if (!aresetn)
        s_axi_arlen_reg <= 8'b0;
    else if (s_axi_arready & s_axi_arvalid)
        s_axi_arlen_reg <= s_axi_arlen;

reg [7:0] tx_ctr;
always @(posedge aclk)
    if (!aresetn | (s_axi_arready & s_axi_arvalid))
        tx_ctr <= 8'd0;
    else if (s_axi_rready & s_axi_rvalid)
        tx_ctr <= tx_ctr + 1'b1;

assign s_axi_rlast  = (tx_ctr==s_axi_arlen_reg);

always @* begin
    s_axi_arready = 1'b0;
    s_axi_rvalid  = 1'b0;
    tx_next_state = tx_curr_state;
    
    case (tx_curr_state)
        STATE_TX_RESET: begin
            s_axi_arready = 1'b1;
            if (s_axi_arvalid)
                tx_next_state = STATE_TX_DATA;
        end
        STATE_TX_DATA: begin
            s_axi_rvalid = 1'b1;
            if (s_axi_rready & (tx_ctr==s_axi_arlen_reg)) begin
                s_axi_arready = 1'b1;
                if (!s_axi_arvalid)
                    tx_next_state = STATE_TX_RESET;
            end
        end
        default: tx_next_state = STATE_TX_RESET;
    endcase
end

endmodule
