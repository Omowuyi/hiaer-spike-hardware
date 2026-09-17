`timescale 1ns / 1ps

module switch_32_1(
    AXIStream_simple.Master m,
    AXIStream_simple.Slave s[31:0]
    );
    wire [511:0] data [1:0];
    wire valid [1:0];
    wire ready [1:0];
    
    wire [512*32 - 1:0] in_data;
    wire [31:0] in_valid;
    wire [31:0] in_ready;
    
    genvar j;
    generate
        for(j=0; j<32; j=j+1) begin
            assign in_data[j*512 +: 512] = s[j].tdata;
            assign in_valid[j] = s[j].tvalid;
            assign s[j].tready = in_ready[j];
        end
        for(j=0; j<2; j=j+1) begin
            switch_16_1 in_switch(
                .aclk(m.aclk),
                .aresetn(m.aresetn),
                .s_axis_tvalid(in_valid[16*j +: 16]),
                .s_axis_tdata(in_data[16*512*j +: 16*512]),
                .s_axis_tready(in_ready[16*j +: 16]),
                .m_axis_tvalid(valid[j]),
                .m_axis_tdata(data[j]),
                .m_axis_tready(ready[j]),
                .s_req_suppress(16'b0)
            );
        end
    endgenerate
        switch_2_1 out_switch(
        .aclk(m.aclk),
        .aresetn(m.aresetn),
        .s_axis_tvalid({valid[1], valid[0]}),
        .s_axis_tdata({data[1], data[0]}),
        .s_axis_tready({ready[1], ready[0]}),
        .m_axis_tvalid(m.tvalid),
        .m_axis_tdata(m.tdata),
        .m_axis_tready(m.tready),
        .s_req_suppress(2'b0)
    );
endmodule