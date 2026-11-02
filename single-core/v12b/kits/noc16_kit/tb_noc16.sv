`timescale 1ps/1fs
// tb_noc16 -- the 16 cores of sixteen_core_noc_top with noc_integration, wired exactly as the build's top level:
// each core its own CORE_ID (v13 R1) and core_number, its own HBM model; core_exec_run tied to 0 and the router's
// host-bound outputs always ready (both as in the build).  The single-core testbench's clocks, HBM model, memory
// initialisation, host pause and TX capture are reused per core.
//
// Host model: one recorded command stream (64-byte lines, as hs_bridge sends them); each command goes to the core in its
// byte 62 (core << 3), in order per core.  Waits mirror hs_bridge's multi-core step: executes are sent to every core
// without waiting; before the next non-execute command every pending step-done (AB CD) must have arrived; before an
// execute the core is idle; after a read (opcode 3, bit 53 clear) that core's CC CC reply must arrive.
// Output: <OUT>_tx.txt -- every response packet as the merged host stream sees it: "time_ns true_core hex";
//         <OUT>_log.txt -- steps, timeouts, per-core counts, host-bound router spikes ("HOSTSPIKE core addr").
module tb_noc16;
    localparam int N = 16;
    realtime core_half, hbm_half;
    reg aclk = 0, aclk450 = 0, rstn = 0;
    initial begin
        int clk_cfg;
        if (!$value$plusargs("CLK=%d", clk_cfg)) clk_cfg = 0;
        if (clk_cfg == 1) begin core_half = 8000.0;   hbm_half = 4000.0;   end
        else              begin core_half = 7961.023; hbm_half = 2000.664; end
    end
    initial begin #1; forever #(core_half) aclk = ~aclk; end
    initial begin #1; forever #(hbm_half)  aclk450 = ~aclk450; end

    // ---------------------------------------------------------------- host pause (as tb_core_trace)
    int host_pause_us, host_period_us; reg host_pause = 1'b0, host_pause_q = 1'b0;
    initial begin
        if (!$value$plusargs("HOST_PAUSE_US=%d", host_pause_us)) host_pause_us = 0;
        if (!$value$plusargs("HOST_PERIOD_US=%d", host_period_us)) host_period_us = 0;
        if (host_pause_us > 0 && host_period_us > host_pause_us)
            forever begin #((host_period_us - host_pause_us) * 1_000_000); host_pause = 1'b1; #(host_pause_us * 1_000_000); host_pause = 1'b0; end
    end
    always @(posedge aclk) host_pause_q <= host_pause;

    // ---------------------------------------------------------------- outputs
    string out_prefix; int ftx, flog;
    real tscale_ns = 0.001;
    initial begin realtime t0; t0 = $realtime; #1000; tscale_ns = 1.0 / ($realtime - t0); end
    initial $timeformat(-9, 1, " ns", 14);
    initial begin
        if (!$value$plusargs("OUT=%s", out_prefix)) out_prefix = "tb";
        ftx  = $fopen({out_prefix, "_tx.txt"}, "w");
        flog = $fopen({out_prefix, "_log.txt"}, "w");
    end
    initial forever begin #10_000_000; $fflush(flog); $fflush(ftx); end
    function automatic string hex64(input [511:0] w);
        string s = "";
        for (int i = 0; i < 64; i++) s = {s, $sformatf("%02x", w[8*i +: 8])};
        return s;
    endfunction

    // ---------------------------------------------------------------- per-core state shared with the host model
    bit [511:0] cmdq [N][$];                       // commands waiting to be pushed into each core's RX FIFO
    int n_abcd [N], n_cccc [N], n_eeee [N], n_other [N], pushed [N];
    bit idle [N];
    initial for (int k = 0; k < N; k++) begin n_abcd[k] = 0; n_cccc[k] = 0; n_eeee[k] = 0; n_other[k] = 0; pushed[k] = 0; end

    // ---------------------------------------------------------------- NoC wiring (as sixteen_core_noc_top)
    wire [18:0] core_noc_out_addr   [15:0];
    wire        core_noc_out_valid  [15:0];
    wire        core_noc_out_ready  [15:0];
    wire [18:0] core_noc_relay_din  [15:0];
    wire        core_noc_relay_wren [15:0];
    wire        core_noc_relay_full [15:0];
    wire        core_exec_run_w     [15:0];
    wire        core_route_cfg_valid [15:0];
    wire [9:0]  core_route_cfg_addr  [15:0];
    wire [5:0]  core_route_cfg_data  [15:0];
    wire [18:0] noc_host_addr  [15:0];
    wire        noc_host_valid [15:0];
    wire        noc_host_ready [15:0];

    genvar j;
    generate for (j = 0; j < N; j = j + 1) begin : c
        assign core_exec_run_w[j] = 1'b0;          // build: core_exec_run_tieoff
        assign noc_host_ready[j]  = 1'b1;          // build: gen_noc_host_ready
        FIFO_input  #(512) rx  (.clk(aclk), .reset(~rstn));
        FIFO_output #(512) tx  (.clk(aclk), .reset(~rstn));
        AXI4 #(33, 256)    hbm (.aclk(aclk450), .aresetn(rstn));
        reg [511:0] rx_din = '0; reg rx_wren = 1'b0;
        assign rx.din = rx_din; assign rx.wren = rx_wren;
        assign tx.rden = ~tx.empty & ~host_pause_q;
        wire [3:0] iep_state, hbm_tx_state; wire [2:0] eep_state; wire p1_done, p2_done;
        core_wrapper #(.CORE_ID(4'(j))) cw (
            .aclk(aclk), .aclk450(aclk450),
            .async_resetn(rstn), .async_resetn450(rstn),
            .core_number(5'(j)),
            .hbm(hbm), .rxFIFO_in(rx), .txFIFO_out(tx),
            .iep_curr_state(iep_state), .hbm_curr_state(hbm_tx_state), .eep_curr_state(eep_state),
            .exec_hbm_rx_phase1_done(p1_done), .exec_hbm_rx_phase2_done(p2_done),
            .route_cfg_valid(core_route_cfg_valid[j]), .route_cfg_addr(core_route_cfg_addr[j]), .route_cfg_data(core_route_cfg_data[j]),
            .noc_spike_out_addr(core_noc_out_addr[j]), .noc_spike_out_valid(core_noc_out_valid[j]),
            .noc_spike_out_ready(core_noc_out_ready[j]),
            .noc_relay_din(core_noc_relay_din[j]), .noc_relay_wren(core_noc_relay_wren[j]), .noc_relay_full(core_noc_relay_full[j])
        );
        initial begin                                // as tb_core_trace: these memories start at zero
            for (int i = 0; i < $size(cw.inst.axon_delay.delay_table); i++) cw.inst.axon_delay.delay_table[i] = '0;
            for (int i = 0; i < $size(cw.inst.axon_delay.buffer_mem);  i++) cw.inst.axon_delay.buffer_mem[i]  = '0;
            for (int i = 0; i < $size(cw.inst.dbuf.delay_mem);         i++) cw.inst.dbuf.delay_mem[i]         = '0;
        end
        hbm_axi_model hbm_mem (.aclk(aclk450), .aresetn(rstn), .s(hbm));
        always @(negedge aclk)
            idle[j] <= cw.inst.rxFIFO_out.empty && cw.inst.ci2hbm_out.empty && hbm_tx_state == 4'd1 && iep_state == 4'd1;
        // commands for this core, in order, into its RX FIFO
        initial forever begin
            @(negedge aclk);
            if (cmdq[j].size() > 0) begin
                rx_din = cmdq[j].pop_front(); rx_wren = 1'b1;
                while (rx.full) @(negedge aclk);
                @(negedge aclk); rx_wren = 1'b0;
                pushed[j]++;
            end
        end
        // this core's responses, as the merged host stream sees them, with the true source core
        always @(negedge aclk) if (rstn && !tx.empty && !host_pause_q) begin
            $fwrite(ftx, "%0.1f %0d %s\n", $realtime * tscale_ns, j, hex64(tx.dout));
            case (tx.dout[511:496])
                16'hABCD: n_abcd[j]++;
                16'hCCCC: n_cccc[j]++;
                16'hEEEE: n_eeee[j]++;
                default:  if (tx.dout[511:496] != 16'hFFFF) n_other[j]++;
            endcase
        end
        // spikes the router sends towards the host (unconsumed in the build)
        always @(posedge aclk) if (rstn && noc_host_valid[j])
            $fwrite(flog, "%t  HOSTSPIKE %0d %05h\n", $realtime, j, noc_host_addr[j]);
    end endgenerate

    noc_integration #(
        .NUM_CORES (16)
    ) noc_i (
        .clk                  (aclk),
        .resetn               (rstn),
        .core_spike_out_addr  (core_noc_out_addr),
        .core_spike_out_valid (core_noc_out_valid),
        .core_spike_out_ready (core_noc_out_ready),
        .core_relay_din       (core_noc_relay_din),
        .core_relay_wren      (core_noc_relay_wren),
        .core_relay_full      (core_noc_relay_full),
        .core_exec_run        (core_exec_run_w),
        .host_spike_addr      (noc_host_addr),
        .host_spike_valid     (noc_host_valid),
        .host_spike_ready     (noc_host_ready),
        .core_route_cfg_valid (core_route_cfg_valid),
        .core_route_cfg_addr  (core_route_cfg_addr),
        .core_route_cfg_data  (core_route_cfg_data)
    );
    // relays delivered into each core (from the NoC), for the log
    int n_relay [N]; initial for (int k = 0; k < N; k++) n_relay[k] = 0;
    always @(posedge aclk) if (rstn) for (int k = 0; k < N; k++) if (core_noc_relay_wren[k]) begin
        n_relay[k]++;
        $fwrite(flog, "%t  RELAY core %0d addr %05h\n", $realtime, k, core_noc_relay_din[k]);
    end

    // ---------------------------------------------------------------- host model
    task automatic wait_idle(input int k);
        int quiet = 0;
        while (quiet < 64) begin
            @(negedge aclk);
            if (cmdq[k].size() == 0 && idle[k]) quiet++; else quiet = 0;
        end
    endtask
    int expect_abcd [N]; int nexec = 0, nstep = 0, nread = 0, ntimeout = 0;
    initial for (int k = 0; k < N; k++) expect_abcd[k] = 0;
    task automatic flush_pending();                 // hs_bridge: every executed core's step-done before anything else
        realtime t0 = $realtime; bit any = 0;
        for (int k = 0; k < N; k++) if (n_abcd[k] < expect_abcd[k]) any = 1;
        if (!any) return;
        forever begin
            bit all = 1;
            for (int k = 0; k < N; k++) if (n_abcd[k] < expect_abcd[k]) all = 0;
            if (all) break;
            if ($realtime - t0 > 400_000.0 * 1000.0) begin
                ntimeout++;
                for (int k = 0; k < N; k++) if (n_abcd[k] < expect_abcd[k])
                    $fwrite(flog, "%t  STEP %0d: TIMEOUT, core %0d step-done %0d of %0d\n", $realtime, nstep, k, n_abcd[k], expect_abcd[k]);
                for (int k = 0; k < N; k++) expect_abcd[k] = n_abcd[k];
                break;
            end
            @(posedge aclk);
        end
        $fwrite(flog, "%t  STEP %0d: step-done from every executed core\n", $realtime, nstep);
        nstep++;
        #5_000_000;                                  // as tb_core_trace: host turnaround after a step
    endtask

    initial begin
        string stim, line; int fs, nline = 0, b, k; bit ok; reg [511:0] w;
        if (!$value$plusargs("STIM=%s", stim)) begin $display("no +STIM"); $finish; end
        fs = $fopen(stim, "r");
        if (fs == 0) begin $display("cannot open %s", stim); $finish; end
        #2_000_000 rstn = 1'b1;
        begin int init_us; if (!$value$plusargs("INIT_US=%d", init_us)) init_us = 150; #(init_us * 1_000_000); end
        $fwrite(flog, "%t  replay start: %s (16 cores)\n", $realtime, stim);
        while (!$feof(fs)) begin
            if ($fgets(line, fs) == 0) break;
            if (line.len() < 2) continue;
            if (line.substr(0, 0) == "#") begin $fwrite(flog, "%t  %s", $realtime, line); continue; end
            for (int i = 0; i < 64; i++) begin
                if ($sscanf(line.substr(2*i, 2*i+1), "%h", b) != 1) b = 0;
                w[8*i +: 8] = b[7:0];
            end
            nline++;
            k = w[503:499];
            if (k >= N) begin $fwrite(flog, "%t  command %0d for core %0d: no such core, skipped\n", $realtime, nline, k); continue; end
            if (w[511:504] == 8'd6) begin                       // execute: no wait (hs_bridge executes every core first)
                wait_idle(k);
                cmdq[k].push_back(w); expect_abcd[k]++; nexec++;
            end else begin
                flush_pending();
                if (w[511:504] == 8'd3 && w[53] == 1'b0) begin   // read: that core's CC CC reply
                    int base; realtime t0;              // assigned here: an initializer in a static block runs once
                    base = n_cccc[k]; cmdq[k].push_back(w); t0 = $realtime;
                    while (n_cccc[k] <= base) begin
                        @(posedge aclk);
                        if ($realtime - t0 > 200_000.0 * 1000.0) begin
                            ntimeout++; $fwrite(flog, "%t  READ %0d core %0d: TIMEOUT, no CC CC in 200 us\n", $realtime, nread, k); break;
                        end
                    end
                    nread++;
                end else
                    cmdq[k].push_back(w);
            end
        end
        flush_pending();
        begin int drain_us; if (!$value$plusargs("DRAIN_US=%d", drain_us)) drain_us = 20; #(drain_us * 1_000_000); end
        $fwrite(flog, "%t  replay end: %0d commands, %0d executes, %0d steps, %0d reads, %0d timeouts\n",
                $realtime, nline, nexec, nstep, nread, ntimeout);
        for (int q = 0; q < N; q++)
            if (pushed[q] || n_abcd[q] || n_relay[q])
                $fwrite(flog, "%t  core %0d: commands %0d, ABCD %0d, CCCC %0d, EEEE %0d, other %0d, relays in %0d\n",
                        $realtime, q, pushed[q], n_abcd[q], n_cccc[q], n_eeee[q], n_other[q], n_relay[q]);
        $fclose(fs); $fclose(ftx); $fclose(flog);
        $finish;
    end
endmodule
