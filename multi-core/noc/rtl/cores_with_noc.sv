`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: cores_with_noc.v (CORRECTED)
//
// Top-level NoC wrapper for 16 cores organized as 4 clusters × 4 cores.
//
// Changes from original:
//   - Removed NUM_CORES/NUM_CLUSTERS parameter overrides on bus instantiations
//     (values come from noc_pkg)
//   - Added spike_secondary_mask wiring for per-core L2 routing
//   - Fixed all port connections to match corrected L1/L2 bus module ports
//   - Added route_cfg passthrough from top-level to per-core routers
//   - Properly declared all intermediate signal arrays
//
// Architecture:
//   16 cores → 16 routers → 4 L1 buses → 1 L2 bus
//   16 injectors ← 4 L1 buses ← 1 L2 bus
//////////////////////////////////////////////////////////////////////////////////

import noc_pkg::*;

module cores_with_noc (
    input  wire clk,
    input  wire resetn,

    // =========================================================================
    // Per-Core Spike Input (from CDC FIFOs, aclk domain, 16 cores)
    // =========================================================================
    input  wire [16:0] core_spike_addr  [0:NUM_CORES-1],
    input  wire [NUM_CORES-1:0]        core_spike_valid,
    output wire [NUM_CORES-1:0]        core_spike_ready,

    // =========================================================================
    // Per-Core NoC Relay Output (to EEP noc_relay interface)
    // =========================================================================
    output wire [16:0] core_noc_relay_addr  [0:NUM_CORES-1],
    output wire [NUM_CORES-1:0]            core_noc_relay_valid,
    input  wire [NUM_CORES-1:0]            core_noc_relay_full,

    // =========================================================================
    // Per-Core Host Spike Output (for LOCAL spikes - dual reporting)
    // In dual-reporting mode, these are left unconnected at top level
    // because the CI already reports all spikes to host via spk2ciFIFO.
    // =========================================================================
    output wire [16:0] host_spike_addr  [0:NUM_CORES-1],
    output wire [NUM_CORES-1:0]        host_spike_valid,
    input  wire [NUM_CORES-1:0]        host_spike_ready,

    // =========================================================================
    // Routing Table Configuration (from CI opcode 0x09)
    // =========================================================================
    input  wire [NUM_CORES-1:0]         route_cfg_valid,
    input  wire [7:0]                   route_cfg_addr  [0:NUM_CORES-1],
    input  wire [ROUTE_ENTRY_WIDTH-1:0] route_cfg_data  [0:NUM_CORES-1],

    // =========================================================================
    // Timestep sync
    // =========================================================================
    input  wire [NUM_CORES-1:0] core_exec_run,

    // =========================================================================
    // Status / Debug
    // =========================================================================
    output wire [3:0] l1_bus_busy,
    output wire       l2_bus_busy,
    output wire [NUM_CORES-1:0] injector_overflow
);

    // =========================================================================
    // Internal Signal Declarations
    // =========================================================================

    // Router → L1 bus (per core)
    wire [16:0] router_to_l1_addr    [0:NUM_CORES-1];
    wire [NUM_CORES-1:0]            router_to_l1_valid;
    wire [NUM_CORES-1:0]            router_to_l1_ready;
    wire [3:0]  router_dest_mask    [0:NUM_CORES-1];
    wire [3:0]  router_secondary    [0:NUM_CORES-1];
    wire [1:0]  router_level        [0:NUM_CORES-1];

    // L1 bus → Injector (per core)
    wire [16:0] l1_to_inj_addr      [0:NUM_CORES-1];
    wire [NUM_CORES-1:0]            l1_to_inj_valid;
    wire [NUM_CORES-1:0]            l1_to_inj_ready;

    // L1 ↔ L2 interfaces (per cluster)
    wire [NOC_DATA_WIDTH-1:0] l1_to_l2_data  [0:NUM_CLUSTERS-1];
    wire [NUM_CLUSTERS-1:0]                   l1_to_l2_valid;
    wire [NUM_CLUSTERS-1:0]                   l1_to_l2_ready;

    wire [NOC_DATA_WIDTH-1:0] l2_to_l1_data  [0:NUM_CLUSTERS-1];
    wire [NUM_CLUSTERS-1:0]                   l2_to_l1_valid;
    wire [NUM_CLUSTERS-1:0]                   l2_to_l1_ready;

    // Injector statistics
    wire [15:0] inject_count [0:NUM_CORES-1];

    // =========================================================================
    // Per-Cluster L1 Signals (repack from flat 16-core arrays to 4×4)
    // =========================================================================
    // L1 bus inputs: 4 cores per cluster
    wire [16:0] cl_spike_addr   [0:NUM_CLUSTERS-1][0:CORES_PER_CLUSTER-1];
    wire [3:0]  cl_spike_valid  [0:NUM_CLUSTERS-1];
    wire [3:0]  cl_spike_ready  [0:NUM_CLUSTERS-1];
    wire [3:0]  cl_dest_mask    [0:NUM_CLUSTERS-1][0:CORES_PER_CLUSTER-1];
    wire [3:0]  cl_secondary    [0:NUM_CLUSTERS-1][0:CORES_PER_CLUSTER-1];
    wire [1:0]  cl_level        [0:NUM_CLUSTERS-1][0:CORES_PER_CLUSTER-1];

    // L1 bus outputs: 4 cores per cluster
    wire [16:0] cl_rx_addr      [0:NUM_CLUSTERS-1][0:CORES_PER_CLUSTER-1];
    wire [3:0]  cl_rx_valid     [0:NUM_CLUSTERS-1];
    wire [3:0]  cl_rx_ready     [0:NUM_CLUSTERS-1];

    // =========================================================================
    // Map flat 16-core signals to clustered 4×4 signals
    // =========================================================================
    genvar c;
    generate
        for (c = 0; c < NUM_CORES; c = c + 1) begin : gen_map
            localparam CLUSTER = c / CORES_PER_CLUSTER;
            localparam LOCAL   = c % CORES_PER_CLUSTER;

            // Router → L1 bus mapping
            assign cl_spike_addr[CLUSTER][LOCAL]  = router_to_l1_addr[c];
            assign cl_spike_valid[CLUSTER][LOCAL]  = router_to_l1_valid[c];
            assign router_to_l1_ready[c]           = cl_spike_ready[CLUSTER][LOCAL];
            assign cl_dest_mask[CLUSTER][LOCAL]    = router_dest_mask[c];
            assign cl_secondary[CLUSTER][LOCAL]    = router_secondary[c];
            assign cl_level[CLUSTER][LOCAL]        = router_level[c];

            // L1 bus → Injector mapping
            assign l1_to_inj_addr[c]  = cl_rx_addr[CLUSTER][LOCAL];
            assign l1_to_inj_valid[c] = cl_rx_valid[CLUSTER][LOCAL];
            assign cl_rx_ready[CLUSTER][LOCAL] = l1_to_inj_ready[c];
        end
    endgenerate

    // =========================================================================
    // Instantiate 16 Routers (one per core)
    // =========================================================================
    generate
        for (c = 0; c < NUM_CORES; c = c + 1) begin : gen_router
            noc_spike_router #(
                .CORE_ID(c)
            ) router (
                .clk                 (clk),
                .resetn              (resetn),

                // From CDC FIFO
                .spike_addr_in       (core_spike_addr[c]),
                .spike_valid_in      (core_spike_valid[c]),
                .spike_ready_in      (core_spike_ready[c]),

                // To L1 bus
                .spike_addr_out      (router_to_l1_addr[c]),
                .spike_valid_out     (router_to_l1_valid[c]),
                .spike_ready_out     (router_to_l1_ready[c]),
                .spike_dest_mask     (router_dest_mask[c]),
                .spike_secondary_mask(router_secondary[c]),
                .spike_level         (router_level[c]),

                // To host (dual reporting - tied ready at top level)
                .spike_addr_host     (host_spike_addr[c]),
                .spike_valid_host    (host_spike_valid[c]),
                .spike_ready_host    (host_spike_ready[c]),

                // Routing table config
                .route_cfg_valid     (route_cfg_valid[c]),
                .route_cfg_addr      (route_cfg_addr[c]),
                .route_cfg_data      (route_cfg_data[c])
            );
        end
    endgenerate

    // =========================================================================
    // Instantiate 16 Injectors (one per core)
    // =========================================================================
    generate
        for (c = 0; c < NUM_CORES; c = c + 1) begin : gen_injector
            noc_spike_injector #(
                .CORE_ID(c)
            ) injector (
                .clk              (clk),
                .resetn           (resetn),

                // From L1 bus
                .noc_spike_addr   (l1_to_inj_addr[c]),
                .noc_spike_valid  (l1_to_inj_valid[c]),
                .noc_spike_ready  (l1_to_inj_ready[c]),

                // To EEP relay FIFO
                .noc_relay_addr   (core_noc_relay_addr[c]),
                .noc_relay_valid  (core_noc_relay_valid[c]),
                .noc_relay_full   (core_noc_relay_full[c]),

                // Status
                .inject_count     (inject_count[c]),
                .overflow_error   (injector_overflow[c]),

                // Timestep sync
                .exec_run         (core_exec_run[c])
            );
        end
    endgenerate

    // =========================================================================
    // Instantiate 4 L1 Buses (one per cluster)
    // =========================================================================
    genvar cl;
    generate
        for (cl = 0; cl < NUM_CLUSTERS; cl = cl + 1) begin : gen_l1
            noc_l1_bus #(
                .CLUSTER_ID(cl)
            ) l1_bus (
                .clk              (clk),
                .resetn           (resetn),

                // From routers (4 cores in this cluster)
                .spike_addr_in    (cl_spike_addr[cl]),
                .spike_valid_in   (cl_spike_valid[cl]),
                .spike_ready_in   (cl_spike_ready[cl]),
                .spike_dest_mask  (cl_dest_mask[cl]),
                .spike_secondary  (cl_secondary[cl]),
                .spike_level      (cl_level[cl]),

                // To injectors (4 cores in this cluster)
                .spike_addr_out   (cl_rx_addr[cl]),
                .spike_valid_out  (cl_rx_valid[cl]),
                .spike_ready_out  (cl_rx_ready[cl]),

                // L2 TX
                .l2_tx_data       (l1_to_l2_data[cl]),
                .l2_tx_valid      (l1_to_l2_valid[cl]),
                .l2_tx_ready      (l1_to_l2_ready[cl]),

                // L2 RX
                .l2_rx_data       (l2_to_l1_data[cl]),
                .l2_rx_valid      (l2_to_l1_valid[cl]),
                .l2_rx_ready      (l2_to_l1_ready[cl]),

                // Status
                .bus_busy          (l1_bus_busy[cl])
            );
        end
    endgenerate

    // =========================================================================
    // Instantiate 1 L2 Bus
    // =========================================================================
    noc_l2_bus l2_bus (
        .clk              (clk),
        .resetn           (resetn),

        // From L1 buses
        .l1_tx_data       (l1_to_l2_data),
        .l1_tx_valid      (l1_to_l2_valid),
        .l1_tx_ready      (l1_to_l2_ready),

        // To L1 buses
        .l1_rx_data       (l2_to_l1_data),
        .l1_rx_valid      (l2_to_l1_valid),
        .l1_rx_ready      (l2_to_l1_ready),

        // Status
        .bus_busy          (l2_bus_busy)
    );

endmodule