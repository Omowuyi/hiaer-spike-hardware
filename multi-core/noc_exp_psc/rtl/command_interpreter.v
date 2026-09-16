`timescale 1ns / 1ps

module command_interpreter #(
   parameter AXI_ADDR_BITS  = 32,
   parameter AXI_DATA_WIDTH = 32,
   parameter HBM_ADDR_BITS  = 33,
   parameter HBM_DATA_WIDTH = 256,
   parameter HBM_BYTE_COUNT = 32,
   parameter CORE_ID        = 0
   )(
   input aclk,
   input aresetn,
   
   // Global core parameters
  // input [16:0]            num_inputs,          // number of inputs/axons (Now moved to PCIe command)
   
   
   ////////////////////
   // PCIe interface //
   ////////////////////
   
   // RX FIFO (host->card)
   input                   rxFIFO_empty,
   input           [511:0] rxFIFO_dout,
   output reg              rxFIFO_rden,
   
   // TX FIFO (card->host)
   input                   txFIFO_full,
   output reg      [511:0] txFIFO_din,
   output reg              txFIFO_wren,
   
   
   //////////////////////////////////////
   // External events (axon) processor //
   //  Write axon event to future BRAM //
   //////////////////////////////////////
   
   output                  axonEvent_set,
   output reg       [12:0] axonEvent_addr,      // [13:0]=row address
   output            [15:0] axonEvent_data,      // [7:0]=data mask
   
   
   ////////////////////////////////////////////
   // HBM (synapse) processor                //
   //  Read/write pointers and synaptic data //
   ////////////////////////////////////////////
   
   input                   ci2hbm_full,
   output     [1+23+255:0] ci2hbm_din,          // [279]=r/w; [278:256]=row address; [255:0]=data
   output reg              ci2hbm_wren,
   input                   hbm2ci_empty,
   input           [255:0] hbm2ci_dout,         // [255:0]=data
   output reg              hbm2ci_rden,
   
   
   ////////////////////////////////////////
   // Internal events (neuron) processor //
   //  Read/write membrane potentials    // 
   ////////////////////////////////////////
   
   input                   ci2iep_full,
   output reg              ci2iep_wren,
   //output      [1+17+15:0] ci2iep_din,          // [33]=r/w; [32:16]=neuron address; [15:0]=data
   output      [1+17+35:0] ci2iep_din,          // [53]=r/w; [52:36]=neuron address; [35:0]=data
   input                   iep2ci_empty,
   output reg              iep2ci_rden,
   //input         [17+15:0] iep2ci_dout,         // [32:16]=neuron address; [15:0]=data
   input         [17+35:0] iep2ci_dout,         // [52:36]=neuron address; [15:0]=data
   
   /////////////////////////////////
   // Spike event FIFO            //
   //  Spike is sent out via PCIe //
   /////////////////////////////////
   
   input            [18:0] spk2ciFIFO_dout,     // [18:0]=spiked neuron address
   input                   spk2ciFIFO_empty,
   input                   spk2ciFIFO_full,      // Feature 2: needed for timeout detection
   output reg              spk2ciFIFO_rden,
   
   
   ///////////////////////
   // Network execution //
   ///////////////////////
   
   input             exec_iep_phase2_done,      // internal events (neuron) processor finished phase 2
   
   output reg        exec_run,                  // algorithm time step execution
   output reg        execRun_running,           // execution: actively running
   output reg        execRun_done,              // execution: finished running

   // Classifier remote destination table, written by CMD 16.  Until it is
   // loaded every block resolves to this device and nothing leaves over the
   // optical link -- the safe default for an unprogrammed device.
   output reg        fpga_id_valid,
   output reg  [2:0] fpga_id_data,
   output reg        remote_cfg_valid,
   output reg  [7:0] remote_cfg_addr,
   output reg  [5:0] remote_cfg_data,
   output reg [31:0] execRun_limit,             // execution: user-defined number of time steps (= number of input data samples)
   output reg [31:0] execRun_ctr,               // execution: time step counter
   output reg [63:0] execRun_timer,             // execution: FPGA clock cycle counter during execution ("timer")
   
   
   // Debugging   
   output [2:0] vio_rx_curr_state,
   output [3:0] vio_tx_curr_state,
   
   output reg [16:0] num_outputs,
   output reg [16:0] num_inputs,
   output reg signed [35:0] threshold, 
   output reg [1:0] exec_neuron_model,
   output reg [5:0] leak,
   output reg [5:0] shift,
   
   input exec_hbm_rvalidready,
   
   //Network_param_mem interface signals
   
   input [3:0] rd_addr_neuron_param_mem,
   output [83:0] dout_neuron_param_mem,
   
   // IEP watchdog and error inputs
   input        iep_watchdog_error,
   input        iep_uram_out_of_range,

   // NoC routing table programming for THIS core's router
   output reg        route_cfg_valid,
   output reg [9:0]  route_cfg_addr,
   output reg [5:0]  route_cfg_data,

   // A spike was discarded because its per-group FIFO was full.
   input        spk_dropped,

   // DIAG: which stage loses microphase-1 spikes
   input        dbg_spike_hi,   // 12: IEP detected a spike above row 512
   input        dbg_mp1_spike,  // 13: a spike >= 8192 reached a FIFO
   input        dbg_mp1_tx,     // 14: TX read microphase-1 output pointers
   input        dbg_mp1_rx,     // 15: RX finished Phase 1 in microphase 1
   
   // Feature 4: Interrupt output
   output reg user_irq,
   
   // Feature 3: Error status register
   output reg [31:0] error_status,
   
   //=========================================================================
   // EXP_PSC: Biological neuron model configuration outputs
   // delta_mode=1 (default): Legacy delta synapse mode (all tests pass unchanged)
   // delta_mode=0: Exponential PSC mode with dual tau, AdEx adaptation, STDP trace
   //=========================================================================
   output reg        delta_mode,           // 1=legacy delta, 0=exp PSC enabled
   output reg [11:0] decay_ex,             // I_ex/g_ex decay factor (fixed-point x 4096, e.g. 3354 for tau=0.5ms, dt=0.1ms)
   output reg [11:0] decay_in,             // I_in/g_in decay factor (fixed-point x 4096)
   output reg [7:0]  decay_w,              // Adaptation current decay factor (fixed-point x 256)
   output reg [7:0]  delta_w_param,        // Adaptation current increment on spike
   
   //=========================================================================
   // COBA: Conductance-based synapse mode
   // When coba_mode=0 (default): CUBA - I_ex/I_in are currents added directly to V
   // When coba_mode=1: COBA - g_ex/g_in are conductances, drive = g x (E_rev - V)
   // Requires delta_mode=0 to be active. Ignored when delta_mode=1.
   //=========================================================================
   output reg        coba_mode,            // 0=CUBA (current-based), 1=COBA (conductance-based)
   output reg signed [11:0] E_ex,          // Excitatory reversal potential (12-bit signed, ~0 mV biological)
   output reg signed [11:0] E_in,          // Inhibitory reversal potential (12-bit signed, ~-80 mV biological)
   
   //=========================================================================
   // NEUROMODULATION: Global per-core modulatory signals
   // neuromod_level: Scales STDP weight update magnitude (0=no learning, 255=full)
   //   Implements dopaminergic/cholinergic gating of plasticity for reward-modulated STDP.
   // neuromod_excitability_bias: Shifts firing threshold (signed, + = harder to fire)
   //   Implements cholinergic excitability modulation (ACh lowers threshold in biology).
   // Both default to 0 (no modulation effect).
   //=========================================================================
   output reg [7:0]         neuromod_level,           // STDP learning rate scale (0-255)
   output reg signed [7:0]  neuromod_excitability_bias, // Threshold shift (signed, subtracted from threshold)
   
   //=========================================================================
   // STDP: Weight update parameters for Phase 4 learning
   // stdp_enable=0 (default): Phase 4 skipped, no weight modification
   // stdp_enable=1: After Phase 2, scan spiking neurons, read-modify-write HBM weights
   //=========================================================================
   output reg               stdp_enable,              // Enable STDP Phase 4
   output reg [7:0]         A_plus,                   // Potentiation magnitude (post-spike weight increase)
   output reg [7:0]         A_minus,                  // Depression magnitude (pre-spike weight decrease)
   output reg signed [15:0] w_max,                    // Weight saturation upper bound (16-bit signed)
   output reg signed [15:0] w_min,                    // Weight saturation lower bound (16-bit signed)

   //=========================================================================
   // Phase-2 synapse entry width.  0 = 32-bit (default, today's behaviour),
   // 1 = 64-bit {op,dest,weight,delay,syn_type,stdp_tag,src}, which carries
   // per-synapse delay and the STDP source address.
   //=========================================================================
   output reg        syn_64bit_en,

   // Per-axon delay table programming (CMD 14) -> axon_delay_buffer
   output reg [12:0] delay_table_waddr,
   output reg [5:0]  delay_table_wdata,
   output reg        delay_table_wr
);



// Command list
wire [7:0] rx_command = rxFIFO_dout[511:504];

//=========================================================================
// NoC routing table write.  Single-cycle pulse with the fields held
// alongside it; noc_spike_router latches on route_cfg_valid.
//=========================================================================
always @(posedge aclk) begin
    if (~aresetn) begin
        route_cfg_valid <= 1'b0;
        route_cfg_addr  <= 10'd0;
        route_cfg_data  <= 6'd0;
    end else begin
        route_cfg_valid <= 1'b0;
        if (rx_curr_state == RX_STATE_IDLE && !rxFIFO_empty &&
            rx_command == CMD_ROUTE_TBL_W) begin
            route_cfg_addr  <= rxFIFO_dout[15:6];
            route_cfg_data  <= rxFIFO_dout[5:0];
            route_cfg_valid <= 1'b1;
        end
    end
end   // [511:504]= 8-bit command

localparam [7:0] CMD_EEP_W        = 8'd1;       // write single input data sample to future external events (axon) BRAM
localparam [7:0] CMD_HBM_RW       = 8'd2;       // read/write HBM (synapse) processor
localparam [7:0] CMD_IEP_RW       = 8'd3;       // read/write internal events (neuron) processor
localparam [7:0] CMD_NTWK_PARAM_W = 8'd4;       // Write Network parameters (Num_inputs, Num_outputs, Threshold, exec_neuron_model)
localparam [7:0] CMD_EXEC_STEP    = 8'd6;       // execute network time step
localparam [7:0] CMD_EXEC_CONT    = 8'd7;       // execute network continuously
localparam [7:0] CMD_NTWK_PARAM_MEM_W  = 8'd8;
// NoC routing table write, one entry per packet.  13 and 14 are taken
// by the PSC parameters and the axon delay table.
//   [13:6]=addr, [5:0]={level[1:0], mask[3:0]}
localparam [7:0] CMD_ROUTE_TBL_W = 8'd15;  // Write to network_params_sram
// CMD 16: one entry of the classifier's remote destination table.
//   [13:6] block index = spike_addr[16:9]   [5:3] dst_server   [2:0] dst_fpga
// Decides which DEVICE owns a 512-neuron block.  Distinct from CMD 15, which
// decides which CORES within this device receive a spike.
localparam [7:0] CMD_REMOTE_DST_W = 8'd16;
// Board identifier, so one bitstream serves every chassis position.
localparam [7:0] CMD_FPGA_ID_W    = 8'd17;
// Feature 2: FIFO timeout configuration
localparam [7:0] CMD_SET_TIMEOUT  = 8'd9;       // Set FIFO timeout value (cycles). 0=disabled.
// Feature 3: Error status read/clear
localparam [7:0] CMD_READ_STATUS  = 8'd10;      // Read error status register -> 0xFACE_FACE response
localparam [7:0] CMD_CLEAR_STATUS = 8'd11;      // Clear error status bits (bitmask in [31:0])
// Bulk DMA HBM write - start address in first packet, then stream data
localparam [7:0] CMD_DMA_HBM_W   = 8'd12;       // [278:256]=start row addr, [31:0]=num rows. Then stream data.
//=========================================================================
// EXP_PSC: New command for biological neuron model configuration
// Packet format:
//   [511:504] = opcode (8'd13)
//   [0]       = delta_mode (1=legacy, 0=exp PSC)
//   [12:1]    = decay_ex  (12-bit, fixed-point x 4096)
//   [24:13]   = decay_in  (12-bit, fixed-point x 4096)
//   [32:25]   = decay_w   (8-bit, fixed-point x 256)
//   [40:33]   = delta_w   (8-bit, adaptation increment on spike)
//   [41]      = coba_mode
//   [53:42]   = E_ex      (12-bit signed)
//   [65:54]   = E_in      (12-bit signed)
//   [73:66]   = neuromod_level (8-bit unsigned)
//   [81:74]   = neuromod_excitability_bias (8-bit signed)
//   [82]      = stdp_enable   (NEW: enable STDP Phase 4)
//   [90:83]   = A_plus        (NEW: 8-bit potentiation magnitude)
//   [98:91]   = A_minus       (NEW: 8-bit depression magnitude)
//   [114:99]  = w_max         (NEW: 16-bit signed max weight)
//   [130:115] = w_min         (NEW: 16-bit signed min weight)
//=========================================================================
localparam [7:0] CMD_SET_PSC_PARAMS = 8'd13;
// Per-axon delay table write.  [18:6]=axon addr, [5:0]=delay (0-63).
localparam [7:0] CMD_AXON_DELAY_W   = 8'd14;

// Read/write HBM (synapse) processor
// DMA bulk mode: auto-incrementing address with write-flag set
reg        dma_hbm_active;       // DMA bulk transfer in progress
reg [22:0] dma_hbm_addr;         // Auto-incrementing HBM row address
reg [31:0] dma_hbm_remaining;    // Rows remaining to transfer

// ci2hbm_din: [279]=R/W, [278:256]=23-bit row addr, [255:0]=256-bit data
// In DMA mode: R/W=1 (write), addr=auto-increment, data=lower 256 bits of rxFIFO
// In normal mode: pass through from rxFIFO as before
assign ci2hbm_din = dma_hbm_active ?
    {1'b1, dma_hbm_addr, rxFIFO_dout[255:0]} :
    rxFIFO_dout[1+23+255:0];


// Read/write internal events (neuron) processor
//assign ci2iep_din = rxFIFO_dout[1+17+15:0];     // [33]=r/w; [32:16]=neuron address; [15:0]=data
assign ci2iep_din = rxFIFO_dout[1+17+35:0];     // [53]=r/w; [52:36]=neuron address; [35:0]=data

// Register execution signals
//  -Execution counter and counter limit
//  -Execution status flags ('running' and 'done')
//  -Execution timer/counter
reg exec_run_rst;                               // reset execution counter and timer; also used for registering execution limit
reg exec_run_set;                               // set execution counter limit
reg exec_run_inc;                               // increment execution counter 
reg exec_run_done;                              // indicates execution has finished

always @(posedge aclk) begin
   if (!aresetn | (exec_run_rst & !exec_run_set))
      execRun_limit <= 32'd0;
   else if (exec_run_set)
      execRun_limit <= rxFIFO_dout[31:0];

   if (!aresetn | exec_run_rst)
      execRun_ctr <= 32'd0;
   else if (exec_run_inc)
      execRun_ctr <= execRun_ctr + 1'b1;
      
   if (!aresetn | exec_run_rst)
      execRun_timer <= 64'd0;
   else if (execRun_running)
      execRun_timer <= execRun_timer + 1'b1;
      
   if (!aresetn) begin
      execRun_running <= 1'b0;
      execRun_done    <= 1'b0;
   end else if (exec_run_rst) begin
      execRun_running <= 1'b1;
      execRun_done    <= 1'b0;
   end else if (exec_run_done) begin
      execRun_running <= 1'b0;
      execRun_done    <= 1'b1;
   end
end   


// Register axon data and address during loading of input data sample
//  Shift register PCIe data and use lower 8 bits for axon event data 
reg [511:0] axon_data_sr;                       // shift register for incoming 512-bit PCIe data packet
reg         axon_data_set;                      // register PCIe data packet into shift register
reg         axon_addr_rst;                      // reset 'axonEvent_addr'
reg         axon_addr_inc;                      // set axon event, shift axon data, and increment axon address

//wire [13:0] axon_addr_limit = num_inputs[16:3]; // 8 axons per axon row address -> ignore lower 3 bits of number of inputs
// FIX: When num_inputs is an exact multiple of 16 (lower 4 bits = 0), subtract 1 from limit.
// Without this, for 256 axons: limit=16, but at addr=15 the packet-fetch (addr[3:0]==4'd15) 
// fires before limit check (addr==16), causing the RX SM to hang waiting for a packet 
// the host never sends. With the fix: limit=15, so limit check fires at addr=15 first.
wire [12:0] axon_addr_limit = (num_inputs[3:0] == 4'd0) ? 
                               (num_inputs[16:4] - 13'd1) : num_inputs[16:4];
// Shift axon data and increment axon address
always @(posedge aclk) begin
   if (!aresetn | axon_addr_rst) begin
      axonEvent_addr <= 13'd0; //Previously 14'd0
      axon_data_sr   <= 512'd0;
   end else if (axon_data_set)
      axon_data_sr   <= rxFIFO_dout;
   else if (axon_addr_inc) begin
      axonEvent_addr <= axonEvent_addr + 1'b1;
      axon_data_sr   <= {16'd0, axon_data_sr[511:16]}; //Previously axon_data_sr   <= {8'd0, axon_data_sr[511:8]};
   end
end

// Set/send axon event at every axon address increment
assign axonEvent_set  = axon_addr_inc;
assign axonEvent_data = axon_data_sr[15:0];      // current axon data = LSB of shift register (previously [7:0])

//=========================================================================
// DMA Bulk HBM Write - address auto-increment and row counter
// CMD_DMA_HBM_W packet: [278:256]=start row addr, [31:0]=number of rows
// Then host streams N consecutive 512-bit packets, each carrying 256 bits
// of data in [255:0]. The CI writes each to HBM at auto-incrementing addr.
//=========================================================================
always @(posedge aclk) begin
    if (!aresetn) begin
        dma_hbm_active <= 1'b0;
        dma_hbm_addr <= 23'd0;
        dma_hbm_remaining <= 32'd0;
    end else begin
        // Latch start address and count when CMD_DMA_HBM_W is received
        if (rx_curr_state == RX_STATE_IDLE && !rxFIFO_empty && rx_command == CMD_DMA_HBM_W) begin
            dma_hbm_addr <= rxFIFO_dout[278:256];
            dma_hbm_remaining <= rxFIFO_dout[31:0];
            dma_hbm_active <= 1'b1;
        end
        // Auto-increment address and decrement count on each write
        else if (rx_curr_state == RX_STATE_DMA_HBM_WRITE && !rxFIFO_empty && ~ci2hbm_full && dma_hbm_remaining > 32'd0) begin
            dma_hbm_addr <= dma_hbm_addr + 23'd1;
            dma_hbm_remaining <= dma_hbm_remaining - 32'd1;
        end
        // Deactivate when done
        if (dma_hbm_remaining == 32'd0 && dma_hbm_active) begin
            dma_hbm_active <= 1'b0;
        end
    end
end



///////////////////////////////////
// RX (host->card) state machine //
///////////////////////////////////

reg [3:0] rx_curr_state, rx_next_state;

localparam [3:0] RX_STATE_RESET                   = 4'd0;
localparam [3:0] RX_STATE_IDLE                    = 4'd1;
localparam [3:0] RX_STATE_REGISTER_PCIE_AXON_DATA = 4'd2;
localparam [3:0] RX_STATE_SET_AXON_DATA           = 4'd3;
localparam [3:0] RX_STATE_EXEC_STEP               = 4'd4;
localparam [3:0] RX_STATE_WAIT_RUN                = 4'd5;
localparam [3:0] RX_STATE_EXEC_DONE               = 4'd6;
// NEW: Bulk DMA HBM write - streams consecutive 256-bit data to HBM
localparam [3:0] RX_STATE_DMA_HBM_WRITE           = 4'd7;

always @(posedge aclk)
   if (~aresetn) rx_curr_state <= RX_STATE_RESET;
   else          rx_curr_state <= rx_next_state;



reg network_params_wren, network_params_mem_wren;

reg [31:0] latency_ctr;
reg [31:0] hbm_access_ctr;

reg wea_neuron_param_mem;
reg [3:0] wr_addr_neuron_param_mem;
reg [83:0] din_neuron_param_mem;
//wire [83:0] dout_neuron_param_mem;

//Network params Mem
neuron_params_mem neuron_param
  (
    .clka(aclk),
    .clkb(aclk),
    .wea(wea_neuron_param_mem),
    .addra(wr_addr_neuron_param_mem),
    .addrb(rd_addr_neuron_param_mem),
    .dina(din_neuron_param_mem),
    .doutb(dout_neuron_param_mem)
  );


   
always @(posedge aclk) begin

    if (~aresetn) begin
        num_inputs <= 17'd0;
        num_outputs <= 17'd0;
        threshold <= 36'd0;
        exec_neuron_model <= 2'd0;
        latency_ctr <=32'b0;
        hbm_access_ctr <= 32'b0;
        wea_neuron_param_mem <= 1'b0;
        din_neuron_param_mem <= 84'b0;
        wr_addr_neuron_param_mem <= 4'b0;
        // EXP_PSC: defaults - legacy mode, all decay constants zero
        delta_mode <= 1'b1;
        decay_ex <= 12'd0;
        decay_in <= 12'd0;
        decay_w <= 8'd0;
        delta_w_param <= 8'd0;
        // COBA: defaults - current-based mode, reversal potentials zero
        coba_mode <= 1'b0;
        E_ex <= 12'sd0;
        E_in <= 12'sd0;
        // NEUROMODULATION: defaults - no modulation
        neuromod_level <= 8'd0;
        neuromod_excitability_bias <= 8'sd0;
        // STDP: defaults - disabled
        stdp_enable <= 1'b0;
        A_plus <= 8'd0;
        A_minus <= 8'd0;
        w_max <= 16'sd32767;   // max positive signed 16-bit
        w_min <= 16'sd0;       // floor at 0 (no negative weights by default)
        syn_64bit_en <= 1'b0;  // default: 32-bit entries
        delay_table_waddr <= 13'd0;
        delay_table_wdata <= 6'd0;
        delay_table_wr    <= 1'b0;
    end else if (network_params_wren) begin
        num_inputs <= rxFIFO_dout[16:0];            //17-bit NUM_INPUTs
        num_outputs <= rxFIFO_dout[33:17];         //17-bit NUM_OUTPUTs
        threshold <= rxFIFO_dout[69:34];           //36-bit Theshold
        exec_neuron_model <= rxFIFO_dout[71:70];   //2-bit Neuron Model
        shift <= rxFIFO_dout[77:72];  //6b shift parameter
        leak <= rxFIFO_dout[83:78];
        wr_addr_neuron_param_mem <= 4'b0;           // Reset param mem address for new network
    end else begin
        wea_neuron_param_mem <= network_params_mem_wren;
        if (network_params_mem_wren) din_neuron_param_mem <= rxFIFO_dout[83:0];
        if (wea_neuron_param_mem) wr_addr_neuron_param_mem <= wr_addr_neuron_param_mem + 1;
    end
    //=========================================================================
    // EXP_PSC + COBA + NEUROMOD: Capture all biological model parameters
    // from CMD_SET_PSC_PARAMS (opcode 13). Single-packet command.
    //
    // Packet format (rxFIFO_dout bit assignments):
    //   [0]      = delta_mode       (1=legacy, 0=exp PSC)
    //   [12:1]   = decay_ex         (12-bit, I_ex/g_ex decay factor x 4096)
    //   [24:13]  = decay_in         (12-bit, I_in/g_in decay factor x 4096)
    //   [32:25]  = decay_w          (8-bit, adaptation decay factor x 256)
    //   [40:33]  = delta_w          (8-bit, adaptation increment on spike)
    //   [41]     = coba_mode        (0=CUBA current-based, 1=COBA conductance-based)
    //   [53:42]  = E_ex             (12-bit signed, excitatory reversal potential)
    //   [65:54]  = E_in             (12-bit signed, inhibitory reversal potential)
    //   [73:66]  = neuromod_level   (8-bit unsigned, STDP learning rate scale 0-255)
    //   [81:74]  = neuromod_excitability_bias (8-bit signed, threshold shift)
    //
    // Typical values for PD model (CUBA, dt=0.1ms, tau_syn=0.5ms):
    //   delta_mode=0, decay_ex=3354, decay_in=3354, decay_w=255, delta_w=10
    //   coba_mode=0, E_ex=0, E_in=0, neuromod_level=0, neuromod_excitability_bias=0
    //
    // Typical values for Travelling Wave model (COBA, dt=0.1ms):
    //   delta_mode=0, decay_ex=3354, decay_in=3277 (tau_in=8ms GABA_A)
    //   coba_mode=1, E_ex=0 (0mV), E_in=-1310 (-80mV scaled)
    //   neuromod_level=128 (50% STDP rate), neuromod_excitability_bias=0
    //=========================================================================
    if (rx_curr_state == RX_STATE_IDLE && !rxFIFO_empty && rx_command == CMD_SET_PSC_PARAMS) begin
        delta_mode    <= rxFIFO_dout[0];
        decay_ex      <= rxFIFO_dout[12:1];
        decay_in      <= rxFIFO_dout[24:13];
        decay_w       <= rxFIFO_dout[32:25];
        delta_w_param <= rxFIFO_dout[40:33];
        // COBA parameters
        coba_mode     <= rxFIFO_dout[41];
        E_ex          <= rxFIFO_dout[53:42];
        E_in          <= rxFIFO_dout[65:54];
        // Neuromodulation parameters
        neuromod_level           <= rxFIFO_dout[73:66];
        neuromod_excitability_bias <= rxFIFO_dout[81:74];
        // STDP parameters (new fields in CMD 13 packet)
        //   [82]       = stdp_enable
        //   [90:83]    = A_plus  (8-bit potentiation magnitude)
        //   [98:91]    = A_minus (8-bit depression magnitude)
        //   [114:99]   = w_max   (16-bit signed max weight)
        //   [130:115]  = w_min   (16-bit signed min weight)
        stdp_enable <= rxFIFO_dout[82];
        A_plus      <= rxFIFO_dout[90:83];
        A_minus     <= rxFIFO_dout[98:91];
        w_max       <= rxFIFO_dout[114:99];
        w_min       <= rxFIFO_dout[130:115];
        syn_64bit_en <= rxFIFO_dout[131];   // [131] = 64-bit synapse format
    end
    // CMD 14: one axon delay table entry per packet.  Single-cycle pulse.
    delay_table_wr <= 1'b0;
    if (rx_curr_state == RX_STATE_IDLE && !rxFIFO_empty &&
        rx_command == CMD_AXON_DELAY_W) begin
        delay_table_waddr <= rxFIFO_dout[18:6];
        delay_table_wdata <= rxFIFO_dout[5:0];
        delay_table_wr    <= 1'b1;
    end
    if(rx_curr_state == RX_STATE_WAIT_RUN) begin
        latency_ctr <=latency_ctr+1;
        if(exec_hbm_rvalidready) hbm_access_ctr <= hbm_access_ctr+1;
    end
end

// Wait to ensure that spk2ciFIFO has been completely emptied after execution finished (and before moving to next time step)
//  Since simple round-robin is used, up to 8 clock cycles may occur before an intermediate spike FIFO
//   sends a spike to spk2ciFIFO. As a guarantee, we are using 15 clock cycles of no activity to ensure
//   all spikes have been transmitted (and be able to move to next time step) 
reg  [7:0] wait_clks_cnt;
wire [7:0] wait_clks_limit = 8'd255;



always @(posedge aclk) begin
    
   if ((rx_curr_state==RX_STATE_WAIT_RUN) & exec_iep_phase2_done & spk2ciFIFO_empty)
      wait_clks_cnt <= wait_clks_cnt + 1'b1;
   else
      wait_clks_cnt <= 8'd0;
end

//=========================================================================
// Feature 2: FIFO Timeout Counter (widened to 28 bits - max ~1.07s at 250MHz)
// When spk2ciFIFO is full during execution, count cycles. If timeout
// expires before FIFO clears, set error bit and trigger flush.
//=========================================================================
reg [27:0] fifo_timeout_value;   // Configurable timeout (0=disabled). Default 10ms @ 250MHz
reg [27:0] fifo_timeout_ctr;     // Current countdown
reg        fifo_timeout_expired; // Pulse: timeout fired
reg        fifo_flush_active;    // FIFO is being flushed

//=========================================================================
// Safeguard: ci2hbm FIFO timeout - detects HBM processor hang
//=========================================================================
reg [27:0] ci2hbm_timeout_ctr;
reg        ci2hbm_timeout_expired;

//=========================================================================
// Safeguard: ci2iep FIFO timeout - detects IEP stall
//=========================================================================
reg [27:0] ci2iep_timeout_ctr;
reg        ci2iep_timeout_expired;

//=========================================================================
// Safeguard: txFIFO timeout - detects host not reading DMA buffer
//=========================================================================
reg [27:0] txFIFO_timeout_ctr;
reg        txFIFO_timeout_expired;

always @(posedge aclk) begin
    if (!aresetn) begin
        fifo_timeout_value <= 28'd2_500_000; // Default 10ms @ 250MHz
        fifo_timeout_ctr <= 28'd0;
        fifo_timeout_expired <= 1'b0;
        fifo_flush_active <= 1'b0;
        ci2hbm_timeout_ctr <= 28'd0;
        ci2hbm_timeout_expired <= 1'b0;
        ci2iep_timeout_ctr <= 28'd0;
        ci2iep_timeout_expired <= 1'b0;
        txFIFO_timeout_ctr <= 28'd0;
        txFIFO_timeout_expired <= 1'b0;
    end else begin
        fifo_timeout_expired <= 1'b0;
        ci2hbm_timeout_expired <= 1'b0;
        ci2iep_timeout_expired <= 1'b0;
        txFIFO_timeout_expired <= 1'b0;
        
        // CMD_SET_TIMEOUT: configure timeout value (now 28-bit)
        if (rx_curr_state == RX_STATE_IDLE && !rxFIFO_empty && rx_command == CMD_SET_TIMEOUT) begin
            fifo_timeout_value <= rxFIFO_dout[27:0];
        end
        
        // spk2ciFIFO timeout
        if (execRun_running && spk2ciFIFO_full && fifo_timeout_value != 28'd0) begin
            if (fifo_timeout_ctr >= fifo_timeout_value) begin
                fifo_timeout_expired <= 1'b1;
                fifo_timeout_ctr <= 28'd0;
                fifo_flush_active <= 1'b1;
            end else begin
                fifo_timeout_ctr <= fifo_timeout_ctr + 1'b1;
            end
        end else begin
            fifo_timeout_ctr <= 28'd0;
            fifo_flush_active <= 1'b0;
        end
        
        // ci2hbm FIFO timeout - HBM processor hang detection
        if (execRun_running && ci2hbm_full && fifo_timeout_value != 28'd0) begin
            if (ci2hbm_timeout_ctr >= fifo_timeout_value) begin
                ci2hbm_timeout_expired <= 1'b1;
                ci2hbm_timeout_ctr <= 28'd0;
            end else begin
                ci2hbm_timeout_ctr <= ci2hbm_timeout_ctr + 1'b1;
            end
        end else begin
            ci2hbm_timeout_ctr <= 28'd0;
        end
        
        // ci2iep FIFO timeout - IEP stall detection
        if (execRun_running && ci2iep_full && fifo_timeout_value != 28'd0) begin
            if (ci2iep_timeout_ctr >= fifo_timeout_value) begin
                ci2iep_timeout_expired <= 1'b1;
                ci2iep_timeout_ctr <= 28'd0;
            end else begin
                ci2iep_timeout_ctr <= ci2iep_timeout_ctr + 1'b1;
            end
        end else begin
            ci2iep_timeout_ctr <= 28'd0;
        end
        
        // txFIFO timeout - host not reading DMA buffer
        if (execRun_running && txFIFO_full && fifo_timeout_value != 28'd0) begin
            if (txFIFO_timeout_ctr >= fifo_timeout_value) begin
                txFIFO_timeout_expired <= 1'b1;
                txFIFO_timeout_ctr <= 28'd0;
            end else begin
                txFIFO_timeout_ctr <= txFIFO_timeout_ctr + 1'b1;
            end
        end else begin
            txFIFO_timeout_ctr <= 28'd0;
        end
    end
end

//=========================================================================
// Feature 3: Error Status Register (32-bit, sticky bits)
// Bit 0:  spk2ciFIFO overflow
// Bit 1:  ci2iep FIFO overflow
// Bit 2:  ci2hbm FIFO overflow
// Bit 3:  HBM read timeout (IEP watchdog - state machine hung)
// Bit 4:  IEP phase hang (IEP watchdog fired)
// Bit 5:  spk2ciFIFO flush occurred (from timeout)
// Bit 6:  ci2hbm FIFO timeout (HBM processor stall)
// Bit 7:  URAM address out of range
// Bit 8:  ci2iep FIFO timeout (IEP stall)
// Bit 9:  txFIFO timeout (host not reading DMA)
// Bit 10: interrupt_asserted (informational)
//=========================================================================
reg status_read_req;   // Pulse from RX SM to send status packet
reg status_clear_req;  // Pulse from RX SM to clear status bits
reg [31:0] status_clear_mask;

always @(posedge aclk) begin
    if (!aresetn) begin
        error_status <= 32'd0;
    end else begin
        // Sticky error bit setting
        if (execRun_running && spk2ciFIFO_full)
            error_status[0] <= 1'b1;  // spk2ciFIFO overflow
        if (ci2iep_full && ci2iep_wren)
            error_status[1] <= 1'b1;  // ci2iep overflow attempt
        if (ci2hbm_full && ci2hbm_wren)
            error_status[2] <= 1'b1;  // ci2hbm overflow attempt
        if (iep_watchdog_error)
            error_status[3] <= 1'b1;  // IEP watchdog - HBM response hang
        if (iep_watchdog_error)
            error_status[4] <= 1'b1;  // IEP phase hang (same source, separate bit for clarity)
        if (fifo_timeout_expired)
            error_status[5] <= 1'b1;  // spk2ciFIFO flush occurred
        if (ci2hbm_timeout_expired)
            error_status[6] <= 1'b1;  // ci2hbm FIFO timeout - HBM processor stall
        if (iep_uram_out_of_range)
            error_status[7] <= 1'b1;  // URAM address out of range
        if (ci2iep_timeout_expired)
            error_status[8] <= 1'b1;  // ci2iep FIFO timeout - IEP stall
        if (txFIFO_timeout_expired)
            error_status[9] <= 1'b1;  // txFIFO timeout - host not reading
        if (user_irq)
            error_status[10] <= 1'b1; // interrupt was asserted (informational)
        if (spk_dropped)
            error_status[11] <= 1'b1; // spike discarded, per-group FIFO full
        if (dbg_spike_hi)  error_status[12] <= 1'b1;
        if (dbg_mp1_spike) error_status[13] <= 1'b1;
        if (dbg_mp1_tx)    error_status[14] <= 1'b1;
        if (dbg_mp1_rx)    error_status[15] <= 1'b1;
            
        // Clear bits via CMD_CLEAR_STATUS
        if (status_clear_req)
            error_status <= error_status & ~status_clear_mask;
    end
end

//=========================================================================
// Feature 4: Interrupt - asserted on exec_done or any error
//=========================================================================
always @(posedge aclk) begin
    if (!aresetn)
        user_irq <= 1'b0;
    else
        user_irq <= exec_run_done | (|error_status[9:0]);
end


// State machine
always @(*) begin
   
   rxFIFO_rden   = 1'b0;
   rx_next_state = rx_curr_state;
   
   // HBM (synapse) processor
   ci2hbm_wren = 1'b0;
   
   // Execution via PCIe
   exec_run_rst  = 1'b0;
   exec_run_set  = 1'b0;
   exec_run_inc  = 1'b0;
   exec_run      = 1'b0;
   exec_run_done = 1'b0;
   
   // External inputs (axon) processor
   axon_data_set = 1'b0;
   axon_addr_rst = 1'b0;
   axon_addr_inc = 1'b0;
   
   // Internal events (neuron) processor
   ci2iep_wren = 1'b0;
   
   network_params_wren = 1'b0;
   network_params_mem_wren = 1'b0;

   // Defaults for the CMD 16 write strobe.  addr and data are taken
   // combinationally from the packet, so the entry lands in the same cycle
   // the command is consumed and no holding register is needed.
   fpga_id_valid    = 1'b0;
   fpga_id_data     = rxFIFO_dout[2:0];
   remote_cfg_valid = 1'b0;
   remote_cfg_addr  = rxFIFO_dout[13:6];
   remote_cfg_data  = rxFIFO_dout[5:0];
   // Features 2,3: defaults for new control signals
   status_read_req = 1'b0;
   status_clear_req = 1'b0;
   status_clear_mask = 32'd0;
   case (rx_curr_state)
   
      RX_STATE_RESET: begin
         rx_next_state = RX_STATE_IDLE;
      end
      
      // Wait for rxFIFO data to be received
      RX_STATE_IDLE: begin
         if (!rxFIFO_empty) begin
         
            // Verify command (upper rxFIFO_dout byte)
            case (rx_command)
               // write single input data sample to external events (axon) processor
               CMD_EEP_W: begin
                  axon_addr_rst = 1'b1;   // reset 'axonEvent_addr'
                  rxFIFO_rden   = 1'b1;
                  rx_next_state = RX_STATE_REGISTER_PCIE_AXON_DATA;
               end 
               
               // read/write HBM data
               // Write one entry of the classifier's remote destination table.
               CMD_FPGA_ID_W: begin
                  fpga_id_valid = 1'b1;
                  rxFIFO_rden   = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               CMD_REMOTE_DST_W: begin
                  remote_cfg_valid = 1'b1;
                  rxFIFO_rden      = 1'b1;
                  rx_next_state    = RX_STATE_IDLE;
               end

               CMD_HBM_RW: begin
                  if (~ci2hbm_full) begin
                     ci2hbm_wren = 1'b1;
                     rxFIFO_rden = 1'b1;
                     rx_next_state = RX_STATE_IDLE;
                  end
               end
            
               // read/write neuron membrane potential
               CMD_IEP_RW: begin
                  if (~ci2iep_full) begin
                     ci2iep_wren = 1'b1;
                     rxFIFO_rden = 1'b1;
                     rx_next_state = RX_STATE_IDLE;
                  end
               end
              //Write Network Parameters
              CMD_NTWK_PARAM_W: begin
                  network_params_wren = 1'b1;
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
              end
               // execute algorithm time step (does NOT load any axon events)
               //  set execRun_limit=0
               CMD_EXEC_STEP: begin
                  axon_addr_rst = 1'b1;   // reset 'axonEvent_addr'
                  exec_run_rst  = 1'b1;   // reset 'execRun_ctr' and 'execRun_timer'
                  rxFIFO_rden   = 1'b1;
                  rx_next_state = RX_STATE_EXEC_STEP;
               end
               
               // continuously execute network via PCIe
               //  set execRun_limit=rxFIFO_dout[31:0]
               CMD_EXEC_CONT: begin
                  axon_addr_rst = 1'b1;   // reset 'axonEvent_addr'
                  exec_run_rst  = 1'b1;   // reset 'execRun_ctr' and 'execRun_timer'
                  exec_run_set  = 1'b1;   // set 'execRun_limit'
                  rxFIFO_rden   = 1'b1;
                  rx_next_state = RX_STATE_REGISTER_PCIE_AXON_DATA;
               end
               CMD_NTWK_PARAM_MEM_W: begin
                  network_params_mem_wren = 1'b1;
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               // Feature 2: Set FIFO timeout value
               CMD_SET_TIMEOUT: begin
                  // fifo_timeout_value is set in the sequential block above
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               // Feature 3: Read error status register
               CMD_READ_STATUS: begin
                  status_read_req = 1'b1;
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               // Feature 3: Clear error status bits
               CMD_CLEAR_STATUS: begin
                  status_clear_req = 1'b1;
                  status_clear_mask = rxFIFO_dout[31:0];
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               // Bulk DMA HBM write: first packet sets start addr + row count
               // Subsequent packets are pure 256-bit data streamed to consecutive HBM rows
               CMD_DMA_HBM_W: begin
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_DMA_HBM_WRITE;
               end
               //=========================================================================
               // EXP_PSC: Set biological neuron model parameters
               // Single-packet command, registers captured in sequential block above
               //=========================================================================
               CMD_SET_PSC_PARAMS: begin
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               // Per-axon delay table write; registers captured above.
               CMD_AXON_DELAY_W: begin
                  rxFIFO_rden = 1'b1;
                  rx_next_state = RX_STATE_IDLE;
               end
               default: begin
                  rx_next_state = rx_curr_state;
               end
            endcase
         end
      end
      
      // Register 'axon_data_sr'
      RX_STATE_REGISTER_PCIE_AXON_DATA: begin
         if (!rxFIFO_empty) begin
            axon_data_set = 1'b1;
            rxFIFO_rden   = 1'b1;
            rx_next_state = RX_STATE_SET_AXON_DATA;
         end
      end
      
      // Set axon event, shift axon data, and increment axon address
      //  if reached axon address limit
      //    if not executing network -> done
      //    else -> wait for network execution
      //  else, if reached 64 x 8-bit axon events -> fetch next PCIe packet
      RX_STATE_SET_AXON_DATA: begin
         axon_addr_inc = 1'b1;

         if (axonEvent_addr==axon_addr_limit) begin  //-1 added to fix the corner cases where the core was waiting for 2 axon packets when num_inputs was 256, axon_addr_limit=16, we need to stop set_axon when axonEvent_addr = 15
            if (!execRun_running) rx_next_state = RX_STATE_IDLE;
            else                  rx_next_state = RX_STATE_EXEC_STEP;

         end else if (axonEvent_addr[3:0]==4'd15) //(For 256-b packets) //Previously axonEvent_addr[5:0]==6'd63 for 8 Neuron Groups (and 512b packets), Previously axonEvent_addr[5:0]==5'd31 for 16 Neuron Groups (512b packets), 
            rx_next_state = RX_STATE_REGISTER_PCIE_AXON_DATA;
      end
      
      // Execute algorithm time step
      RX_STATE_EXEC_STEP: begin
         exec_run = 1'b1;
         rx_next_state = RX_STATE_WAIT_RUN;
      end
      
      // Execute algorithm time step (after previous time step has been completed)
      //  if 'wait_clks_cnt' reached limit (i.e. internal events processor done and spk2ciFIFO empty for 15 clock cycles)
      //    -if reached execution counter limit -> done
      //    -else -> increment execution counter, restart axon address, and fetch new input data sample from PCIe
      RX_STATE_WAIT_RUN: begin
         
          if (execRun_ctr==execRun_limit) begin
            if (wait_clks_cnt==wait_clks_limit) rx_next_state = RX_STATE_EXEC_DONE;
          end else if (!rxFIFO_empty && wait_clks_cnt>=wait_clks_limit) begin  //Wait until atleast new timestep spikes are available and enough wait after the prev exec_run
                    exec_run_inc  = 1'b1;      // increment 'execRun_ctr' 
                    axon_addr_rst = 1'b1;      // reset 'axonEvent_addr'
                    rx_next_state = RX_STATE_REGISTER_PCIE_AXON_DATA;
           end
      end
      
      // Stop 'execRun_timer' and set 'execRun_done' flag
      RX_STATE_EXEC_DONE: begin
         exec_run_done = 1'b1;
         rx_next_state = RX_STATE_IDLE;
      end
      
      // Bulk DMA HBM write: stream consecutive 256-bit data packets to HBM
      // Each 512-bit rxFIFO packet contains 256 bits of data in [255:0].
      // Address auto-increments. Transfer completes when dma_hbm_remaining reaches 0.
      RX_STATE_DMA_HBM_WRITE: begin
         if (dma_hbm_remaining == 32'd0) begin
            // Transfer complete
            rx_next_state = RX_STATE_IDLE;
         end else if (!rxFIFO_empty && ~ci2hbm_full) begin
            ci2hbm_wren = 1'b1;
            rxFIFO_rden = 1'b1;
            // dma_hbm_addr and dma_hbm_remaining updated in sequential block
         end
      end
      
      default: begin
         rx_next_state = rx_curr_state;
      end
   endcase
end


// Register spike events from 'spk2ciFIFO'
//  Shift register used for grouping spikes in batches of 14
reg [447:0] spike_sr;                        // shift register for incoming spike event
reg         spike_rst, spike_inc;            // reset,increment spike counter
reg   [3:0] spike_ctr;                       // spike event counter (number of received spikes)
wire  [3:0] spike_limit = 4'd14;             // 1 spike = 32 bits (8-bit sub-timestamp + 7-bit zero-padding + 17-bit neuron address)
                                             // 512-bit PCIe data packet -> 32-bit opcode + 14 x 32-bit spikes + 32-bit timestamp ('execRun_ctr')
reg         spikes_sent;                     // indicates if last packet of spikes has already been sent

always @(posedge aclk) begin
   if (!aresetn | spike_rst) begin
      spike_ctr   <= 4'd0;
      spike_sr    <= 448'd0;
      spikes_sent <= 1'b1;             // set flag upon writing packet of spikes to txFIFO
   end else if (spike_inc) begin
      spike_ctr   <= spike_ctr + 1'b1;
      // CORE_ID[3:0] now sits at [22:19] and the address occupies [18:0].
      // The two bits formerly reserved at [22:21] are part of the address.
      spike_sr    <= {execRun_ctr[7:0], 1'b1, CORE_ID[3:0], spk2ciFIFO_dout, spike_sr[447:32]};
      spikes_sent <= 1'b0;             // any new received spike clears the flag
   end 
end


///////////////////////////////////
// TX (card->host) state machine //
///////////////////////////////////

reg [3:0] tx_curr_state, tx_next_state;
reg [511:0] held_mp_data;  // Holds 0xCCCC MP response for continuous retransmission
reg execution_started;  // Prevents HOLD_MP before first exec completes

localparam [3:0] TX_STATE_RESET               = 4'd0;
localparam [3:0] TX_STATE_IDLE                = 4'd1;
localparam [3:0] TX_STATE_WAIT_FOR_SPIKES     = 4'd2;
localparam [3:0] TX_STATE_SEND_SPIKES         = 4'd3;
localparam [3:0] TX_STATE_SEND_LATENCY_CNT    = 4'd4;
localparam [3:0] TX_STATE_SEND_HBM_ACCESS_CNT = 4'd5;
// Feature 3: New TX states for status and error reporting
localparam [3:0] TX_STATE_SEND_STATUS         = 4'd6;
localparam [3:0] TX_STATE_SEND_ERROR          = 4'd7;
localparam [3:0] TX_STATE_HOLD_MP             = 4'd8;  // Hold MP response until next command
                                                       // NOTE: now UNREACHABLE - see TX_STATE_IDLE below

always @(posedge aclk)
   if (!aresetn) begin
      tx_curr_state <= TX_STATE_RESET;
      held_mp_data <= 512'd0;
      execution_started <= 1'b0;
   end else begin
      tx_curr_state <= tx_next_state;
      if (exec_run_done) execution_started <= 1'b1;
      // Capture MP data when transitioning to HOLD_MP
      if (tx_curr_state == TX_STATE_IDLE && !iep2ci_empty && !txFIFO_full && !execRun_running)
         held_mp_data <= {16'hCCCC, 443'd0, iep2ci_dout};
      else if (tx_curr_state == TX_STATE_HOLD_MP && !iep2ci_empty)
         held_mp_data <= {16'hCCCC, 443'd0, iep2ci_dout};
   end


// State machine
always @(*) begin
   
   txFIFO_din  = 512'dX;
   txFIFO_wren = 1'b0;
   tx_next_state = tx_curr_state;
   
   // Output spike events
   spike_rst = 1'b0;
   spike_inc = 1'b0;
   
   // Spike FIFO read enable (default: not reading)
   spk2ciFIFO_rden = 1'b0;
   
   // HBM (synapse) processor
   hbm2ci_rden = 1'b0;
   
   // Internal events (neuron) processor
   iep2ci_rden = 1'b0;
   
   case (tx_curr_state)
   
      TX_STATE_RESET: begin
         tx_next_state = TX_STATE_IDLE;
      end
      
      // Verify execution state and outgoing FIFOs
      //  if error/status responses pending -> handle first
      //  if executing network -> wait for spikes 
      //  else -> verify if FIFOs are not empty
      TX_STATE_IDLE: begin
         // Send error packet on any timeout event
         if (fifo_timeout_expired || ci2hbm_timeout_expired || ci2iep_timeout_expired || txFIFO_timeout_expired) begin
            tx_next_state = TX_STATE_SEND_ERROR;
         // Send status response on CMD_READ_STATUS
         end else if (status_read_req) begin
            tx_next_state = TX_STATE_SEND_STATUS;
         end else if (execRun_running) begin
            spike_rst = 1'b1;
            tx_next_state = TX_STATE_WAIT_FOR_SPIKES;
         
         end else begin
            // Drain any stale spikes from previous execution (only when NOT running)
            if (!spk2ciFIFO_empty) begin
               spk2ciFIFO_rden = 1'b1;  // Discard stale spike data
            end
            
            if (!txFIFO_full) begin
               // HBM data
               if (!hbm2ci_empty) begin
                  txFIFO_din  = {16'hBBBB, 240'd0, hbm2ci_dout};
                  txFIFO_wren = 1'b1;
                  hbm2ci_rden = 1'b1;
               // neuron membrane potential - send once then hold
               end else if (!iep2ci_empty) begin
                  txFIFO_din  = {16'hCCCC, 443'd0, iep2ci_dout};
                  txFIFO_wren = 1'b1;
                  iep2ci_rden = 1'b1;
                  // HOLD_MP DISABLED: TX_STATE_HOLD_MP rewrites held_mp_data into
                  // txFIFO on every cycle the FIFO is not full.  The FPGA refills
                  // faster than the host drains, and readSelect() breaks on the
                  // FIRST 0xCCCC packet it finds, so it always gets a frozen stale
                  // packet.  Measured on hardware: in exp_psc mode
                  // readMP([0,16,32,48]) returned n0 for all four requests, in all
                  // three access patterns; delta_mode returned 0,16,32,48 correctly.
                  // Removing this transition makes TX_STATE_HOLD_MP unreachable, so
                  // exp_psc uses the same TX path as delta mode.
                  // if (execution_started && !delta_mode) tx_next_state = TX_STATE_HOLD_MP;
               end
            end
         end
      end

      // Verify if network is still running and if sufficient spikes have been received to send to PCIe
      //  if execution done ->
      //   -if spikes have already been sent (with no new spikes received since then) -> done
      //   -else -> send last packet of spikes
      //  else, if number of spikes reached packet limit (=14) -> send packet of spikes
      //  else, if spike FIFO not empty -> read FIFO data into 'spike_sr'
      TX_STATE_WAIT_FOR_SPIKES: begin
         if (execRun_done && spk2ciFIFO_empty) begin  //Don't finish sending spikes until entire spikeFIFO is empty.
            //if (spikes_sent) tx_next_state = TX_STATE_IDLE;
            //else             tx_next_state = TX_STATE_SEND_SPIKES;
            tx_next_state = TX_STATE_SEND_SPIKES;
            
         end else if (spike_ctr==spike_limit)
            tx_next_state = TX_STATE_SEND_SPIKES;
            
         else if (!spk2ciFIFO_empty) begin
            spike_inc       = 1'b1;
            spk2ciFIFO_rden = 1'b1;
         end
      end
      
      // Send opcode + 14 spikes + timestamp in 512-bit PCIe packet 
      TX_STATE_SEND_SPIKES: begin
         if (!txFIFO_full) begin
            if (execRun_done && spk2ciFIFO_empty) begin
                txFIFO_din  = {32'hABCD_ABCD, spike_sr, execRun_ctr}; //Send ExecDone Flag and return to IDLE state
                txFIFO_wren = 1'b1;
                spike_rst   = 1'b1;
                tx_next_state = TX_STATE_SEND_LATENCY_CNT;
            end else begin
                txFIFO_din  = {32'hEEEE_EEEE, spike_sr, execRun_ctr};
                txFIFO_wren = 1'b1;
                spike_rst   = 1'b1;
                tx_next_state = TX_STATE_WAIT_FOR_SPIKES;
             end
         end
      end
      TX_STATE_SEND_LATENCY_CNT: begin
            txFIFO_din  = {32'hBABA_BABA, 448'b0, latency_ctr}; //Send ExecDone Flag and return to IDLE state
            txFIFO_wren = 1'b1;
            spike_rst   = 1'b1;
            tx_next_state = TX_STATE_SEND_HBM_ACCESS_CNT;
      end
      TX_STATE_SEND_HBM_ACCESS_CNT: begin
            txFIFO_din  = {32'hCABA_CABA, 448'b0, hbm_access_ctr}; //Send ExecDone Flag and return to IDLE state
            txFIFO_wren = 1'b1;
            spike_rst   = 1'b1;
            tx_next_state = TX_STATE_IDLE;
      end

      // Hold MP response: continuously write 0xCCCC to txFIFO so
      // readSelect always finds it in the DMA ring buffer.
      // Exit when: new execution starts, new command arrives, or
      // another iep2ci/hbm2ci response needs to be sent.
      //
      // RETAINED BUT UNREACHABLE: the only transition into this state has been
      // removed in TX_STATE_IDLE above.  Synthesis will optimise this away and
      // report held_mp_data / execution_started as unused.  Left in place so the
      // diff stays minimal and the history is visible.
      TX_STATE_HOLD_MP: begin
         if (execRun_running) begin
            // New step starting - stop holding, go to spike processing
            spike_rst = 1'b1;
            tx_next_state = TX_STATE_WAIT_FOR_SPIKES;
         end else if (fifo_timeout_expired || ci2hbm_timeout_expired || ci2iep_timeout_expired || txFIFO_timeout_expired) begin
            tx_next_state = TX_STATE_SEND_ERROR;
         end else if (status_read_req) begin
            tx_next_state = TX_STATE_SEND_STATUS;
         end else if (!iep2ci_empty) begin
            // New MP read response - send it and stay in hold
            txFIFO_din  = {16'hCCCC, 443'd0, iep2ci_dout};
            txFIFO_wren = 1'b1;
            iep2ci_rden = 1'b1;
         end else if (!hbm2ci_empty) begin
            // HBM response - send it and return to idle
            txFIFO_din  = {16'hBBBB, 240'd0, hbm2ci_dout};
            txFIFO_wren = 1'b1;
            hbm2ci_rden = 1'b1;
            tx_next_state = TX_STATE_IDLE;
         end else if (!txFIFO_full) begin
            // No new data - resend the held MP response
            txFIFO_din  = held_mp_data;
            txFIFO_wren = 1'b1;
         end
      end
      // Send error packet (0xDEAD_DEAD) - includes full error_status for diagnostics
      TX_STATE_SEND_ERROR: begin
         if (!txFIFO_full) begin
            txFIFO_din  = {32'hDEAD_DEAD, error_status[7:0], error_status, 408'd0, execRun_ctr};
            txFIFO_wren = 1'b1;
            tx_next_state = TX_STATE_IDLE;
         end
      end
      // Feature 3: Send status response (0xFACE_FACE)
      TX_STATE_SEND_STATUS: begin
         if (!txFIFO_full) begin
            txFIFO_din  = {32'hFACE_FACE, error_status, 416'd0, execRun_ctr};
            txFIFO_wren = 1'b1;
            tx_next_state = TX_STATE_IDLE;
         end
      end
      default: begin
         tx_next_state = tx_curr_state;
      end
   endcase
end


// Debugging
assign vio_rx_curr_state = rx_curr_state;
assign vio_tx_curr_state = tx_next_state;



endmodule