`timescale 1ns / 1ps

// verilator lint_off PINCONNECTEMPTY
// verilator lint_off PINMISSING

`define FIFO(DEPTH) \
module FIFO_``DEPTH ( \
    FIFO_input.Sink i, \
    FIFO_output.Source o \
    ); \
    fifo_``DEPTH``_wide IP( \
        .clk(i.clk), \
        .srst(i.reset), \
        .din(i.din), \
        .wr_en(i.wren), \
        .full(i.full), \
        .dout(o.dout), \
        .rd_en(o.rden), \
        .empty(o.empty), \
        .wr_rst_busy(), \
        .rd_rst_busy() \
    ); \
endmodule

`FIFO(17)
`FIFO(32)
`FIFO(33)
`FIFO(34)
//`FIFO(256)
//`FIFO(280)

`define sync_FIFO(DEPTH) \
module sync_FIFO_``DEPTH ( \
    FIFO_input.Sink i, \
    FIFO_output.Source o \
    ); \
    sync_fifo_``DEPTH``_wide IP( \
        .wr_clk(i.clk), \
        .rd_clk(o.clk), \
        .srst(i.reset), \
        .din(i.din), \
        .wr_en(i.wren), \
        .full(i.full), \
        .dout(o.dout), \
        .rd_en(o.rden), \
        .empty(o.empty), \
        .wr_rst_busy(), \
        .rd_rst_busy() \
    ); \
endmodule

`sync_FIFO(256)
`sync_FIFO(280)
`sync_FIFO(32)
`sync_FIFO(17)

/* ////Independent CLK Built-in FIFO (To reduce BRAM utilization)
module hbmdata_FIFO_``DEPTH ( \
    FIFO_input.Sink i, \
    FIFO_output.Source o \
    ); \
    hbmdata_FIFO_``DEPTH``_wide IP( \
        .wr_clk(i.clk), \
        .rd_clk(o.clk), \
        .srst(i.reset), \
        .din(i.din), \
        .wr_en(i.wren), \
        .full(i.full), \
        .dout(o.dout), \
        .rd_en(o.rden), \
        .empty(o.empty), \
        .wr_rst_busy(), \
        .rd_rst_busy() \
    ); \
endmodule
*/
//Independent CLK FIFO Distributed RAM (To reduce BRAM utilization)

`define hbmdata_FIFO(DEPTH) \
module hbmdata_FIFO_``DEPTH ( \
    FIFO_input.Sink i, \
    FIFO_output.Source o \
    ); \
    hbmdata_FIFO_``DEPTH``_wide IP( \
        .wr_clk(i.clk), \
        .rd_clk(o.clk), \
        .rst(i.reset), \
        .din(i.din), \
        .wr_en(i.wren), \
        .full(i.full), \
        .dout(o.dout), \
        .rd_en(o.rden), \
        .empty(o.empty) \
    ); \
endmodule
`hbmdata_FIFO(512)

module FIFO_512(
    FIFO_input.Sink i,
    FIFO_output.Source o
    );
    fifo_512_wide IP(
        .wr_clk(i.clk),
        .rst(i.reset),
        .din(i.din),
        .wr_en(i.wren),
        .full(i.full),
        .rd_clk(o.clk),
        .dout(o.dout),
        .rd_en(o.rden),
        .empty(o.empty)
    );
endmodule

module FIFO_512_ASYNC(
    AXIStream_simple.Slave s,
    AXIStream_simple.Master m
    );
    fifo_512_wide_async IP(
        .s_aclk(s.aclk),
        .s_aresetn(s.aresetn),
        .s_axis_tdata(s.tdata),
        .s_axis_tvalid(s.tvalid),
        .s_axis_tready(s.tready),
        .m_aclk(m.aclk),
        .m_axis_tvalid(m.tvalid),
        .m_axis_tdata(m.tdata),
        .m_axis_tready(m.tready)
    );
endmodule
module EEP_BRAM(
    RAM.Slave s
);
    eep_bram IP(
        .clka(s.clk),
        .clkb(s.clk),
        .ena(s.wren),
        .enb(s.rden),
        .wea(s.wren),
        .addra(s.waddr),
        .addrb(s.raddr),
        .dina(s.wdata),
        .doutb(s.rdata)
    );
endmodule
/*
// Previously Arranged as 16kx8 for 8 NGs
// Now arranged as 8kx16 for 16 NGs:- 13-bit addr, 16-bit width
module EEP_BRAM(
    RAM.Slave s
);
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(13),
        .ADDR_WIDTH_B(13),
        .MEMORY_SIZE(131072),
        .MEMORY_PRIMITIVE("block"),
        .WRITE_DATA_WIDTH_A(16),
        .CLOCKING_MODE("common_clock"),
        .WRITE_MODE_B("read_first"),
        .READ_LATENCY_B(3)
    ) IP (
        .clka(s.clk),
        .clkb(s.clk),
        .rstb(0),
        .ena(s.wren),
        .enb(s.rden),
        .regceb(1),
        .wea(s.wren),
        .addra(s.waddr),
        .addrb(s.raddr),
        .dina(s.wdata),
        .doutb(s.rdata),
        .sleep(0)
    );
endmodule
*/
//URAM size = Neurons per Neuron Group (16384) X bitwidth per neuron (16)
// or shared URAM size = Number of Rows (8192) X bitwidth per neuron (16) x number of neurons per row (2) = 262144
// Now shared URAM size = Number of Rows (8192) X bitwidth per neuron (36) x number of neurons per row (2) = 589824

//Now 16 NGs, 8192 Neurons per NG.
//12 bit adddress to each, Memory size = Number of Rows (4096) X bitwidth per neuron (36) x number of neurons per row (2) = 294912

module URAM(
    RAM.Slave s
);
     xpm_memory_sdpram #(
        .ADDR_WIDTH_A(12),
        .ADDR_WIDTH_B(12),
        .MEMORY_SIZE(294912),
        .MEMORY_PRIMITIVE("ultra"),
        .CLOCKING_MODE("common_clock"),
        .WRITE_DATA_WIDTH_A(72),
        .WRITE_MODE_B("read_first"),
        .READ_LATENCY_B(1),
        .ECC_MODE("no_ecc")
    ) IP (
        .clka(s.clk),
        .clkb(s.clk),
        .rstb(0),
        .ena(s.wren),
        .enb(s.rden),
        .regceb(1),
        .wea(s.wren),
        .addra(s.waddr),
        .addrb(s.raddr),
        .dina(s.wdata),
        .doutb(s.rdata),
        .sleep(0)
    );
endmodule

// verilator lint_on PINCONNECTEMPTY
// verilator lint_on PINMISSING

/*
// xpm_memory_sdpram: Simple Dual Port RAM
// Xilinx Parameterized Macro, version 2018.1
xpm_memory_sdpram #(
.ADDR_WIDTH_A(6), // DECIMAL
.ADDR_WIDTH_B(6), // DECIMAL
.AUTO_SLEEP_TIME(0), // DECIMAL
.BYTE_WRITE_WIDTH_A(32), // DECIMAL
.CLOCKING_MODE("common_clock"), // String
.ECC_MODE("no_ecc"), // String
.MEMORY_INIT_FILE("none"), // String
.MEMORY_INIT_PARAM("0"), // String
.MEMORY_OPTIMIZATION("true"), // String
.MEMORY_PRIMITIVE("auto"), // String
.MEMORY_SIZE(2048), // DECIMAL
.MESSAGE_CONTROL(0), // DECIMAL
.READ_DATA_WIDTH_B(32), // DECIMAL
.READ_LATENCY_B(2), // DECIMAL
.READ_RESET_VALUE_B("0"), // String
.USE_EMBEDDED_CONSTRAINT(0), // DECIMAL
.USE_MEM_INIT(1), // DECIMAL
.WAKEUP_TIME("disable_sleep"), // String
.WRITE_DATA_WIDTH_A(32), // DECIMAL
.WRITE_MODE_B("no_change") // String
)
*/