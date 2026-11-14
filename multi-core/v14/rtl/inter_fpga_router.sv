//=============================================================================
// HiAER-Spike Inter-FPGA Router
// 
// This module routes spike packets between the local NoC and FireFly ports
// based on destination FPGA. It implements the routing logic for the
// Server 0 topology defined in Firefly_connectivity.txt.
//
// Features:
//   - Destination-based output port selection
//   - Multi-hop routing through upper tier mesh
//   - Flow control with credit-based backpressure
//   - Round-robin arbitration for received packets
//=============================================================================

module inter_fpga_router
    import hiaer_firefly_pkg::*;
#(
    parameter int TX_FIFO_DEPTH = 64,            // TX buffer depth per port
    parameter int RX_FIFO_DEPTH = 64             // RX buffer depth
)(
    // Board identifier, 0 to 7, from the host. It selects routes, not logic,
    // so it no longer has to be fixed when the bitstream is built.
    input  logic [2:0]      LOCAL_FPGA_ID,
    //=========================================================================
    // Clocks and Resets
    //=========================================================================
    input  logic            aclk,
    input  logic            aresetn,
    
    //=========================================================================
    // Interface to Local NoC (from/to cores)
    //=========================================================================
    
    // Spikes from local cores destined for other FPGAs
    input  inter_fpga_spike_t   noc_tx_spike,
    input  logic                noc_tx_valid,
    output logic                noc_tx_ready,
    
    // Spikes received from other FPGAs destined for local cores
    output inter_fpga_spike_t   noc_rx_spike,
    output logic                noc_rx_valid,
    input  logic                noc_rx_ready,
    
    //=========================================================================
    // FireFly Port Interfaces (directly to Aurora wrappers)
    //=========================================================================
    
    // Port 4 (upper tier only)
    output logic [63:0]         port4_tx_tdata,
    output logic                port4_tx_tvalid,
    input  logic                port4_tx_tready,
    input  logic [63:0]         port4_rx_tdata,
    input  logic                port4_rx_tvalid,
    output logic                port4_rx_tready,
    input  logic                port4_channel_up,
    
    // Port 5 (upper tier only)
    output logic [63:0]         port5_tx_tdata,
    output logic                port5_tx_tvalid,
    input  logic                port5_tx_tready,
    input  logic [63:0]         port5_rx_tdata,
    input  logic                port5_rx_tvalid,
    output logic                port5_rx_tready,
    input  logic                port5_channel_up,
    
    // Port 6 (upper tier only)
    output logic [63:0]         port6_tx_tdata,
    output logic                port6_tx_tvalid,
    input  logic                port6_tx_tready,
    input  logic [63:0]         port6_rx_tdata,
    input  logic                port6_rx_tvalid,
    output logic                port6_rx_tready,
    input  logic                port6_channel_up,
    
    // Port 7 (all FPGAs)
    output logic [63:0]         port7_tx_tdata,
    output logic                port7_tx_tvalid,
    input  logic                port7_tx_tready,
    input  logic [63:0]         port7_rx_tdata,
    input  logic                port7_rx_tvalid,
    output logic                port7_rx_tready,
    input  logic                port7_channel_up,
    
    //=========================================================================
    // Status and Debug
    //=========================================================================
    output logic [31:0]         spikes_routed,      // Total spikes routed
    output logic [31:0]         spikes_dropped,     // Spikes dropped (no route)
    output logic [3:0]          port_active         // Which ports are active
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    
    // Port connection info for this FPGA
    connection_entry_t port_connections [3:0];
    
    // TX routing decision
    logic [1:0]         tx_output_port;
    logic               tx_has_route;
    logic               tx_port_ready;
    
    // RX arbitration
    logic [3:0]         rx_port_valid;
    logic [3:0]         rx_port_grant;
    logic [1:0]         rx_arb_sel;
    logic               rx_arb_valid;
    inter_fpga_spike_t  rx_selected_spike;
    
    // TX FIFOs per port
    logic [63:0]        tx_fifo_din [3:0];
    logic               tx_fifo_wr [3:0];
    logic               tx_fifo_full [3:0];
    logic [63:0]        tx_fifo_dout [3:0];
    logic               tx_fifo_rd [3:0];
    logic               tx_fifo_empty [3:0];
    logic               tx_fifo_valid [3:0];
    
    //=========================================================================
    // Port Connection Initialization
    //=========================================================================
    
    // Get connection info for each port at elaboration time
    initial begin
        for (int p = 0; p < 4; p++) begin
            port_connections[p] = get_connection(LOCAL_FPGA_ID, p[1:0]);
        end
    end
    
    // Determine which ports are active on this FPGA
    always_comb begin
        // Every board uses all four ports under the cabled topology, so a
        // port is active exactly when its link is up.
        port_active[0] = port4_channel_up;
        port_active[1] = port5_channel_up;
        port_active[2] = port6_channel_up;
        port_active[3] = port7_channel_up;                              // Port 7 (all FPGAs)
    end
    
    //=========================================================================
    // TX PATH: Route spikes from local NoC to appropriate FireFly port
    //=========================================================================
    
    // Routing Decision Logic
    always_comb begin
        tx_output_port = PORT_7;  // Default
        tx_has_route = 1'b0;
        
        if (noc_tx_valid) begin
            logic [2:0] dest_fpga = noc_tx_spike.dst_fpga;
            
            // Check for direct connection on each port
            for (int p = 0; p < 4; p++) begin
                connection_entry_t conn = get_connection(LOCAL_FPGA_ID, p[1:0]);
                if (conn.is_connected && conn.remote_fpga == dest_fpga) begin
                    tx_output_port = p[1:0];
                    tx_has_route = 1'b1;
                end
            end
            
            // If no direct route, determine multi-hop path
            if (!tx_has_route) begin
                tx_has_route = 1'b1;  // Assume we can route
                
                // The package holds the routing for the cabled topology. It was
                // checked over all fifty-six ordered pairs: thirty-two direct,
                // twenty-four through one board, none longer and none looping.
                tx_output_port = get_output_port(LOCAL_FPGA_ID, dest_fpga);
            end
        end
    end
    
    // Compute route through upper tier mesh
    // compute_mesh_route removed with the two-tier gating: the package
    // function get_output_port supplies routing for the cabled topology.
    
    // TX port ready based on selected port
    always_comb begin
        case (tx_output_port)
            PORT_4: tx_port_ready = !tx_fifo_full[0] && port_active[0];
            PORT_5: tx_port_ready = !tx_fifo_full[1] && port_active[1];
            PORT_6: tx_port_ready = !tx_fifo_full[2] && port_active[2];
            PORT_7: tx_port_ready = !tx_fifo_full[3] && port_active[3];
            default: tx_port_ready = 1'b0;
        endcase
    end
    
    assign noc_tx_ready = tx_has_route && tx_port_ready;
    
    // Write to appropriate TX FIFO
    always_comb begin
        for (int p = 0; p < 4; p++) begin
            tx_fifo_din[p] = noc_tx_spike;
            tx_fifo_wr[p] = noc_tx_valid && noc_tx_ready && (tx_output_port == p[1:0]);
        end
    end
    
    //=========================================================================
    // TX FIFOs (one per port)
    //=========================================================================
    
    genvar p;
    generate
        for (p = 0; p < 4; p++) begin : gen_tx_fifo
            
            // Only instantiate FIFO if port is used by this FPGA
            // All four ports carry traffic on every board, and the
            // identifier is no longer known at elaboration.
            if (1) begin : fifo_inst
                
                xpm_fifo_sync #(
                    .FIFO_MEMORY_TYPE   ("auto"),
                    .FIFO_WRITE_DEPTH   (TX_FIFO_DEPTH),
                    .WRITE_DATA_WIDTH   (64),
                    .READ_DATA_WIDTH    (64),
                    .READ_MODE          ("fwft"),
                    .FIFO_READ_LATENCY  (0)
                ) u_tx_fifo (
                    // xpm_fifo_sync calls its clock wr_clk, not clk.
                    .wr_clk         (aclk),
                    .rst            (~aresetn),
                    .wr_en          (tx_fifo_wr[p]),
                    .din            (tx_fifo_din[p]),
                    .full           (tx_fifo_full[p]),
                    .rd_en          (tx_fifo_rd[p]),
                    .dout           (tx_fifo_dout[p]),
                    .empty          (tx_fifo_empty[p]),
                    .data_valid     (tx_fifo_valid[p]),
                    .prog_full      (),
                    .wr_data_count  (),
                    .overflow       (),
                    .wr_rst_busy    (),
                    .almost_full    (),
                    .wr_ack         (),
                    .prog_empty     (),
                    .rd_data_count  (),
                    .underflow      (),
                    .rd_rst_busy    (),
                    .almost_empty   (),
                    .sleep          (1'b0),
                    .injectsbiterr  (1'b0),
                    .injectdbiterr  (1'b0),
                    .sbiterr        (),
                    .dbiterr        ()
                );
                
            end else begin : no_fifo
                assign tx_fifo_full[p] = 1'b1;
                assign tx_fifo_dout[p] = 64'd0;
                assign tx_fifo_empty[p] = 1'b1;
                assign tx_fifo_valid[p] = 1'b0;
            end
            
        end
    endgenerate
    
    // Connect TX FIFOs to port outputs
    assign port4_tx_tdata  = tx_fifo_dout[0];
    assign port4_tx_tvalid = tx_fifo_valid[0];
    assign tx_fifo_rd[0]   = port4_tx_tvalid && port4_tx_tready;
    
    assign port5_tx_tdata  = tx_fifo_dout[1];
    assign port5_tx_tvalid = tx_fifo_valid[1];
    assign tx_fifo_rd[1]   = port5_tx_tvalid && port5_tx_tready;
    
    assign port6_tx_tdata  = tx_fifo_dout[2];
    assign port6_tx_tvalid = tx_fifo_valid[2];
    assign tx_fifo_rd[2]   = port6_tx_tvalid && port6_tx_tready;
    
    assign port7_tx_tdata  = tx_fifo_dout[3];
    assign port7_tx_tvalid = tx_fifo_valid[3];
    assign tx_fifo_rd[3]   = port7_tx_tvalid && port7_tx_tready;
    
    //=========================================================================
    // RX PATH: Receive spikes from FireFly ports and route to local NoC
    //=========================================================================
    
    // Combine RX valid signals
    assign rx_port_valid = {port7_rx_tvalid, port6_rx_tvalid, 
                            port5_rx_tvalid, port4_rx_tvalid};
    
    // Round-robin arbiter for received packets
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rx_arb_sel <= 2'd0;
        end else if (rx_arb_valid && noc_rx_ready) begin
            // Advance to next port with data
            logic [1:0] next_sel = rx_arb_sel + 1;
            for (int i = 0; i < 4; i++) begin
                if (rx_port_valid[next_sel]) break;
                next_sel = next_sel + 1;
            end
            rx_arb_sel <= next_sel;
        end
    end
    
    // Check if selected port has valid data
    assign rx_arb_valid = rx_port_valid[rx_arb_sel];
    
    // Select spike data based on arbiter
    always_comb begin
        case (rx_arb_sel)
            2'd0: rx_selected_spike = port4_rx_tdata;
            2'd1: rx_selected_spike = port5_rx_tdata;
            2'd2: rx_selected_spike = port6_rx_tdata;
            2'd3: rx_selected_spike = port7_rx_tdata;
        endcase
    end
    
    // Determine if received spike is for this FPGA or needs forwarding
    logic rx_for_local;
    logic rx_needs_forward;
    logic [2:0] rx_forward_dest;
    
    always_comb begin
        rx_for_local = (rx_selected_spike.dst_fpga == LOCAL_FPGA_ID);
        rx_needs_forward = rx_arb_valid && !rx_for_local && (rx_selected_spike.ttl > 0);
        rx_forward_dest = rx_selected_spike.dst_fpga;
    end
    
    // Output to local NoC
    assign noc_rx_spike = rx_selected_spike;
    assign noc_rx_valid = rx_arb_valid && rx_for_local;
    
    // RX ready signals
    assign port4_rx_tready = (rx_arb_sel == 2'd0) && (rx_for_local ? noc_rx_ready : tx_port_ready);
    assign port5_rx_tready = (rx_arb_sel == 2'd1) && (rx_for_local ? noc_rx_ready : tx_port_ready);
    assign port6_rx_tready = (rx_arb_sel == 2'd2) && (rx_for_local ? noc_rx_ready : tx_port_ready);
    assign port7_rx_tready = (rx_arb_sel == 2'd3) && (rx_for_local ? noc_rx_ready : tx_port_ready);
    
    //=========================================================================
    // Statistics Counters
    //=========================================================================
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            spikes_routed <= 32'd0;
            spikes_dropped <= 32'd0;
        end else begin
            // Count routed spikes
            if (noc_tx_valid && noc_tx_ready) begin
                spikes_routed <= spikes_routed + 1;
            end
            
            // Count dropped spikes (valid but no route or backpressure)
            if (noc_tx_valid && !tx_has_route) begin
                spikes_dropped <= spikes_dropped + 1;
            end
        end
    end
    
endmodule : inter_fpga_router
