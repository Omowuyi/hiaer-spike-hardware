`timescale 1ns/1ps
module tb_at2;
    localparam RB=13, NG=16, TB=5, TR=4;
    logic clk=0, rstn=0; always #4 clk=~clk;
    logic [TB-1:0] ts=0; logic tick=0;
    logic rf=0; logic [RB-1:0] ra=0; logic [NG-1:0] rm=0;
    logic rd=0; logic [16:0] ri=0; logic [TR-1:0] rdata;
    integer pass=0, fail=0;

    axon_trace_mem #(.NUM_ROWS(64), .ROW_BITS(RB), .NUM_GROUPS(NG),
                     .TS_BITS(TB), .TRACE_BITS(TR)) dut (
        .clk(clk), .resetn(rstn), .timestep(ts), .timestep_tick(tick),
        .row_fired(rf), .row_addr(ra), .row_mask(rm),
        .trace_rd_en(rd), .trace_rd_idx(ri), .trace_rd_data(rdata));

    task fire(input int row, input logic [NG-1:0] mask);
        begin @(posedge clk); ra<=row[RB-1:0]; rm<=mask; rf<=1;
              @(posedge clk); rf<=0; end
    endtask
    task read(input int row, input int grp);
        begin @(posedge clk); ri<={row[12:0], grp[3:0]}; rd<=1;
              @(posedge clk); rd<=0; @(posedge clk); #1; end
    endtask
    task chk(input string s, input logic ok);
        begin if(ok) begin $display("  PASS %s",s); pass++; end
              else begin $display("  FAIL %s (got %0d)",s,rdata); fail++; end end
    endtask

    initial begin
        repeat(4) @(posedge clk); rstn<=1; repeat(2) @(posedge clk);
        $display("axon trace -- EEP row + 16-bit group mask");

        read(5,3); chk("never fired -> 0", rdata==0);

        // row 5, only groups 0 and 3
        ts=5'd10; fire(5, 16'b0000_0000_0000_1001);
        read(5,0); chk("row 5 group 0 fired -> 15", rdata==15);
        read(5,3); chk("row 5 group 3 fired -> 15", rdata==15);
        read(5,1); chk("row 5 group 1 NOT in mask -> 0", rdata==0);
        read(5,2); chk("row 5 group 2 NOT in mask -> 0", rdata==0);
        read(6,0); chk("row 6 untouched -> 0", rdata==0);

        ts=5'd11; read(5,0); chk("1 timestep later -> 7", rdata==7);
        ts=5'd12; read(5,0); chk("2 later -> 3", rdata==3);
        ts=5'd13; read(5,0); chk("3 later -> 1", rdata==1);
        ts=5'd14; read(5,0); chk("4 later -> 0", rdata==0);

        // group independence across a second row
        ts=5'd14; fire(9, 16'b1000_0000_0000_0000);
        read(9,15); chk("row 9 group 15 -> 15", rdata==15);
        read(9,0);  chk("row 9 group 0 not fired -> 0", rdata==0);
        read(5,3);  chk("row 5 group 3 still decayed -> 0", rdata==0);

        // wrap
        ts=5'd30; fire(2, 16'h0002);
        ts=5'd1;  read(2,1); chk("timestep wrap, age 3 -> 1", rdata==1);

        $display("");
        $display("  %0d passed, %0d failed", pass, fail);
        $finish;
    end
    initial begin #100000; $display("TIMEOUT"); $finish; end
endmodule
