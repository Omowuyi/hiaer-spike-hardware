`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// stdp_ctrl.v -- Phase-4 plasticity controller: Pfister-Gerstner full triplet with signed amplitudes,
// per-pre-spike constant and eligibility traces, bit-exact with stdp_ref.py v3 at the network level.
//
// HBM (256-bit rows), one request at a time through a generic request/response port:
//   pointer    32 bits {len[31:23] = rows-1, addr[22:0]}, 8 per row (lane = index & 7); addr 0 = no list
//              axon a: AXON_PTR_BASE + (a>>3);  neuron n: NRN_PTR_BASE + (n>>3);  incoming list of n: INC_PTR_BASE + (n>>3)
//   synapse    4 x 64-bit entries per row, slot s at [64s+63:64s]:
//              {op[63:61], dest[60:48], weight[47:32], delay[31:26], syn_type[25:22], tag[21:18], src[17:0]}
//              plastic = (op == 0 && tag != 0); tag selects rule 1..15; src[17] = axon, src[16:0] = index
//              post neuron of the entry at row offset o (from the list start), slot s:
//                  n = dest*16 + POST_GROUP(o, s), POST_GROUP = {o[1], ~o[0], ~s} (neuron processor's decode)
//   incoming   32-bit entries {valid[31], slot[30:29], rsvd[28:23], row[22:0]}, 8 per row
//   axon stamp 32-bit step of the axon's last spike, 8 per row: AXON_STAMP_BASE + (a>>3), lane a & 7
//   shadow     eligibility of a plastic row R: SHADOW_BASE + (R - PLASTIC_START), slot s = {t_e[63:32], e[31:0]}
//   plastic rows: [PLASTIC_START, PLASTIC_END) hold every list with a plastic synapse (reward sweep range)
// Config port (32-bit words): cfg_addr[15] = 1: table write, {table[14:12], index[11:0]}, data[15:0]
//   rule r (1..15), word k at cfg_addr = 16r + k:
//     k0 {A3p, A2p}   k1 {A3m, A2m}   k2 {e_shift[27:24], elig_reset[23], elig[22], soft[21], s0 s3m s2m s3p s2p [20:16], A0}
//     k3 {w_max, w_min}   k4 inv_range   k5 {lut_e[30:28], lut_x[27:25], lut_y[24:22], lut_m[21:19], lut_p[18:16], eta}
//   0x100 AXON_PTR_BASE  0x101 NRN_PTR_BASE  0x102 INC_PTR_BASE  0x103 AXON_STAMP_BASE  0x104 SHADOW_BASE
//   0x105 PLASTIC_START  0x106 PLASTIC_END
// Time: step_tick starts a step (t <= t + 1); clear_req restarts t at 0 (host writes axon stamps -4095 and
// zero shadows with the network).  Captures (firing neuron rows, firing axon rows) arrive during the step;
// p4_start runs: axon stamps + axon LTD, neuron LTD, LTP; then p4_done.  reward_req runs the reward sweep.
//////////////////////////////////////////////////////////////////////////////////
module stdp_ctrl #(
    parameter integer NW = 4096, NWB = 12,              // neuron stamp words (8 neurons each)
    parameter integer NLIST = 2048, NLB = 11,           // firing neuron rows per step
    parameter integer ALIST = 8192, ALB = 13            // firing axon rows per step
)(
    input  wire clk, rst,
    input  wire cfg_wr, input wire [15:0] cfg_addr, input wire [31:0] cfg_data,
    input  wire [7:0] neuromod_g,
    input  wire step_tick, clear_req,
    input  wire p4_start, output reg p4_done,
    input  wire reward_req, input wire signed [15:0] reward_R, output reg reward_done,
    input  wire ncap_valid, input wire [12:0] ncap_row, input wire [15:0] ncap_mask, output wire ncap_ready,
    input  wire acap_valid, input wire [12:0] acap_row, input wire [15:0] acap_mask, output wire acap_ready,
    output reg  hreq_valid, input wire hreq_ready, output reg hreq_we, output reg [22:0] hreq_addr, output reg [255:0] hreq_wdata,
    input  wire hrsp_valid, input wire [255:0] hrsp_rdata,
    output wire hrsp_ready,                              // pops a first-word-fall-through response FIFO
    output wire busy
);
    // ------------------------------------------------------------------ layout fact owned by the neuron processor
    // From internal_events_processor.v's 64-bit Phase-2 decode: a list's 4-row regions arrive as two 512-bit words
    // {second beat, first beat}; phase2_halfsel (reset to 0 at each Phase 2) selects groups 0-7 then 8-15, and within a
    // word the entry at the top of the 512 bits feeds the lowest group.  Hence group = {o[1], ~o[0], ~s}.
    // UNVERIFIED on the real design: verified end to end by the integration round (wrong group -> wrong post stamp).
    function [3:0] POST_GROUP(input [8:0] o, input [1:0] s);
        POST_GROUP = {o[1], ~o[0], ~s};
    endfunction
    // ------------------------------------------------------------------ configuration
    reg [15:0] A2p [0:15], A3p [0:15], A2m [0:15], A3m [0:15], A0 [0:15], eta [0:15];
    reg [4:0]  sgn [0:15];                    // {s0, s3m, s2m, s3p, s2p}
    reg        rsoft [0:15], elig [0:15], ereset [0:15];
    reg [3:0]  esh [0:15];
    reg signed [15:0] wmin [0:15], wmax [0:15];
    reg [31:0] inv [0:15];
    reg [2:0]  lp [0:15], lm [0:15], ly [0:15], lx [0:15], le [0:15];
    reg [22:0] AXON_PTR_BASE, NRN_PTR_BASE, INC_PTR_BASE, AXON_STAMP_BASE, SHADOW_BASE, PLASTIC_START, PLASTIC_END;
    (* ram_style = "block" *) reg [15:0] lut [0:32767];
    reg [14:0] lut_a; reg [15:0] lut_q;
    wire [14:0] lut_rd;                       // the eligibility unit's address is used combinationally (see e_v)
    always @(posedge clk) begin
        if (cfg_wr && cfg_addr[15]) lut[cfg_addr[14:0]] <= cfg_data[15:0];
        lut_q <= lut[lut_rd];
    end
    always @(posedge clk) if (cfg_wr && !cfg_addr[15]) begin
        if (cfg_addr[15:8] == 8'h00) case (cfg_addr[3:0])
            4'd0: begin A2p[cfg_addr[7:4]] <= cfg_data[15:0]; A3p[cfg_addr[7:4]] <= cfg_data[31:16]; end
            4'd1: begin A2m[cfg_addr[7:4]] <= cfg_data[15:0]; A3m[cfg_addr[7:4]] <= cfg_data[31:16]; end
            4'd2: begin A0[cfg_addr[7:4]] <= cfg_data[15:0]; sgn[cfg_addr[7:4]] <= cfg_data[20:16]; rsoft[cfg_addr[7:4]] <= cfg_data[21];
                        elig[cfg_addr[7:4]] <= cfg_data[22]; ereset[cfg_addr[7:4]] <= cfg_data[23]; esh[cfg_addr[7:4]] <= cfg_data[27:24]; end
            4'd3: begin wmin[cfg_addr[7:4]] <= cfg_data[15:0]; wmax[cfg_addr[7:4]] <= cfg_data[31:16]; end
            4'd4: inv[cfg_addr[7:4]] <= cfg_data;
            4'd5: begin eta[cfg_addr[7:4]] <= cfg_data[15:0]; lp[cfg_addr[7:4]] <= cfg_data[18:16]; lm[cfg_addr[7:4]] <= cfg_data[21:19];
                        ly[cfg_addr[7:4]] <= cfg_data[24:22]; lx[cfg_addr[7:4]] <= cfg_data[27:25]; le[cfg_addr[7:4]] <= cfg_data[30:28]; end
            default: ;
        endcase
        else if (cfg_addr[15:8] == 8'h01) case (cfg_addr[3:0])
            4'd0: AXON_PTR_BASE <= cfg_data[22:0];   4'd1: NRN_PTR_BASE <= cfg_data[22:0];
            4'd2: INC_PTR_BASE <= cfg_data[22:0];    4'd3: AXON_STAMP_BASE <= cfg_data[22:0];
            4'd4: SHADOW_BASE <= cfg_data[22:0];     4'd5: PLASTIC_START <= cfg_data[22:0];
            4'd6: PLASTIC_END <= cfg_data[22:0];     default: ;
        endcase
    end
    // ------------------------------------------------------------------ time, capture lists, neuron stamps
    reg [31:0] t32;
    always @(posedge clk) if (rst || clear_req) t32 <= 32'd0; else if (step_tick) t32 <= t32 + 32'd1;
    reg [28:0] nlist [0:NLIST-1]; reg [NLB:0] ncount;
    reg [28:0] alist [0:ALIST-1]; reg [ALB:0] acount;
    wire ns_cap_ready, ns_lk_ready, ns_lk_ov, ns_idle, ns_cbusy; wire [11:0] ns_d, ns_isi, ns_t;
    reg  lk_v; reg [16:0] lk_i;
    assign ncap_ready = (ncount < NLIST);                 // lists accept one row per cycle; the feeder applies them
    assign acap_ready = (acount < ALIST);
    always @(posedge clk) begin
        if (rst || step_tick || clear_req) begin ncount <= 0; acount <= 0; end
        else begin
            if (ncap_valid && ncap_ready) begin nlist[ncount[NLB-1:0]] <= {ncap_row, ncap_mask}; ncount <= ncount + 1'b1; end
            if (acap_valid && acap_ready) begin alist[acount[ALB-1:0]] <= {acap_row, acap_mask}; acount <= acount + 1'b1; end
        end
    end
    // feeder: applies captured neuron rows to the stamp memory at its own pace (captures are never refused)
    reg [NLB:0] nfeed; reg fv; reg [28:0] fdat;
    always @(posedge clk) begin
        if (rst || step_tick || clear_req) begin nfeed <= 0; fv <= 1'b0; end
        else begin
            if (fv && ns_cap_ready) fv <= 1'b0;
            if ((!fv || ns_cap_ready) && (nfeed < ncount)) begin fdat <= nlist[nfeed[NLB-1:0]]; fv <= 1'b1; nfeed <= nfeed + 1'b1; end
        end
    end
    wire feed_done = !fv && (nfeed == ncount) && ns_cap_ready;
    stdp_nstamps #(.NW(NW), .NWB(NWB)) u_ns (.clk(clk), .rst(rst), .step_tick(step_tick), .clear_req(clear_req), .clear_busy(ns_cbusy),
        .cap_valid(fv), .cap_row(fdat[28:16]), .cap_mask(fdat[15:0]), .cap_ready(ns_cap_ready),
        .lk_valid(lk_v), .lk_idx(lk_i), .lk_ready(ns_lk_ready), .lk_out_valid(ns_lk_ov), .lk_d(ns_d), .lk_isi(ns_isi), .t_now(ns_t), .idle(ns_idle));
    // ------------------------------------------------------------------ arithmetic units
    reg  u_v, u_ltp, u_dir; reg signed [27:0] u_pd; reg signed [15:0] u_w; reg [15:0] u_trm, u_try; reg [7:0] u_g;
    reg  [3:0] rl;                                            // rule of the entry in hand
    wire u_ov; wire signed [15:0] u_wn; wire signed [27:0] u_praw;
    stdp_update_unit u_upd (.clk(clk), .rst(rst), .in_valid(u_v), .in_ltp(u_ltp), .in_skip(1'b0), .in_direct(u_dir), .p_direct(u_pd),
        .w(u_w), .tr_main(u_trm), .tr_y(u_try), .A2(u_ltp ? A2p[rl] : A2m[rl]), .A3(u_ltp ? A3p[rl] : A3m[rl]),
        .s2(u_ltp ? sgn[rl][0] : sgn[rl][2]), .s3(u_ltp ? sgn[rl][1] : sgn[rl][3]), .A0(A0[rl]), .s0(sgn[rl][4]),
        .w_min(wmin[rl]), .w_max(wmax[rl]), .inv_range(inv[rl]), .soft_bound(rsoft[rl]), .g(u_g),
        .out_valid(u_ov), .w_new(u_wn), .p_raw(u_praw));
    reg  e_v, e_rew; reg signed [31:0] e_e; reg [31:0] e_te; reg signed [27:0] e_pev;
    wire e_ov; wire [11:0] e_la; wire signed [31:0] e_en; wire [31:0] e_ten; wire signed [27:0] e_pr;
    stdp_elig_unit u_el (.clk(clk), .rst(rst), .in_valid(e_v), .in_reward(e_rew), .e(e_e), .t_e(e_te), .t(t32), .e_shift(esh[rl]),
        .p_event(e_pev), .R(reward_R), .eta(eta[rl]), .elig_reset(ereset[rl]), .lut_addr(e_la), .lut_data(lut_q),
        .out_valid(e_ov), .e_new(e_en), .t_e_new(e_ten), .p_reward(e_pr));
    // ------------------------------------------------------------------ sequencer
    localparam [6:0]
        S_IDLE = 0, S_AX_NEXT = 1, S_AX_HALF = 2, S_AX_STAMPS = 3, S_AX_LANE = 4, S_AX_HDONE = 5,
        S_N_NEXT = 6, S_N_LANE = 7, S_N_ISI = 8, S_N_RET = 9, S_P_NEXT = 10, S_P_LANE = 11, S_P_ISI = 12, S_P_RET = 13, S_DONE = 14,
        W_PTR = 15, W_PTRD = 16, W_ROW = 17, W_ROWD = 18, W_SLOT = 19, W_POSTD = 20, W_NEXT = 21, W_ROWEND = 22,
        L_PTR = 23, L_PTRD = 24, L_IROW = 25, L_IROWD = 26, L_IENT = 27, L_SYND = 28, L_AXSD = 29, L_PREN = 30, L_PRE2 = 31,
        L_ENTEND = 32, L_NEXTE = 33,
        E_LUT1 = 34, E_W1 = 35, E_R1 = 36, E_W2 = 37, E_R2 = 38, E_UPD = 39, E_UPDW = 40, E_SHD = 41, E_ELIG = 42, E_ELIGW = 43,
        R_ROW = 44, R_ROWD = 45, R_SHD = 46, R_SLOT = 47, R_EL = 48, R_ELW = 49, R_UPD = 50, R_UPDW = 51, R_NEXT = 52, R_ROWEND = 53,
        H_ACC = 54, H_WAIT = 55, K_ACC = 56, K_WAIT = 57, R_ADV = 58, S_FEEDW = 59;
    reg [6:0] st, hret, kret, wret, eret;
    reg [255:0] hbuf, rowbuf, shbuf, ibuf;
    reg [NLB:0] ni; reg [ALB:0] ai; reg [28:0] cur; reg half; reg [3:0] lane;
    reg [11:0] isi8 [0:7]; reg [11:0] pre_isi, post_isi, dcur;
    reg [16:0] pre, post; reg pre_axon;
    reg [8:0] plen, ro, lr; reg [22:0] paddr, synrow, rr; reg [1:0] slot; reg [2:0] ie;
    reg row_dirty, sh_loaded, sh_dirty, ltp_ev;
    reg [14:0] i_main, i_y;
    reg signed [27:0] praw_r, prew_r;
    integer L;
    wire [63:0]  ent    = rowbuf[64*slot +: 64];
    wire [63:0]  hent   = hbuf[64*slot +: 64];
    wire         entp   = (ent[63:61] == 3'd0) && (ent[21:18] != 4'd0);
    wire         hentp  = (hent[63:61] == 3'd0) && (hent[21:18] != 4'd0);
    wire [22:0]  shrow  = SHADOW_BASE + (synrow - PLASTIC_START);
    reg  [3:0]   any_el_v;
    always @(*) for (L = 0; L < 4; L = L + 1)
        any_el_v[L] = (hbuf[64*L + 61 +: 3] == 3'd0) && (hbuf[64*L + 18 +: 4] != 4'd0) && elig[hbuf[64*L + 18 +: 4]];
    wire         rentel = (ent[63:61] == 3'd0) && (ent[21:18] != 4'd0) && elig[ent[21:18]];
    assign lut_rd = e_v ? {le[rl], e_la} : lut_a;
    assign busy = (st != S_IDLE);
    assign hrsp_ready = (st == H_WAIT);
    function [11:0] dclip(input [31:0] dt); dclip = (dt > 32'd4095) ? 12'd4095 : dt[11:0]; endfunction

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; p4_done <= 1'b0; reward_done <= 1'b0; hreq_valid <= 1'b0; lk_v <= 1'b0; u_v <= 1'b0; e_v <= 1'b0; lut_a <= 15'd0;
        end else begin
            p4_done <= 1'b0; reward_done <= 1'b0; u_v <= 1'b0; e_v <= 1'b0;
            case (st)
            S_IDLE: if (p4_start) st <= S_FEEDW;
                    else if (reward_req) begin rr <= PLASTIC_START; st <= R_ROW; end
            S_FEEDW: if (feed_done) begin ai <= 0; st <= S_AX_NEXT; end
            // ---- 1. firing axon rows: interval and new 32-bit stamp per firing axon, then its LTD walk -------
            S_AX_NEXT: if (ai < acount) begin cur <= alist[ai[ALB-1:0]]; half <= 1'b0; st <= S_AX_HALF; end
                       else begin ni <= 0; st <= S_N_NEXT; end
            S_AX_HALF: if ((half ? cur[15:8] : cur[7:0]) == 8'd0) st <= S_AX_HDONE;
                       else begin hreq_we <= 1'b0; hreq_addr <= AXON_STAMP_BASE + {cur[28:16], half}; hret <= S_AX_STAMPS;
                                  hreq_valid <= 1'b1; st <= H_ACC; end
            S_AX_STAMPS: begin
                for (L = 0; L < 8; L = L + 1) begin
                    isi8[L] <= dclip(t32 - hbuf[32*L +: 32]);
                    hreq_wdata[32*L +: 32] <= (half ? cur[8+L] : cur[L]) ? t32 : hbuf[32*L +: 32];
                end
                hreq_we <= 1'b1; hreq_addr <= AXON_STAMP_BASE + {cur[28:16], half}; lane <= 4'd0; hret <= S_AX_LANE;
                hreq_valid <= 1'b1; st <= H_ACC;
            end
            S_AX_LANE: if (lane == 4'd8) st <= S_AX_HDONE;
                       else if (half ? cur[8 + lane[2:0]] : cur[lane[2:0]]) begin
                           pre <= {cur[28:16], half, lane[2:0]}; pre_axon <= 1'b1; pre_isi <= isi8[lane[2:0]];
                           lane <= lane + 1'b1; wret <= S_AX_LANE; st <= W_PTR;
                       end else lane <= lane + 1'b1;
            S_AX_HDONE: if (!half) begin half <= 1'b1; st <= S_AX_HALF; end else begin ai <= ai + 1'b1; st <= S_AX_NEXT; end
            // ---- 2. firing neurons, LTD as presynaptic ---------------------------------------------------------
            S_N_NEXT: if (ni < ncount) begin cur <= nlist[ni[NLB-1:0]]; lane <= 4'd0; st <= S_N_LANE; end
                      else begin ni <= 0; st <= S_P_NEXT; end
            S_N_LANE: if (cur[lane]) begin lk_i <= {cur[28:16], lane}; kret <= S_N_ISI; lk_v <= 1'b1; st <= K_ACC; end
                      else st <= S_N_RET;
            S_N_ISI:  begin pre <= {cur[28:16], lane}; pre_axon <= 1'b0; pre_isi <= ns_isi; wret <= S_N_RET; st <= W_PTR; end
            S_N_RET:  if (lane == 4'd15) begin ni <= ni + 1'b1; st <= S_N_NEXT; end else begin lane <= lane + 1'b1; st <= S_N_LANE; end
            // ---- 3. firing neurons, LTP as postsynaptic ---------------------------------------------------------
            S_P_NEXT: if (ni < ncount) begin cur <= nlist[ni[NLB-1:0]]; lane <= 4'd0; st <= S_P_LANE; end
                      else st <= S_DONE;
            S_P_LANE: if (cur[lane]) begin lk_i <= {cur[28:16], lane}; kret <= S_P_ISI; lk_v <= 1'b1; st <= K_ACC; end
                      else st <= S_P_RET;
            S_P_ISI:  begin post <= {cur[28:16], lane}; post_isi <= ns_isi; wret <= S_P_RET; st <= L_PTR; end
            S_P_RET:  if (lane == 4'd15) begin ni <= ni + 1'b1; st <= S_P_NEXT; end else begin lane <= lane + 1'b1; st <= S_P_LANE; end
            S_DONE:   begin p4_done <= 1'b1; st <= S_IDLE; end
            // ---- LTD walk: every plastic entry of pre's outgoing list -------------------------------------------
            W_PTR:  begin hreq_we <= 1'b0; hreq_addr <= (pre_axon ? AXON_PTR_BASE : NRN_PTR_BASE) + pre[16:3]; hret <= W_PTRD;
                          hreq_valid <= 1'b1; st <= H_ACC; end
            W_PTRD: if (hbuf[32*pre[2:0] +: 23] == 23'd0) st <= wret;
                    else begin plen <= hbuf[32*pre[2:0] + 23 +: 9]; paddr <= hbuf[32*pre[2:0] +: 23]; ro <= 9'd0; st <= W_ROW; end
            W_ROW:  if (ro > plen) st <= wret;
                    else begin synrow <= paddr + ro; hreq_we <= 1'b0; hreq_addr <= paddr + ro; hret <= W_ROWD; hreq_valid <= 1'b1; st <= H_ACC; end
            W_ROWD: begin rowbuf <= hbuf; row_dirty <= 1'b0; sh_loaded <= 1'b0; sh_dirty <= 1'b0; slot <= 2'd0; st <= W_SLOT; end
            W_SLOT: if (entp) begin rl <= ent[21:18]; lk_i <= {ent[60:48], POST_GROUP(ro, slot)}; kret <= W_POSTD; lk_v <= 1'b1; st <= K_ACC; end
                    else st <= W_NEXT;
            W_POSTD: if (ns_d == 12'd0) st <= W_NEXT;                    // pre and post fired in the same step
                     else begin ltp_ev <= 1'b0; i_main <= {lm[rl], ns_d}; i_y <= {lx[rl], pre_isi}; eret <= W_NEXT; st <= E_LUT1; end
            W_NEXT: if (slot == 2'd3) st <= W_ROWEND; else begin slot <= slot + 1'b1; st <= W_SLOT; end
            W_ROWEND:
                if (row_dirty) begin row_dirty <= 1'b0; hreq_we <= 1'b1; hreq_addr <= synrow; hreq_wdata <= rowbuf; hret <= W_ROWEND; hreq_valid <= 1'b1; st <= H_ACC; end
                else if (sh_dirty) begin sh_dirty <= 1'b0; hreq_we <= 1'b1; hreq_addr <= shrow; hreq_wdata <= shbuf; hret <= W_ROWEND; hreq_valid <= 1'b1; st <= H_ACC; end
                else begin ro <= ro + 1'b1; st <= W_ROW; end
            // ---- LTP walk: every entry of post's incoming list ------------------------------------------------
            L_PTR:  begin hreq_we <= 1'b0; hreq_addr <= INC_PTR_BASE + post[16:3]; hret <= L_PTRD; hreq_valid <= 1'b1; st <= H_ACC; end
            L_PTRD: if (hbuf[32*post[2:0] +: 23] == 23'd0) st <= wret;
                    else begin plen <= hbuf[32*post[2:0] + 23 +: 9]; paddr <= hbuf[32*post[2:0] +: 23]; lr <= 9'd0; st <= L_IROW; end
            L_IROW: if (lr > plen) st <= wret;
                    else begin hreq_we <= 1'b0; hreq_addr <= paddr + lr; hret <= L_IROWD; hreq_valid <= 1'b1; st <= H_ACC; end
            L_IROWD: begin ibuf <= hbuf; ie <= 3'd0; st <= L_IENT; end
            L_IENT: if (ibuf[32*ie + 31]) begin
                        synrow <= ibuf[32*ie +: 23]; slot <= ibuf[32*ie + 29 +: 2];
                        hreq_we <= 1'b0; hreq_addr <= ibuf[32*ie +: 23]; hret <= L_SYND; hreq_valid <= 1'b1; st <= H_ACC;
                    end else st <= L_NEXTE;
            L_SYND: begin
                rowbuf <= hbuf; row_dirty <= 1'b0; sh_loaded <= 1'b0; sh_dirty <= 1'b0;
                if (!hentp) st <= L_NEXTE;
                else begin
                    rl <= hent[21:18];
                    if (hent[17]) begin                                     // axon pre: 32-bit stamp in HBM
                        pre <= hent[16:0]; hreq_we <= 1'b0; hreq_addr <= AXON_STAMP_BASE + hent[16:3]; hret <= L_AXSD;
                        hreq_valid <= 1'b1; st <= H_ACC;
                    end else begin lk_i <= hent[16:0]; kret <= L_PREN; lk_v <= 1'b1; st <= K_ACC; end
                end
            end
            L_AXSD: begin dcur <= dclip(t32 - hbuf[32*pre[2:0] +: 32]); st <= L_PRE2; end
            L_PREN: begin dcur <= ns_d; st <= L_PRE2; end
            L_PRE2: if (dcur == 12'd0) st <= L_NEXTE;
                    else begin ltp_ev <= 1'b1; i_main <= {lp[rl], dcur}; i_y <= {ly[rl], post_isi}; eret <= L_ENTEND; st <= E_LUT1; end
            L_ENTEND:
                if (row_dirty) begin row_dirty <= 1'b0; hreq_we <= 1'b1; hreq_addr <= synrow; hreq_wdata <= rowbuf; hret <= L_ENTEND; hreq_valid <= 1'b1; st <= H_ACC; end
                else if (sh_dirty) begin sh_dirty <= 1'b0; hreq_we <= 1'b1; hreq_addr <= shrow; hreq_wdata <= shbuf; hret <= L_ENTEND; hreq_valid <= 1'b1; st <= H_ACC; end
                else st <= L_NEXTE;
            L_NEXTE: if (ie == 3'd7) begin lr <= lr + 1'b1; st <= L_IROW; end else begin ie <= ie + 1'b1; st <= L_IENT; end
            // ---- one event on the entry in hand (rowbuf, slot, rule rl) ---------------------------------------
            E_LUT1: begin lut_a <= i_main; st <= E_W1; end
            E_W1:   st <= E_R1;
            E_R1:   begin u_trm <= lut_q; lut_a <= i_y; st <= E_W2; end
            E_W2:   st <= E_R2;
            E_R2:   begin u_try <= lut_q; st <= E_UPD; end
            E_UPD:  begin u_v <= 1'b1; u_ltp <= ltp_ev; u_dir <= 1'b0; u_w <= ent[47:32]; u_g <= neuromod_g; st <= E_UPDW; end
            E_UPDW: if (u_ov) begin
                        if (!elig[rl]) begin
                            if (u_wn != $signed(ent[47:32])) begin rowbuf[64*slot + 32 +: 16] <= u_wn; row_dirty <= 1'b1; end
                            st <= eret;
                        end else begin
                            praw_r <= u_praw;
                            if (sh_loaded) st <= E_ELIG;
                            else begin hreq_we <= 1'b0; hreq_addr <= shrow; hret <= E_SHD; hreq_valid <= 1'b1; st <= H_ACC; end
                        end
                    end
            E_SHD:  begin shbuf <= hbuf; sh_loaded <= 1'b1; st <= E_ELIG; end
            E_ELIG: begin e_v <= 1'b1; e_rew <= 1'b0; e_e <= shbuf[64*slot +: 32]; e_te <= shbuf[64*slot + 32 +: 32]; e_pev <= praw_r; st <= E_ELIGW; end
            E_ELIGW: if (e_ov) begin shbuf[64*slot +: 64] <= {e_ten, e_en}; sh_dirty <= 1'b1; st <= eret; end
            // ---- reward sweep over the plastic rows ----------------------------------------------------------
            R_ROW:  if (rr >= PLASTIC_END) begin reward_done <= 1'b1; st <= S_IDLE; end
                    else begin synrow <= rr; hreq_we <= 1'b0; hreq_addr <= rr; hret <= R_ROWD; hreq_valid <= 1'b1; st <= H_ACC; end
            R_ROWD: begin
                rowbuf <= hbuf; row_dirty <= 1'b0; slot <= 2'd0;
                if (any_el_v == 4'd0) begin rr <= rr + 1'b1; st <= R_ROW; end
                else begin hreq_we <= 1'b0; hreq_addr <= shrow; hret <= R_SHD; hreq_valid <= 1'b1; st <= H_ACC; end
            end
            R_SHD:  begin shbuf <= hbuf; st <= R_SLOT; end
            R_SLOT: if (rentel) begin rl <= ent[21:18]; st <= R_EL; end else st <= R_NEXT;
            R_EL:   begin e_v <= 1'b1; e_rew <= 1'b1; e_e <= shbuf[64*slot +: 32]; e_te <= shbuf[64*slot + 32 +: 32]; e_pev <= 28'sd0; st <= R_ELW; end
            R_ELW:  if (e_ov) begin shbuf[64*slot +: 64] <= {e_ten, e_en}; prew_r <= e_pr; st <= R_UPD; end
            R_UPD:  begin u_v <= 1'b1; u_ltp <= 1'b0; u_dir <= 1'b1; u_pd <= prew_r; u_w <= ent[47:32]; u_g <= 8'd128; st <= R_UPDW; end
            R_UPDW: if (u_ov) begin
                        if (u_wn != $signed(ent[47:32])) begin rowbuf[64*slot + 32 +: 16] <= u_wn; row_dirty <= 1'b1; end
                        st <= R_NEXT;
                    end
            R_NEXT: if (slot == 2'd3) st <= R_ROWEND; else begin slot <= slot + 1'b1; st <= R_SLOT; end
            R_ROWEND:
                if (row_dirty) begin row_dirty <= 1'b0; hreq_we <= 1'b1; hreq_addr <= synrow; hreq_wdata <= rowbuf; hret <= R_ROWEND; hreq_valid <= 1'b1; st <= H_ACC; end
                else begin hreq_we <= 1'b1; hreq_addr <= shrow; hreq_wdata <= shbuf; hret <= R_ADV; hreq_valid <= 1'b1; st <= H_ACC; end
            R_ADV:  begin rr <= rr + 1'b1; st <= R_ROW; end
            // ---- HBM request / response, stamp lookup ---------------------------------------------------------
            H_ACC:  if (hreq_ready) begin hreq_valid <= 1'b0; st <= hreq_we ? hret : H_WAIT; end
            H_WAIT: if (hrsp_valid) begin hbuf <= hrsp_rdata; st <= hret; end
            K_ACC:  if (ns_lk_ready) begin lk_v <= 1'b0; st <= K_WAIT; end
            K_WAIT: if (ns_lk_ov) st <= kret;
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
