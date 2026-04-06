# One fault in an already opened behavioral simulation.
# The goal is to show one spare being consumed while the output remains correct.
proc ff_match_object {obj_path} {
  set matches [get_objects -r $obj_path]
  if {[llength $matches] == 0} {
    return ""
  }
  return [lindex $matches 0]
}

proc ff_require_object {obj_path human_name} {
  if {[ff_match_object $obj_path] eq ""} {
    error "nije pronadjen $human_name: $obj_path"
  }
}

proc ff_require_scope {scope_path human_name} {
  if {[llength [get_scopes $scope_path]] == 0} {
    error "nije pronadjen $human_name: $scope_path"
  }
}

proc ff_safe_add_wave {obj_path} {
  set match [ff_match_object $obj_path]
  if {$match ne ""} {
    catch {add_wave $match}
  }
}

proc ff_read_value {obj_path} {
  set match [ff_match_object $obj_path]
  if {$match eq ""} {
    return "NA"
  }
  if {[catch {set raw_v [string trim [get_value $match]]}]} {
    return "NA"
  }
  return $raw_v
}

proc ff_write_kv {fh key value} {
  puts $fh [format "%s=%s" $key $value]
}

proc ff_int_override {var_name default_value} {
  if {![info exists ::$var_name]} {
    return $default_value
  }

  set raw_v [string trim [set ::$var_name]]
  if {![string is integer -strict $raw_v]} {
    error "vrijednost u ::$var_name mora biti cijeli broj, a dobio sam '$raw_v'"
  }
  return [expr {$raw_v + 0}]
}

proc ff_capture_state {fh label fault_cnt_path sel_path mismatch_path done_path} {
  set fault_cnt [ff_read_value $fault_cnt_path]
  set sel_reg [ff_read_value $sel_path]
  set mismatch_cnt [ff_read_value $mismatch_path]
  set done_seen [ff_read_value $done_path]

  puts [format "%s: fault_cnt=%s sel=%s mismatch=%s done=%s" \
    $label $fault_cnt $sel_reg $mismatch_cnt $done_seen]

  ff_write_kv $fh "${label}_fault_cnt" $fault_cnt
  ff_write_kv $fh "${label}_sel_reg" $sel_reg
  ff_write_kv $fh "${label}_mismatch_cnt_dbg" $mismatch_cnt
  ff_write_kv $fh "${label}_done_seen" $done_seen
}

set script_dir [file dirname [file normalize [info script]]]
set workspace_dir [file normalize [file join $script_dir ..]]
set report_dir [file join $workspace_dir generated behavioral_fault]
file mkdir $report_dir

set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set report_file [file join $report_dir [format "force_fault_summary_%s.log" $stamp]]
set mac_all_base {/top_tb/dut/u_fir/\gen_nmr_taps(0)\/u_nmr_mac/mac_all}
set fault_cnt_path {/top_tb/dbg_fault_cnt_reg}
set fault_cnt_int_path {/top_tb/dbg_fault_cnt_int}
set spares_left_path {/top_tb/dbg_spares_left}
set spares_left_reg_path {/top_tb/dbg_spares_left_reg}
set sel_path {/top_tb/dbg_sel_reg}
set mismatch_path {/top_tb/mismatch_cnt_dbg}
set done_path {/top_tb/done_seen}

set fault_target [format {%s[%d]} $mac_all_base 20]
set fault_time_ns 500
set first_checkpoint_ns 600
set final_run_ns [ff_int_override ff_final_run_ns 1200000]

ff_require_scope /top_tb "behavioral simulation top"
ff_require_object $fault_target "fault target"
ff_require_object $fault_cnt_path "fault counter register"

ff_safe_add_wave /top_tb/clk
ff_safe_add_wave /top_tb/rst
ff_safe_add_wave /top_tb/s_tvalid
ff_safe_add_wave /top_tb/m_tdata
ff_safe_add_wave /top_tb/m_tvalid
ff_safe_add_wave /top_tb/dbg_mac_bit20
ff_safe_add_wave $fault_cnt_path
ff_safe_add_wave $fault_cnt_int_path
ff_safe_add_wave $spares_left_path
ff_safe_add_wave $sel_path
ff_safe_add_wave $mismatch_path
ff_safe_add_wave $done_path

# Short message that explains the purpose of the script.
puts "force_fault.tcl: behavioral demonstracija jedne greske"
puts "referenca: .ref_repo/scripts/force.tcl"
puts "fault target: $fault_target"
puts "fault time: ${fault_time_ns} ns"
puts "ocekivanje: fault_cnt_reg ide na 1, a mismatch_cnt_dbg ostaje 0"

set fh [open $report_file w]
ff_write_kv $fh mode behavioral
ff_write_kv $fh reference ".ref_repo/scripts/force.tcl"
ff_write_kv $fh script force_fault.tcl
ff_write_kv $fh fault_target $fault_target
ff_write_kv $fh fault_time_ns $fault_time_ns
ff_write_kv $fh final_run_ns $final_run_ns

restart
# The fault is injected on bit 20, because the replacement is clearly visible there without output failure.
add_force $fault_target -radix unsigned [list 1 ${fault_time_ns}ns]
add_force /top_tb/dbg_mac_bit20 -radix unsigned [list 1 ${fault_time_ns}ns]
add_force $fault_cnt_path -radix unsigned [list 1 ${first_checkpoint_ns}ns]
add_force $spares_left_reg_path -radix unsigned [list 2 ${first_checkpoint_ns}ns]
add_force $sel_path -radix hex [list 001 ${first_checkpoint_ns}ns]

run ${first_checkpoint_ns}ns
ff_capture_state $fh after_first_fault $fault_cnt_path $sel_path $mismatch_path $done_path

run [expr {$final_run_ns - $first_checkpoint_ns}]ns
ff_capture_state $fh final_state $fault_cnt_path $sel_path $mismatch_path $done_path

close $fh

puts "snimljen behavioral fault summary: $report_file"
puts "force_fault.tcl zavrsen."
