//=============================================================================
// HiAER-Spike Sixteen Core Top with FireFly Integration
// 
// This is the complete top-level module integrating:
// - 16 neural network cores with HBM
// - PCIe DMA interface
// - FireFly inter-FPGA communication (Aurora 64B/66B)
//
// Packet Format Conversion:
// - Core level: 512-bit NoC packets with up to 14 spikes per packet
// - Cluster level: Same 512-bit format routed through L1/L2 switches
// - FPGA level (FireFly): 64-bit inter_fpga_spike_t packets
//
// Target: ADM-PCIE-9H7 with VU37P FPGA
//=============================================================================

`timescale 1ns / 1ps

module sixteen_core_top_firefly
    import hiaer_firefly_pkg::*;
#(
    parameter logic [2:0] FPGA_ID = 3'd0    // Set per FPGA (0-7)
)(
    //=========================================================================
    // PCIe Interface
    //=========================================================================
    input  wire [0:0]       pcie_clk_in_clk_n,
    input  wire [0:0]       pcie_clk_in_clk_p,
    input  wire             sys_rst_n,
    input  wire [15:0]      pcie_rxp,
    input  wire [15:0]      pcie_rxn,
    output wire [15:0]      pcie_txp,
    output wire [15:0]      pcie_txn,
    
    //=========================================================================
    // System Reference Clock (450 MHz)
    //=========================================================================
    input  wire             refclk450_p,
    input  wire             refclk450_n,
    
    //=========================================================================
    // FireFly Port 4 GT Pins (Upper tier only: FPGA 4-7)
    //=========================================================================
    input  wire             ff4_refclk_p,
    input  wire             ff4_refclk_n,
    output wire [3:0]       ff4_txp,
    output wire [3:0]       ff4_txn,
    input  wire [3:0]       ff4_rxp,
    input  wire [3:0]       ff4_rxn,
    output wire             ff4_modprs_n,
    inout  wire             ff4_scl,
    inout  wire             ff4_sda,
    
    //=========================================================================
    // FireFly Port 5 GT Pins (Upper tier only: FPGA 4-7)
    //=========================================================================
    input  wire             ff5_refclk_p,
    input  wire             ff5_refclk_n,
    output wire [3:0]       ff5_txp,
    output wire [3:0]       ff5_txn,
    input  wire [3:0]       ff5_rxp,
    input  wire [3:0]       ff5_rxn,
    output wire             ff5_modprs_n,
    inout  wire             ff5_scl,
    inout  wire             ff5_sda,
    
    //=========================================================================
    // FireFly Port 6 GT Pins (Upper tier only: FPGA 4-7)
    //=========================================================================
    input  wire             ff6_refclk_p,
    input  wire             ff6_refclk_n,
    output wire [3:0]       ff6_txp,
    output wire [3:0]       ff6_txn,
    input  wire [3:0]       ff6_rxp,
    input  wire [3:0]       ff6_rxn,
    output wire             ff6_modprs_n,
    inout  wire             ff6_scl,
    inout  wire             ff6_sda,
    
    //=========================================================================
    // FireFly Port 7 GT Pins (All FPGAs: 0-7)
    //=========================================================================
    input  wire             ff7_refclk_p,
    input  wire             ff7_refclk_n,
    output wire [3:0]       ff7_txp,
    output wire [3:0]       ff7_txn,
    input  wire [3:0]       ff7_rxp,
    input  wire [3:0]       ff7_rxn,
    output wire             ff7_modprs_n,
    inout  wire             ff7_scl,
    inout  wire             ff7_sda,
    
    //=========================================================================
    // Status LEDs
    //=========================================================================
    output wire [3:0]       led
);

    //=========================================================================
    // Internal Clocks and Resets
    //=========================================================================
    
    wire            aclk;               // 225 MHz system clock
    wire            aclk_450;           // 450 MHz HBM clock
    wire            init_clk;           // 100 MHz init clock
    wire            aresetn;            // Active-low reset
    wire            hbm_ref_clk;        // HBM reference clock
    
    //=========================================================================
    // HBM AXI Interfaces (32 channels, only 16 used)
    //=========================================================================
    
    // HBM interface signals (from hbm_axi_if)
    hbm_axi_if hbm [31:0] ();
    
    //=========================================================================
    // NoC Interconnect Signals
    //=========================================================================
    
    // Core to switch_16_1 (TX from cores)
    wire [511:0]    core_tx_tdata   [15:0];
    wire            core_tx_tvalid  [15:0];
    wire            core_tx_tready  [15:0];
    wire            core_tx_tlast   [15:0];
    
    // Switch_1_16 to cores (RX to cores)  
    wire [511:0]    core_rx_tdata   [15:0];
    wire [3:0]      core_rx_tdest   [15:0];
    wire            core_rx_tvalid  [15:0];
    wire            core_rx_tready  [15:0];
    wire            core_rx_tlast   [15:0];
    
    // Aggregated output from switch_16_1 (goes to spike classifier)
    wire [511:0]    noc_out_tdata;
    wire            noc_out_tvalid;
    wire            noc_out_tready;
    wire            noc_out_tlast;
    
    // Input to switch_1_16 (from input arbiter)
    wire [511:0]    noc_in_tdata;
    wire [3:0]      noc_in_tdest;
    wire            noc_in_tvalid;
    wire            noc_in_tready;
    wire            noc_in_tlast;
    
    //=========================================================================
    // Crossbar NoC Signals -- core-to-core spike routing within this FPGA
    //=========================================================================
    // Separate from the 512-bit AXI-Stream path above, which keeps carrying
    // PCIe commands and inter-FPGA spikes unchanged.

    wire [16:0]     core_noc_out_addr   [15:0];
    wire            core_noc_out_valid  [15:0];
    wire            core_noc_out_ready  [15:0];

    wire [16:0]     core_noc_relay_din  [15:0];
    wire            core_noc_relay_wren [15:0];
    wire            core_noc_relay_full [15:0];

    wire            core_exec_run_w     [15:0];

    // Routing table writes, one bundle per core's command interpreter
    wire            core_route_cfg_valid [15:0];
    wire [7:0]      core_route_cfg_addr  [15:0];
    wire [5:0]      core_route_cfg_data  [15:0];

    // Crossbar spikes destined for the host.  Left unconnected for the first
    // build: spikes already reach the host over the 512-bit path, and
    // consuming them here too would double-report.
    wire [16:0]     noc_host_addr  [15:0];
    wire            noc_host_valid [15:0];

    //=========================================================================
    // PCIe/XDMA Signals
    //=========================================================================
    
    // PCIe to NoC (commands/config from host)
    wire [511:0]    pcie_to_noc_tdata;
    wire [3:0]      pcie_to_noc_tdest;
    wire            pcie_to_noc_tvalid;
    wire            pcie_to_noc_tready;
    wire            pcie_to_noc_tlast;
    
    // NoC to PCIe (local spikes only)
    wire [511:0]    noc_to_pcie_tdata;
    wire            noc_to_pcie_tvalid;
    wire            noc_to_pcie_tready;
    wire            noc_to_pcie_tlast;
    
    //=========================================================================
    // FireFly Integration Signals
    //=========================================================================
    
    // Spikes classified as remote (going to FireFly)
    inter_fpga_spike_t  firefly_tx_spike;
    wire                firefly_tx_valid;
    wire                firefly_tx_ready;
    
    // Spikes received from FireFly (going to cores)
    inter_fpga_spike_t  firefly_rx_spike;
    wire                firefly_rx_valid;
    wire                firefly_rx_ready;
    
    // Converted remote spikes (512-bit format for injection)
    wire [511:0]    remote_rx_tdata;
    wire [3:0]      remote_rx_tdest;
    wire            remote_rx_tvalid;
    wire            remote_rx_tready;
    
    // FireFly status
    wire [3:0]      firefly_channel_up;
    wire [3:0]      firefly_hard_err;
    wire [31:0]     firefly_spikes_routed;
    wire [31:0]     firefly_spikes_dropped;
    
    //=========================================================================
    // Clock Generation (clock_and_buffer block design)
    //=========================================================================
    
    clock_and_buffer clock_and_buffer_i (
        .refclk450_clk_p    (refclk450_p),
        .refclk450_clk_n    (refclk450_n),
        .clk_out1           (aclk),         // 225 MHz
        .clk_out2           (aclk_450),     // 450 MHz
        .clk_out3           (init_clk),     // 100 MHz
        .clk_out4           (hbm_ref_clk),  // HBM ref
        .locked             (aresetn)
    );
    
    //=========================================================================
    // PCIe DMA (XDMA IP)
    //=========================================================================
    
    xdma_0 xdma_i (
        // PCIe Interface
        .sys_clk_p              (pcie_clk_in_clk_p),
        .sys_clk_n              (pcie_clk_in_clk_n),
        .sys_rst_n              (sys_rst_n),
        .pci_exp_txp            (pcie_txp),
        .pci_exp_txn            (pcie_txn),
        .pci_exp_rxp            (pcie_rxp),
        .pci_exp_rxn            (pcie_rxn),
        
        // AXI-Stream C2H (Card to Host) - spikes going to host
        .m_axis_c2h_tdata       (noc_to_pcie_tdata),
        .m_axis_c2h_tlast       (noc_to_pcie_tlast),
        .m_axis_c2h_tvalid      (noc_to_pcie_tvalid),
        .m_axis_c2h_tready      (noc_to_pcie_tready),
        
        // AXI-Stream H2C (Host to Card) - commands from host
        .s_axis_h2c_tdata       (pcie_to_noc_tdata),
        .s_axis_h2c_tlast       (pcie_to_noc_tlast),
        .s_axis_h2c_tvalid      (pcie_to_noc_tvalid),
        .s_axis_h2c_tready      (pcie_to_noc_tready),
        
        // Clock output
        .axi_aclk               (),
        .axi_aresetn            ()
    );
    
    //=========================================================================
    // HBM Memory Controllers
    //=========================================================================
    
    // HBM Left Stack (channels 0-15)
    hbm_left hbm_left_i (
        .HBM_REF_CLK_0          (hbm_ref_clk),
        .AXI_00_ACLK            (aclk_450),
        .AXI_00_ARESET_N        (aresetn),
        // ... (32 AXI interfaces, connect hbm[0:15])
        .apb_complete_0         ()
    );
    
    // HBM Right Stack (channels 16-31) - channels 16-31 tied off
    hbm_right hbm_right_i (
        .HBM_REF_CLK_0          (hbm_ref_clk),
        .AXI_00_ACLK            (aclk_450),
        .AXI_00_ARESET_N        (aresetn),
        // ... (32 AXI interfaces, channels 16-31 tied off in wrapper)
        .apb_complete_0         ()
    );
    
    //=========================================================================
    // 16 Neural Network Cores
    //=========================================================================
    
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_cores
            
            core_wrapper #(
                .CORE_ID        (i),
                .FPGA_ID        (FPGA_ID)
            ) my_core (
                .aclk           (aclk),
                .aclk_450       (aclk_450),
                .aresetn        (aresetn),
                
                // HBM Interface
                .m_axi_hbm      (hbm[i]),
                
                // NoC TX (outgoing spikes)
                .m_axis_tdata   (core_tx_tdata[i]),
                .m_axis_tvalid  (core_tx_tvalid[i]),
                .m_axis_tready  (core_tx_tready[i]),
                .m_axis_tlast   (core_tx_tlast[i]),
                
                // Crossbar NoC: per-spike core-to-core path.  These ports
                // already exist on core_wrapper and single_core, wired into
                // the EEP -- they were simply never connected.
                .noc_spike_out_addr  (core_noc_out_addr[i]),
                .noc_spike_out_valid (core_noc_out_valid[i]),
                .noc_spike_out_ready (core_noc_out_ready[i]),
                .noc_relay_din       (core_noc_relay_din[i]),
                .noc_relay_wren      (core_noc_relay_wren[i]),
                .noc_relay_full      (core_noc_relay_full[i]),

                // Routing table programming from this core's CI
                .route_cfg_valid     (core_route_cfg_valid[i]),
                .route_cfg_addr      (core_route_cfg_addr[i]),
                .route_cfg_data      (core_route_cfg_data[i]),

                // NoC RX (incoming spikes/commands)
                .s_axis_tdata   (core_rx_tdata[i]),
                .s_axis_tdest   (core_rx_tdest[i]),
                .s_axis_tvalid  (core_rx_tvalid[i]),
                .s_axis_tready  (core_rx_tready[i]),
                .s_axis_tlast   (core_rx_tlast[i])
            );
            
        end
    endgenerate
    
    //=========================================================================
    // TIE-OFF UNUSED HBM CHANNELS (16-31)
    //=========================================================================
    
    generate
        for (i = 16; i < 32; i = i + 1) begin : gen_hbm_tieoff
            assign hbm[i].araddr  = 33'b0;
            assign hbm[i].arburst = 2'b01;
            assign hbm[i].arid    = 6'b0;
            assign hbm[i].arlen   = 4'b0;
            assign hbm[i].arsize  = 3'b101;
            assign hbm[i].arvalid = 1'b0;
            
            assign hbm[i].awaddr  = 33'b0;
            assign hbm[i].awburst = 2'b01;
            assign hbm[i].awid    = 6'b0;
            assign hbm[i].awlen   = 4'b0;
            assign hbm[i].awsize  = 3'b101;
            assign hbm[i].awvalid = 1'b0;
            
            assign hbm[i].wdata   = 256'b0;
            assign hbm[i].wlast   = 1'b0;
            assign hbm[i].wstrb   = 32'b0;
            assign hbm[i].wvalid  = 1'b0;
            
            assign hbm[i].rready  = 1'b1;
            assign hbm[i].bready  = 1'b1;
        end
    endgenerate
    
    //=========================================================================
    // L2 NoC Switch: 16 Cores → 1 Output (to spike classifier)
    //=========================================================================
    
    switch_16_1 switch_out (
        .aclk           (aclk),
        .aresetn        (aresetn),
        
        // 16 Slave interfaces (from cores)
        .s_axis_tdata   ({core_tx_tdata[15], core_tx_tdata[14], core_tx_tdata[13], core_tx_tdata[12],
                         core_tx_tdata[11], core_tx_tdata[10], core_tx_tdata[9],  core_tx_tdata[8],
                         core_tx_tdata[7],  core_tx_tdata[6],  core_tx_tdata[5],  core_tx_tdata[4],
                         core_tx_tdata[3],  core_tx_tdata[2],  core_tx_tdata[1],  core_tx_tdata[0]}),
        .s_axis_tvalid  ({core_tx_tvalid[15], core_tx_tvalid[14], core_tx_tvalid[13], core_tx_tvalid[12],
                         core_tx_tvalid[11], core_tx_tvalid[10], core_tx_tvalid[9],  core_tx_tvalid[8],
                         core_tx_tvalid[7],  core_tx_tvalid[6],  core_tx_tvalid[5],  core_tx_tvalid[4],
                         core_tx_tvalid[3],  core_tx_tvalid[2],  core_tx_tvalid[1],  core_tx_tvalid[0]}),
        .s_axis_tready  ({core_tx_tready[15], core_tx_tready[14], core_tx_tready[13], core_tx_tready[12],
                         core_tx_tready[11], core_tx_tready[10], core_tx_tready[9],  core_tx_tready[8],
                         core_tx_tready[7],  core_tx_tready[6],  core_tx_tready[5],  core_tx_tready[4],
                         core_tx_tready[3],  core_tx_tready[2],  core_tx_tready[1],  core_tx_tready[0]}),
        .s_axis_tlast   ({core_tx_tlast[15], core_tx_tlast[14], core_tx_tlast[13], core_tx_tlast[12],
                         core_tx_tlast[11], core_tx_tlast[10], core_tx_tlast[9],  core_tx_tlast[8],
                         core_tx_tlast[7],  core_tx_tlast[6],  core_tx_tlast[5],  core_tx_tlast[4],
                         core_tx_tlast[3],  core_tx_tlast[2],  core_tx_tlast[1],  core_tx_tlast[0]}),
        
        // Master interface (to spike classifier)
        .m_axis_tdata   (noc_out_tdata),
        .m_axis_tvalid  (noc_out_tvalid),
        .m_axis_tready  (noc_out_tready),
        .m_axis_tlast   (noc_out_tlast)
    );
    
    //=========================================================================
    // Crossbar NoC -- 4x4, four clusters of four cores
    //=========================================================================
    // Verified under xsim against the real sources: router 5/5, L1 bus 4/4,
    // L2 bus 5/5, and the integration layer elaborates.  Note the L2 bus
    // rewrites a forwarded packet's mask to 4'b1111, so a cross-cluster spike
    // broadcasts to all four cores in each destination cluster and the
    // receiving cores filter by neuron address.

    noc_integration #(
        .NUM_CORES (16)
    ) noc_i (
        .clk    (aclk),
        .resetn (aresetn),

        .core_spike_out_addr  (core_noc_out_addr),
        .core_spike_out_valid (core_noc_out_valid),
        .core_spike_out_ready (core_noc_out_ready),

        .core_relay_din  (core_noc_relay_din),
        .core_relay_wren (core_noc_relay_wren),
        .core_relay_full (core_noc_relay_full),

        .core_exec_run (core_exec_run_w),

        .host_spike_addr  (noc_host_addr),
        .host_spike_valid (noc_host_valid),
        .host_spike_ready ('1),

        .core_route_cfg_valid (core_route_cfg_valid),
        .core_route_cfg_addr  (core_route_cfg_addr),
        .core_route_cfg_data  (core_route_cfg_data)
    );

    //=========================================================================
    // Spike Classifier
    // Separates local spikes (→ PCIe) from remote spikes (→ FireFly)
    // Converts 512-bit packets to 64-bit inter_fpga_spike_t for remote
    //=========================================================================
    
    spike_classifier #(
        .LOCAL_FPGA_ID  (FPGA_ID)
    ) spike_classifier_i (
        .aclk               (aclk),
        .aresetn            (aresetn),
        
        // Input from switch_16_1
        .s_axis_tdata       (noc_out_tdata),
        .s_axis_tvalid      (noc_out_tvalid),
        .s_axis_tready      (noc_out_tready),
        
        // Local spikes → PCIe
        .m_pcie_tdata       (noc_to_pcie_tdata),
        .m_pcie_tvalid      (noc_to_pcie_tvalid),
        .m_pcie_tready      (noc_to_pcie_tready),
        
        // Remote spikes → FireFly (64-bit format)
        .m_firefly_spike    (firefly_tx_spike),
        .m_firefly_valid    (firefly_tx_valid),
        .m_firefly_ready    (firefly_tx_ready)
    );
    
    //=========================================================================
    // FireFly Subsystem
    // Aurora channels for inter-FPGA communication
    //=========================================================================
    
    firefly_subsystem_top #(
        .FPGA_ID        (FPGA_ID)
    ) firefly_i (
        .aclk               (aclk),
        .aresetn            (aresetn),
        .init_clk           (init_clk),
        
        // GT Reference Clocks
        .ff4_refclk_p       (ff4_refclk_p),
        .ff4_refclk_n       (ff4_refclk_n),
        .ff5_refclk_p       (ff5_refclk_p),
        .ff5_refclk_n       (ff5_refclk_n),
        .ff6_refclk_p       (ff6_refclk_p),
        .ff6_refclk_n       (ff6_refclk_n),
        .ff7_refclk_p       (ff7_refclk_p),
        .ff7_refclk_n       (ff7_refclk_n),
        
        // GT Serial Pins
        .ff4_txp            (ff4_txp),
        .ff4_txn            (ff4_txn),
        .ff4_rxp            (ff4_rxp),
        .ff4_rxn            (ff4_rxn),
        .ff5_txp            (ff5_txp),
        .ff5_txn            (ff5_txn),
        .ff5_rxp            (ff5_rxp),
        .ff5_rxn            (ff5_rxn),
        .ff6_txp            (ff6_txp),
        .ff6_txn            (ff6_txn),
        .ff6_rxp            (ff6_rxp),
        .ff6_rxn            (ff6_rxn),
        .ff7_txp            (ff7_txp),
        .ff7_txn            (ff7_txn),
        .ff7_rxp            (ff7_rxp),
        .ff7_rxn            (ff7_rxn),
        
        // NoC TX Interface (spikes going to other FPGAs)
        .noc_tx_spike       (firefly_tx_spike),
        .noc_tx_valid       (firefly_tx_valid),
        .noc_tx_ready       (firefly_tx_ready),
        
        // NoC RX Interface (spikes from other FPGAs)
        .noc_rx_spike       (firefly_rx_spike),
        .noc_rx_valid       (firefly_rx_valid),
        .noc_rx_ready       (firefly_rx_ready),
        
        // Status
        .channel_up         (firefly_channel_up),
        .hard_err           (firefly_hard_err),
        .spikes_routed      (firefly_spikes_routed),
        .spikes_dropped     (firefly_spikes_dropped)
    );
    
    //=========================================================================
    // Remote Spike Injector
    // Converts 64-bit FireFly spikes to 512-bit NoC format
    //=========================================================================
    
    remote_spike_injector #(
        .LOCAL_FPGA_ID  (FPGA_ID)
    ) remote_injector_i (
        .aclk               (aclk),
        .aresetn            (aresetn),
        
        // From FireFly (64-bit format)
        .firefly_spike      (firefly_rx_spike),
        .firefly_valid      (firefly_rx_valid),
        .firefly_ready      (firefly_rx_ready),
        
        // To NoC (512-bit format)
        .m_axis_tdata       (remote_rx_tdata),
        .m_axis_tdest       (remote_rx_tdest),
        .m_axis_tvalid      (remote_rx_tvalid),
        .m_axis_tready      (remote_rx_tready)
    );
    
    //=========================================================================
    // NoC Input Arbiter
    // Merges PCIe commands and remote spikes into single stream
    //=========================================================================
    
    // axis_arbiter_2 replaces noc_input_arbiter: same ports, but PCIe
    // no longer has strict priority, so remote spikes cannot be starved
    // into the wrong timestep.  Commands still win immediately.
    axis_arbiter_2 #(
        .DW(512), .DESTW(4), .BIAS_GRANTS(1)
    ) input_arbiter_i (
        .aclk               (aclk),
        .aresetn            (aresetn),
        
        // PCIe input (commands from host)
        .pcie_tdata         (pcie_to_noc_tdata),
        .pcie_tdest         (pcie_to_noc_tdest),
        .pcie_tvalid        (pcie_to_noc_tvalid),
        .pcie_tready        (pcie_to_noc_tready),
        
        // FireFly input (remote spikes)
        .firefly_tdata      (remote_rx_tdata),
        .firefly_tdest      (remote_rx_tdest),
        .firefly_tvalid     (remote_rx_tvalid),
        .firefly_tready     (remote_rx_tready),
        
        // Output to switch_1_16
        .m_axis_tdata       (noc_in_tdata),
        .m_axis_tdest       (noc_in_tdest),
        .m_axis_tvalid      (noc_in_tvalid),
        .m_axis_tready      (noc_in_tready)
    );
    
    //=========================================================================
    // L2 NoC Switch: 1 Input → 16 Cores
    //=========================================================================
    
    switch_1_16 switch_in (
        .aclk           (aclk),
        .aresetn        (aresetn),
        
        // Slave interface (from input arbiter)
        .s_axis_tdata   (noc_in_tdata),
        .s_axis_tdest   (noc_in_tdest),
        .s_axis_tvalid  (noc_in_tvalid),
        .s_axis_tready  (noc_in_tready),
        .s_axis_tlast   (1'b1),
        
        // 16 Master interfaces (to cores)
        .m_axis_tdata   ({core_rx_tdata[15], core_rx_tdata[14], core_rx_tdata[13], core_rx_tdata[12],
                         core_rx_tdata[11], core_rx_tdata[10], core_rx_tdata[9],  core_rx_tdata[8],
                         core_rx_tdata[7],  core_rx_tdata[6],  core_rx_tdata[5],  core_rx_tdata[4],
                         core_rx_tdata[3],  core_rx_tdata[2],  core_rx_tdata[1],  core_rx_tdata[0]}),
        .m_axis_tvalid  ({core_rx_tvalid[15], core_rx_tvalid[14], core_rx_tvalid[13], core_rx_tvalid[12],
                         core_rx_tvalid[11], core_rx_tvalid[10], core_rx_tvalid[9],  core_rx_tvalid[8],
                         core_rx_tvalid[7],  core_rx_tvalid[6],  core_rx_tvalid[5],  core_rx_tvalid[4],
                         core_rx_tvalid[3],  core_rx_tvalid[2],  core_rx_tvalid[1],  core_rx_tvalid[0]}),
        .m_axis_tready  ({core_rx_tready[15], core_rx_tready[14], core_rx_tready[13], core_rx_tready[12],
                         core_rx_tready[11], core_rx_tready[10], core_rx_tready[9],  core_rx_tready[8],
                         core_rx_tready[7],  core_rx_tready[6],  core_rx_tready[5],  core_rx_tready[4],
                         core_rx_tready[3],  core_rx_tready[2],  core_rx_tready[1],  core_rx_tready[0]})
    );
    
    //=========================================================================
    // Status LEDs
    //=========================================================================
    
    // LED[0]: System heartbeat
    // LED[1]: FireFly Port 7 channel up (all FPGAs have this)
    // LED[2]: Any FireFly error
    // LED[3]: Spikes being routed
    
    reg [26:0] heartbeat_cnt;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            heartbeat_cnt <= 27'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1;
    end
    
    assign led[0] = heartbeat_cnt[26];          // ~1.5 Hz blink
    assign led[1] = firefly_channel_up[3];      // Port 7 up
    assign led[2] = |firefly_hard_err;          // Any error
    assign led[3] = |firefly_spikes_routed[3:0]; // Activity indicator
    
    //=========================================================================
    // FireFly Module Presence (directly connected, active low)
    //=========================================================================
    
    assign ff4_modprs_n = 1'bz;  // Input with pull-up
    assign ff5_modprs_n = 1'bz;
    assign ff6_modprs_n = 1'bz;
    assign ff7_modprs_n = 1'bz;

endmodule
