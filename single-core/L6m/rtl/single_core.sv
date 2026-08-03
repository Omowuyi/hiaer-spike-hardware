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
    
    wire       exec_eep_phase1_ready;
    wire     [15:0] exec_eep_spiked;
    wire       exec_eep_phase1_done;
    wire       exec_uram_phase0_done;
    wire       exec_uram_phase1_done;
    wire       exec_uram_phase2_done;
    
    RAM #(16,13) eep_bram_0(.clk(aclk));
    RAM #(16,13) eep_bram_1(.clk(aclk));
    
    external_events_processor_simple #(
        .PIPE_DEPTH(3),
        .NOC_FIFO_DEPTH(512)
    ) eep (
        .resetn(aresetn),
        .clk(aclk),
        .num_inputs(num_inputs),
        .axonEvent_set(axonEvent_set),
        .axonEvent_addr(axonEvent_addr),
        .axonEvent_data(axonEvent_data),
        .exec_run(exec_run),
        .exec_eep_phase1_ready(exec_eep_phase1_ready),
        .exec_hbm_rvalidready(exec_hbm_rvalidready),
        .exec_eep_spiked(exec_eep_spiked),
        .exec_eep_phase1_done(exec_eep_phase1_done),
        .exec_uram_phase0_done(exec_uram_phase0_done),
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
        .curr_bram_waddr(curr_bram_waddr)
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

    FIFO_input #(17) spk_in [7:0] (.clk(aclk450), .reset(~aresetn450));
    FIFO_output #(17) spk_out [7:0] (.clk(aclk450), .reset(~aresetn450));
    
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
    
    FIFO_input #(17) spk2ci_in (.clk(aclk450), .reset(~aresetn450));
    FIFO_output #(17) spk2ci_out (.clk(aclk), .reset(~aresetn));

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
            FIFO_17 spkFIFIO(
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
        .ci2hbm_din(ci2hbm_in.din),
        .ci2hbm_wren(ci2hbm_in.wren),
        .hbm2ci_empty(hbm2ci_out.empty),
        .hbm2ci_dout(hbm2ci_out.dout),
        .hbm2ci_rden(hbm2ci_out.rden),

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
        .user_irq(user_irq),
        .error_status(error_status)
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
        .uram_raddr_0(iep_uram[0].raddr),
        .uram_raddr_1(iep_uram[1].raddr),
        .uram_raddr_2(iep_uram[2].raddr),
        .uram_raddr_3(iep_uram[3].raddr),
        .uram_raddr_4(iep_uram[4].raddr),
        .uram_raddr_5(iep_uram[5].raddr),
        .uram_raddr_6(iep_uram[6].raddr),
        .uram_raddr_7(iep_uram[7].raddr),
        .uram_raddr_8(iep_uram[8].raddr),
        .uram_raddr_9(iep_uram[9].raddr),
        .uram_raddr_10(iep_uram[10].raddr),
        .uram_raddr_11(iep_uram[11].raddr),
        .uram_raddr_12(iep_uram[12].raddr),
        .uram_raddr_13(iep_uram[13].raddr),
        .uram_raddr_14(iep_uram[14].raddr),
        .uram_raddr_15(iep_uram[15].raddr),
        .uram_rden_0(iep_uram[0].rden),
        .uram_rden_1(iep_uram[1].rden),
        .uram_rden_2(iep_uram[2].rden),
        .uram_rden_3(iep_uram[3].rden),
        .uram_rden_4(iep_uram[4].rden),
        .uram_rden_5(iep_uram[5].rden),
        .uram_rden_6(iep_uram[6].rden),
        .uram_rden_7(iep_uram[7].rden),
        .uram_rden_8(iep_uram[8].rden),
        .uram_rden_9(iep_uram[9].rden),
        .uram_rden_10(iep_uram[10].rden),
        .uram_rden_11(iep_uram[11].rden),
        .uram_rden_12(iep_uram[12].rden),
        .uram_rden_13(iep_uram[13].rden),
        .uram_rden_14(iep_uram[14].rden),
        .uram_rden_15(iep_uram[15].rden),
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
        .iep_uram_out_of_range(iep_uram_out_of_range_w)
    );

    FIFO_34 ci2iepFIFO(
        .i(ci2iep_in.Sink),
        .o(ci2iep_out.Source)
    );

    FIFO_33 iep2ciFIFO(
        .i(iep2ci_in.Sink),
        .o(iep2ci_out.Source)
    );

    sync_FIFO_17 spk2ciFIFO(
        .i(spk2ci_in.Sink),
        .o(spk2ci_out.Source)
    );
    
    generate
        for(genvar j=0; j<16; j=j+1) begin
            URAM my_uram(iep_uram[j].Slave);
        end
    endgenerate
endmodule