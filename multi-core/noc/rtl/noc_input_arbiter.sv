//=============================================================================
// NoC Input Arbiter Module
//
// Arbitrates between two input sources for the switch_1_16:
// 1. PCIe commands/spikes from host (higher priority for commands)
// 2. Remote spikes received from FireFly
//
// Arbitration Policy:
// - PCIe has priority when both sources have valid data
// - This ensures host commands are processed promptly
// - Remote spikes are processed when PCIe is idle
//
// Future Enhancement: Could add weighted fair queuing or round-robin
// for better spike throughput balance.
//=============================================================================

module noc_input_arbiter (
    input  logic            aclk,
    input  logic            aresetn,
    
    //=========================================================================
    // PCIe Input (from XDMA H2C)
    //=========================================================================
    input  logic [511:0]    pcie_tdata,
    input  logic [3:0]      pcie_tdest,
    input  logic            pcie_tvalid,
    output logic            pcie_tready,
    
    //=========================================================================
    // FireFly Input (from remote_spike_injector)
    //=========================================================================
    input  logic [511:0]    firefly_tdata,
    input  logic [3:0]      firefly_tdest,
    input  logic            firefly_tvalid,
    output logic            firefly_tready,
    
    //=========================================================================
    // Output to switch_1_16
    //=========================================================================
    output logic [511:0]    m_axis_tdata,
    output logic [3:0]      m_axis_tdest,
    output logic            m_axis_tvalid,
    input  logic            m_axis_tready
);

    //=========================================================================
    // Arbitration Logic
    //=========================================================================
    
    // Selection signals
    logic sel_pcie;
    logic sel_firefly;
    
    // Packet type detection (for potential priority adjustment)
    logic pcie_is_command;
    logic pcie_is_spike;
    
    // Detect packet type from header
    // Commands typically have different headers than spike packets
    localparam SPIKE_HEADER = 32'hEEEE_EEEE;
    localparam REMOTE_HEADER = 32'hFFFF_FFFF;
    
    assign pcie_is_spike = (pcie_tdata[511:480] == SPIKE_HEADER);
    assign pcie_is_command = pcie_tvalid && !pcie_is_spike;
    
    //=========================================================================
    // Priority Arbiter
    // PCIe wins if:
    // - PCIe has a command (always high priority)
    // - PCIe has a spike and FireFly doesn't (avoid starvation)
    // 
    // FireFly wins if:
    // - PCIe is not valid
    // - Both have spikes and it's FireFly's turn (round-robin enhancement)
    //=========================================================================
    
    // Simple priority: PCIe commands always win, then round-robin for spikes
    logic rr_turn;  // 0 = PCIe's turn, 1 = FireFly's turn
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rr_turn <= 1'b0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            // Toggle turn after each successful transfer
            rr_turn <= ~rr_turn;
        end
    end
    
    always_comb begin
        sel_pcie = 1'b0;
        sel_firefly = 1'b0;
        
        if (pcie_is_command) begin
            // Commands always get priority
            sel_pcie = 1'b1;
        end else if (pcie_tvalid && !firefly_tvalid) begin
            // Only PCIe has data
            sel_pcie = 1'b1;
        end else if (!pcie_tvalid && firefly_tvalid) begin
            // Only FireFly has data
            sel_firefly = 1'b1;
        end else if (pcie_tvalid && firefly_tvalid) begin
            // Both have data - use round-robin for spikes
            if (rr_turn) begin
                sel_firefly = 1'b1;
            end else begin
                sel_pcie = 1'b1;
            end
        end
        // Neither has data: both sel signals stay 0
    end
    
    //=========================================================================
    // Output Multiplexer
    //=========================================================================
    
    assign m_axis_tdata  = sel_pcie ? pcie_tdata  : firefly_tdata;
    assign m_axis_tdest  = sel_pcie ? pcie_tdest  : firefly_tdest;
    assign m_axis_tvalid = sel_pcie | sel_firefly;
    
    //=========================================================================
    // Ready Signal Distribution
    //=========================================================================
    
    assign pcie_tready    = sel_pcie & m_axis_tready;
    assign firefly_tready = sel_firefly & m_axis_tready;

endmodule : noc_input_arbiter
