# archive_v12.tcl -- run by backup_v12.sh vivado.  Lists every file the project references (missing ones stop the
# archive; ones outside the project directory are reported, archive_project brings them in), reports IP status, then
# writes the self-contained Vivado archive.  Env: V12_XPR, OUTD, ZIP.
open_project $::env(V12_XPR)
set pdir [file normalize [get_property DIRECTORY [current_project]]]
set all [get_files -all]; set ext 0; set miss_src 0; set miss_gen 0; set miss_utl 0
set f [open $::env(OUTD)/project_files.txt w]
foreach fl $all {
    set p [file normalize $fl]
    set gen [expr {[string match "*/multi_core.gen/*" $p] || [string match "*ip_user_files*" $p]}]
    set utl [string match "*/utils_1/*" $p]   ;# incremental-synthesis reference checkpoints: not design sources
    if {![file exists $p]} { if {$utl} { incr miss_utl; puts $f "MISSING_UTILS $p" } elseif {$gen} { incr miss_gen; puts $f "MISSING $p" } else { incr miss_src; puts $f "MISSING $p" } } else { puts $f "OK $p" }
    if {[string first "$pdir/" $p] != 0} { incr ext; puts $f "EXTERNAL $p" }
}
close $f
puts "FILES_TOTAL [llength $all] EXTERNAL $ext MISSING_SOURCES $miss_src MISSING_GENERATED $miss_gen MISSING_UTILS $miss_utl"
report_ip_status -file $::env(OUTD)/ip_status.txt
puts "LOCKED_IPS [llength [get_ips -quiet -filter {IS_LOCKED == 1}]] ([join [lsort [get_ips -quiet -filter {IS_LOCKED == 1}]] { }])"
if {$miss_src > 0} { puts "ARCHIVE_ABORT: $miss_src referenced source file(s) missing (see project_files.txt)"; close_project; exit 1 }
synth_design -rtl -top sixteen_core_noc_top -name rtl_original   ;# the expected elaboration for the restore proof
puts "ORIGINAL_ELAB_DONE"
close_design
archive_project $::env(ZIP) -force -include_config_settings
puts "ARCHIVE_OK"
close_project
