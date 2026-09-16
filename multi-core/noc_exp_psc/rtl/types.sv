interface AXI4 #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input aclk,
    input aresetn
);
    wire [ADDR_WIDTH-1:0] araddr;
    wire                [1:0] arburst;
    wire                [5:0] arid;
    wire            [3:0] arlen;
    wire                       arready;
    wire                [2:0] arsize;
    wire                  arvalid;
    // Write address
    wire  [ADDR_WIDTH-1:0] awaddr;
    wire                [1:0] awburst;
    wire                [5:0] awid;
    wire                [3:0] awlen;
    wire                       awready;
    wire                [2:0] awsize;
    wire                  awvalid;
    // Write response
    wire                 [5:0] bid;
    wire                  bready;
    wire                 [1:0] bresp;
    wire                       bvalid;
    // Read response
    wire  [DATA_WIDTH-1:0] rdata;
    wire                 [5:0] rid;
    wire                       rlast;
    wire                  rready;
    wire                 [1:0] rresp;
    wire                       rvalid;
    // Write data
    wire [DATA_WIDTH-1:0] wdata;
    wire                      wlast;
    wire                       wready;
    wire [(DATA_WIDTH/8)-1:0] wstrb;
    wire                  wvalid;
    
    modport Slave(
        input aclk, aresetn, araddr, arburst, arid, arlen, arsize, arvalid, awaddr, awburst, awid, awlen, awsize, awvalid, bready, rready, wdata, wlast, wstrb, wvalid,
        output arready, awready, bid, bresp, bvalid, rdata, rid, rlast, rresp, rvalid, wready
    );
    modport Master(
        input aclk, aresetn, arready, awready, bid, bresp, bvalid, rdata, rid, rlast, rresp, rvalid, wready,
        output araddr, arburst, arid, arlen, arsize, arvalid, awaddr, awburst, awid, awlen, awsize, awvalid, bready, rready, wdata, wlast, wstrb, wvalid
    );
endinterface

interface AXILite #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input aclk,
    input aresetn
);
    wire [ADDR_WIDTH-1:0] araddr;
    wire                       arready;
    wire                  arvalid;
    // Write address
    wire  [ADDR_WIDTH-1:0] awaddr;
    wire                       awready;
    wire                  awvalid;
    // Write response
    wire                  bready;
    wire                 [1:0] bresp;
    wire                       bvalid;
    // Read response
    wire  [DATA_WIDTH-1:0] rdata;
    wire                  rready;
    wire                 [1:0] rresp;
    wire                       rvalid;
    // Write data
    wire [DATA_WIDTH-1:0] wdata;
    wire                       wready;
    wire [(DATA_WIDTH/8)-1:0] wstrb;
    wire                  wvalid;
    modport Slave(
        input aclk, aresetn, araddr, arvalid, awaddr, awvalid, bready, rready, wdata, wstrb, wvalid,
        output arready, awready, bresp, bvalid, rdata, rresp, rvalid, wready
    );
    modport Master(
        input aclk, aresetn, arready, awready, bresp, bvalid, rdata, rresp, rvalid, wready,
        output araddr, arvalid, awaddr, awvalid, bready, rready, wdata, wstrb, wvalid
    );
endinterface

interface AXIStream #(
    parameter DATA_WIDTH = 32,
    parameter TID_WIDTH = 1
) (
    input aclk,
    input aresetn
);
    wire [DATA_WIDTH-1:0] tdata;
    wire tvalid;
    wire tlast;
    wire [(DATA_WIDTH/8)-1:0] tkeep;
    wire [TID_WIDTH-1:0] tdest;
    wire tready;
    
    modport Slave(
        input aclk, aresetn, tdata, tvalid, tlast, tkeep, tdest,
        output tready
    );
    modport Master(
        input aclk, aresetn, tready,
        output tdata, tvalid, tlast, tkeep, tdest
    );
endinterface

interface AXIStream_simple #(
    parameter DATA_WIDTH = 32
) (
    input aclk,
    input aresetn
);
    wire [DATA_WIDTH-1:0] tdata;
    wire tvalid;
    wire tready;
    
    modport Slave(
        input aclk, aresetn, tdata, tvalid,
        output tready
    );
    modport Master(
        input aclk, aresetn, tready,
        output tdata, tvalid
    );
endinterface

interface FIFO_input #(
    parameter DATA_WIDTH = 32
) (
    input clk,
    input reset
);
    wire [DATA_WIDTH-1:0] din;
    wire wren;
    wire full;
    
    modport Sink(
        input clk, reset, din, wren,
        output full
    );
    modport Source(
        input clk, reset, full,
        output din, wren
    );
endinterface

interface FIFO_output #(
    parameter DATA_WIDTH = 32
) (
    input clk,
    input reset
);
    wire [DATA_WIDTH-1:0] dout;
    wire rden;
    wire empty;
    
    modport Source(
        input clk, reset, rden,
        output empty, dout
    );
    modport Sink(
        input clk, reset, dout, empty,
        output rden 
    );
endinterface

interface RAM #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 14
) (
    input clk
);
    wire wren;
    wire rden;
    wire [ADDR_WIDTH-1:0] waddr;
    wire [ADDR_WIDTH-1:0] raddr;
    wire [DATA_WIDTH-1:0] wdata;
    wire [DATA_WIDTH-1:0] rdata;
    
    modport Slave(
        input clk, wren, rden, waddr, raddr, wdata,
        output rdata
    );
    modport Master(
        input clk, rdata,
        output wren, rden, waddr, raddr, wdata
    );
endinterface