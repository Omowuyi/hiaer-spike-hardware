// fix 35: first-word-fall-through FIFO, common clock, synchronous reset; DEPTH = 2**AW words of storage plus the output register.
// Block-RAM style: synchronous read into the output register (one word per cycle).  empty = no valid output word; full = storage full.
module fwft_fifo_core #(parameter W = 32, parameter AW = 10) (
    input  wire         clk, srst,
    input  wire [W-1:0] din,
    input  wire         wr_en,
    output wire         full,
    output wire [W-1:0] dout,
    input  wire         rd_en,
    output wire         empty
);
    reg [W-1:0] mem [0:(1<<AW)-1];
    reg [AW-1:0] wptr, rptr;
    reg [AW:0]   cnt;                       // words in storage (not counting the output register)
    reg [W-1:0]  q;
    reg          v;                         // output register holds a valid word
    wire wr  = wr_en & ~full;
    wire pop = rd_en & v;
    wire ld  = (cnt != 0) & (~v | pop);     // move one word from storage into the output register
    assign full  = (cnt == (1 << AW));
    assign empty = ~v;
    assign dout  = q;
    always @(posedge clk) if (wr) mem[wptr] <= din;
    always @(posedge clk) if (ld) q <= mem[rptr];
    always @(posedge clk) begin
        if (srst) begin wptr <= 0; rptr <= 0; cnt <= 0; v <= 1'b0; end
        else begin
            if (wr) wptr <= wptr + 1'b1;
            if (ld) rptr <= rptr + 1'b1;
            cnt <= cnt + (wr ? 1'b1 : 1'b0) - (ld ? 1'b1 : 1'b0);
            v   <= ld ? 1'b1 : (pop ? 1'b0 : v);
        end
    end
endmodule
