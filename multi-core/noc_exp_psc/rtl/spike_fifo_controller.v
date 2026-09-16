`timescale 1ns / 1ps

module spike_fifo_controller(

    input resetn,
    input clk,

    // Spike FIFOs
    input         spk0_empty,
    input  [18:0] spk0_dout,
    output reg    spk0_rden,

    input         spk1_empty,
    input  [18:0] spk1_dout,
    output reg    spk1_rden,

    input         spk2_empty,
    input  [18:0] spk2_dout,
    output reg    spk2_rden,

    input         spk3_empty,
    input  [18:0] spk3_dout,
    output reg    spk3_rden,

    input         spk4_empty,
    input  [18:0] spk4_dout,
    output reg    spk4_rden,

    input         spk5_empty,
    input  [18:0] spk5_dout,
    output reg    spk5_rden,

    input         spk6_empty,
    input  [18:0] spk6_dout,
    output reg    spk6_rden,

    input         spk7_empty,
    input  [18:0] spk7_dout,
    output reg    spk7_rden,

    // to HBM processor
    input             spk2ciFIFO_full,
    output reg [18:0] spk2ciFIFO_din,
    output reg        spk2ciFIFO_wren
);


// =========================================================================
// FIX: Replace blind round-robin with greedy next-non-empty arbitration.
//
// Problem: The original round-robin increments addr every cycle regardless
// of whether the current FIFO has data. With 8 FIFOs, each FIFO is only
// serviced once every 8 cycles. When spike bursts fill multiple FIFOs
// simultaneously (e.g. 2 consecutive URAM groups each with 16 spiking
// neurons), the FIFOs overflow before the round-robin comes back to drain
// them, causing spike loss.
//
// Fix: After servicing a FIFO (or finding it empty), immediately advance
// to the next non-empty FIFO using a priority search rooted at (addr+1).
// This ensures no cycles are wasted on empty FIFOs, maximizing drain
// throughput to 1 spike per cycle when any FIFO has data.
// =========================================================================

reg [2:0] addr;
wire [7:0] spks_empty = {spk7_empty, spk6_empty, spk5_empty, spk4_empty,
                          spk3_empty, spk2_empty, spk1_empty, spk0_empty};

// Compute next non-empty FIFO starting from (addr+1), wrapping around.
// If all empty, stay at addr+1 (will find nothing and idle).
// Reverse loop: k=7 (lowest priority = addr) to k=0 (highest = addr+1).
// Later iterations overwrite earlier, so k=0 wins when non-empty.
reg [2:0] next_addr;
integer k;
always @(*) begin
    next_addr = addr + 1'b1; // default: advance by 1 (if all empty)
    for (k = 7; k >= 0; k = k - 1) begin
        if (!spks_empty[(addr + 1 + k) & 3'b111])
            next_addr = (addr + 1 + k) & 3'b111;
    end
end

always @(posedge clk) begin
    if (!resetn)
        addr <= 3'd0;
    else
        addr <= next_addr;
end

// Spike FIFO read and spk2ciFIFO write logic (unchanged structure)
always @(*) begin
    spk0_rden       = 1'b0;
    spk1_rden       = 1'b0;
    spk2_rden       = 1'b0;
    spk3_rden       = 1'b0;
    spk4_rden       = 1'b0;
    spk5_rden       = 1'b0;
    spk6_rden       = 1'b0;
    spk7_rden       = 1'b0;
    spk2ciFIFO_din  = 19'dX;
    spk2ciFIFO_wren = 1'b0;

    case (addr)
        3'd0: begin
            if (!spk0_empty & !spk2ciFIFO_full) begin
                spk0_rden       = 1'b1;
                spk2ciFIFO_din  = spk0_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        3'd1: begin
            if (!spk1_empty & !spk2ciFIFO_full) begin
                spk1_rden       = 1'b1;
                spk2ciFIFO_din  = spk1_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        3'd2: begin
            if (!spk2_empty & !spk2ciFIFO_full) begin
                spk2_rden       = 1'b1;
                spk2ciFIFO_din  = spk2_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        3'd3: begin
            if (!spk3_empty & !spk2ciFIFO_full) begin
                spk3_rden       = 1'b1;
                spk2ciFIFO_din  = spk3_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        3'd4: begin
            if (!spk4_empty & !spk2ciFIFO_full) begin
                spk4_rden       = 1'b1;
                spk2ciFIFO_din  = spk4_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        3'd5: begin
            if (!spk5_empty & !spk2ciFIFO_full) begin
                spk5_rden       = 1'b1;
                spk2ciFIFO_din  = spk5_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        3'd6: begin
            if (!spk6_empty & !spk2ciFIFO_full) begin
                spk6_rden       = 1'b1;
                spk2ciFIFO_din  = spk6_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        3'd7: begin
            if (!spk7_empty & !spk2ciFIFO_full) begin
                spk7_rden       = 1'b1;
                spk2ciFIFO_din  = spk7_dout;
                spk2ciFIFO_wren = 1'b1;
            end
        end
        default: begin
            spk2ciFIFO_din  = 19'dX;
            spk2ciFIFO_wren = 1'b0;
        end
    endcase
end

endmodule