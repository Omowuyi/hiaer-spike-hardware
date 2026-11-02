`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// stdp_elig_unit.v -- eligibility trace arithmetic, bit-exact with stdp_ref.py v3 (decay, elig_accumulate,
// and the change computed by reward_apply).
//   idx  = min((t - t_e) >> e_shift, 4095);  t_e' = (idx == 4095) ? t : t_e + (idx << e_shift)
//   ed   = scale(e, LUT_e[idx], 15)
//   accumulate (in_reward = 0): e' = sat32(ed + p_event)
//   reward     (in_reward = 1): p = sgn(ed)*sgn(R) * ((|ed| * |R|) >> 8);  p = sat(scale(p, eta, 8), +/-(2^26-1))
//                               e' = elig_reset ? 0 : ed   (t_e' = t when reset)
// The decay table is outside: lut_addr is presented in stage 1 and lut_data must arrive one cycle later
// (a registered block-RAM read).  Four stages.
//////////////////////////////////////////////////////////////////////////////////
module stdp_elig_unit (
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire               in_reward,
    input  wire signed [31:0] e,
    input  wire [31:0]        t_e,
    input  wire [31:0]        t,
    input  wire [3:0]         e_shift,
    input  wire signed [27:0] p_event,      // raw change from stdp_update_unit (accumulate)
    input  wire signed [15:0] R,            // reward, Q8.8
    input  wire [15:0]        eta,          // Q8.8
    input  wire               elig_reset,
    output wire [11:0]        lut_addr,
    input  wire [15:0]        lut_data,     // LUT_e[lut_addr], one cycle after lut_addr
    output reg                out_valid,
    output reg  signed [31:0] e_new,
    output reg  [31:0]        t_e_new,
    output reg  signed [27:0] p_reward
);
    // ---- stage 1: elapsed time, table index, new stamp ----
    wire [31:0] dt  = t - t_e;
    wire [31:0] sh  = dt >> e_shift;
    wire [11:0] idx = (sh > 32'd4095) ? 12'd4095 : sh[11:0];
    assign lut_addr = idx;
    reg v1, rew1, rst1;
    reg signed [31:0] e1; reg [31:0] t1, te1n;
    reg signed [27:0] pe1; reg signed [15:0] R1; reg [15:0] eta1;
    always @(posedge clk) begin
        if (rst) v1 <= 1'b0;
        else begin
            v1 <= in_valid; rew1 <= in_reward; rst1 <= elig_reset; e1 <= e; t1 <= t; pe1 <= p_event; R1 <= R; eta1 <= eta;
            te1n <= (idx == 12'd4095) ? t : (t_e + ({20'd0, idx} << e_shift));
        end
    end
    // ---- stage 2: ed = scale(e, D, 15)  (lut_data valid now) ----
    wire [31:0] emag = e1[31] ? -e1 : e1;                      // |e| <= 2^31
    wire [47:0] ed_full = {16'd0, emag} * {32'd0, lut_data};
    wire [32:0] edm = ed_full[47:15];                           // <= 2^32 (D <= 65535)
    reg v2, rew2, rst2, neg2;
    reg [32:0] edm2; reg [31:0] t2, te2n;
    reg signed [27:0] pe2; reg signed [15:0] R2; reg [15:0] eta2;
    always @(posedge clk) begin
        if (rst) v2 <= 1'b0;
        else begin
            v2 <= v1; rew2 <= rew1; rst2 <= rst1; neg2 <= e1[31]; edm2 <= edm; t2 <= t1; te2n <= te1n; pe2 <= pe1; R2 <= R1; eta2 <= eta1;
        end
    end
    // ---- stage 3: accumulate sum, or the reward product (|ed| * |R|) >> 8 ----
    wire signed [34:0] ed_s = neg2 ? -$signed({2'b00, edm2}) : $signed({2'b00, edm2});
    wire signed [35:0] acc  = {ed_s[34], ed_s} + {{8{pe2[27]}}, pe2};
    wire [15:0] Rmag = R2[15] ? -R2 : R2;
    wire [48:0] er  = {16'd0, edm2} * {33'd0, Rmag};
    wire [40:0] pr  = er[48:8];
    wire        pneg = neg2 ^ R2[15];                           // sgn(ed) * sgn(R); sgn(0) = +1
    reg v3, rew3, rst3, pneg3;
    reg signed [35:0] acc3; reg signed [34:0] ed3; reg [40:0] pr3; reg [31:0] t3, te3n; reg [15:0] eta3;
    always @(posedge clk) begin
        if (rst) v3 <= 1'b0;
        else begin
            v3 <= v2; rew3 <= rew2; rst3 <= rst2; pneg3 <= pneg; acc3 <= acc; ed3 <= ed_s; pr3 <= pr; t3 <= t2; te3n <= te2n; eta3 <= eta2;
        end
    end
    // ---- stage 4: eta scaling and saturation, trace saturation, outputs ----
    wire [56:0] pe_eta = {16'd0, pr3} * {41'd0, eta3};
    wire [48:0] pmag = pe_eta[56:8];
    wire [25:0] psat = (pmag > 49'h3FFFFFF) ? 26'h3FFFFFF : pmag[25:0];
    wire signed [35:0] EMAXS = 36'sd2147483647, EMINS = -36'sd2147483648;
    wire signed [31:0] acc_sat = (acc3 > EMAXS) ? 32'sh7FFFFFFF : (acc3 < EMINS) ? 32'sh80000000 : acc3[31:0];
    wire signed [31:0] ed_sat  = ($signed({ed3[34], ed3}) > EMAXS) ? 32'sh7FFFFFFF : ($signed({ed3[34], ed3}) < EMINS) ? 32'sh80000000 : ed3[31:0];
    always @(posedge clk) begin
        if (rst) out_valid <= 1'b0;
        else begin
            out_valid <= v3;
            p_reward  <= pneg3 ? -$signed({2'b00, psat}) : $signed({2'b00, psat});
            if (!rew3) begin e_new <= acc_sat; t_e_new <= te3n; end
            else if (rst3) begin e_new <= 32'sd0; t_e_new <= t3; end
            else begin e_new <= ed_sat; t_e_new <= te3n; end
        end
    end
endmodule
