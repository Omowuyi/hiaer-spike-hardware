module core #(
    parameter AXI_ADDR_BITS  = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter HBM_ADDR_BITS  = 33,
    parameter HBM_DATA_WIDTH = 256,
    parameter HBM_BYTE_COUNT = 32,
    // NEW: Core identification for multi-core spike tagging
    parameter [3:0] CORE_ID  = 4'd0
    )(
    input aclk,
    input aclk450,
    input aresetn,
    input aresetn450,
    
    //Set as output to view from VIO
    output [16:0] num_outputs_out,
    output [16:0] num_inputs_out,
    output [35:0] threshold_out,
    output [1:0] exec_neuron_model_out,
    output [5:0] leak_out,
    output [5:0] shift_out,
    
    input [4:0] core_number,
    // HBM
    // Read data
    
    output  [HBM_ADDR_BITS-1:0] hbm_araddr,
    output                [1:0] hbm_arburst,
    output                [5:0] hbm_arid,
    output                [3:0] hbm_arlen,
    input                       hbm_arready,
    output                [2:0] hbm_arsize,
    output                      hbm_arvalid,
    // Write address
    output  [HBM_ADDR_BITS-1:0] hbm_awaddr,
    output                [1:0] hbm_awburst,
    output                [5:0] hbm_awid,
    output                [3:0] hbm_awlen,
    input                       hbm_awready,
    output                [2:0] hbm_awsize,
    output                      hbm_awvalid,
    // Write response
    input                 [5:0] hbm_bid,
    output                      hbm_bready,
    input                 [1:0] hbm_bresp,
    input                       hbm_bvalid,
    // Read response
    input  [HBM_DATA_WIDTH-1:0] hbm_rdata,
    input                 [5:0] hbm_rid,
    input                       hbm_rlast,
    output                      hbm_rready,
    input                 [1:0] hbm_rresp,
    input                       hbm_rvalid,
    // Write data
    output [HBM_DATA_WIDTH-1:0] hbm_wdata,
    output                      hbm_wlast,
    input                       hbm_wready,
    output [HBM_BYTE_COUNT-1:0] hbm_wstrb,
    output                      hbm_wvalid,
    
    input [511:0] rxFIFO_in_din,
    input rxFIFO_in_wren,
    output rxFIFO_in_full,
    output [511:0] txFIFO_out_dout,
    input txFIFO_out_rden,
    output txFIFO_out_empty,
    
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
    output execRun_done,
    
    // =========================================================================
    // NoC Interface
    // =========================================================================
    // NoC routing table programming, from this core's CI
    output wire        route_cfg_valid,
    output wire [9:0]  route_cfg_addr,
    output wire [5:0]  route_cfg_data,

    output wire [18:0] noc_spike_out_addr,
    output wire        noc_spike_out_valid,
    input  wire        noc_spike_out_ready,
    
    input  wire [18:0] noc_relay_din,
    input  wire        noc_relay_wren,
    output wire        noc_relay_full,
    output wire        exec_eep_phase3_done,

    // =========================================================================
    // NEW: Feature ports - interrupt, error status, watchdog
    // =========================================================================
    output wire        user_irq,
    output wire [31:0] error_status,
    output wire        iep_watchdog_error,
    output wire        iep_uram_out_of_range,

    // CMD 16: one entry of the classifier's remote destination table.
    // Only core 0's copy is used at the top -- there is one classifier per
    // device, not one per core.
    output wire        remote_cfg_valid,
    output wire [7:0]  remote_cfg_addr,
    output wire [5:0]  remote_cfg_data,
    output wire        fpga_id_valid,
    output wire [2:0]  fpga_id_data
    );

    
    ////////////////////
    // PCIe interface //
    ////////////////////
   
    // RX FIFO (host->card)
    FIFO_output #(512) rxFIFO_out(.clk(aclk), .reset(~aresetn));
    FIFO_input #(512) rxFIFO_in(.clk(aclk), .reset(~aresetn));
    assign rxFIFO_in.din = rxFIFO_in_din;
    assign rxFIFO_in.wren = rxFIFO_in_wren;
    assign rxFIFO_in_full = rxFIFO_in.full;
    // TX FIFO (card->host)
    FIFO_input #(512) txFIFO_in(.clk(aclk), .reset(~aresetn));
    FIFO_output #(512) txFIFO_out(.clk(aclk), .reset(~aresetn));
    assign txFIFO_out_dout = txFIFO_out.dout;
    assign txFIFO_out.rden = txFIFO_out_rden;
    assign txFIFO_out_empty = txFIFO_out.empty;
   
    FIFO_512 txFIFO(
        .i(txFIFO_in.Sink),
        .o(txFIFO_out)
    );
    
    FIFO_512 rxFIFO(
        .i(rxFIFO_in),
        .o(rxFIFO_out.Source)
    );
   
    //////////////////////////////////////
    // External events (axon) processor //
    //////////////////////////////////////
   
    wire                  axonEvent_set;
    wire       [12:0] axonEvent_addr;
    wire            [15:0] axonEvent_data;
   
   
   FIFO_input #(54) ci2iep_in (.clk(aclk), .reset(~aresetn));
   FIFO_output #(54) ci2iep_out (.clk(aclk), .reset(~aresetn));
   FIFO_input #(53) iep2ci_in (.clk(aclk), .reset(~aresetn));
   FIFO_output #(53) iep2ci_out (.clk(aclk), .reset(~aresetn));

    ///////////////////////
    // Network execution //
    ///////////////////////
    
    wire        exec_run;
    wire        execRun_running;
    wire [31:0] execRun_limit;
    wire [31:0] execRun_ctr;
    wire [63:0] execRun_timer;
   
    // Debugging   
    wire [2:0] vio_rx_curr_state;
    wire [3:0] vio_tx_curr_state;  // CHANGED: widened from [1:0] to [3:0]
   
    
    wire [16:0] num_inputs;
    wire [16:0] num_outputs;
    wire [35:0] threshold;
    wire [1:0]  exec_neuron_model;
    wire [5:0]  leak;
    wire [5:0]  shift;
    
    assign num_inputs_out = num_inputs;
    assign num_outputs_out = num_outputs;
    assign threshold_out = threshold;
    assign exec_neuron_model_out = exec_neuron_model;
    assign shift_out = shift;
    assign leak_out = leak;
    
    //=========================================================================
    // EXP_PSC + COBA + NEUROMOD: Internal wires between CI and IEP
    // These carry biological neuron model configuration from CI registers to IEP.
    // All default to safe values on reset (delta_mode=1, everything else zero).
    //=========================================================================
    wire        w_delta_mode;              // 1=legacy delta, 0=exp PSC
    wire [11:0] w_decay_ex;                // I_ex/g_ex decay factor
    wire [11:0] w_decay_in;                // I_in/g_in decay factor
    wire [7:0]  w_decay_w;                 // Adaptation decay factor
    wire [7:0]  w_delta_w_param;           // Adaptation increment on spike
    wire        w_coba_mode;               // 0=CUBA, 1=COBA
    wire signed [11:0] w_E_ex;             // Excitatory reversal potential
    wire signed [11:0] w_E_in;             // Inhibitory reversal potential
    wire [7:0]  w_neuromod_level;          // STDP rate scale
    wire signed [7:0] w_neuromod_excitability_bias; // Threshold shift
    
    //=========================================================================
    // STDP: Internal wires between CI and IEP for learning parameters
    //=========================================================================
    wire        w_stdp_enable;             // Enable STDP Phase 4
    wire [7:0]  w_A_plus;                  // Potentiation magnitude
    wire [7:0]  w_A_minus;                 // Depression magnitude
    wire signed [15:0] w_w_max;            // Weight saturation upper bound
    wire signed [15:0] w_w_min;            // Weight saturation lower bound
    
    //=========================================================================
    // STDP Phase 4: Internal wires
    //=========================================================================
    wire [18:0] w_stdp_spike_addr;         // IEP → stdp_controller: spiked neuron addr
    wire        w_stdp_spike_wr;           // IEP → stdp_controller: spike write strobe
    wire        w_stdp_phase4_active;      // stdp_controller → single_core: Phase 4 active
    wire        w_stdp_phase4_done;        // stdp_controller → IEP state machine
    
    // URAM read port intermediates (for Phase 4 mux)
    wire [11:0] iep_uram_raddr_w [0:15];   // IEP's read address output
    wire [15:0] iep_uram_rden_w;            // IEP's read enable output (1 bit per group)
    wire [191:0] stdp_uram_raddr_flat;     // STDP controller's read addresses (16×12)
    wire         stdp_uram_rden_w;          // STDP controller's read enable
    
    //=========================================================================
    // DELAY BUFFER: Internal wires between IEP and delay_buffer
    //=========================================================================
    wire        w_dbuf_syn_valid;
    wire [12:0] w_dbuf_syn_dest;
    wire signed [15:0] w_dbuf_syn_weight;
    wire [5:0]  w_dbuf_syn_delay;
    wire [17:0] w_dbuf_syn_src;
    wire [3:0]  w_dbuf_syn_stdp_tag;
    wire        w_dbuf_syn_ready;
    wire        w_dbuf_imm_valid;
    wire [12:0] w_dbuf_imm_dest;
    wire signed [15:0] w_dbuf_imm_weight;
    wire [17:0] w_dbuf_imm_src;
    wire [3:0]  w_dbuf_imm_stdp_tag;
    wire        w_dbuf_delayed_valid;
    wire [12:0] w_dbuf_delayed_dest;
    wire signed [15:0] w_dbuf_delayed_weight;
    wire [17:0] w_dbuf_delayed_src;
    wire [3:0]  w_dbuf_delayed_stdp_tag;
    wire        w_dbuf_delayed_ready;
    wire        w_dbuf_drain_done;
    wire        w_spk_dropped;   // spike discarded, FIFO full
    wire        w_dbg_spike_hi;  // DIAG bit 12
    wire        w_dbg_mp1_spike; // DIAG bit 13
    wire        w_dbg_mp1_tx;    // DIAG bit 14
    wire        w_dbg_mp1_rx;    // DIAG bit 15
    wire [3:0]  w_dbuf_delayed_group;   // FIX I: bank for a drained entry
    wire        w_syn_64bit_en;         // FIX E: Phase-2 entry width
    wire [3:0]  w_dbuf_syn_group;       // FIX F: bank for a pushed entry
    
    wire       exec_eep_phase1_ready;
    wire     [15:0] exec_eep_spiked;

    //=========================================================================
    // Cross-core STDP support signals.
    //
    // curr_bram_waddr is an output port; the EEP now drives an internal wire
    // and the port is driven from it, so axon_trace_mem can see it too.
    //=========================================================================
    wire            w_axon_row_valid;
    wire     [12:0] w_curr_bram_waddr;
    assign curr_bram_waddr = w_curr_bram_waddr;

    wire            w_axon_trace_rd_en;
    wire     [16:0] w_axon_trace_rd_idx;
    wire     [3:0]  w_axon_trace_rd_data;

    // exec_run is the timestep tick already used by both delay buffers.
    // axon_trace_mem needs a counter of it for decay-on-read.
    reg      [4:0]  axon_trace_timestep;
    always @(posedge aclk) begin
        if (~aresetn)      axon_trace_timestep <= 5'd0;
        else if (exec_run) axon_trace_timestep <= axon_trace_timestep + 5'd1;
    end
    wire       exec_eep_phase1_done;
    wire       exec_uram_phase0_done;
    wire       exec_uram_phase1_done;
    wire       exec_uram_phase2_done;
    
    RAM #(16,13) eep_bram_0(.clk(aclk));
    RAM #(16,13) eep_bram_1(.clk(aclk));
    
    //=========================================================================
    // AXON DELAY BUFFER: Per-axon hardware delay (L6m feature)
    //
    // Sits between CI and EEP. Each axon has a configurable 6-bit delay
    // (0–63 timesteps). Delay=0 passes through immediately (default).
    // Delay table loaded from host via delay_table_wr interface.
    //=========================================================================
    wire        axon_delayed_set;
    wire [12:0] axon_delayed_addr;
    wire [15:0] axon_delayed_data;
    wire        axon_drain_busy;
    
    // Delay table programming wires (from CI — new CMD or CMD_04 extension)
    // TODO: Add CMD 14 (opcode 0x0E) to CI for delay table loading.
    // Packet format: [511:504]=0x0E, [12:0]=axon_addr, [18:13]=delay_value
    // For now: all delays default to 0 (immediate pass-through, backward compatible)
    // Driven by the CI from CMD 14 (was hardwired to 0, so the table could
    // never be written and every axon delay stayed at 0).
    wire [12:0] w_delay_table_waddr;
    wire [5:0]  w_delay_table_wdata;
    wire        w_delay_table_wr;
    
    axon_delay_buffer axon_delay (
        .clk(aclk),
        .resetn(aresetn),
        // Input from CI
        .axon_in_set(axonEvent_set),
        .axon_in_addr(axonEvent_addr),
        .axon_in_data(axonEvent_data),
        // Output to EEP (delayed)
        .axon_out_set(axon_delayed_set),
        .axon_out_addr(axon_delayed_addr),
        .axon_out_data(axon_delayed_data),
        // Timestep control
        .timestep_tick(exec_run),
        .drain_busy(axon_drain_busy),
        // Delay table programming (from CI)
        .delay_table_waddr(w_delay_table_waddr),
        .delay_table_wdata(w_delay_table_wdata),
        .delay_table_wr(w_delay_table_wr)
    );
    
    external_events_processor_simple #(
        .PIPE_DEPTH(3),
        .NOC_FIFO_DEPTH(512)
    ) eep (
        .resetn(aresetn),
        .clk(aclk),
        .num_inputs(num_inputs),
        .axonEvent_set(axon_delayed_set),
        .axonEvent_addr(axon_delayed_addr),
        .axonEvent_data(axon_delayed_data),
        .exec_run(exec_run),
        .exec_eep_phase1_ready(exec_eep_phase1_ready),
        .exec_hbm_rvalidready(exec_hbm_rvalidready),
        .exec_eep_spiked(exec_eep_spiked),
        .exec_eep_phase1_done(exec_eep_phase1_done),
        .exec_uram_phase0_done(exec_uram_phase0_done),
        .delta_mode(w_delta_mode),
        .exec_uram_phase1_done(exec_uram_phase1_done),
        .exec_uram_phase2_done(exec_uram_phase2_done),
        .noc_relay_din(noc_relay_din),
        .noc_relay_wren(noc_relay_wren),
        .noc_relay_full(noc_relay_full),
        .exec_eep_phase3_done(exec_eep_phase3_done),
        .bram0_waddr(eep_bram_0.waddr),
        .bram0_wdata(eep_bram_0.wdata),
        .bram0_wren(eep_bram_0.wren),
        .bram0_raddr(eep_bram_0.raddr),
        .bram0_rden(eep_bram_0.rden),
        .bram0_rdata(eep_bram_0.rdata),
        .bram1_waddr(eep_bram_1.waddr),
        .bram1_wdata(eep_bram_1.wdata),
        .bram1_wren(eep_bram_1.wren),
        .bram1_raddr(eep_bram_1.raddr),
        .bram1_rden(eep_bram_1.rden),
        .bram1_rdata(eep_bram_1.rdata),
        .eep_curr_state(eep_curr_state),
        .hbm2eep_rden(hbm2eep_rden),
        .curr_bram_waddr(w_curr_bram_waddr),
        .axon_row_valid(w_axon_row_valid)
    );
    
    EEP_BRAM bram_0(
        .s(eep_bram_0.Slave)
    );
    EEP_BRAM bram_1(
        .s(eep_bram_1.Slave)
    );
    
    reg exec_run_FF1_450M;
    reg exec_run_FF2_450M;
    reg exec_eep_phase1_ready_FF1_450M;
    reg exec_eep_phase1_ready_FF2_450M;
    wire exec_uram_phase1_ready;
    reg exec_uram_phase1_ready_FF1_450M;
    reg exec_uram_phase1_ready_FF2_450M;
    
    always @(posedge aclk450) begin
        exec_run_FF1_450M <= exec_run;
        exec_run_FF2_450M <= exec_run_FF1_450M;
        exec_eep_phase1_ready_FF1_450M <= exec_eep_phase1_ready;
        exec_eep_phase1_ready_FF2_450M <= exec_eep_phase1_ready_FF1_450M;
        exec_uram_phase1_ready_FF1_450M <= exec_uram_phase1_ready;
        exec_uram_phase1_ready_FF2_450M <= exec_uram_phase1_ready_FF1_450M;
    end

    wire exec_hbm_tx_phase1_done;
    reg exec_hbm_tx_phase1_done_FF1_225M;
    reg exec_hbm_tx_phase1_done_FF2_225M;
    wire exec_hbm_tx_phase2_done;
    reg exec_hbm_tx_phase2_done_FF1_225M;
    reg exec_hbm_tx_phase2_done_FF2_225M;
    reg exec_hbm_rx_phase1_done_FF1_225M;
    reg exec_hbm_rx_phase1_done_FF2_225M;
    reg exec_hbm_rx_phase2_done_FF1_225M;
    reg exec_hbm_rx_phase2_done_FF2_225M;
   
    
    always @(posedge aclk) begin
        exec_hbm_tx_phase1_done_FF1_225M <= exec_hbm_tx_phase1_done;
        exec_hbm_tx_phase1_done_FF2_225M <= exec_hbm_tx_phase1_done_FF1_225M;
        exec_hbm_tx_phase2_done_FF1_225M <= exec_hbm_tx_phase2_done;
        exec_hbm_tx_phase2_done_FF2_225M <= exec_hbm_tx_phase2_done_FF1_225M;
        exec_hbm_rx_phase1_done_FF1_225M <= exec_hbm_rx_phase1_done;
        exec_hbm_rx_phase1_done_FF2_225M <= exec_hbm_rx_phase1_done_FF1_225M;
        exec_hbm_rx_phase2_done_FF1_225M <= exec_hbm_rx_phase2_done;
        exec_hbm_rx_phase2_done_FF2_225M <= exec_hbm_rx_phase2_done_FF1_225M;
    end
    
    wire [511:0] exec_hbm_rdata;
    
    FIFO_output #(280) ci2hbm_out(.clk(aclk450), .reset(~aresetn450));
    FIFO_input #(280) ci2hbm_in(.clk(aclk), .reset(~aresetn));
    FIFO_output #(256) hbm2ci_out(.clk(aclk), .reset(~aresetn));
    FIFO_input #(256) hbm2ci_in(.clk(aclk450), .reset(~aresetn450));

    FIFO_input #(19) spk_in [7:0] (.clk(aclk450), .reset(~aresetn450));
    FIFO_output #(19) spk_out [7:0] (.clk(aclk450), .reset(~aresetn450));
    
    FIFO_output #(512) hbmdataFIFO_out(.clk(aclk), .reset(~aresetn));
    FIFO_input #(512) hbmdataFIFO_in(.clk(aclk450), .reset(~aresetn450)); 
    
    hbmdata_FIFO_512 hbmdataFIFO(
        .i(hbmdataFIFO_in.Sink),
        .o(hbmdataFIFO_out.Source)
    );

    assign hbmdataFIFO_out.rden = hbm2iep_rden;
    assign exec_hbm_rvalidready = ~hbmdataFIFO_out.empty;
    assign hbmFIFO_empty = hbmdataFIFO_out.empty;
   
    
    wire       exec_hbm_rvalidready_from_hbm;
    assign hbmdataFIFO_in.wren = exec_hbm_rvalidready_from_hbm;
    hbm_processor #(
        .HBM_ADDR_BITS(HBM_ADDR_BITS),
        .HBM_DATA_WIDTH(HBM_DATA_WIDTH),
        .HBM_BYTE_COUNT(HBM_BYTE_COUNT)
    ) hbmp (
        .clk(aclk450),
        .resetn(aresetn450),
        .num_inputs(num_inputs),
        .num_outputs(num_outputs),
        .exec_run(exec_run_FF2_450M),
        .core_number(core_number),
        .exec_bram_phase1_ready(exec_eep_phase1_ready),
        .exec_uram_phase1_ready(exec_uram_phase1_ready_FF2_450M),
        .exec_hbm_rvalidready(exec_hbm_rvalidready_from_hbm),
        .exec_hbm_tx_phase1_done(exec_hbm_tx_phase1_done),
        .exec_hbm_tx_phase2_done(exec_hbm_tx_phase2_done),
        .exec_hbm_rx_phase1_done(exec_hbm_rx_phase1_done),
        .exec_hbm_rx_phase2_done(exec_hbm_rx_phase2_done),
        .exec_hbm_rdata(hbmdataFIFO_in.din),
        .hbmFIFO_full(hbmdataFIFO_in.full),
        .ptrFIFO_empty(ptrFIFO_out.empty),
        .ptrFIFO_dout(ptrFIFO_out.dout),
        .ptrFIFO_rden(ptrFIFO_out.rden),
        .ci2hbm_empty(ci2hbm_out.empty),
        .ci2hbm_dout(ci2hbm_out.dout),
        .ci2hbm_rden(ci2hbm_out.rden),
        .hbm2ci_full(hbm2ci_in.full),
        .hbm2ci_din(hbm2ci_in.din),
        .hbm2ci_wren(hbm2ci_in.wren),
        .hbm_araddr(hbm_araddr),
        .hbm_arburst(hbm_arburst),
        .hbm_arid(hbm_arid),
        .hbm_arlen(hbm_arlen),
        .hbm_arready(hbm_arready),
        .hbm_arsize(hbm_arsize),
        .hbm_arvalid(hbm_arvalid),
        .hbm_awaddr(hbm_awaddr),
        .hbm_awburst(hbm_awburst),
        .hbm_awid(hbm_awid),
        .hbm_awlen(hbm_awlen),
        .hbm_awready(hbm_awready),
        .hbm_awsize(hbm_awsize),
        .hbm_awvalid(hbm_awvalid),
        .hbm_bid(hbm_bid),
        .hbm_bready(hbm_bready),
        .hbm_bresp(hbm_bresp),
        .hbm_bvalid(hbm_bvalid),
        .hbm_rdata(hbm_rdata),
        .hbm_rid(hbm_rid),
        .hbm_rlast(hbm_rlast),
        .hbm_rready(hbm_rready),
        .hbm_rresp(hbm_rresp),
        .hbm_rvalid(hbm_rvalid),
        .hbm_wdata(hbm_wdata),
        .hbm_wlast(hbm_wlast),
        .hbm_wready(hbm_wready),
        .hbm_wstrb(hbm_wstrb),
        .hbm_wvalid(hbm_wvalid),
        .spk0_full(spk_in[0].full),
        .spk0_din(spk_in[0].din),
        .spk0_wren(spk_in[0].wren),
        .spk1_full(spk_in[1].full),
        .spk1_din(spk_in[1].din),
        .spk1_wren(spk_in[1].wren),
        .spk2_full(spk_in[2].full),
        .spk2_din(spk_in[2].din),
        .spk2_wren(spk_in[2].wren),
        .spk3_full(spk_in[3].full),
        .spk3_din(spk_in[3].din),
        .spk3_wren(spk_in[3].wren),
        .spk4_full(spk_in[4].full),
        .spk4_din(spk_in[4].din),
        .spk4_wren(spk_in[4].wren),
        .spk5_full(spk_in[5].full),
        .spk5_din(spk_in[5].din),
        .spk5_wren(spk_in[5].wren),
        .spk6_full(spk_in[6].full),
        .spk6_din(spk_in[6].din),
        .spk6_wren(spk_in[6].wren),
        .spk7_full(spk_in[7].full),
        .spk7_din(spk_in[7].din),
        .spk7_wren(spk_in[7].wren),
        .dbg_mp1_spike(w_dbg_mp1_spike),
        .dbg_mp1_tx(w_dbg_mp1_tx),
        .dbg_mp1_rx(w_dbg_mp1_rx),
        .spk_dropped(w_spk_dropped),
        .hbm_curr_state(hbm_curr_state)
    );
    
    wire [15:0] exec_bram_spiked;
    assign exec_bram_spiked = exec_eep_spiked;
    
    wire       exec_bram_phase1_done;
    assign exec_bram_phase1_done = exec_eep_phase1_done;
    
    wire [15:0] exec_uram_spiked;

    FIFO_input #(32) ptr_in [15:0] (.clk(aclk), .reset(~aresetn));
    FIFO_output #(32) ptr_out [15:0] (.clk(aclk), .reset(~aresetn)); 
    
    wire             ptrFIFO_full;
    wire [31:0] ptrFIFO_din;
    wire        ptrFIFO_wren;
    
    FIFO_input #(32) ptrFIFO_in(.clk(aclk), .reset(~aresetn));
    FIFO_output #(32) ptrFIFO_out(.clk(aclk450), .reset(~aresetn450));
    
    pointer_fifo_controller ptf_fifo_controller(
        .resetn(aresetn),
        .clk(aclk),
        .exec_run(exec_run),
        .exec_bram_spiked(exec_bram_spiked),
        .exec_bram_phase1_done(exec_bram_phase1_done),
        .exec_bram_phase1_ready(exec_eep_phase1_ready),
        .exec_uram_spiked(exec_uram_spiked),
        .exec_uram_phase1_ready(exec_uram_phase1_ready),
        .exec_uram_phase0_done(exec_uram_phase0_done),
        .exec_uram_phase1_done(exec_uram_phase1_done),
        .exec_hbm_rvalidready(exec_hbm_rvalidready),
        .exec_hbm_rdata(hbmdataFIFO_out.dout),
        .hbm2pfc_rden(hbm2pfc_rden),
        .ptr0_full(ptr_in[0].full),
        .ptr0_din(ptr_in[0].din),
        .ptr0_wren(ptr_in[0].wren),
        .ptr0_empty(ptr_out[0].empty),
        .ptr0_dout(ptr_out[0].dout),
        .ptr0_rden(ptr_out[0].rden),
        .ptr1_full(ptr_in[1].full),
        .ptr1_din(ptr_in[1].din),
        .ptr1_wren(ptr_in[1].wren),
        .ptr1_empty(ptr_out[1].empty),
        .ptr1_dout(ptr_out[1].dout),
        .ptr1_rden(ptr_out[1].rden),
        .ptr2_full(ptr_in[2].full),
        .ptr2_din(ptr_in[2].din),
        .ptr2_wren(ptr_in[2].wren),
        .ptr2_empty(ptr_out[2].empty),
        .ptr2_dout(ptr_out[2].dout),
        .ptr2_rden(ptr_out[2].rden),
        .ptr3_full(ptr_in[3].full),
        .ptr3_din(ptr_in[3].din),
        .ptr3_wren(ptr_in[3].wren),
        .ptr3_empty(ptr_out[3].empty),
        .ptr3_dout(ptr_out[3].dout),
        .ptr3_rden(ptr_out[3].rden),
        .ptr4_full(ptr_in[4].full),
        .ptr4_din(ptr_in[4].din),
        .ptr4_wren(ptr_in[4].wren),
        .ptr4_empty(ptr_out[4].empty),
        .ptr4_dout(ptr_out[4].dout),
        .ptr4_rden(ptr_out[4].rden),
        .ptr5_full(ptr_in[5].full),
        .ptr5_din(ptr_in[5].din),
        .ptr5_wren(ptr_in[5].wren),
        .ptr5_empty(ptr_out[5].empty),
        .ptr5_dout(ptr_out[5].dout),
        .ptr5_rden(ptr_out[5].rden),
        .ptr6_full(ptr_in[6].full),
        .ptr6_din(ptr_in[6].din),
        .ptr6_wren(ptr_in[6].wren),
        .ptr6_empty(ptr_out[6].empty),
        .ptr6_dout(ptr_out[6].dout),
        .ptr6_rden(ptr_out[6].rden),
        .ptr7_full(ptr_in[7].full),
        .ptr7_din(ptr_in[7].din),
        .ptr7_wren(ptr_in[7].wren),
        .ptr7_empty(ptr_out[7].empty),
        .ptr7_dout(ptr_out[7].dout),
        .ptr7_rden(ptr_out[7].rden),
        .ptr8_full(ptr_in[8].full),
        .ptr8_din(ptr_in[8].din),
        .ptr8_wren(ptr_in[8].wren),
        .ptr8_empty(ptr_out[8].empty),
        .ptr8_dout(ptr_out[8].dout),
        .ptr8_rden(ptr_out[8].rden),
        .ptr9_full(ptr_in[9].full),
        .ptr9_din(ptr_in[9].din),
        .ptr9_wren(ptr_in[9].wren),
        .ptr9_empty(ptr_out[9].empty),
        .ptr9_dout(ptr_out[9].dout),
        .ptr9_rden(ptr_out[9].rden),
        .ptr10_full(ptr_in[10].full),
        .ptr10_din(ptr_in[10].din),
        .ptr10_wren(ptr_in[10].wren),
        .ptr10_empty(ptr_out[10].empty),
        .ptr10_dout(ptr_out[10].dout),
        .ptr10_rden(ptr_out[10].rden),
        .ptr11_full(ptr_in[11].full),
        .ptr11_din(ptr_in[11].din),
        .ptr11_wren(ptr_in[11].wren),
        .ptr11_empty(ptr_out[11].empty),
        .ptr11_dout(ptr_out[11].dout),
        .ptr11_rden(ptr_out[11].rden),
        .ptr12_full(ptr_in[12].full),
        .ptr12_din(ptr_in[12].din),
        .ptr12_wren(ptr_in[12].wren),
        .ptr12_empty(ptr_out[12].empty),
        .ptr12_dout(ptr_out[12].dout),
        .ptr12_rden(ptr_out[12].rden),
        .ptr13_full(ptr_in[13].full),
        .ptr13_din(ptr_in[13].din),
        .ptr13_wren(ptr_in[13].wren),
        .ptr13_empty(ptr_out[13].empty),
        .ptr13_dout(ptr_out[13].dout),
        .ptr13_rden(ptr_out[13].rden),
        .ptr14_full(ptr_in[14].full),
        .ptr14_din(ptr_in[14].din),
        .ptr14_wren(ptr_in[14].wren),
        .ptr14_empty(ptr_out[14].empty),
        .ptr14_dout(ptr_out[14].dout),
        .ptr14_rden(ptr_out[14].rden),
        .ptr15_full(ptr_in[15].full),
        .ptr15_din(ptr_in[15].din),
        .ptr15_wren(ptr_in[15].wren),
        .ptr15_empty(ptr_out[15].empty),
        .ptr15_dout(ptr_out[15].dout),
        .ptr15_rden(ptr_out[15].rden),
        .ptrFIFO_full(ptrFIFO_in.full),
        .ptrFIFO_din(ptrFIFO_in.din),
        .ptrFIFO_wren(ptrFIFO_in.wren)
    );
    
    generate
        for(genvar j = 0; j<16; j=j+1) begin
            FIFO_32 ptr(
                .i(ptr_in[j]),
                .o(ptr_out[j])
            );
        end
    endgenerate

    sync_FIFO_32 ptrFIFO(
        .i(ptrFIFO_in),
        .o(ptrFIFO_out)
    );
    
    sync_FIFO_280 ci2hbmFIFO(
        .i(ci2hbm_in.Sink),
        .o(ci2hbm_out.Source)
    );
    sync_FIFO_256 hbm2ciFIFO(
        .i(hbm2ci_in.Sink),
        .o(hbm2ci_out.Source)
    );
    
    FIFO_input #(19) spk2ci_in (.clk(aclk450), .reset(~aresetn450));
    FIFO_output #(19) spk2ci_out (.clk(aclk), .reset(~aresetn));

    spike_fifo_controller spk_fifo_controller(
        .clk(aclk450),
        .resetn(aresetn450),
        .spk0_empty(spk_out[0].empty),
        .spk0_dout(spk_out[0].dout),
        .spk0_rden(spk_out[0].rden),
        .spk1_empty(spk_out[1].empty),
        .spk1_dout(spk_out[1].dout),
        .spk1_rden(spk_out[1].rden),
        .spk2_empty(spk_out[2].empty),
        .spk2_dout(spk_out[2].dout),
        .spk2_rden(spk_out[2].rden),
        .spk3_empty(spk_out[3].empty),
        .spk3_dout(spk_out[3].dout),
        .spk3_rden(spk_out[3].rden),
        .spk4_empty(spk_out[4].empty),
        .spk4_dout(spk_out[4].dout),
        .spk4_rden(spk_out[4].rden),
        .spk5_empty(spk_out[5].empty),
        .spk5_dout(spk_out[5].dout),
        .spk5_rden(spk_out[5].rden),
        .spk6_empty(spk_out[6].empty),
        .spk6_dout(spk_out[6].dout),
        .spk6_rden(spk_out[6].rden),
        .spk7_empty(spk_out[7].empty),
        .spk7_dout(spk_out[7].dout),
        .spk7_rden(spk_out[7].rden),
        .spk2ciFIFO_full(spk2ci_in.full),
        .spk2ciFIFO_din(spk2ci_in.din),
        .spk2ciFIFO_wren(spk2ci_in.wren)
    );
    
    // =========================================================================
    // NoC Spike Output
    // =========================================================================
    assign noc_spike_out_addr = spk2ci_in.din;
    assign noc_spike_out_valid = spk2ci_in.wren && !spk2ci_in.full;

    
    generate
        for(genvar j=0; j<8; j=j+1) begin
    wire [279:0] ci_ci2hbm_din;   // declared before first use;
                                  // an implicit wire here would be 1 bit
            FIFO_19 spkFIFIO(
                .i(spk_in[j].Sink),
                .o(spk_out[j].Source)
            );
        end
    endgenerate
    
    wire [3:0] rd_addr_neuron_param_mem;
    wire [83:0] dout_neuron_param_mem;
    
    // =========================================================================
    // NEW: Internal wires for IEP watchdog → CI connection
    // =========================================================================
    wire iep_watchdog_error_w;
    wire iep_uram_out_of_range_w;
    assign iep_watchdog_error = iep_watchdog_error_w;
    assign iep_uram_out_of_range = iep_uram_out_of_range_w;

    // =========================================================================
    // Command Interpreter with CORE_ID for multi-core spike tagging
    // =========================================================================
    command_interpreter #(
        .AXI_ADDR_BITS(AXI_ADDR_BITS),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .HBM_ADDR_BITS(HBM_ADDR_BITS),
        .HBM_DATA_WIDTH(HBM_DATA_WIDTH),
        .HBM_BYTE_COUNT(HBM_BYTE_COUNT),
        .CORE_ID(CORE_ID)    // NEW: Pass CORE_ID for spike packet tagging
    ) ci (
        .remote_cfg_valid(remote_cfg_valid),
        .remote_cfg_addr(remote_cfg_addr),
        .remote_cfg_data(remote_cfg_data),
        .fpga_id_valid(fpga_id_valid),
        .fpga_id_data(fpga_id_data),
        .aclk(aclk),
        .aresetn(aresetn),
        .num_inputs(num_inputs),
        .num_outputs(num_outputs),
        .threshold(threshold),
        .exec_neuron_model(exec_neuron_model),
        .leak(leak),
        .shift(shift),

        // RX FIFO (host->card)
        .rxFIFO_empty(rxFIFO_out.empty),
        .rxFIFO_dout(rxFIFO_out.dout),
        .rxFIFO_rden(rxFIFO_out.rden),
   
        // TX FIFO (card->host)
        .txFIFO_full(txFIFO_in.full),
        .txFIFO_din(txFIFO_in.din),
        .txFIFO_wren(txFIFO_in.wren),

        // External events (axon) processor
        .axonEvent_set(axonEvent_set),
        .axonEvent_addr(axonEvent_addr),
        .axonEvent_data(axonEvent_data),

        // HBM (synapse) processor
        .ci2hbm_full(ci2hbm_in.full),
        .ci2hbm_din(ci_ci2hbm_din),
        .ci2hbm_wren(ci_ci2hbm_wren),
        .hbm2ci_empty(hbm2ci_out.empty),
        .hbm2ci_dout(hbm2ci_out.dout),
        .hbm2ci_rden(ci_hbm2ci_rden),

        // Internal events (neuron) processor
        .ci2iep_full(ci2iep_in.full),
        .ci2iep_wren(ci2iep_in.wren),
        .ci2iep_din(ci2iep_in.din),
        .iep2ci_empty(iep2ci_out.empty),
        .iep2ci_rden(iep2ci_out.rden),
        .iep2ci_dout(iep2ci_out.dout),

        // Spike event FIFO
        .spk2ciFIFO_dout(spk2ci_out.dout),
        .spk2ciFIFO_empty(spk2ci_out.empty),
        .spk2ciFIFO_full(spk2ci_in.full),       // NEW: for timeout detection
        .spk2ciFIFO_rden(spk2ci_out.rden),

        // Network execution
        .exec_iep_phase2_done(exec_uram_phase2_done),
        .exec_run(exec_run),
        .execRun_running(execRun_running),
        .execRun_done(execRun_done),
        .execRun_limit(execRun_limit),
        .execRun_ctr(execRun_ctr),
        .execRun_timer(execRun_timer),

        // Debugging   
        .vio_rx_curr_state(vio_rx_curr_state),
        .vio_tx_curr_state(vio_tx_curr_state),
        
        .exec_hbm_rvalidready(exec_hbm_rvalidready),
        
        .rd_addr_neuron_param_mem(rd_addr_neuron_param_mem),
        .dout_neuron_param_mem(dout_neuron_param_mem),
        
        // NEW: Feature ports
        .iep_watchdog_error(iep_watchdog_error_w),
        .iep_uram_out_of_range(iep_uram_out_of_range_w),
        .route_cfg_valid(route_cfg_valid),
        .route_cfg_addr(route_cfg_addr),
        .route_cfg_data(route_cfg_data),
        .user_irq(user_irq),
        .error_status(error_status),
        
        // EXP_PSC + COBA + NEUROMOD: Biological model config outputs → wired to IEP
        .delta_mode(w_delta_mode),
        .decay_ex(w_decay_ex),
        .decay_in(w_decay_in),
        .decay_w(w_decay_w),
        .delta_w_param(w_delta_w_param),
        .coba_mode(w_coba_mode),
        .E_ex(w_E_ex),
        .E_in(w_E_in),
        .neuromod_level(w_neuromod_level),
        .neuromod_excitability_bias(w_neuromod_excitability_bias),
        // STDP: Learning parameters → wired to IEP
        .stdp_enable(w_stdp_enable),
        .A_plus(w_A_plus),
        .A_minus(w_A_minus),
        .w_max(w_w_max),
        .w_min(w_w_min),
        .syn_64bit_en(w_syn_64bit_en),
        .spk_dropped(w_spk_dropped),
        .dbg_spike_hi(w_dbg_spike_hi),
        .dbg_mp1_spike(w_dbg_mp1_spike),
        .dbg_mp1_tx(w_dbg_mp1_tx),
        .dbg_mp1_rx(w_dbg_mp1_rx),
        .delay_table_waddr(w_delay_table_waddr),
        .delay_table_wdata(w_delay_table_wdata),
        .delay_table_wr(w_delay_table_wr)
    );
    
    RAM #(72, 12) iep_uram [15:0] (.clk(aclk));
    
    internal_events_processor iep(
        .resetn(aresetn),
        .clk(aclk),
        .num_outputs(num_outputs),
        .threshold(threshold),
        .exec_run(exec_run),
        .exec_bram_phase1_done(exec_bram_phase1_done),
        .exec_uram_phase1_ready(exec_uram_phase1_ready),
        .exec_hbm_rdata(hbmdataFIFO_out.dout),
        .exec_hbm_rvalidready(exec_hbm_rvalidready),
        .hbm2iep_rden(hbm2iep_rden),
        .exec_uram_spiked(exec_uram_spiked),
        .exec_uram_phase0_done(exec_uram_phase0_done),
        .exec_uram_phase1_done(exec_uram_phase1_done),
        .exec_uram_phase2_done(exec_uram_phase2_done),
        .exec_hbm_rx_phase2_done(exec_hbm_rx_phase2_done_FF2_225M),
        .exec_neuron_model(exec_neuron_model),
        .leak(leak),
        .shift(shift),
        .ci2iep_empty(ci2iep_out.empty),
        .ci2iep_dout(ci2iep_out.dout),
        .ci2iep_rden(ci2iep_out.rden),
        .iep2ci_full(iep2ci_in.full),
        .iep2ci_din(iep2ci_in.din),
        .iep2ci_wren(iep2ci_in.wren),
        .uram_raddr_0(iep_uram_raddr_w[0]),
        .uram_raddr_1(iep_uram_raddr_w[1]),
        .uram_raddr_2(iep_uram_raddr_w[2]),
        .uram_raddr_3(iep_uram_raddr_w[3]),
        .uram_raddr_4(iep_uram_raddr_w[4]),
        .uram_raddr_5(iep_uram_raddr_w[5]),
        .uram_raddr_6(iep_uram_raddr_w[6]),
        .uram_raddr_7(iep_uram_raddr_w[7]),
        .uram_raddr_8(iep_uram_raddr_w[8]),
        .uram_raddr_9(iep_uram_raddr_w[9]),
        .uram_raddr_10(iep_uram_raddr_w[10]),
        .uram_raddr_11(iep_uram_raddr_w[11]),
        .uram_raddr_12(iep_uram_raddr_w[12]),
        .uram_raddr_13(iep_uram_raddr_w[13]),
        .uram_raddr_14(iep_uram_raddr_w[14]),
        .uram_raddr_15(iep_uram_raddr_w[15]),
        .uram_rden_0(iep_uram_rden_w[0]),
        .uram_rden_1(iep_uram_rden_w[1]),
        .uram_rden_2(iep_uram_rden_w[2]),
        .uram_rden_3(iep_uram_rden_w[3]),
        .uram_rden_4(iep_uram_rden_w[4]),
        .uram_rden_5(iep_uram_rden_w[5]),
        .uram_rden_6(iep_uram_rden_w[6]),
        .uram_rden_7(iep_uram_rden_w[7]),
        .uram_rden_8(iep_uram_rden_w[8]),
        .uram_rden_9(iep_uram_rden_w[9]),
        .uram_rden_10(iep_uram_rden_w[10]),
        .uram_rden_11(iep_uram_rden_w[11]),
        .uram_rden_12(iep_uram_rden_w[12]),
        .uram_rden_13(iep_uram_rden_w[13]),
        .uram_rden_14(iep_uram_rden_w[14]),
        .uram_rden_15(iep_uram_rden_w[15]),
        .uram_rdata_0(iep_uram[0].rdata),
        .uram_rdata_1(iep_uram[1].rdata),
        .uram_rdata_2(iep_uram[2].rdata),
        .uram_rdata_3(iep_uram[3].rdata),
        .uram_rdata_4(iep_uram[4].rdata),
        .uram_rdata_5(iep_uram[5].rdata),
        .uram_rdata_6(iep_uram[6].rdata),
        .uram_rdata_7(iep_uram[7].rdata),
        .uram_rdata_8(iep_uram[8].rdata),
        .uram_rdata_9(iep_uram[9].rdata),
        .uram_rdata_10(iep_uram[10].rdata),
        .uram_rdata_11(iep_uram[11].rdata),
        .uram_rdata_12(iep_uram[12].rdata),
        .uram_rdata_13(iep_uram[13].rdata),
        .uram_rdata_14(iep_uram[14].rdata),
        .uram_rdata_15(iep_uram[15].rdata),
        .uram_waddr_0(iep_uram[0].waddr),
        .uram_waddr_1(iep_uram[1].waddr),
        .uram_waddr_2(iep_uram[2].waddr),
        .uram_waddr_3(iep_uram[3].waddr),
        .uram_waddr_4(iep_uram[4].waddr),
        .uram_waddr_5(iep_uram[5].waddr),
        .uram_waddr_6(iep_uram[6].waddr),
        .uram_waddr_7(iep_uram[7].waddr),
        .uram_waddr_8(iep_uram[8].waddr),
        .uram_waddr_9(iep_uram[9].waddr),
        .uram_waddr_10(iep_uram[10].waddr),
        .uram_waddr_11(iep_uram[11].waddr),
        .uram_waddr_12(iep_uram[12].waddr),
        .uram_waddr_13(iep_uram[13].waddr),
        .uram_waddr_14(iep_uram[14].waddr),
        .uram_waddr_15(iep_uram[15].waddr),
        .uram_wdata_0(iep_uram[0].wdata),
        .uram_wdata_1(iep_uram[1].wdata),
        .uram_wdata_2(iep_uram[2].wdata),
        .uram_wdata_3(iep_uram[3].wdata),
        .uram_wdata_4(iep_uram[4].wdata),
        .uram_wdata_5(iep_uram[5].wdata),
        .uram_wdata_6(iep_uram[6].wdata),
        .uram_wdata_7(iep_uram[7].wdata),
        .uram_wdata_8(iep_uram[8].wdata),
        .uram_wdata_9(iep_uram[9].wdata),
        .uram_wdata_10(iep_uram[10].wdata),
        .uram_wdata_11(iep_uram[11].wdata),
        .uram_wdata_12(iep_uram[12].wdata),
        .uram_wdata_13(iep_uram[13].wdata),
        .uram_wdata_14(iep_uram[14].wdata),
        .uram_wdata_15(iep_uram[15].wdata),
        .uram_wren_0(iep_uram[0].wren),
        .uram_wren_1(iep_uram[1].wren),
        .uram_wren_2(iep_uram[2].wren),
        .uram_wren_3(iep_uram[3].wren),
        .uram_wren_4(iep_uram[4].wren),
        .uram_wren_5(iep_uram[5].wren),
        .uram_wren_6(iep_uram[6].wren),
        .uram_wren_7(iep_uram[7].wren),
        .uram_wren_8(iep_uram[8].wren),
        .uram_wren_9(iep_uram[9].wren),
        .uram_wren_10(iep_uram[10].wren),
        .uram_wren_11(iep_uram[11].wren),
        .uram_wren_12(iep_uram[12].wren),
        .uram_wren_13(iep_uram[13].wren),
        .uram_wren_14(iep_uram[14].wren),
        .uram_wren_15(iep_uram[15].wren),
        .iep_curr_state(iep_curr_state),
        .curr_uram_waddr(curr_uram_waddr),
        
        .rd_addr_neuron_param_mem(rd_addr_neuron_param_mem),
        .dout_neuron_param_mem(dout_neuron_param_mem),
        
        // NEW: Watchdog outputs → wired to CI inputs
        .iep_watchdog_error(iep_watchdog_error_w),
        .iep_uram_out_of_range(iep_uram_out_of_range_w),
        
        // EXP_PSC + COBA + NEUROMOD: Biological model config inputs ← wired from CI
        .delta_mode(w_delta_mode),
        .decay_ex(w_decay_ex),
        .decay_in(w_decay_in),
        .decay_w(w_decay_w),
        .delta_w_param_in(w_delta_w_param),
        .coba_mode(w_coba_mode),
        .E_ex(w_E_ex),
        .E_in(w_E_in),
        .neuromod_level(w_neuromod_level),
        .neuromod_excitability_bias(w_neuromod_excitability_bias),
        // STDP: Learning parameters ← wired from CI
        .stdp_enable(w_stdp_enable),
        .A_plus(w_A_plus),
        .A_minus(w_A_minus),
        .w_max(w_w_max),
        .w_min(w_w_min),
        // STDP: Spike address capture → stdp_controller
        .stdp_spike_addr(w_stdp_spike_addr),
        .stdp_spike_wr(w_stdp_spike_wr),
        // DELAY BUFFER: per-synapse delay interface
        .dbuf_syn_valid(w_dbuf_syn_valid),
        .dbuf_syn_dest(w_dbuf_syn_dest),
        .dbuf_syn_weight(w_dbuf_syn_weight),
        .dbuf_syn_delay(w_dbuf_syn_delay),
        .dbuf_syn_src(w_dbuf_syn_src),
        .dbuf_syn_stdp_tag(w_dbuf_syn_stdp_tag),
        .dbuf_syn_ready(w_dbuf_syn_ready),
        .dbuf_delayed_valid(w_dbuf_delayed_valid),
        .dbuf_delayed_dest(w_dbuf_delayed_dest),
        .dbuf_delayed_weight(w_dbuf_delayed_weight),
        .dbg_spike_hi(w_dbg_spike_hi),
        .dbuf_delayed_group(w_dbuf_delayed_group),
        .dbuf_syn_group(w_dbuf_syn_group),
        .syn_64bit_en(w_syn_64bit_en),
        .dbuf_drain_done(w_dbuf_drain_done),
        .dbuf_delayed_ready(w_dbuf_delayed_ready)
    );

    FIFO_34 ci2iepFIFO(
        .i(ci2iep_in.Sink),
        .o(ci2iep_out.Source)
    );

    FIFO_33 iep2ciFIFO(
        .i(iep2ci_in.Sink),
        .o(iep2ci_out.Source)
    );

    sync_FIFO_19 spk2ciFIFO(
        .i(spk2ci_in.Sink),
        .o(spk2ci_out.Source)
    );
    
    //=========================================================================
    // URAM read port mux: IEP during Phases 0-2, stdp_controller during Phase 4
    // During Phase 4, the IEP is in IDLE and does not drive URAM read ports.
    // The stdp_controller drives them for trace lookups.
    //=========================================================================
    
    //=========================================================================
    // PER-SYNAPSE DELAY BUFFER: sits between HBM data and IEP accumulation
    //
    // During Phase 2: IEP pushes entries with delay>0 into delay_buffer
    // At each timestep_tick: delay_buffer drains expired entries
    // Expired entries are accumulated into URAM via the IEP
    //=========================================================================
    
    delay_buffer dbuf (
        .clk(aclk),
        .resetn(aresetn),
        // Input from IEP Phase 2 (entries with delay>0)
        .syn_valid(w_dbuf_syn_valid),
        .syn_dest_addr(w_dbuf_syn_dest),
        .syn_weight(w_dbuf_syn_weight),
        .syn_delay(w_dbuf_syn_delay),
        .syn_src_addr(w_dbuf_syn_src),
        .syn_stdp_tag(w_dbuf_syn_stdp_tag),
        .syn_group(w_dbuf_syn_group),
        .syn_ready(w_dbuf_syn_ready),
        // Immediate output (delay=0 bypass — not used, IEP handles these directly)
        .immediate_valid(w_dbuf_imm_valid),
        .immediate_dest_addr(w_dbuf_imm_dest),
        .immediate_weight(w_dbuf_imm_weight),
        .immediate_src_addr(w_dbuf_imm_src),
        .immediate_stdp_tag(w_dbuf_imm_stdp_tag),
        .immediate_ready(1'b1),  // always accept (but IEP only sends delay>0)
        // Delayed output (expired entries drained at timestep start)
        .delayed_valid(w_dbuf_delayed_valid),
        .delayed_dest_addr(w_dbuf_delayed_dest),
        .delayed_weight(w_dbuf_delayed_weight),
        .delayed_src_addr(w_dbuf_delayed_src),
        .delayed_stdp_tag(w_dbuf_delayed_stdp_tag),
        .delayed_group(w_dbuf_delayed_group),
        .immediate_group(),
        .delayed_ready(w_dbuf_delayed_ready),
        // Timestep control
        .timestep_tick(exec_run),
        .drain_done(w_dbuf_drain_done)
    );
    generate
        for (genvar m = 0; m < 16; m = m + 1) begin : gen_uram_raddr_mux
            assign iep_uram[m].raddr = w_stdp_phase4_active ? stdp_uram_raddr_flat[12*m +: 12] : iep_uram_raddr_w[m];
            assign iep_uram[m].rden  = w_stdp_phase4_active ? stdp_uram_rden_w      : iep_uram_rden_w[m];
        end
    endgenerate

    //=========================================================================
    // STDP Controller instantiation
    //
    // Uses the existing ci2hbm FIFO path for HBM access. After Phase 2,
    // the HBM processor returns to IDLE and processes ci2hbm entries.
    // The stdp_controller pushes read/write commands through this path.
    //
    // ci2hbm mux: during Phase 4, stdp_controller drives ci2hbm_in.
    // During normal operation, CI drives ci2hbm_in.
    // No changes to hbm_processor.v required.
    //
    // When stdp_enable=0: phase4_done fires immediately, zero overhead.
    //=========================================================================
    
    // ci2hbm mux wires
    wire [279:0] p4_ci2hbm_din;
    wire         p4_ci2hbm_wren;
    wire [255:0] p4_hbm2ci_dout;
    wire         p4_hbm2ci_empty;
    wire         p4_hbm2ci_rden;
    
    // ci2hbm input mux: CI during normal operation, stdp_controller during Phase 4
    // CI drives: ci2hbm_in.din, ci2hbm_in.wren (from command_interpreter)
    // These are already connected to CI. We need to intercept them.
    // The CI connections go through ci2hbm_in which feeds ci2hbmFIFO.
    // During Phase 4, we override ci2hbm_in.din and ci2hbm_in.wren.
    //
    // IMPORTANT: The CI should not send commands during Phase 4 because
    // the timestep is not yet complete (IEP is waiting for phase4_done).
    // So muxing is safe — no contention.
    
    // We need to intercept the CI's ci2hbm connection.
    // The CI currently drives ci2hbm_in directly. We'll add a wire-level mux.
    wire         ci_ci2hbm_wren;  // CI's original write enable
    
    // hbm2ci output: shared between CI and stdp_controller
    // During Phase 4, stdp_controller reads responses.
    // During normal operation, CI reads responses.
    wire [255:0] ci_hbm2ci_dout;
    wire         ci_hbm2ci_empty;
    wire         ci_hbm2ci_rden;
    
    stdp_controller stdp_ctrl (
        .clk(aclk),
        .resetn(aresetn),
        // STDP configuration
        .stdp_enable(w_stdp_enable),
        .A_plus(w_A_plus),
        .A_minus(w_A_minus),
        .w_max(w_w_max),
        .w_min(w_w_min),
        .neuromod_level(w_neuromod_level),
        // Spike address capture
        .spike_addr_in(w_stdp_spike_addr),
        .spike_addr_wr(w_stdp_spike_wr),
        // Phase 4 coordination
        .phase2_done(exec_hbm_rx_phase2_done_FF2_225M),
        .phase4_active(w_stdp_phase4_active),
        .phase4_done(w_stdp_phase4_done),
        // ci2hbm FIFO interface (muxed below)
        .p4_ci2hbm_din(p4_ci2hbm_din),
        .p4_ci2hbm_wren(p4_ci2hbm_wren),
        .p4_ci2hbm_full(ci2hbm_in.full),
        // hbm2ci FIFO interface (read responses)
        .p4_hbm2ci_dout(hbm2ci_out.dout),
        .p4_hbm2ci_empty(hbm2ci_out.empty),
        .p4_hbm2ci_rden(p4_hbm2ci_rden),
        // URAM read port
        .uram_raddr_phase4_flat(stdp_uram_raddr_flat),
        .uram_rden_phase4(stdp_uram_rden_w),
        .uram_rdata_phase4_flat({iep_uram[15].rdata, iep_uram[14].rdata, iep_uram[13].rdata, iep_uram[12].rdata,
                                  iep_uram[11].rdata, iep_uram[10].rdata, iep_uram[9].rdata,  iep_uram[8].rdata,
                                  iep_uram[7].rdata,  iep_uram[6].rdata,  iep_uram[5].rdata,  iep_uram[4].rdata,
                                  iep_uram[3].rdata,  iep_uram[2].rdata,  iep_uram[1].rdata,  iep_uram[0].rdata}),
        .axon_trace_rd_en(w_axon_trace_rd_en),
        .axon_trace_rd_idx(w_axon_trace_rd_idx),
        .axon_trace_rd_data(w_axon_trace_rd_data)
    );

    //=========================================================================
    // Eligibility traces for incoming axons.
    //
    // A presynaptic neuron on another core keeps its trace in that core's
    // memory, which this core cannot read.  Sending the trace inside the spike
    // packet does not help either: potentiation is evaluated when the
    // POSTsynaptic neuron fires, generally a later timestep, so a value
    // sampled at emission is already stale.
    //
    // This core receives every such spike -- that is how the synapse fires at
    // all -- so it rebuilds the trace itself.  Spikes from the NoC enter as
    // axon events exactly like host-injected ones, so one write port serves
    // both, and the mechanism extends unchanged to spikes from other devices.
    //=========================================================================
    // NUM_ROWS must cover the full 13-bit row address.  The EEP sweeps rows
    // 0-511 in microphase 0, 512-1023 in microphase 1, and so on, so a 512-row
    // memory would alias every microphase onto the first.
    axon_trace_mem #(.NUM_ROWS(8192)) u_axon_trace (
        .clk           (aclk),
        .resetn        (aresetn),
        .timestep      (axon_trace_timestep),
        .timestep_tick (exec_run),
        .row_fired     (w_axon_row_valid),
        .row_addr      (w_curr_bram_waddr),
        .row_mask      (exec_eep_spiked),
        .trace_rd_en   (w_axon_trace_rd_en),
        .trace_rd_idx  (w_axon_trace_rd_idx),
        .trace_rd_data (w_axon_trace_rd_data)
    );
    
    // ci2hbm input mux: stdp_controller during Phase 4, CI otherwise
    assign ci2hbm_in.din  = w_stdp_phase4_active ? p4_ci2hbm_din  : ci_ci2hbm_din;
    assign ci2hbm_in.wren = w_stdp_phase4_active ? p4_ci2hbm_wren : ci_ci2hbm_wren;
    
    // hbm2ci output mux: stdp_controller reads during Phase 4, CI otherwise
    assign hbm2ci_out.rden = w_stdp_phase4_active ? p4_hbm2ci_rden : ci_hbm2ci_rden;

    generate
        for(genvar j=0; j<16; j=j+1) begin
            URAM my_uram(iep_uram[j].Slave);
        end
    endgenerate
endmodule