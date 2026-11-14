`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// stdp_update_unit.v (v3) -- one plasticity update, bit-exact with stdp_ref.py v3 (event_p + apply_p).
//   sgn(v) = -1 if v < 0 else +1;  scale(v, m, k) = sgn(v) * ((|v| * m) >> k)
//   a   = (s2 ? -A2 : A2) + (s3 ? -((A3 * tr_y) >> 15) : (A3 * tr_y) >> 15)     (A2/A3/s2/s3 of this event type)
//   LTP : p = scale(a, tr_main, 15)                       LTD : p = -scale(a, tr_main, 15) + (s0 ? -A0 : A0)
//   direct (reward path): p = p_direct (|p| <= 2^26 - 1)
//   soft: s = p >= 0 ? max(w_max - w, 0) : max(w - w_min, 0);  f = (s * inv_range) >> 16;  p = scale(p, f, 16)
//   p = scale(p, g, 7);  dw = sgn(p) * ((|p| + 128) >> 8);  w_new = clamp(w + dw);  skip: w_new = w (unchanged)
//   p_raw: the event's p before bounds and gating (accumulated by eligibility rules instead of applied)
// Six registered stages, one update per cycle.  Widths cover every input value.
//////////////////////////////////////////////////////////////////////////////////
module stdp_update_unit (
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire               in_ltp,         // 1 = LTP event (post fired), 0 = LTD event (pre fired)
    input  wire               in_skip,        // same-step pair: no change at all
    input  wire               in_direct,      // reward path: use p_direct
    input  wire signed [27:0] p_direct,
    input  wire signed [15:0] w,
    input  wire [15:0]        tr_main,        // x (LTP) or o (LTD), Q1.15
    input  wire [15:0]        tr_y,           // y (LTP) or r (LTD), Q1.15
    input  wire [15:0]        A2, A3,         // magnitudes for this event type
    input  wire               s2, s3,         // signs (1 = negative)
    input  wire [15:0]        A0,             // per-pre-spike constant (LTD events only)
    input  wire               s0,
    input  wire signed [15:0] w_min, w_max,
    input  wire [31:0]        inv_range,      // min(round(2^32 / (w_max - w_min)), 2^32 - 1)
    input  wire               soft_bound,
    input  wire [7:0]         g,
    output reg                out_valid,
    output reg  signed [15:0] w_new,
    output reg  signed [27:0] p_raw
);
    // ---- stage 1: signed amplitude ----
    wire [31:0] t3full = {16'd0, A3} * {16'd0, tr_y};
    wire [16:0] t3 = t3full[31:15];
    wire signed [18:0] a_w = (s2 ? -$signed({3'b000, A2}) : $signed({3'b000, A2})) + (s3 ? -$signed({2'b00, t3}) : $signed({2'b00, t3}));
    reg v1, ltp1, skip1, dir1, s01, soft1;
    reg signed [18:0] a1;
    reg signed [27:0] pd1;
    reg [15:0] tr1, A01;
    reg signed [15:0] w1, wmin1, wmax1;
    reg [31:0] inv1; reg [7:0] g1;
    always @(posedge clk) begin
        if (rst) v1 <= 1'b0;
        else begin
            v1 <= in_valid; ltp1 <= in_ltp; skip1 <= in_skip; dir1 <= in_direct; pd1 <= p_direct;
            a1 <= a_w; tr1 <= tr_main; A01 <= A0; s01 <= s0;
            w1 <= w; wmin1 <= w_min; wmax1 <= w_max; inv1 <= inv_range; soft1 <= soft_bound; g1 <= g;
        end
    end
    // ---- stage 2: p = scale(a, tr, 15), LTD negation and constant, or the direct value ----
    wire [17:0] a_mag = a1[18] ? -a1[17:0] : a1[17:0];
    wire [33:0] am = {16'd0, a_mag} * {18'd0, tr1};
    wire signed [20:0] pe = a1[18] ? -$signed({2'b00, am[33:15]}) : $signed({2'b00, am[33:15]});
    wire signed [21:0] pl = -$signed({pe[20], pe}) + (s01 ? -$signed({6'd0, A01}) : $signed({6'd0, A01}));
    wire signed [27:0] p_ev = ltp1 ? {{7{pe[20]}}, pe} : {{6{pl[21]}}, pl};
    reg v2, skip2, soft2;
    reg signed [27:0] p2;
    reg signed [15:0] w2, wmin2, wmax2;
    reg [31:0] inv2; reg [7:0] g2;
    always @(posedge clk) begin
        if (rst) v2 <= 1'b0;
        else begin
            v2 <= v1; skip2 <= skip1; soft2 <= soft1; w2 <= w1; wmin2 <= wmin1; wmax2 <= wmax1; inv2 <= inv1; g2 <= g1;
            p2 <= dir1 ? pd1 : p_ev;
        end
    end
    // ---- stage 3: bound distance by the direction of the change, factor f = (s * inv) >> 16 ----
    wire signed [17:0] dist_hi = $signed({wmax2[15], wmax2}) - $signed({w2[15], w2});
    wire signed [17:0] dist_lo = $signed({w2[15], w2}) - $signed({wmin2[15], wmin2});
    wire [16:0] s_w = p2[27] ? (dist_lo[17] ? 17'd0 : dist_lo[16:0]) : (dist_hi[17] ? 17'd0 : dist_hi[16:0]);
    wire [48:0] sinv = {32'd0, s_w} * {17'd0, inv2};
    reg v3, skip3, soft3, neg3;
    reg [26:0] pm3;
    reg [32:0] f3;
    reg signed [27:0] praw3;
    reg signed [15:0] w3, wmin3, wmax3;
    reg [7:0] g3;
    always @(posedge clk) begin
        if (rst) v3 <= 1'b0;
        else begin
            v3 <= v2; skip3 <= skip2; soft3 <= soft2; w3 <= w2; wmin3 <= wmin2; wmax3 <= wmax2; g3 <= g2;
            neg3 <= p2[27]; pm3 <= p2[27] ? -p2[26:0] : p2[26:0]; f3 <= sinv[48:16]; praw3 <= p2;
        end
    end
    // ---- stage 4: soft bound ----
    wire [59:0] pf = {33'd0, pm3} * {27'd0, f3};
    reg v4, skip4, neg4;
    reg [43:0] pm4;
    reg signed [27:0] praw4;
    reg signed [15:0] w4, wmin4, wmax4;
    reg [7:0] g4;
    always @(posedge clk) begin
        if (rst) v4 <= 1'b0;
        else begin
            v4 <= v3; skip4 <= skip3; neg4 <= neg3; w4 <= w3; wmin4 <= wmin3; wmax4 <= wmax3; g4 <= g3; praw4 <= praw3;
            pm4 <= soft3 ? pf[59:16] : {17'd0, pm3};
        end
    end
    // ---- stage 5: gating ----
    wire [51:0] pg = {8'd0, pm4} * {44'd0, g4};
    reg v5, skip5, neg5;
    reg [44:0] pm5;
    reg signed [27:0] praw5;
    reg signed [15:0] w5, wmin5, wmax5;
    always @(posedge clk) begin
        if (rst) v5 <= 1'b0;
        else begin
            v5 <= v4; skip5 <= skip4; neg5 <= neg4; w5 <= w4; wmin5 <= wmin4; wmax5 <= wmax4; praw5 <= praw4;
            pm5 <= pg[51:7];
        end
    end
    // ---- stage 6: round, apply, clamp ----
    wire [45:0] dwm = ({1'b0, pm5} + 46'd128) >> 8;                     // < 2^38
    wire signed [48:0] wext = {{33{w5[15]}}, w5};
    wire signed [48:0] wsum = neg5 ? (wext - $signed({3'b000, dwm})) : (wext + $signed({3'b000, dwm}));
    wire signed [48:0] lo = {{33{wmin5[15]}}, wmin5};
    wire signed [48:0] hi = {{33{wmax5[15]}}, wmax5};
    wire signed [48:0] wc = (wsum < lo) ? lo : (wsum > hi) ? hi : wsum;
    always @(posedge clk) begin
        if (rst) out_valid <= 1'b0;
        else begin
            out_valid <= v5;
            w_new <= skip5 ? w5 : wc[15:0];
            p_raw <= praw5;
        end
    end
endmodule
