
create_waiver -internal -scope -type CDC -id {CDC-10} -user "aurora64b66b" -tags "1128038"  -desc "Reviewd by team, safe to waive off"  -to [get_pins -of [get_cells -hier -filter {name =~ *syncstages_ff_reg*}] -filter {REF_PIN_NAME == D}]

create_waiver -internal -scope -type CDC -id {CDC-11} -user "aurora64b66b" -tags "1128038"  -desc "Reviewd by team, safe to waive off" -to [get_pins -of [get_cells -hier -filter {name =~ *syncstages_ff_reg*}] -filter {REF_PIN_NAME == D}]

  
create_waiver -internal -scope -type CDC -id {CDC-11} -user "aurora64b66b" -tags "1128038" -desc "Reviewed by team, safe to waive off" -to [get_pins -of [get_cells -hier -filter {name =~ *cdc_to_reg}] -filter {REF_PIN_NAME == D}]
create_waiver -internal -scope -type CDC -id {CDC-10} -user "aurora64b66b" -tags "1128038" -desc "Reviewed by team, safe to waive off" -to [get_pins -of [get_cells -hier -filter {name =~ *cdc_to_reg}] -filter {REF_PIN_NAME == D}] 


create_waiver -internal -scope -type CDC -id {CDC-7} -user "aurora64b66b" -desc "Reviewed by team, safe to waive off" -to [get_pins -of [get_cells -hier -filter {name =~ *fabric_pcs_rst_extend_cntr_reg[*]}] -filter {REF_PIN_NAME == CLR}] 
create_waiver -internal -scope -type CDC -id {CDC-7} -user "aurora64b66b" -desc "Reviewed by team, safe to waive off" -to [get_pins -of [get_cells -hier -filter {name =~ *fabric_pcs_rst_extend_cntr_reg[*]_inv}] -filter {REF_PIN_NAME == PRE}]
create_waiver -internal -scope -type CDC -id {CDC-7} -user "aurora64b66b" -desc "Reviewed by team, safe to waive off" -to [get_pins -of [get_cells -hier -filter {name =~ *fabric_pcs_rst_extend_cntr_reg[*]_fret}] -filter {REF_PIN_NAME == CLR}] 
create_waiver -internal -scope -type CDC -id {CDC-7} -user "aurora64b66b" -desc "Reviewed by team, safe to waive off" -to [get_pins -of [get_cells -hier -filter {name =~ *fabric_pcs_rst_extend_cntr_reg[*]_fret}] -filter {REF_PIN_NAME == PRE}]
