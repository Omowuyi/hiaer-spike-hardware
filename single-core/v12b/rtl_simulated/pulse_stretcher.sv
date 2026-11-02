`timescale 1ns / 1ps

module pulse_stretcher #(
    parameter ACTIVE="high",
    parameter pulse_width = 2
) (
    input pulse_in,
    input clk,
    output pulse_out
    );
    reg [$clog2(pulse_width+1)-1:0] counter;
    generate
        if(ACTIVE == "high") begin
            always @(posedge clk) begin
                if(pulse_in) counter <= pulse_width;
                else begin
                    if(counter > 0) counter <= counter-1;
                end
            end
            assign pulse_out = counter > 0;
        end else if(ACTIVE == "low") begin
            always @(posedge clk) begin
                if(~pulse_in) counter <= pulse_width;
                else begin
                    if(counter > 0) counter <= counter-1;
                end
            end
            assign pulse_out = ~(counter > 0);
        end
    endgenerate
endmodule
