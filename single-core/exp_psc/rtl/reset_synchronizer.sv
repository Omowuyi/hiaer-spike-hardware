`timescale 1ns / 1ps

module reset_synchronizer #(
    parameter ACTIVE = "high"
) (
    input reset_in,
    input clk,
    output reg reset_out
    );
    
    reg q;
    
    generate
        if(ACTIVE == "high") begin
            always @(posedge clk or posedge reset_in) begin
                if (reset_in) {reset_out, q} <= 2'b11;
                else {reset_out, q} <= {q, 1'b0};
            end
        end else if(ACTIVE == "low") begin
            always @(posedge clk or negedge reset_in) begin
                if (~reset_in) {reset_out, q} <= 2'b00;
                else {reset_out, q} <= {q, 1'b1};
            end
        end
    endgenerate
endmodule
