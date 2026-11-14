`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: cores_with_noc.sv
// 
// MODIFIED FOR MULTI-CORE SUPPORT:
// - Added CORE_ID parameter to each core_wrapper instantiation
// - Each core gets unique ID (0-15) for spike packet tagging
//
// Architecture:
//   ┌─────────────────────────────────────────────────────────────────┐
//   │                         L2 Bus                                   │
//   │              (Inter-Cluster Multicast)                          │
//   └───────┬───────────┬───────────┬───────────┬────────────────────┘
//           │           │           │           │
//     ┌─────┴─────┐ ┌───┴───┐ ┌───┴───┐ ┌───┴───┐
//     │ Cluster 0 │ │   1   │ │   2   │ │   3   │
//     │  L1 Bus   │ │L1 Bus │ │L1 Bus │ │L1 Bus │
//     └─┬──┬──┬──┬┘ └───────┘ └───────┘ └───────┘
//       │  │  │  │
//      C0 C1 C2 C3  (Cores 0-3 in Cluster 0)
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module cores_with_noc #(
    parameter NUM_CORES = 16,
    parameter NUM_CLUSTERS = 4,
    parameter CORES_PER_CLUSTER = 4,
    parameter DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic resetn,
    
    // =========================================================================
    // Core Spike Outputs (from spk2ciFIFO of each core)
    // =========================================================================
    input  logic [18:0] core_spike_addr [NUM_CORES-1:0],
    input  logic [NUM_CORES-1:0] core_spike_valid,
    output logic [NUM_CORES-1:0] core_spike_ready,
    
    // =========================================================================
    // NoC Relay FIFO Interface (to external_events_processor of each core)
    // =========================================================================
    output logic [18:0] core_noc_relay_addr [NUM_CORES-1:0],
    output logic [NUM_CORES-1:0] core_noc_relay_valid,
    input  logic [NUM_CORES-1:0] core_noc_relay_full,
    
    // =========================================================================
    // Host Spike Outputs (spikes that go to PCIe instead of NoC)
    // =========================================================================
    output logic [18:0] host_spike_addr [NUM_CORES-1:0],
    output logic [NUM_CORES-1:0] host_spike_valid,
    input  logic [NUM_CORES-1:0] host_spike_ready,
    
    // =========================================================================
    // Routing Table Configuration (from Command Interpreter)
    // =========================================================================
    input  logic        route_cfg_valid [NUM_CORES-1:0],   // v13 N4: each router takes its own core's writes
    input  logic [9:0]  route_cfg_addr  [NUM_CORES-1:0],
    input  logic [5:0]  route_cfg_data  [NUM_CORES-1:0],
    
    // =========================================================================
    // Timestep Synchronization
    // =========================================================================
    input  logic [NUM_CORES-1:0] core_exec_run,
    
    // =========================================================================
    // Debug/Status
    // =========================================================================
    output logic [NUM_CLUSTERS-1:0] l1_bus_busy,
    output logic                    l2_bus_busy,
    output logic [NUM_CORES-1:0]    router_overflow,
    output logic [NUM_CORES-1:0]    injector_overflow,
    output logic                    noc_quiet,         // v13 B: no spike anywhere in the NoC (see below)
    input  logic [NUM_CORES-1:0]    core_noc_part,     // full B: cores taking part in the step barrier
    input  logic [NUM_CORES-1:0]    core_noc_arrive_par, // full B: parity of each core's last barrier arrival
    output logic                    noc_go0,           // full B: every participating core at the parity-0 barrier, NoC quiet
    output logic                    noc_go1            // full B: the same for parity 1
);

    // =========================================================================
    // Internal Signals - Per Core
    // =========================================================================
    
    logic [18:0] router_spike_addr [NUM_CORES-1:0];
    logic [NUM_CORES-1:0] router_spike_valid;
    logic [NUM_CORES-1:0] router_spike_ready;
    logic [3:0]  router_dest_mask [NUM_CORES-1:0];
    logic [1:0]  router_level [NUM_CORES-1:0];
    
    logic [18:0] injector_spike_addr [NUM_CORES-1:0];
    logic [NUM_CORES-1:0] injector_spike_valid;
    logic [NUM_CORES-1:0] injector_spike_ready;
    
    logic [NUM_CORES-1:0] route_cfg_valid_per_core;
    
    // =========================================================================
    // Internal Signals - Per Cluster (L1)
    // =========================================================================
    
    logic [18:0] l1_spike_addr [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];
    logic [CORES_PER_CLUSTER-1:0] l1_spike_valid [NUM_CLUSTERS-1:0];
    logic [CORES_PER_CLUSTER-1:0] l1_spike_ready [NUM_CLUSTERS-1:0];
    logic [3:0]  l1_spike_mask [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];
    logic [1:0]  l1_spike_level [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];
    
    logic [18:0] l1_rx_addr [NUM_CLUSTERS-1:0][CORES_PER_CLUSTER-1:0];
    logic [CORES_PER_CLUSTER-1:0] l1_rx_valid [NUM_CLUSTERS-1:0];
    logic [CORES_PER_CLUSTER-1:0] l1_rx_ready [NUM_CLUSTERS-1:0];
    
    logic [DATA_WIDTH-1:0] l1_to_l2_data [NUM_CLUSTERS-1:0];
    logic [NUM_CLUSTERS-1:0] l1_to_l2_valid;
    logic [NUM_CLUSTERS-1:0] l1_to_l2_ready;
    
    logic [DATA_WIDTH-1:0] l2_to_l1_data [NUM_CLUSTERS-1:0];
    logic [NUM_CLUSTERS-1:0] l2_to_l1_valid;
    logic [NUM_CLUSTERS-1:0] l2_to_l1_ready;
    
    // =========================================================================
    // Generate Spike Routers (one per core)
    // MODIFIED: Each router now has unique CORE_ID
    // =========================================================================
    
    genvar c;
    generate
        for (c = 0; c < NUM_CORES; c++) begin : gen_routers
            
            assign route_cfg_valid_per_core[c] = route_cfg_valid[c];   // v13 N4
            
            noc_spike_router #(
                .CORE_ID(c)    // Each core gets unique ID 0-15
            ) spike_router (
                .clk(clk),
                .resetn(resetn),
                
                .spike_addr_in(core_spike_addr[c]),
                .spike_valid_in(core_spike_valid[c]),
                .spike_ready_in(core_spike_ready[c]),
                
                .spike_addr_out(router_spike_addr[c]),
                .spike_valid_out(router_spike_valid[c]),
                .spike_ready_out(router_spike_ready[c]),
                .spike_dest_mask(router_dest_mask[c]),
                .spike_level(router_level[c]),
                
                .spike_addr_host(host_spike_addr[c]),
                .spike_valid_host(host_spike_valid[c]),
                .spike_ready_host(host_spike_ready[c]),
                
                .route_cfg_valid(route_cfg_valid_per_core[c]),
                .route_cfg_addr(route_cfg_addr[c]),   // v13 N4
                .route_cfg_data(route_cfg_data[c])   // v13 N4
            );
        end
    endgenerate
    
    // =========================================================================
    // Generate Spike Injectors (one per core)
    // MODIFIED: Each injector now has unique CORE_ID
    // =========================================================================
    
    generate
        for (c = 0; c < NUM_CORES; c++) begin : gen_injectors
            
            noc_spike_injector #(
                .CORE_ID(c)    // Each core gets unique ID 0-15
            ) spike_injector (
                .clk(clk),
                .resetn(resetn),
                
                .noc_spike_addr(injector_spike_addr[c]),
                .noc_spike_valid(injector_spike_valid[c]),
                .noc_spike_ready(injector_spike_ready[c]),
                
                .noc_relay_addr(core_noc_relay_addr[c]),
                .noc_relay_valid(core_noc_relay_valid[c]),
                .noc_relay_full(core_noc_relay_full[c]),
                
                .inject_count(),
                .overflow_error(injector_overflow[c]),
                
                .exec_run(core_exec_run[c])
            );
        end
    endgenerate
    
    // =========================================================================
    // Map core indices to cluster/local indices
    // =========================================================================
    
    generate
        for (c = 0; c < NUM_CORES; c++) begin : gen_router_to_l1
            localparam int CLUSTER = c / CORES_PER_CLUSTER;
            localparam int LOCAL = c % CORES_PER_CLUSTER;
            
            assign l1_spike_addr[CLUSTER][LOCAL] = router_spike_addr[c];
            assign l1_spike_valid[CLUSTER][LOCAL] = router_spike_valid[c];
            assign router_spike_ready[c] = l1_spike_ready[CLUSTER][LOCAL];
            assign l1_spike_mask[CLUSTER][LOCAL] = router_dest_mask[c];
            assign l1_spike_level[CLUSTER][LOCAL] = router_level[c];
        end
    endgenerate
    
    generate
        for (c = 0; c < NUM_CORES; c++) begin : gen_l1_to_injector
            localparam int CLUSTER = c / CORES_PER_CLUSTER;
            localparam int LOCAL = c % CORES_PER_CLUSTER;
            
            assign injector_spike_addr[c] = l1_rx_addr[CLUSTER][LOCAL];
            assign injector_spike_valid[c] = l1_rx_valid[CLUSTER][LOCAL];
            assign l1_rx_ready[CLUSTER][LOCAL] = injector_spike_ready[c];
        end
    endgenerate
    
    // =========================================================================
    // Generate L1 Buses (one per cluster)
    // =========================================================================
    
    genvar cl;
    generate
        for (cl = 0; cl < NUM_CLUSTERS; cl++) begin : gen_l1_buses
            
            noc_l1_bus #(
                .CLUSTER_ID(cl),
                .NUM_CORES(CORES_PER_CLUSTER),
                .DATA_WIDTH(DATA_WIDTH)
            ) l1_bus (
                .clk(clk),
                .resetn(resetn),
                
                .spike_addr_in(l1_spike_addr[cl]),
                .spike_valid_in(l1_spike_valid[cl]),
                .spike_ready_in(l1_spike_ready[cl]),
                .spike_dest_mask(l1_spike_mask[cl]),
                .spike_level(l1_spike_level[cl]),
                
                .spike_addr_out(l1_rx_addr[cl]),
                .spike_valid_out(l1_rx_valid[cl]),
                .spike_ready_out(l1_rx_ready[cl]),
                
                .l2_tx_data(l1_to_l2_data[cl]),
                .l2_tx_valid(l1_to_l2_valid[cl]),
                .l2_tx_ready(l1_to_l2_ready[cl]),
                .l2_rx_data(l2_to_l1_data[cl]),
                .l2_rx_valid(l2_to_l1_valid[cl]),
                .l2_rx_ready(l2_to_l1_ready[cl]),
                
                .bus_busy(l1_bus_busy[cl])
            );
        end
    endgenerate
    
    // =========================================================================
    // L2 Bus (inter-cluster)
    // =========================================================================
    
    noc_l2_bus #(
        .NUM_CLUSTERS(NUM_CLUSTERS),
        .DATA_WIDTH(DATA_WIDTH)
    ) l2_bus (
        .clk(clk),
        .resetn(resetn),
        
        .l1_tx_data(l1_to_l2_data),
        .l1_tx_valid(l1_to_l2_valid),
        .l1_tx_ready(l1_to_l2_ready),
        
        .l1_rx_data(l2_to_l1_data),
        .l1_rx_valid(l2_to_l1_valid),
        .l1_rx_ready(l2_to_l1_ready),
        
        .bus_busy(l2_bus_busy)
    );
    
    // =========================================================================
    // v13 B: noc_quiet -- every place a spike can wait between a core's NoC output and a destination's relay FIFO
    // is empty: the cores' NoC output FIFOs (core_spike_valid = !empty), the routers' NoC output stages, the L1 buses'
    // registered deliveries to cores (injectors are pass-through into the relay FIFOs), the L2 bus's held deliveries
    // to clusters, and the L2 crossbar and its senders (l2_bus_busy).  Each hand-off moves a spike between these on
    // one clock edge, so no cycle hides one; 4 consecutive idle cycles are required anyway.  The routers' host
    // path (local spikes, ready tied 1) carries no relay and is not included.
    // =========================================================================
    wire noc_busy = (|core_spike_valid) | (|router_spike_valid) | (|injector_spike_valid) | (|l2_to_l1_valid) | l2_bus_busy;
    logic [2:0] noc_quiet_cnt;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)                   noc_quiet_cnt <= 3'd0;
        else if (noc_busy)             noc_quiet_cnt <= 3'd0;
        else if (noc_quiet_cnt != 3'd4) noc_quiet_cnt <= noc_quiet_cnt + 3'd1;
    end
    assign noc_quiet = (noc_quiet_cnt == 3'd4) && !noc_busy;
    // full B: the step barrier -- every participating core has arrived at the barrier of one parity and the NoC is quiet
    wire all_at0 = &(~core_noc_part | ~core_noc_arrive_par);
    wire all_at1 = &(~core_noc_part |  core_noc_arrive_par);
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin noc_go0 <= 1'b0; noc_go1 <= 1'b0; end
        else begin noc_go0 <= noc_quiet && all_at0 && (|core_noc_part); noc_go1 <= noc_quiet && all_at1 && (|core_noc_part); end
    end

    // =========================================================================
    // Router Overflow Status
    // =========================================================================
    
    generate
        for (c = 0; c < NUM_CORES; c++) begin : gen_overflow
            assign router_overflow[c] = 1'b0;
        end
    endgenerate

endmodule