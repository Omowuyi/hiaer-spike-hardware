`timescale 1ns / 1ps
/*
Clocks:
refclk45 - free running 450MHz reference clock which is used to derive other clocks
pcie_clk_in - free running 100MHz clock for PCIe, required for PCIe DMA
apb_clk - 100MHz clock derived from refclk450, used for 
aclk - 150MHz derived clock that runs the core logic, hopefully will be increased to >300MHz
pcie_axi_clk - 250MHz clock created by PCIe endpoint which must drive all logic directly connected to PCIe DMA

*/
module sixteen_core_top(
    input orig_clk_p,
    input orig_clk_n,
//    output dbg_clk,
    input sys_rst_n,
    
    output [7:0] pci_exp_txp,
    output [7:0] pci_exp_txn,
    input [7:0] pci_exp_rxp,
    input [7:0] pci_exp_rxn,
    
//    output Si5328_input_1_clk_p,
//    output Si5328_input_1_clk_n,
//    output Si5328_input_2_clk_p,
//    output Si5328_input_2_clk_n,
/*    
    input [0:3]GT_SERIAL_RX_AUR_0_rxn,
    input [0:3]GT_SERIAL_RX_AUR_0_rxp,
    output [0:3]GT_SERIAL_TX_AUR_0_txn,
    output [0:3]GT_SERIAL_TX_AUR_0_txp,
    
    input [0:3]GT_SERIAL_RX_AUR_1_rxn,
    input [0:3]GT_SERIAL_RX_AUR_1_rxp,
    output [0:3]GT_SERIAL_TX_AUR_1_txn,
    output [0:3]GT_SERIAL_TX_AUR_1_txp,
    
    input GT_DIFF_REFCLK1_0_clk_n,
    input GT_DIFF_REFCLK1_0_clk_p,
    input GT_DIFF_REFCLK1_1_clk_n,
    input GT_DIFF_REFCLK1_1_clk_p,
*/    
    input [0:0]pcie_clk_in_clk_n,
    input [0:0]pcie_clk_in_clk_p,
    
    input refclk450_p,
    input refclk450_n
    );
    genvar j;
    
    wire [0:0]pcie_clk_gt;
    wire [0:0]pcie_clk_out;
    
    wire pcie_axi_clk;
    wire pcie_axi_aresetn;
    
    wire aclk;
    wire aclk450;
    wire apb_clk;
    wire refclk450;
    
   
    
//    wire aresetn_out;
//    reg aresetn_pipeline [1:0];
//    reg not_aresetn;
    wire async_resetn;
    wire aresetn;
    
    
    wire [31:0] APB_0_PWDATA;
    assign APB_0_PWDATA = 32'b0;
    wire [21:0] APB_0_PADDR;
    assign APB_0_PADDR = 22'b0;
    wire APB_0_PCLK;
    assign APB_0_PCLK = apb_clk;
    wire APB_0_PENABLE;
    assign APB_0_PENABLE = 1'b0;
    //wire APB_0_PRESET_N;
    //assign APB_0_PRESET_N = 1'b1;
    wire APB_0_PSEL;
    assign APB_0_PSEL = 1'b0;
    wire APB_0_PWRITE;
    assign APB_0_PWRITE = 1'b0;
    
    wire [31:0] APB_1_PWDATA;
    assign APB_1_PWDATA = 32'b0;
    wire [21:0] APB_1_PADDR;
    assign APB_1_PADDR = 22'b0;
    wire APB_1_PCLK;
    assign APB_1_PCLK = apb_clk;
    wire APB_1_PENABLE;
    assign APB_1_PENABLE = 1'b0;
    //wire APB_1_PRESET_N;
    //assign APB_1_PRESET_N = 1'b1;
    wire APB_1_PSEL;
    assign APB_1_PSEL = 1'b0;
    wire APB_1_PWRITE;
    assign APB_1_PWRITE = 1'b0;
    
    pulse_stretcher #( // make long reset pulses to send out over the board
        .ACTIVE("low"),
        .pulse_width(15)
    ) reset_stretcher (
        .clk(aclk),
        .pulse_in(pcie_axi_aresetn),
        .pulse_out(async_resetn)
    );
    
    reset_synchronizer #(
        .ACTIVE("low")
    ) top_reset_sync (
        .clk(aclk),
        .reset_in(pcie_axi_aresetn),
        .reset_out(aresetn)
    );
    wire APB_0_PRESET_N;
    reset_synchronizer #(
        .ACTIVE("low")
    ) apb_0_reset_sync (
        .clk(apb_clk),
        .reset_in(pcie_axi_aresetn),
        .reset_out(APB_0_PRESET_N)
    );
    wire APB_1_PRESET_N;
    reset_synchronizer #(
        .ACTIVE("low")
    ) apb_1_reset_sync (
        .clk(apb_clk),
        .reset_in(pcie_axi_aresetn),
        .reset_out(APB_1_PRESET_N)
    );
    reset_synchronizer #(
        .ACTIVE("low")
    ) reset_sync_450 (
        .clk(aclk450),
        .reset_in(pcie_axi_aresetn),
        .reset_out(aresetn450)
    );
    
/*    main_reset my_reset (
        .slowest_sync_clk(apb_clk),          // input wire slowest_sync_clk
        .ext_reset_in(sys_rst_n),                  // input wire ext_reset_in
        .aux_reset_in(0),                  // input wire aux_reset_in
        .mb_debug_sys_rst(0),          // input wire mb_debug_sys_rst
        .dcm_locked(0),                      // input wire dcm_locked
        .mb_reset(),                          // output wire mb_reset
        .bus_struct_reset(),          // output wire [0 : 0] bus_struct_reset
        .peripheral_reset(),          // output wire [0 : 0] peripheral_reset
        .interconnect_aresetn(),  // output wire [0 : 0] interconnect_aresetn
        .peripheral_aresetn(aresetn_out)      // output wire [0 : 0] peripheral_aresetn
    );

    always @(posedge aclk) begin
        aresetn_pipeline[1] <= aresetn_out;
        aresetn_pipeline[0] <= aresetn_pipeline[1];
        not_aresetn <= aresetn_pipeline[0];
    end
*/
    clock_and_buffer clock_and_buffer_i(
        .refclk450_clk_p(refclk450_p), //Previously refclk300_p
        .refclk450_clk_n(refclk450_n),  //Previously refclk300_n
        .aclk(aclk),
        .aclk450(aclk450), //Derived 450MHz Clock
        .apb_clk(apb_clk),
        .refclk450(refclk450), //Free Running 450MHz clock
        .pcie_clk_in_clk_n(pcie_clk_in_clk_n),
        .pcie_clk_in_clk_p(pcie_clk_in_clk_p),
        .pcie_clk_gt(pcie_clk_gt),
        .pcie_clk_out(pcie_clk_out)
    );
    
    assign dbg_clk = aclk;
    
    /*
    AXI4 #(33, 256) hbm [31:0] (.aclk(aclk450), .aresetn(aresetn450)); //Here HBM AXI interface running at 450MHz
    FIFO_input #(512) rxFIFO_in [31:0] (.clk(aclk), .reset(~aresetn));
    FIFO_output #(512) txFIFO_out [31:0] (.clk(aclk), .reset(~aresetn));
    
    AXIStream_simple #(512) to_rxFIFO_small (.aclk(pcie_axi_clk), .aresetn(pcie_axi_aresetn));
    AXIStream_simple #(512) to_rxFIFO (.aclk(aclk), .aresetn(aresetn)); //After synchronized to Core clock (from PCIE AXI clock using Async FIFO)
    AXIStream #(512, 5) to_rxFIFO_with_dest (.aclk(aclk), .aresetn(aresetn));
    AXIStream_simple #(512) after_switch [31:0] (.aclk(aclk), .aresetn(aresetn));
    pcie_tdest_generator tdest_gen(.s(to_rxFIFO), .m(to_rxFIFO_with_dest));
    
    AXIStream_simple #(512) before_switch [31:0] (.aclk(aclk), .aresetn(aresetn));
    AXIStream_simple #(512) from_txFIFO (.aclk(aclk), .aresetn(aresetn));
    AXIStream_simple #(512) from_txFIFO_small (.aclk(pcie_axi_clk), .aresetn(pcie_axi_aresetn));
    
   
    
    switch_1_32 s_1_32(
        .s(to_rxFIFO_with_dest),
        .m(after_switch)
    );
    
    switch_32_1 s_32_1(
        .s(before_switch),
        .m(from_txFIFO)
    );
    */
    
    //Modifications to check if single_core synthesis is clean
    
    AXI4 #(33, 256) hbm [32] ({32{aclk450}}, {32{aresetn450}}); //Here HBM AXI interface running at 450MHz
    FIFO_input #(512) rxFIFO_in [16] ({16{aclk}}, {16{~aresetn}});
    FIFO_output #(512) txFIFO_out [16] ({16{aclk}}, {16{~aresetn}});
    
    AXIStream_simple #(512) to_rxFIFO_small (.aclk(pcie_axi_clk), .aresetn(pcie_axi_aresetn));
    AXIStream_simple #(512) to_rxFIFO (.aclk(aclk), .aresetn(aresetn)); //After synchronized to Core clock (from PCIE AXI clock using Async FIFO)
    AXIStream #(512, 5) to_rxFIFO_with_dest (.aclk(aclk), .aresetn(aresetn));
    AXIStream_simple #(512) after_switch [16] ({16{aclk}}, {16{aresetn}});
    AXIStream_simple #(512) after_switch_regslice [16] ({16{aclk}}, {16{aresetn}});
    pcie_tdest_generator tdest_gen(.s(to_rxFIFO), .m(to_rxFIFO_with_dest));
    
    AXIStream_simple #(512) before_switch_regslice [16] ({16{aclk}}, {16{aresetn}});
    AXIStream_simple #(512) before_switch [16] ({16{aclk}}, {16{aresetn}});
    AXIStream_simple #(512) from_txFIFO (.aclk(aclk), .aresetn(aresetn));
    AXIStream_simple #(512) from_txFIFO_small (.aclk(pcie_axi_clk), .aresetn(pcie_axi_aresetn));
    
    
    /*
    switch_1_2 s_1_2(
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(to_rxFIFO_with_dest.tvalid),
        .s_axis_tdata(to_rxFIFO_with_dest.tdata),
        .s_axis_tdest(to_rxFIFO_with_dest.tdest),
        .s_axis_tready(to_rxFIFO_with_dest.tready),
        .m_axis_tvalid({after_switch[1].tvalid, after_switch[0].tvalid}),
        .m_axis_tdata({after_switch[1].tdata, after_switch[0].tdata}),
        .m_axis_tready({after_switch[1].tready, after_switch[0].tready}),
        .m_axis_tdest(),
        .s_decode_err()
    );
    */
    switch_1_16 out_switch(
                .aclk(aclk),
                .aresetn(aresetn),
                .s_axis_tvalid(to_rxFIFO_with_dest.tvalid),
                .s_axis_tdata(to_rxFIFO_with_dest.tdata),
                .s_axis_tdest(to_rxFIFO_with_dest.tdest),
                .s_axis_tready(to_rxFIFO_with_dest.tready),
                .m_axis_tvalid({after_switch[15].tvalid, after_switch[14].tvalid, after_switch[13].tvalid, after_switch[12].tvalid, after_switch[11].tvalid, after_switch[10].tvalid, after_switch[9].tvalid, after_switch[8].tvalid, after_switch[7].tvalid, after_switch[6].tvalid, after_switch[5].tvalid, after_switch[4].tvalid, after_switch[3].tvalid, after_switch[2].tvalid, after_switch[1].tvalid, after_switch[0].tvalid}),
                .m_axis_tdata({after_switch[15].tdata, after_switch[14].tdata, after_switch[13].tdata, after_switch[12].tdata, after_switch[11].tdata, after_switch[10].tdata, after_switch[9].tdata, after_switch[8].tdata, after_switch[7].tdata, after_switch[6].tdata, after_switch[5].tdata, after_switch[4].tdata, after_switch[3].tdata, after_switch[2].tdata, after_switch[1].tdata, after_switch[0].tdata}),
                .m_axis_tready({after_switch[15].tready, after_switch[14].tready, after_switch[13].tready, after_switch[12].tready, after_switch[11].tready, after_switch[10].tready, after_switch[9].tready, after_switch[8].tready, after_switch[7].tready, after_switch[6].tready, after_switch[5].tready, after_switch[4].tready, after_switch[3].tready, after_switch[2].tready, after_switch[1].tready, after_switch[0].tready}),
                .m_axis_tdest(),
                .s_decode_err()
            );
    /*
    switch_2_1 s_2_1(
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid({before_switch[1].tvalid, before_switch[0].tvalid}),
        .s_axis_tdata({before_switch[1].tdata, before_switch[0].tdata}),
        .s_axis_tready({before_switch[1].tready, before_switch[0].tready}),
        .m_axis_tvalid(from_txFIFO.tvalid),
        .m_axis_tdata(from_txFIFO.tdata),
        .m_axis_tready(from_txFIFO.tready),
        .s_req_suppress(2'b0),
        .s_decode_err()
    );
    */
    switch_16_1 in_switch(
                .aclk(aclk),
                .aresetn(aresetn),
                .s_axis_tvalid({before_switch[15].tvalid, before_switch[14].tvalid, before_switch[13].tvalid, before_switch[12].tvalid, before_switch[11].tvalid, before_switch[10].tvalid, before_switch[9].tvalid, before_switch[8].tvalid, before_switch[7].tvalid, before_switch[6].tvalid, before_switch[5].tvalid, before_switch[4].tvalid, before_switch[3].tvalid, before_switch[2].tvalid, before_switch[1].tvalid, before_switch[0].tvalid}),
                .s_axis_tdata({before_switch[15].tdata, before_switch[14].tdata, before_switch[13].tdata, before_switch[12].tdata, before_switch[11].tdata, before_switch[10].tdata, before_switch[9].tdata, before_switch[8].tdata, before_switch[7].tdata, before_switch[6].tdata, before_switch[5].tdata, before_switch[4].tdata, before_switch[3].tdata, before_switch[2].tdata, before_switch[1].tdata, before_switch[0].tdata}),
                .s_axis_tready({before_switch[15].tready, before_switch[14].tready, before_switch[13].tready, before_switch[12].tready, before_switch[11].tready, before_switch[10].tready, before_switch[9].tready, before_switch[8].tready, before_switch[7].tready, before_switch[6].tready, before_switch[5].tready, before_switch[4].tready, before_switch[3].tready, before_switch[2].tready, before_switch[1].tready, before_switch[0].tready}),
                .m_axis_tvalid(from_txFIFO.tvalid),
                .m_axis_tdata(from_txFIFO.tdata),
                .m_axis_tready(from_txFIFO.tready),
                .s_req_suppress(16'b0),
                .s_decode_err()
            );
   
    
    wire [16:0] num_outputs[0:31];
    wire [16:0] num_inputs[0:31];
    wire [35:0] threshold[0:31];
    wire [1:0] exec_neuron_model[0:31];
    wire exec_hbm_rvalidready[0:31];
    wire hbmFIFO_empty[0:31];
    wire [3:0] iep_curr_state[0:31];
    wire [3:0] hbm_curr_state[0:31];
    wire [2:0] eep_curr_state[0:31];
    wire exec_hbm_rx_phase2_done[0:31];
    wire exec_hbm_rx_phase1_done[0:31];
    wire  [12:0] curr_bram_waddr[0:31];
    wire  [12:0] curr_uram_waddr[0:31];
    wire  hbm2eep_rden[0:31];
    wire  hbm2iep_rden[0:31];
    wire  hbm2pfc_rden[0:31];
    wire  execRun_done[0:31];
    // NEW: Per-core interrupt wires, OR'd together for XDMA
    // Only core 0 exists - explicitly tie bits [15:1] to 0 to prevent floating inputs
    wire [15:0] user_irq_per_core;
    assign user_irq_per_core[15:1] = 15'b0;
    wire user_irq_core0 = |user_irq_per_core;  // Any core can trigger interrupt
    
    top_vio my_vio(
        .clk(aclk),
        .probe_in0(sys_rst_n),
        .probe_in1(APB_0_PRESET_N),
        .probe_in2(msix_enable),
        .probe_in3(user_lnk_up),
        .probe_in4(aresetn),
        .probe_in5(apb_clk),
        .probe_in6(pcie_axi_aresetn),
        .probe_in7(num_outputs[0]),
        .probe_in8(num_inputs[0]),
        .probe_in9(threshold[0]),
        .probe_in10(exec_neuron_model[0]),
        .probe_in11(exec_hbm_rvalidready[0]),
        .probe_in12(hbmFIFO_empty[0]),
        .probe_in13(iep_curr_state[0]),
        .probe_in14(hbm_curr_state[0]),
        .probe_in15(eep_curr_state[0]),
        .probe_in16(exec_hbm_rx_phase1_done[0]),
        .probe_in17(exec_hbm_rx_phase2_done[0]),
        .probe_in18(curr_bram_waddr[0]),
        .probe_in19(curr_uram_waddr[0]),
        .probe_in20(hbm2eep_rden[0]),
        .probe_in21(hbm2iep_rden[0]),
        .probe_in22(hbm2pfc_rden[0]),
        .probe_in23(to_rxFIFO_with_dest.tdata[255:0]),
        .probe_in24(to_rxFIFO_with_dest.tdata[511:256]),
        .probe_in25(to_rxFIFO_with_dest.tvalid),
        .probe_in26(to_rxFIFO_with_dest.tdest),
        .probe_in27(from_txFIFO.tdata[255:0]),
        .probe_in28(from_txFIFO.tdata[511:256]),
        .probe_in29(from_txFIFO.tvalid),
        .probe_in30(execRun_done[0])
    );
    
    /*
    generate
        for(j=0; j<32; j=j+1) begin
            AXIS_to_FIFO_input AXIS_to_rxFIFO(
                .a(after_switch[j].Slave),
                .f(rxFIFO_in[j].Source)
            );
            if(j<1) begin
                core_wrapper my_core(
                    .aclk(aclk),
                    .aclk450(aclk450), //Core receives the derived 450MHz clock.
                    .async_resetn(aresetn),
                    .async_resetn450(aresetn450),
                    .num_outputs(num_outputs[j]),
                    .num_inputs(num_inputs[j]),
                    .threshold(threshold[j]),
                    .exec_neuron_model(exec_neuron_model[j]),
                    
                    .core_number(j[4:0]),
                    
                    .hbm(hbm[j]),
                    .rxFIFO_in(rxFIFO_in[j]),
                    .txFIFO_out(txFIFO_out[j]),
                    .exec_hbm_rvalidready(exec_hbm_rvalidready[j]),
                    .hbmFIFO_empty(hbmFIFO_empty[j]),
                    .iep_curr_state(iep_curr_state[j]),
                    .hbm_curr_state(hbm_curr_state[j]),
                    .eep_curr_state(eep_curr_state[j]),
                    .exec_hbm_rx_phase1_done(exec_hbm_rx_phase1_done[j]),
                    .exec_hbm_rx_phase2_done(exec_hbm_rx_phase2_done[j]),
                    .curr_bram_waddr(curr_bram_waddr[j]),
                    .curr_uram_waddr(curr_uram_waddr[j]),
                    .hbm2eep_rden(hbm2eep_rden[j]),
                    .hbm2iep_rden(hbm2iep_rden[j]),
                    .hbm2pfc_rden(hbm2pfc_rden[j]) 
                );
            end else begin
                dummy_core my_core(
                    .aclk(aclk),
                    .async_resetn(async_resetn),
                    .num_outputs(17'b0),
                    .num_inputs(17'b0),
                    .threshold(16'b0),
                    .exec_neuron_model(2'b0),
                    
                    .core_number(j[4:0]),
                    
                    .hbm(hbm[j]),
                    .rxFIFO_in(rxFIFO_in[j]),
                    .txFIFO_out(txFIFO_out[j])
                );
            end
            FIFO_output_to_AXIS txFIFO_to_AXIS(
                .f(txFIFO_out[j].Sink),
                .a(before_switch[j].Master)
            );
        end
    endgenerate
    */
     //Modifications to check if single_core synthesis is clean
    
    generate
        for(j=0; j<1; j=j+1) begin
               axis_register_slice_0 rxFIFO_axis_reg(
                    .aclk(aclk),
                    .aresetn(aresetn),
                    .s_axis_tvalid(after_switch[j].tvalid),
                    .s_axis_tready(after_switch[j].tready),
                    .s_axis_tdata(after_switch[j].tdata),
                    .m_axis_tvalid(after_switch_regslice[j].tvalid),
                    .m_axis_tready(after_switch_regslice[j].tready),
                    .m_axis_tdata(after_switch_regslice[j].tdata)
                    );      
               AXIS_to_FIFO_input AXIS_to_rxFIFO(
                .a(after_switch_regslice[j].Slave),
                .f(rxFIFO_in[j].Source)
               );
                 core_wrapper my_core(
                    .aclk(aclk),
                    .aclk450(aclk450), //Core receives the derived 450MHz clock.
                    .async_resetn(aresetn),
                    .async_resetn450(aresetn450),
                    .num_outputs(num_outputs[j]),
                    .num_inputs(num_inputs[j]),
                    .threshold(threshold[j]),
                    .exec_neuron_model(exec_neuron_model[j]),
                    
                    .core_number(j[4:0]),
                    
                    .hbm(hbm[j]),
                    .rxFIFO_in(rxFIFO_in[j]),
                    .txFIFO_out(txFIFO_out[j]),
                    .exec_hbm_rvalidready(exec_hbm_rvalidready[j]),
                    .hbmFIFO_empty(hbmFIFO_empty[j]),
                    .iep_curr_state(iep_curr_state[j]),
                    .hbm_curr_state(hbm_curr_state[j]),
                    .eep_curr_state(eep_curr_state[j]),
                    .exec_hbm_rx_phase1_done(exec_hbm_rx_phase1_done[j]),
                    .exec_hbm_rx_phase2_done(exec_hbm_rx_phase2_done[j]),
                    .curr_bram_waddr(curr_bram_waddr[j]),
                    .curr_uram_waddr(curr_uram_waddr[j]),
                    .hbm2eep_rden(hbm2eep_rden[j]),
                    .hbm2iep_rden(hbm2iep_rden[j]),
                    .hbm2pfc_rden(hbm2pfc_rden[j]),
                    .execRun_done(execRun_done[j]),

                    .noc_spike_out_addr(),
                    .noc_spike_out_valid(),
                    .noc_spike_out_ready(1'b1),
                    
                    .noc_relay_din(17'b0),
                    .noc_relay_wren(1'b0),

                    .noc_relay_full(),
                    .exec_eep_phase3_done(),
                    
                    // NEW: Feature ports - each core has its own user_irq
                    .user_irq(user_irq_per_core[j]),
                    .error_status(),
                    .iep_watchdog_error(),
                    .iep_uram_out_of_range()
                );
                  
                FIFO_output_to_AXIS txFIFO_to_AXIS(
                .f(txFIFO_out[j].Sink),
                .a(before_switch_regslice[j].Master)
                );
                
                axis_register_slice_0 txFIFO_axis_reg(
                    .aclk(aclk),
                    .aresetn(aresetn),
                    .s_axis_tvalid(before_switch_regslice[j].tvalid),
                    .s_axis_tready(before_switch_regslice[j].tready),
                    .s_axis_tdata(before_switch_regslice[j].tdata),
                    .m_axis_tvalid(before_switch[j].tvalid),
                    .m_axis_tready(before_switch[j].tready),
                    .m_axis_tdata(before_switch[j].tdata)
                 );  
         end
      endgenerate
    
    // Tie off unused AXI-Stream switch ports 1-15 (only core 0 is instantiated)
    // Without these, the 16-port switches have undriven inputs causing DRC errors
    generate
        for(j=1; j<16; j=j+1) begin : gen_switch_tieoff
            assign after_switch[j].tready = 1'b1;
            assign after_switch_regslice[j].tvalid = 1'b0;
            assign after_switch_regslice[j].tdata = 512'b0;
            assign after_switch_regslice[j].tready = 1'b1;
            assign before_switch_regslice[j].tvalid = 1'b0;
            assign before_switch_regslice[j].tdata = 512'b0;
            assign before_switch_regslice[j].tready = 1'b1;
            assign before_switch[j].tvalid = 1'b0;
            assign before_switch[j].tdata = 512'b0;
        end
    endgenerate
    
    // Tie off unused HBM AXI master ports 1-31 (no cores driving them)
    generate
        for(j=1; j<32; j=j+1) begin : gen_hbm_tieoff
            assign hbm[j].araddr  = 33'b0;
            assign hbm[j].arburst = 2'b01;
            assign hbm[j].arid    = 6'b0;
            assign hbm[j].arlen   = 4'b0;
            assign hbm[j].arsize  = 3'b101;
            assign hbm[j].arvalid = 1'b0;
            assign hbm[j].awaddr  = 33'b0;
            assign hbm[j].awburst = 2'b01;
            assign hbm[j].awid    = 6'b0;
            assign hbm[j].awlen   = 4'b0;
            assign hbm[j].awsize  = 3'b101;
            assign hbm[j].awvalid = 1'b0;
            assign hbm[j].wdata   = 256'b0;
            assign hbm[j].wlast   = 1'b0;
            assign hbm[j].wstrb   = 32'b0;
            assign hbm[j].wvalid  = 1'b0;
            assign hbm[j].rready  = 1'b1;
            assign hbm[j].bready  = 1'b1;
        end
    endgenerate
      
    
    
/*
    FIFO_512_ASYNC rx_cdc(
        .s(to_rxFIFO_small),
        .m(to_rxFIFO)
    );
    
    FIFO_512_ASYNC tx_cdc(
        .s(from_txFIFO),
        .m(from_txFIFO_small)
    );
*/
 //Modifications to check if single_core synthesis is clean
    FIFO_512_ASYNC rx_cdc(
        .s(to_rxFIFO_small),
        .m(to_rxFIFO)
    );
    
    FIFO_512_ASYNC tx_cdc(
        .s(from_txFIFO),
        .m(from_txFIFO_small)
    );
  
    
    top_ila my_ila(
        .clk(aclk),
        .probe0(from_txFIFO_small.tdata),
        .probe1(from_txFIFO_small.tvalid),
        .probe2(from_txFIFO_small.tready),
        .probe3(to_rxFIFO_small.tdata),
        .probe4(to_rxFIFO_small.tvalid),
        .probe5(to_rxFIFO_small.tready),
        .probe6(from_txFIFO.tdata),
        .probe7(from_txFIFO.tvalid),
        .probe8(from_txFIFO.tready),
        .probe9(to_rxFIFO.tdata),
        .probe10(to_rxFIFO.tvalid),
        .probe11(to_rxFIFO.tready)
    );
    
    //Empty Buffer handling
    reg [31:0] missed_inputs;
    always @(posedge pcie_axi_clk) begin
        if (!pcie_axi_aresetn) begin
            missed_inputs <= 0;
        end else begin
            missed_inputs <= missed_inputs + (to_rxFIFO_small.tvalid & ~to_rxFIFO_small.tready);
        end
    end
     
    xdma_0 pcie_dma (
        .sys_clk(pcie_clk_out),                                    // input wire sys_clk
        .sys_clk_gt(pcie_clk_gt),                              // input wire sys_clk_gt
        .sys_rst_n(sys_rst_n),                                // input wire sys_rst_n
        .user_lnk_up(user_lnk_up),                            // output wire user_lnk_up
        .pci_exp_txp(pci_exp_txp),                            // output wire [7 : 0] pci_exp_txp
        .pci_exp_txn(pci_exp_txn),                            // output wire [7 : 0] pci_exp_txn
        .pci_exp_rxp(pci_exp_rxp),                            // input wire [7 : 0] pci_exp_rxp
        .pci_exp_rxn(pci_exp_rxn),                            // input wire [7 : 0] pci_exp_rxn
        .axi_aclk(pcie_axi_clk),                                  // output wire axi_aclk
        .axi_aresetn(pcie_axi_aresetn),                            // output wire axi_aresetn
        .usr_irq_req(user_irq_core0),                   // NEW: interrupt from core 0
        .usr_irq_ack(usr_irq_ack),                            // output wire [0 : 0] usr_irq_ack
        .msix_enable(msix_enable),                  // output wire msix_enable

//        .s_axis_c2h_tdata_0(from_txFIFO_small.tdata),
        .s_axis_c2h_tdata_0(from_txFIFO_small.tvalid ? from_txFIFO_small.tdata : {{480{1'b1}}, missed_inputs}),
        .s_axis_c2h_tkeep_0({64{1'b1}}),
        //.s_axis_c2h_tlast_0(1'b1), //TLAST 1'b1 indicates every packet has individual boundaries, this might have issues in burst accesses.
        .s_axis_c2h_tlast_0(1'b0), //This indicates that all transfers are within the same packet.
        //.s_axis_c2h_tvalid_0(from_txFIFO_small.tvalid),
        .s_axis_c2h_tvalid_0(1),
        .s_axis_c2h_tready_0(from_txFIFO_small.tready),
        
        .m_axis_h2c_tdata_0(to_rxFIFO_small.tdata),
        .m_axis_h2c_tkeep_0(),
        .m_axis_h2c_tlast_0(),
        .m_axis_h2c_tvalid_0(to_rxFIFO_small.tvalid),
        //.m_axis_h2c_tready_0(1'b1) 
       .m_axis_h2c_tready_0(to_rxFIFO_small.tready) //Backpressure for slowing down PCIe link when FIFO is full.
    );
   

`define hbmAXI(M, N) \
        .AXI_``M``_ACLK(aclk450),                      \
        .AXI_``M``_ARESET_N(aresetn450),               \
        .AXI_``M``_ARADDR(hbm[N].araddr),              \
        .AXI_``M``_ARBURST(hbm[N].arburst),            \
        .AXI_``M``_ARID(hbm[N].arid),                  \
        .AXI_``M``_ARLEN(hbm[N].arlen),                \
        .AXI_``M``_ARSIZE(hbm[N].arsize),              \
        .AXI_``M``_ARVALID(hbm[N].arvalid),            \
        .AXI_``M``_AWADDR(hbm[N].awaddr),              \
        .AXI_``M``_AWBURST(hbm[N].awburst),            \
        .AXI_``M``_AWID(hbm[N].awid),                  \
        .AXI_``M``_AWLEN(hbm[N].awlen),                \
        .AXI_``M``_AWSIZE(hbm[N].awsize),              \
        .AXI_``M``_AWVALID(hbm[N].awvalid),            \
        .AXI_``M``_RREADY(hbm[N].rready),              \
        .AXI_``M``_BREADY(hbm[N].bready),              \
        .AXI_``M``_WDATA(hbm[N].wdata),                \
        .AXI_``M``_WDATA_PARITY(~hbm[N].wdata),         \
        .AXI_``M``_WLAST(hbm[N].wlast),                \
        .AXI_``M``_WSTRB(hbm[N].wstrb),                \
        .AXI_``M``_WVALID(hbm[N].wvalid),              \
        .AXI_``M``_ARREADY(hbm[N].arready),            \
        .AXI_``M``_AWREADY(hbm[N].awready),            \
        .AXI_``M``_RDATA_PARITY(),\
        .AXI_``M``_RDATA(hbm[N].rdata),                \
        .AXI_``M``_RID(hbm[N].rid),                    \
        .AXI_``M``_RLAST(hbm[N].rlast),                \
        .AXI_``M``_RRESP(hbm[N].rresp),                \
        .AXI_``M``_RVALID(hbm[N].rvalid),              \
        .AXI_``M``_WREADY(hbm[N].wready),              \
        .AXI_``M``_BID(hbm[N].bid),                    \
        .AXI_``M``_BRESP(hbm[N].bresp),                \
        .AXI_``M``_BVALID(hbm[N].bvalid),              \
        
    hbm_left hbm1 (
        .HBM_REF_CLK_0(refclk450),              // input wire HBM_REF_CLK_0
        `hbmAXI(00, 0)
        `hbmAXI(01, 1)
        `hbmAXI(02, 2)
        `hbmAXI(03, 3)
        `hbmAXI(04, 4)
        `hbmAXI(05, 5)
        `hbmAXI(06, 6)
        `hbmAXI(07, 7)
        `hbmAXI(08, 8)
        `hbmAXI(09, 9)
        `hbmAXI(10, 10)
        `hbmAXI(11, 11)
        `hbmAXI(12, 12)
        `hbmAXI(13, 13)
        `hbmAXI(14, 14)
        `hbmAXI(15, 15)
        .APB_0_PRDATA(APB_0_PRDATA),                // output wire [31 : 0] APB_0_PRDATA
        .APB_0_PREADY(APB_0_PREADY),                // output wire APB_0_PREADY
        .APB_0_PSLVERR(APB_0_PSLVERR),              // output wire APB_0_PSLVERR
        .APB_0_PWDATA(APB_0_PWDATA),                // input wire [31 : 0] APB_0_PWDATA
        .APB_0_PADDR(APB_0_PADDR),                  // input wire [21 : 0] APB_0_PADDR
        .APB_0_PCLK(APB_0_PCLK),                    // input wire APB_0_PCLK
        .APB_0_PENABLE(APB_0_PENABLE),              // input wire APB_0_PENABLE
        .APB_0_PRESET_N(APB_0_PRESET_N),            // input wire APB_0_PRESET_N
        .APB_0_PSEL(APB_0_PSEL),                    // input wire APB_0_PSEL
        .APB_0_PWRITE(APB_0_PWRITE),                // input wire APB_0_PWRITE
        .apb_complete_0(apb_complete_0),            // output wire apb_complete_0
        .DRAM_0_STAT_CATTRIP(DRAM_0_STAT_CATTRIP),  // output wire DRAM_0_STAT_CATTRIP
        .DRAM_0_STAT_TEMP(DRAM_0_STAT_TEMP)        // output wire [6 : 0] DRAM_0_STAT_TEMP
    );

    hbm_right hbm2 (
        .HBM_REF_CLK_0(refclk450),              // input wire HBM_REF_CLK_0
        `hbmAXI(00, 16)
        `hbmAXI(01, 17)
        `hbmAXI(02, 18)
        `hbmAXI(03, 19)
        `hbmAXI(04, 20)
        `hbmAXI(05, 21)
        `hbmAXI(06, 22)
        `hbmAXI(07, 23)
        `hbmAXI(08, 24)
        `hbmAXI(09, 25)
        `hbmAXI(10, 26)
        `hbmAXI(11, 27)
        `hbmAXI(12, 28)
        `hbmAXI(13, 29)
        `hbmAXI(14, 30)
        `hbmAXI(15, 31)
        .APB_0_PRDATA(APB_1_PRDATA),                // output wire [31 : 0] APB_0_PRDATA
        .APB_0_PREADY(APB_1_PREADY),                // output wire APB_0_PREADY
        .APB_0_PSLVERR(APB_1_PSLVERR),              // output wire APB_0_PSLVERR
        .APB_0_PWDATA(APB_1_PWDATA),                // input wire [31 : 0] APB_0_PWDATA
        .APB_0_PADDR(APB_1_PADDR),                  // input wire [21 : 0] APB_0_PADDR
        .APB_0_PCLK(APB_1_PCLK),                    // input wire APB_0_PCLK
        .APB_0_PENABLE(APB_1_PENABLE),              // input wire APB_0_PENABLE
        .APB_0_PRESET_N(APB_1_PRESET_N),            // input wire APB_0_PRESET_N
        .APB_0_PSEL(APB_1_PSEL),                    // input wire APB_0_PSEL
        .APB_0_PWRITE(APB_1_PWRITE),                // input wire APB_0_PWRITE
        .apb_complete_0(apb_complete_1),            // output wire apb_complete_0
        .DRAM_0_STAT_CATTRIP(DRAM_1_STAT_CATTRIP),  // output wire DRAM_0_STAT_CATTRIP
        .DRAM_0_STAT_TEMP(DRAM_1_STAT_TEMP)        // output wire [6 : 0] DRAM_0_STAT_TEMP
    );
       
endmodule