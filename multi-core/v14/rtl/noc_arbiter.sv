`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: noc_arbiter.sv
// 
// Description:
//   Round-robin arbiter for NoC bus access. Grants bus access to one master
//   at a time, cycling through requesters fairly.
//
// Parameters:
//   NUM_MASTERS - Number of masters competing for bus access (4 for L1, 4 for L2)
//
// Features:
//   - Fair round-robin arbitration
//   - Single-cycle grant latency when bus is free
//   - Holds grant until master releases bus request
//////////////////////////////////////////////////////////////////////////////////

module noc_arbiter #(
    parameter NUM_MASTERS = 4
)(
    input  logic                      clk,
    input  logic                      resetn,
    
    // Bus requests from masters
    input  logic [NUM_MASTERS-1:0]    hbusreq,
    
    // Grant signals to masters (one-hot)
    output logic [NUM_MASTERS-1:0]    hgrant,
    
    // Currently selected master ID
    output logic [$clog2(NUM_MASTERS)-1:0] sel_id,
    
    // Bus busy indicator
    output logic                      bus_busy
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    localparam SEL_WIDTH = $clog2(NUM_MASTERS);
    
    // =========================================================================
    // FSM States
    // =========================================================================
    typedef enum logic [1:0] {
        STATE_IDLE      = 2'b00,
        STATE_GRANTED   = 2'b01,
        STATE_WAIT_REL  = 2'b10
    } arbiter_state_t;
    
    arbiter_state_t state, next_state;
    
    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [SEL_WIDTH-1:0] current_master;
    logic [SEL_WIDTH-1:0] next_master;
    logic [NUM_MASTERS-1:0] grant_reg;
    logic found_request;
    
    // =========================================================================
    // Priority Encoder - Find next requester (round-robin)
    // =========================================================================
    always_comb begin
        found_request = 1'b0;
        next_master = current_master;
        
        // Search from current_master+1 to NUM_MASTERS-1
        for (int i = 0; i < NUM_MASTERS; i++) begin
            automatic int idx = (current_master + 1 + i) % NUM_MASTERS;
            if (hbusreq[idx] && !found_request) begin
                next_master = idx[SEL_WIDTH-1:0];
                found_request = 1'b1;
            end
        end
    end
    
    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= STATE_IDLE;
            current_master <= '0;
            grant_reg <= '0;
        end else begin
            state <= next_state;
            
            case (next_state)
                STATE_IDLE: begin
                    grant_reg <= '0;
                end
                
                STATE_GRANTED: begin
                    current_master <= next_master;
                    grant_reg <= (1 << next_master);
                end
                
                STATE_WAIT_REL: begin
                    // Hold current grant
                end
                
                default: begin
                    grant_reg <= '0;
                end
            endcase
        end
    end
    
    // =========================================================================
    // FSM Next State Logic
    // =========================================================================
    always_comb begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (|hbusreq) begin
                    next_state = STATE_GRANTED;
                end
            end
            
            STATE_GRANTED: begin
                // Wait for granted master to assert request
                if (hbusreq[current_master]) begin
                    next_state = STATE_WAIT_REL;
                end else if (|hbusreq) begin
                    // Granted master didn't want bus, try next
                    next_state = STATE_GRANTED;
                end else begin
                    next_state = STATE_IDLE;
                end
            end
            
            STATE_WAIT_REL: begin
                // Wait for master to release bus
                if (!hbusreq[current_master]) begin
                    if (|hbusreq) begin
                        next_state = STATE_GRANTED;
                    end else begin
                        next_state = STATE_IDLE;
                    end
                end
            end
            
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end
    
    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign hgrant = grant_reg;
    assign sel_id = current_master;
    assign bus_busy = (state != STATE_IDLE);

endmodule
