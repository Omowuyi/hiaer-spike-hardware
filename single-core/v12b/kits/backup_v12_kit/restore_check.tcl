# restore_check.tcl -- run on the RESTORED project: every referenced file exists, no IP locked, and the design
# elaborates exactly as the build's elaboration gate did.  Env: R_XPR, OUTD.
open_project $::env(R_XPR)
set miss 0; set n 0
set mutl 0
foreach fl [get_files -all] { incr n; if {![file exists [file normalize $fl]]} { if {[string match "*/utils_1/*" $fl]} { incr mutl } else { incr miss; puts "MISSING $fl" } } }
puts "RESTORE_FILES $n MISSING $miss MISSING_UTILS $mutl"
puts "LOCKED_IPS [llength [get_ips -quiet -filter {IS_LOCKED == 1}]] ([join [lsort [get_ips -quiet -filter {IS_LOCKED == 1}]] { }])"
report_ip_status -file $::env(OUTD)/ip_status_restored.txt
puts "RUNS [join [get_runs] { }]"
synth_design -rtl -top sixteen_core_noc_top -name rtl_restore_check
puts "RESTORE_ELAB_DONE"
close_project
