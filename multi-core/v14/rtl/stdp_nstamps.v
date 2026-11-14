`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// stdp_nstamps.v -- neuron spike times for STDP, the RTL form of NeuronStamps in stdp_ref.py.
// (Axon spike times live in HBM as 32-bit stamps and are handled by the controller.)
//
// NW words x 192 bits (3 URAMs at NW = 4096), 8 neurons per word; lane L = {isi[11:0], stamp[11:0]}
// at [24L+23:24L]; neuron n is word n>>3, lane n&7; a 16-neuron row r is words 2r and 2r+1.
// Time t is 12 bits; d = (t - stamp) mod 4096.
//   capture : firing lanes get stamp = t and isi = d (before the update) if d < OLD, else 4095
//   lookup  : returns d and isi
//   clear   : restarts t at 0, then every stamp = -OLD (d = OLD), every isi = 4095
//   scrub   : the budget grows by SCRUB_N words per step_tick and never resets, so every word is
//             visited within 128 steps when NW <= 128 * SCRUB_N; any lane with d >= OLD is re-aged
//             to d = OLD and therefore never wraps into looking recent
// One operation at a time; priority clear > capture > lookup > scrub.
//////////////////////////////////////////////////////////////////////////////////
module stdp_nstamps #(
    parameter integer NW      = 4096,
    parameter integer NWB     = 12,          // log2(NW)
    parameter integer OLD     = 3967,        // 4095 - 128
    parameter integer SCRUB_N = 32
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        step_tick,
    input  wire        clear_req,
    output wire        clear_busy,
    input  wire        cap_valid,
    input  wire [12:0] cap_row,
    input  wire [15:0] cap_mask,
    output wire        cap_ready,
    input  wire        lk_valid,
    input  wire [16:0] lk_idx,
    output wire        lk_ready,
    output reg         lk_out_valid,
    output reg  [11:0] lk_d,
    output reg  [11:0] lk_isi,
    output reg  [11:0] t_now,
    output wire        idle
);
    (* ram_style = "ultra" *) reg [191:0] mem [0:NW-1];
    localparam S_IDLE = 3'd0, S_CLR = 3'd1, S_CAP_RD = 3'd2, S_CAP_WR = 3'd3, S_LK_RD = 3'd4, S_LK_OUT = 3'd5,
               S_SCR_RD = 3'd6, S_SCR_WR = 3'd7;
    reg [2:0]  st;
    reg        clear_pend, half;
    reg [NWB:0] clr_ptr;
    reg [12:0] row_r;
    reg [15:0] mask_r;
    reg [2:0]  lane_r;
    reg [NWB-1:0] raddr, scr_ptr;
    reg [191:0] rd;
    reg [8:0]  scr_left;
    wire [11:0] t_old = t_now - OLD[11:0];

    assign clear_busy = clear_pend || (st == S_CLR);
    assign cap_ready  = (st == S_IDLE) && !clear_pend && !clear_req;
    assign lk_ready   = (st == S_IDLE) && !clear_pend && !clear_req && !cap_valid;
    assign idle       = (st == S_IDLE) && !clear_pend && !cap_valid && !lk_valid && scr_left == 0;

    always @(posedge clk) rd <= mem[raddr];          // registered read, 1-cycle latency

    function [191:0] cap_word(input [191:0] wd, input [7:0] m, input [11:0] t);
        integer L; reg [11:0] d;
        begin
            cap_word = wd;
            for (L = 0; L < 8; L = L + 1) if (m[L]) begin
                d = t - wd[24*L +: 12];
                cap_word[24*L +: 12]      = t;
                cap_word[24*L + 12 +: 12] = (d < OLD) ? d : 12'd4095;
            end
        end
    endfunction
    function [191:0] scrub_word(input [191:0] wd, input [11:0] t, input [11:0] told);
        integer L; reg [11:0] d;
        begin
            scrub_word = wd;
            for (L = 0; L < 8; L = L + 1) begin
                d = t - wd[24*L +: 12];
                if (d >= OLD) scrub_word[24*L +: 12] = told;
            end
        end
    endfunction
    function [191:0] clear_word(input [11:0] told);
        integer L;
        begin for (L = 0; L < 8; L = L + 1) clear_word[24*L +: 24] = {12'd4095, told}; end
    endfunction
    function [8:0] sat_add(input [8:0] cur, input [8:0] add, input dec);
        reg [10:0] v;
        begin
            v = {2'b00, cur} + {2'b00, add} - {10'd0, dec};
            sat_add = (v > 11'd511) ? 9'd511 : v[8:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; t_now <= 12'd0; clear_pend <= 1'b0; clr_ptr <= 0; scr_ptr <= 0; scr_left <= 9'd0;
            lk_out_valid <= 1'b0; half <= 1'b0; raddr <= 0;
        end else begin
            lk_out_valid <= 1'b0;
            if (clear_req) clear_pend <= 1'b1;
            if (step_tick) t_now <= t_now + 12'd1;
            scr_left <= sat_add(scr_left, step_tick ? SCRUB_N[8:0] : 9'd0, st == S_SCR_WR);
            case (st)
                S_IDLE: begin
                    if (clear_pend || clear_req) begin clear_pend <= 1'b0; clr_ptr <= 0; t_now <= 12'd0; st <= S_CLR; end
                    else if (cap_valid) begin
                        row_r <= cap_row; mask_r <= cap_mask; raddr <= {cap_row[NWB-2:0], 1'b0}; half <= 1'b0; st <= S_CAP_RD;
                    end else if (lk_valid) begin
                        raddr <= lk_idx[NWB+2:3]; lane_r <= lk_idx[2:0]; st <= S_LK_RD;
                    end else if (scr_left != 0 && !step_tick) begin
                        raddr <= scr_ptr; st <= S_SCR_RD;
                    end
                end
                S_CLR: begin
                    mem[clr_ptr[NWB-1:0]] <= clear_word(t_old);
                    clr_ptr <= clr_ptr + 1'b1;
                    if (clr_ptr == NW - 1) st <= S_IDLE;
                end
                S_CAP_RD: st <= S_CAP_WR;
                S_CAP_WR: begin
                    mem[raddr] <= cap_word(rd, half ? mask_r[15:8] : mask_r[7:0], t_now);
                    if (!half) begin half <= 1'b1; raddr <= {row_r[NWB-2:0], 1'b1}; st <= S_CAP_RD; end
                    else st <= S_IDLE;
                end
                S_LK_RD: st <= S_LK_OUT;
                S_LK_OUT: begin
                    lk_out_valid <= 1'b1;
                    lk_d   <= t_now - rd[24*lane_r +: 12];
                    lk_isi <= rd[24*lane_r + 12 +: 12];
                    st <= S_IDLE;
                end
                S_SCR_RD: st <= S_SCR_WR;
                S_SCR_WR: begin
                    mem[raddr] <= scrub_word(rd, t_now, t_old);
                    scr_ptr <= (scr_ptr == NW - 1) ? {NWB{1'b0}} : scr_ptr + 1'b1;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
