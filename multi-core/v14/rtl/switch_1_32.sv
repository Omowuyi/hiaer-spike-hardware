`timescale 1ns / 1ps

module pcie_tdest_generator(
    AXIStream_simple.Slave s,
    AXIStream.Master m
);
    assign m.tdata = s.tdata;
    assign m.tvalid = s.tvalid;
    assign m.tdest = s.tdata[503:499];
    assign s.tready = m.tready;
    //assign m.tlast = 1'b1;
    assign m.tlast = 1'b0;
    assign m.tkeep = 64'hFFFF_FFFF_FFFF_FFFF;
endmodule

module switch_1_32(
    AXIStream.Slave s,
    AXIStream_simple.Master m[31:0]
    );
    wire [511:0] data [1:0];
    wire valid [1:0];
    wire ready [1:0];
    wire [4:0] dest [1:0];
    
    wire [32*512 - 1:0] out_data;
    wire [31:0] out_valid;
    wire [31:0] out_ready;
    
    
    genvar j;
    switch_1_2 in_switch(
        .aclk(s.aclk),
        .aresetn(s.aresetn),
        .s_axis_tvalid(s.tvalid),
        .s_axis_tdata(s.tdata),
        .s_axis_tdest(s.tdest),
        .s_axis_tready(s.tready),
        .m_axis_tvalid({valid[1], valid[0]}),
        .m_axis_tdata({data[1], data[0]}),
        .m_axis_tdest({dest[1], dest[0]}),
        .m_axis_tready({ready[1], ready[0]})
    );
    generate
        for(j=0; j<2; j=j+1) begin
            switch_1_16 out_switch(
                .aclk(s.aclk),
                .aresetn(s.aresetn),
                .s_axis_tvalid(valid[j]),
                .s_axis_tdata(data[j]),
                .s_axis_tdest(dest[j][3:0]),
                .s_axis_tready(ready[j]),
                .m_axis_tvalid(out_valid[16*j +: 16]),
                .m_axis_tdata(out_data[16*512*j +: 16*512]),
                .m_axis_tready(out_ready[16*j +: 16])
            );
        end
        for(j=0; j<32; j=j+1) begin
            assign m[j].tdata = out_data[j*512 +: 512];
            assign m[j].tvalid = out_valid[j];
            assign out_ready[j] = m[j].tready;
        end
    endgenerate
endmodule

module switch_1_32_simple(
      input wire  aclk,
      input wire aresetn,
      input wire s_axis_tvalid,
      input wire s_axis_tready,
      input wire [511:0] s_axis_tdata,
      input wire [4 : 0] s_axis_tdest,
      output wire [31:0] m_axis_tvalid,
      input wire [31:0] m_axis_tready ,
      output wire [512*32-1 : 0] m_axis_tdata,
      output wire [32*5-1: 0] m_axis_tdest
    );
    
    wire [511:0] data [1:0];
    wire valid [1:0];
    wire ready [1:0];
    wire [4:0] dest [1:0];
    
    wire [32*512 - 1:0] out_data;
    wire [31:0] out_valid;
    wire [31:0] out_ready;
    
    
    genvar j;
    switch_1_2 in_switch(
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tdest(s_axis_tdest),
        .s_axis_tready(s_axis_tready),
        .m_axis_tvalid({valid[1], valid[0]}),
        .m_axis_tdata({data[1], data[0]}),
        .m_axis_tdest({dest[1], dest[0]}),
        .m_axis_tready({ready[1], ready[0]})
    );
    generate
        for(j=0; j<2; j=j+1) begin
            switch_1_16 out_switch(
                .aclk(aclk),
                .aresetn(aresetn),
                .s_axis_tvalid(valid[j]),
                .s_axis_tdata(data[j]),
                .s_axis_tdest(dest[j][3:0]),
                .s_axis_tready(ready[j]),
                .m_axis_tvalid(out_valid[16*j +: 16]),
                .m_axis_tdata(out_data[16*512*j +: 16*512]),
                .m_axis_tready(out_ready[16*j +: 16])
            );
        end
        
        for(j=0; j<32; j=j+1) begin
            assign m_axis_tdata[j*512 +: 512] = out_data[j*512 +: 512];
            //assign m_axis_tdata[j*512 +: 512] = s_axis_tdata;
            assign m_axis_tvalid[j] = out_valid[j];
            assign out_ready[j] = m_axis_tready[j];
        end
    endgenerate
    
    //assign m_axis_tdata = s_axis_tdata; //assign all data to be same to prevent routing congestion
    
endmodule
