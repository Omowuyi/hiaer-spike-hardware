//=============================================================================
// Aurora Channel Wrapper
// Wraps Aurora 64B66B IP with CDC FIFOs for clock domain crossing
//
// This wrapper provides:
// - CDC between system clock (aclk) and Aurora user_clk
// - AXI-Stream interface to/from system
// - Status signals
//
// The Aurora IP generates its own user_clk from the GT recovered clock
//=============================================================================

module aurora_channel_wrapper
    import hiaer_firefly_pkg::*;   // for OP_NOP, used as beat padding
#(
    parameter int PORT_NUM = 7,           // Port number (4,5,6,7)
    parameter logic [2:0] FPGA_ID = 3'd0, // FPGA ID for debug
    parameter int CDC_FIFO_DEPTH = 64     // CDC FIFO depth
)(
    //=========================================================================
    // System Interface (aclk domain)
    //=========================================================================
    input  logic            aclk,           // System clock (~225 MHz)
    input  logic            aresetn,        // System reset (active low)
    input  logic            init_clk,       // Aurora init clock (100 MHz)
    
    //=========================================================================
    // GT Interface (directly to package pins)
    //=========================================================================
    input  logic            gt_refclk_p,    // GT reference clock (161.1328125 MHz)
    input  logic            gt_refclk_n,
    output logic [3:0]      gt_txp,         // GT TX differential
    output logic [3:0]      gt_txn,
    input  logic [3:0]      gt_rxp,         // GT RX differential
    input  logic [3:0]      gt_rxn,
    
    //=========================================================================
    // AXI-Stream TX Interface (aclk domain, to remote FPGA)
    //=========================================================================
    input  logic [63:0]     s_axis_tx_tdata,
    input  logic            s_axis_tx_tvalid,
    output logic            s_axis_tx_tready,
    
    //=========================================================================
    // AXI-Stream RX Interface (aclk domain, from remote FPGA)
    //=========================================================================
    output logic [63:0]     m_axis_rx_tdata,
    output logic            m_axis_rx_tvalid,
    input  logic            m_axis_rx_tready,
    
    //=========================================================================
    // Status
    //=========================================================================
    output logic            channel_up,
    output logic [3:0]      lane_up,
    output logic            hard_err,
    output logic            soft_err,
    output logic            link_reset_out,
    
    //=========================================================================
    // Control
    //=========================================================================
    input  logic [2:0]      loopback        // GT loopback mode
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    
    // Aurora user clock domain
    logic           user_clk;
    logic           user_rst;
    logic           sys_reset_out;
    
    // GT reference clock buffer output
    logic           gt_refclk_out;
    
    // Aurora TX interface (user_clk domain)
    // The four-lane cores present 256 bits per beat, four spikes' worth.
    logic [255:0]   aurora_tx_tdata;
    logic           aurora_tx_tvalid;
    logic           aurora_tx_tready;
    
    // Aurora RX interface (user_clk domain)
    logic [255:0]   aurora_rx_tdata;
    logic           aurora_rx_tvalid;
    
    // CDC FIFO signals
    logic           tx_fifo_full;
    logic           tx_fifo_empty;
    logic           rx_fifo_full;
    logic           rx_fifo_empty;
    
    // Reset synchronization
    logic           aresetn_sync;
    logic [2:0]     reset_sync_reg;
    
    //=========================================================================
    // Reset Synchronization (aclk to user_clk)
    //=========================================================================
    
    always_ff @(posedge user_clk or negedge aresetn) begin
        if (!aresetn) begin
            reset_sync_reg <= 3'b000;
        end else begin
            reset_sync_reg <= {reset_sync_reg[1:0], 1'b1};
        end
    end
    
    assign aresetn_sync = reset_sync_reg[2];
    

    //=========================================================================
    // Spike packing
    //
    // The transmit queue is written one 64-bit spike at a time and read as a
    // 256-bit beat, so four spikes cross the link together. A group that stops
    // short is completed with no-operation words after a period of inactivity;
    // without that a lone spike would sit in the queue until three more
    // arrived. Streaming mode carries no tkeep, so the padding has to be in
    // band, and the packet format already defines the opcode for it.
    //=========================================================================
    localparam int TX_FLUSH_CYCLES = 256;

    logic [1:0]  tx_pack_count;    // words written so far, modulo four
    logic [9:0]  tx_idle_count;
    logic [63:0] tx_fifo_din;
    logic        tx_fifo_wr;

    wire tx_user_wr   = s_axis_tx_tvalid && s_axis_tx_tready;
    wire tx_need_pad  = (tx_pack_count != 2'd0)
                     && (tx_idle_count >= TX_FLUSH_CYCLES[9:0])
                     && !tx_fifo_full;

    assign tx_fifo_wr  = tx_user_wr || tx_need_pad;
    assign tx_fifo_din = tx_user_wr ? s_axis_tx_tdata
                                    : {OP_NOP, 61'd0};

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            tx_pack_count <= 2'd0;
            tx_idle_count <= 10'd0;
        end else begin
            if (tx_fifo_wr)
                tx_pack_count <= tx_pack_count + 2'd1;   // wraps at four
            if (tx_user_wr)
                tx_idle_count <= 10'd0;
            else if (tx_pack_count != 2'd0)
                tx_idle_count <= tx_idle_count + 10'd1;
        end
    end

    //=========================================================================
    // Received beats arrive as four 64-bit slots. Those carrying the
    // no-operation opcode were padding and are drained without being offered
    // downstream.
    //=========================================================================
    logic [63:0] rx_dout_raw;
    logic        rx_dvalid_raw;

    wire rx_slot_is_nop = (rx_dout_raw[63:61] == OP_NOP);

    assign m_axis_rx_tdata  = rx_dout_raw;
    assign m_axis_rx_tvalid = rx_dvalid_raw && !rx_slot_is_nop;

    //=========================================================================
    // TX CDC FIFO (aclk → user_clk)
    //=========================================================================
    
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE   ("auto"),
        .FIFO_WRITE_DEPTH   (CDC_FIFO_DEPTH),
        .WRITE_DATA_WIDTH   (64),
        .READ_DATA_WIDTH    (256),   // four spikes gathered into one beat
        // The asymmetric ratio changes the queue's internal geometry, so the
        // default programmable-full threshold falls outside its legal range.
        // The flag is unused here; this is set only to a permitted value.
        .PROG_FULL_THRESH   (16),
        .READ_MODE          ("fwft"),
        .FIFO_READ_LATENCY  (0),
        .CDC_SYNC_STAGES    (3),
        .FULL_RESET_VALUE   (1)
    ) u_tx_cdc_fifo (
        // Write side (aclk domain)
        .wr_clk         (aclk),
        .rst            (~aresetn),
        .wr_en          (tx_fifo_wr),
        .din            (tx_fifo_din),
        .full           (tx_fifo_full),
        .prog_full      (),
        .wr_data_count  (),
        .overflow       (),
        .wr_rst_busy    (),
        .almost_full    (),
        .wr_ack         (),
        
        // Read side (user_clk domain)
        .rd_clk         (user_clk),
        .rd_en          (aurora_tx_tvalid && aurora_tx_tready),
        .dout           (aurora_tx_tdata),
        .empty          (tx_fifo_empty),
        .prog_empty     (),
        .rd_data_count  (),
        .underflow      (),
        .rd_rst_busy    (),
        .almost_empty   (),
        .data_valid     (aurora_tx_tvalid),
        
        .sleep          (1'b0),
        .injectsbiterr  (1'b0),
        .injectdbiterr  (1'b0),
        .sbiterr        (),
        .dbiterr        ()
    );
    
    assign s_axis_tx_tready = ~tx_fifo_full && channel_up;
    
    //=========================================================================
    // RX CDC FIFO (user_clk → aclk)
    //=========================================================================
    
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE   ("auto"),
        .FIFO_WRITE_DEPTH   (CDC_FIFO_DEPTH),
        .WRITE_DATA_WIDTH   (256),  // one beat in, four spikes out
        .READ_DATA_WIDTH    (64),
        .READ_MODE          ("fwft"),
        .FIFO_READ_LATENCY  (0),
        .CDC_SYNC_STAGES    (3),
        .FULL_RESET_VALUE   (1)
    ) u_rx_cdc_fifo (
        // Write side (user_clk domain)
        .wr_clk         (user_clk),
        .rst            (user_rst),
        .wr_en          (aurora_rx_tvalid && ~rx_fifo_full),
        .din            (aurora_rx_tdata),
        .full           (rx_fifo_full),
        .prog_full      (),
        .wr_data_count  (),
        .overflow       (),
        .wr_rst_busy    (),
        .almost_full    (),
        .wr_ack         (),
        
        // Read side (aclk domain)
        .rd_clk         (aclk),
        .rd_en          (rx_dvalid_raw && (rx_slot_is_nop || m_axis_rx_tready)),
        .dout           (rx_dout_raw),
        .empty          (rx_fifo_empty),
        .prog_empty     (),
        .rd_data_count  (),
        .underflow      (),
        .rd_rst_busy    (),
        .almost_empty   (),
        .data_valid     (rx_dvalid_raw),
        
        .sleep          (1'b0),
        .injectsbiterr  (1'b0),
        .injectdbiterr  (1'b0),
        .sbiterr        (),
        .dbiterr        ()
    );
    
    //=========================================================================
    // Aurora IP Instance (generated by create_aurora_ips.tcl)
    // Port-specific instantiation using generate
    //=========================================================================
    
    generate
        if (PORT_NUM == 4) begin : gen_aurora_port4
            // Same shape as port 7: the IP owns its shared logic, so the
            // reference clock arrives differentially and there are no QPLL
            // inputs to drive.
            aurora_64b66b_port4 u_aurora (
                .rxp                    (gt_rxp),
                .rxn                    (gt_rxn),
                .txp                    (gt_txp),
                .txn                    (gt_txn),
                .gt_refclk1_p           (gt_refclk_p),
                .gt_refclk1_n           (gt_refclk_n),
                .user_clk_out           (user_clk),
                .reset_pb               (~aresetn),
                .power_down             (1'b0),
                .pma_init               (~aresetn),
                .init_clk               (init_clk),
                .s_axi_tx_tdata         (aurora_tx_tdata),
                .s_axi_tx_tvalid        (aurora_tx_tvalid),
                .s_axi_tx_tready        (aurora_tx_tready),
                .m_axi_rx_tdata         (aurora_rx_tdata),
                .m_axi_rx_tvalid        (aurora_rx_tvalid),
                .channel_up             (channel_up),
                .lane_up                (lane_up),
                .hard_err               (hard_err),
                .soft_err               (soft_err),
                .sys_reset_out          (sys_reset_out),
                .link_reset_out         (link_reset_out),
                .loopback               (loopback)
            );
        end else if (PORT_NUM == 5) begin : gen_aurora_port5
            // Same shape as port 7: the IP owns its shared logic, so the
            // reference clock arrives differentially and there are no QPLL
            // inputs to drive.
            aurora_64b66b_port5 u_aurora (
                .rxp                    (gt_rxp),
                .rxn                    (gt_rxn),
                .txp                    (gt_txp),
                .txn                    (gt_txn),
                .gt_refclk1_p           (gt_refclk_p),
                .gt_refclk1_n           (gt_refclk_n),
                .user_clk_out           (user_clk),
                .reset_pb               (~aresetn),
                .power_down             (1'b0),
                .pma_init               (~aresetn),
                .init_clk               (init_clk),
                .s_axi_tx_tdata         (aurora_tx_tdata),
                .s_axi_tx_tvalid        (aurora_tx_tvalid),
                .s_axi_tx_tready        (aurora_tx_tready),
                .m_axi_rx_tdata         (aurora_rx_tdata),
                .m_axi_rx_tvalid        (aurora_rx_tvalid),
                .channel_up             (channel_up),
                .lane_up                (lane_up),
                .hard_err               (hard_err),
                .soft_err               (soft_err),
                .sys_reset_out          (sys_reset_out),
                .link_reset_out         (link_reset_out),
                .loopback               (loopback)
            );
        end else if (PORT_NUM == 6) begin : gen_aurora_port6
            // Same shape as port 7: the IP owns its shared logic, so the
            // reference clock arrives differentially and there are no QPLL
            // inputs to drive.
            aurora_64b66b_port6 u_aurora (
                .rxp                    (gt_rxp),
                .rxn                    (gt_rxn),
                .txp                    (gt_txp),
                .txn                    (gt_txn),
                .gt_refclk1_p           (gt_refclk_p),
                .gt_refclk1_n           (gt_refclk_n),
                .user_clk_out           (user_clk),
                .reset_pb               (~aresetn),
                .power_down             (1'b0),
                .pma_init               (~aresetn),
                .init_clk               (init_clk),
                .s_axi_tx_tdata         (aurora_tx_tdata),
                .s_axi_tx_tvalid        (aurora_tx_tvalid),
                .s_axi_tx_tready        (aurora_tx_tready),
                .m_axi_rx_tdata         (aurora_rx_tdata),
                .m_axi_rx_tvalid        (aurora_rx_tvalid),
                .channel_up             (channel_up),
                .lane_up                (lane_up),
                .hard_err               (hard_err),
                .soft_err               (soft_err),
                .sys_reset_out          (sys_reset_out),
                .link_reset_out         (link_reset_out),
                .loopback               (loopback)
            );
        end else begin : gen_aurora_port7  // PORT_NUM == 7
            
            // The configured IP is named _logic: 4 lanes, 25.78125 Gb/s,
            // 161.13 MHz reference.  `aurora_64b66b_port7` is a different,
            // unconfigured IP that Vivado was stubbing.
            aurora_64b66b_port7_logic u_aurora (
                .rxp                    (gt_rxp),
                .rxn                    (gt_rxn),
                .txp                    (gt_txp),
                .txn                    (gt_txn),
                .gt_refclk1_p           (gt_refclk_p),
                .gt_refclk1_n           (gt_refclk_n),
                .user_clk_out           (user_clk),
                .reset_pb               (~aresetn),
                .power_down             (1'b0),
                .pma_init               (~aresetn),
                .init_clk               (init_clk),
                .s_axi_tx_tdata         (aurora_tx_tdata),
                .s_axi_tx_tvalid        (aurora_tx_tvalid),
                .s_axi_tx_tready        (aurora_tx_tready),
                .m_axi_rx_tdata         (aurora_rx_tdata),
                .m_axi_rx_tvalid        (aurora_rx_tvalid),
                .channel_up             (channel_up),
                .lane_up                (lane_up),
                .hard_err               (hard_err),
                .soft_err               (soft_err),
                .sys_reset_out          (sys_reset_out),
                .link_reset_out         (link_reset_out),
                .loopback               (loopback)
            );
            
        end
    endgenerate
    
    // User reset from Aurora
    assign user_rst = sys_reset_out | ~aresetn_sync;

endmodule : aurora_channel_wrapper
