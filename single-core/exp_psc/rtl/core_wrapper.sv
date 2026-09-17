`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module: core_wrapper.sv
// 
// MODIFIED FOR MULTI-CORE SUPPORT:
// - Added CORE_ID parameter to identify which core (0-15)
// - Passes CORE_ID through to core instance for spike tagging
// MODIFIED FOR NEW FEATURES:
// - Added user_irq, error_status, iep_watchdog_error, iep_uram_out_of_range
////////////////////////////////////////////////////////////////////////////////

module core_wrapper #(
    // NEW: Core identification for multi-core spike tagging
    parameter [3:0] CORE_ID = 4'd0
)(
    input aclk,
    input aclk450,
    input async_resetn,
    input async_resetn450,
    
    //Outputs to VIO probe
    output [16:0] num_outputs,
    output [16:0] num_inputs,
    output [35:0] threshold,
    output [1:0] exec_neuron_model,
    
    input [4:0] core_number,
    
    AXI4.Master hbm,
    
    FIFO_input.Sink rxFIFO_in,
    FIFO_output.Source txFIFO_out,
    
    //Output to VIO
    output exec_hbm_rvalidready,
    output hbmFIFO_empty,
    output [3:0] iep_curr_state,
    output [3:0] hbm_curr_state,
    output [2:0] eep_curr_state,
    output   exec_hbm_rx_phase1_done,
    output   exec_hbm_rx_phase2_done,
    output  [12:0] curr_bram_waddr,
    output  [12:0] curr_uram_waddr,
    output  hbm2eep_rden,
    output  hbm2iep_rden,
    output  hbm2pfc_rden,
    output  execRun_done,
    
    // =========================================================================
    // NoC Interface
    // =========================================================================
    output wire [16:0] noc_spike_out_addr,
    output wire        noc_spike_out_valid,
    input  wire        noc_spike_out_ready,
    input  wire [16:0] noc_relay_din,
    input  wire        noc_relay_wren,
    output wire        noc_relay_full,
    output wire        exec_eep_phase3_done,
    
    // =========================================================================
    // NEW: Feature ports - interrupt, error status, watchdog
    // =========================================================================
    output wire        user_irq,
    output wire [31:0] error_status,
    output wire        iep_watchdog_error,
    output wire        iep_uram_out_of_range
);
    
    wire aresetn;
    wire aresetn450;
    
    reset_synchronizer #(
        .ACTIVE("low")
    ) reset_sync (
        .clk(aclk),
        .reset_in(async_resetn),
        .reset_out(aresetn)
    );
    
    reset_synchronizer #(
        .ACTIVE("low")
    ) reset_sync_450 (
        .clk(aclk450),
        .reset_in(async_resetn450),
        .reset_out(aresetn450)
    );
    
    AXI4 #(33, 256) hbm_prebuffer(.aclk(hbm.aclk), .aresetn(hbm.aresetn));
    
    // =========================================================================
    // FIX: AXI len width conversion
    // The hbm_register_slice IP expects 8-bit awlen/arlen signals,
    // but our AXI4 interface uses 4-bit len signals.
    // Add intermediate wires to handle the width mismatch.
    // =========================================================================
    wire [7:0] hbm_awlen_to_slice;
    wire [7:0] hbm_arlen_to_slice;
    wire [7:0] hbm_awlen_from_slice;
    wire [7:0] hbm_arlen_from_slice;
    
    // Zero-extend 4-bit to 8-bit for slave side (input to IP)
    assign hbm_awlen_to_slice = {4'b0000, hbm_prebuffer.awlen};
    assign hbm_arlen_to_slice = {4'b0000, hbm_prebuffer.arlen};
    
    // Truncate 8-bit to 4-bit for master side (output from IP)
    assign hbm.awlen = hbm_awlen_from_slice[3:0];
    assign hbm.arlen = hbm_arlen_from_slice[3:0];
    
    hbm_register_slice axi_slice (
        .aclk(aclk450),
        .aresetn(aresetn450),
        // Slave side (from hbm_prebuffer)
        .s_axi_awaddr(hbm_prebuffer.awaddr),
        .s_axi_awlen(hbm_awlen_to_slice),
        .s_axi_awsize(hbm_prebuffer.awsize),
        .s_axi_awburst(hbm_prebuffer.awburst),
        .s_axi_awid(hbm_prebuffer.awid),
        .s_axi_awvalid(hbm_prebuffer.awvalid),
        .s_axi_awready(hbm_prebuffer.awready),
        .s_axi_wdata(hbm_prebuffer.wdata),
        .s_axi_wstrb(hbm_prebuffer.wstrb),
        .s_axi_wlast(hbm_prebuffer.wlast),
        .s_axi_wvalid(hbm_prebuffer.wvalid),
        .s_axi_wready(hbm_prebuffer.wready),
        .s_axi_bid(hbm_prebuffer.bid),
        .s_axi_bresp(hbm_prebuffer.bresp),
        .s_axi_bvalid(hbm_prebuffer.bvalid),
        .s_axi_bready(hbm_prebuffer.bready),
        .s_axi_araddr(hbm_prebuffer.araddr),
        .s_axi_arlen(hbm_arlen_to_slice),
        .s_axi_arsize(hbm_prebuffer.arsize),
        .s_axi_arburst(hbm_prebuffer.arburst),
        .s_axi_arid(hbm_prebuffer.arid),
        .s_axi_arvalid(hbm_prebuffer.arvalid),
        .s_axi_arready(hbm_prebuffer.arready),
        .s_axi_rid(hbm_prebuffer.rid),
        .s_axi_rdata(hbm_prebuffer.rdata),
        .s_axi_rresp(hbm_prebuffer.rresp),
        .s_axi_rlast(hbm_prebuffer.rlast),
        .s_axi_rvalid(hbm_prebuffer.rvalid),
        .s_axi_rready(hbm_prebuffer.rready),
        // Master side (to hbm)
        .m_axi_awaddr(hbm.awaddr),
        .m_axi_awlen(hbm_awlen_from_slice),
        .m_axi_awsize(hbm.awsize),
        .m_axi_awburst(hbm.awburst),
        .m_axi_awid(hbm.awid),
        .m_axi_awvalid(hbm.awvalid),
        .m_axi_awready(hbm.awready),
        .m_axi_wdata(hbm.wdata),
        .m_axi_wstrb(hbm.wstrb),
        .m_axi_wlast(hbm.wlast),
        .m_axi_wvalid(hbm.wvalid),
        .m_axi_wready(hbm.wready),
        .m_axi_bid(hbm.bid),
        .m_axi_bresp(hbm.bresp),
        .m_axi_bvalid(hbm.bvalid),
        .m_axi_bready(hbm.bready),
        .m_axi_araddr(hbm.araddr),
        .m_axi_arlen(hbm_arlen_from_slice),
        .m_axi_arsize(hbm.arsize),
        .m_axi_arburst(hbm.arburst),
        .m_axi_arid(hbm.arid),
        .m_axi_arvalid(hbm.arvalid),
        .m_axi_arready(hbm.arready),
        .m_axi_rid(hbm.rid),
        .m_axi_rdata(hbm.rdata),
        .m_axi_rresp(hbm.rresp),
        .m_axi_rlast(hbm.rlast),
        .m_axi_rvalid(hbm.rvalid),
        .m_axi_rready(hbm.rready)
    );
    
    // =========================================================================
    // Core instance with CORE_ID for multi-core spike tagging
    // =========================================================================
    core #(
        .CORE_ID(CORE_ID)
    ) inst (
        .aclk(aclk),
        .aclk450(aclk450),
        .aresetn(aresetn),
        .aresetn450(aresetn450),
        .num_outputs_out(num_outputs),
        .num_inputs_out(num_inputs),
        .threshold_out(threshold),
        .exec_neuron_model_out(exec_neuron_model),
        
        .core_number(core_number),
        
        .hbm_araddr(hbm_prebuffer.araddr),
        .hbm_arburst(hbm_prebuffer.arburst),
        .hbm_arid(hbm_prebuffer.arid),
        .hbm_arlen(hbm_prebuffer.arlen),
        .hbm_arready(hbm_prebuffer.arready),
        .hbm_arsize(hbm_prebuffer.arsize),
        .hbm_arvalid(hbm_prebuffer.arvalid),
        .hbm_awaddr(hbm_prebuffer.awaddr),
        .hbm_awburst(hbm_prebuffer.awburst),
        .hbm_awid(hbm_prebuffer.awid),
        .hbm_awlen(hbm_prebuffer.awlen),
        .hbm_awready(hbm_prebuffer.awready),
        .hbm_awsize(hbm_prebuffer.awsize),
        .hbm_awvalid(hbm_prebuffer.awvalid),
        .hbm_bid(hbm_prebuffer.bid),
        .hbm_bready(hbm_prebuffer.bready),
        .hbm_bresp(hbm_prebuffer.bresp),
        .hbm_bvalid(hbm_prebuffer.bvalid),
        .hbm_rdata(hbm_prebuffer.rdata),
        .hbm_rid(hbm_prebuffer.rid),
        .hbm_rlast(hbm_prebuffer.rlast),
        .hbm_rready(hbm_prebuffer.rready),
        .hbm_rresp(hbm_prebuffer.rresp),
        .hbm_rvalid(hbm_prebuffer.rvalid),
        .hbm_wdata(hbm_prebuffer.wdata),
        .hbm_wlast(hbm_prebuffer.wlast),
        .hbm_wready(hbm_prebuffer.wready),
        .hbm_wstrb(hbm_prebuffer.wstrb),
        .hbm_wvalid(hbm_prebuffer.wvalid),
        
        .rxFIFO_in_din(rxFIFO_in.din),
        .rxFIFO_in_wren(rxFIFO_in.wren),
        .rxFIFO_in_full(rxFIFO_in.full),
        
        .txFIFO_out_dout(txFIFO_out.dout),
        .txFIFO_out_rden(txFIFO_out.rden),
        .txFIFO_out_empty(txFIFO_out.empty),
        
        .exec_hbm_rvalidready(exec_hbm_rvalidready),
        .hbmFIFO_empty(hbmFIFO_empty),
        .iep_curr_state(iep_curr_state),
        .hbm_curr_state(hbm_curr_state),
        .eep_curr_state(eep_curr_state),
        .exec_hbm_rx_phase1_done(exec_hbm_rx_phase1_done),
        .exec_hbm_rx_phase2_done(exec_hbm_rx_phase2_done),
        .curr_bram_waddr(curr_bram_waddr),
        .curr_uram_waddr(curr_uram_waddr),
        .hbm2eep_rden(hbm2eep_rden),
        .hbm2iep_rden(hbm2iep_rden),
        .hbm2pfc_rden(hbm2pfc_rden),
        .execRun_done(execRun_done),
        
        // NoC Interface
        .noc_spike_out_addr(noc_spike_out_addr),
        .noc_spike_out_valid(noc_spike_out_valid),
        .noc_spike_out_ready(noc_spike_out_ready),
        .noc_relay_din(noc_relay_din),
        .noc_relay_wren(noc_relay_wren),
        .noc_relay_full(noc_relay_full),
        .exec_eep_phase3_done(exec_eep_phase3_done),
        
        // NEW: Feature ports
        .user_irq(user_irq),
        .error_status(error_status),
        .iep_watchdog_error(iep_watchdog_error),
        .iep_uram_out_of_range(iep_uram_out_of_range)
    );

endmodule