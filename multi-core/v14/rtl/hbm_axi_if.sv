//=============================================================================
// hbm_axi_if.sv
//
// The AXI interface between each core and its HBM channel.
//
// WHY THIS FILE EXISTS
// sixteen_core_top_firefly.sv declares
//
//     hbm_axi_if hbm [31:0] ();
//
// at line 114 and passes hbm[i] to each core_wrapper as .m_axi_hbm.  The
// interface itself was never in the project -- `grep -rl "interface hbm_axi_if"`
// across every tree returns nothing -- so the top was written against a design
// that had it and it has to be declared here.  Without it the top elaborates to
// a black box and nothing HBM-related resolves, which also took down
// axon_delay_buffer, delay_buffer and stdp_controller: they sit inside `core`,
// which cannot elaborate without its HBM port.
//
// SIGNAL WIDTHS
// Taken from the tie-off block in the top itself (lines ~297-320), which drives
// every field for the unused channels 16-31:
//
//     araddr 33   arburst 2   arid 6   arlen 4   arsize 3   arvalid 1
//     awaddr 33   awburst 2   awid 6   awlen 4   awsize 3   awvalid 1
//     wdata 256   wstrb 32    wlast 1  wvalid 1
//     rready 1    bready 1
//
// The response fields are not tied off there because they are inputs to the
// core, so their widths follow from the HBM controller: 256-bit data, 6-bit ID,
// 2-bit response.  arlen is 4 bits rather than AXI4's 8, matching the HBM
// controller's burst limit.
//
// MODPORTS
// Master is the core side, Slave the HBM controller side.  The top connects
// hbm[i] to core_wrapper without naming a modport, so the full interface is
// visible there; the modports are declared for anything that wants to be
// explicit.
//=============================================================================

`timescale 1ns / 1ps

interface hbm_axi_if #(
    parameter ADDR_WIDTH = 33,
    parameter DATA_WIDTH = 256,
    parameter ID_WIDTH   = 6,
    parameter LEN_WIDTH  = 4
)();

    // ---- read address ----
    logic [ADDR_WIDTH-1:0]   araddr;
    logic [1:0]              arburst;
    logic [ID_WIDTH-1:0]     arid;
    logic [LEN_WIDTH-1:0]    arlen;
    logic [2:0]              arsize;
    logic                    arvalid;
    logic                    arready;

    // ---- read data ----
    logic [DATA_WIDTH-1:0]   rdata;
    logic [ID_WIDTH-1:0]     rid;
    logic [1:0]              rresp;
    logic                    rlast;
    logic                    rvalid;
    logic                    rready;

    // ---- write address ----
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic [1:0]              awburst;
    logic [ID_WIDTH-1:0]     awid;
    logic [LEN_WIDTH-1:0]    awlen;
    logic [2:0]              awsize;
    logic                    awvalid;
    logic                    awready;

    // ---- write data ----
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wlast;
    logic                    wvalid;
    logic                    wready;

    // ---- write response ----
    logic [ID_WIDTH-1:0]     bid;
    logic [1:0]              bresp;
    logic                    bvalid;
    logic                    bready;

    // Core side: drives the address and write channels, receives responses.
    modport Master (
        output araddr, arburst, arid, arlen, arsize, arvalid,
        input  arready,
        input  rdata, rid, rresp, rlast, rvalid,
        output rready,
        output awaddr, awburst, awid, awlen, awsize, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready
    );

    // HBM controller side: the mirror of the above.
    modport Slave (
        input  araddr, arburst, arid, arlen, arsize, arvalid,
        output arready,
        output rdata, rid, rresp, rlast, rvalid,
        input  rready,
        input  awaddr, awburst, awid, awlen, awsize, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready
    );

endinterface
