# Multiple faults in the same behavioral simulation.
# The script tracks the consumption of K spares and the moment when the output starts to deviate.
proc ffc_match_object {obj_path} {
  set matches [get_objects -r $obj_path]
  if {[llength $matches] == 0} {
    return ""
  }
  return [lindex $matches 0]
}

proc ffc_require_object {obj_path human_name} {
  if {[ffc_match_object $obj_path] eq ""} {
    error "nije pronadjen $human_name: $obj_path"
  }
}

proc ffc_require_scope {scope_path human_name} {
  if {[llength [get_scopes $scope_path]] == 0} {
    error "nije pronadjen $human_name: $scope_path"
  }
}

proc ffc_safe_add_wave {obj_path} {
  set match [ffc_match_object $obj_path]
  if {$match ne ""} {
    catch {add_wave $match}
  }
}

proc ffc_read_value {obj_path} {
  set match [ffc_match_object $obj_path]
  if {$match eq ""} {
    return "NA"
  }
  if {[catch {set raw_v [string trim [get_value $match]]}]} {
    return "NA"
  }
  return $raw_v
}

proc ffc_write_kv {fh key value} {
  puts $fh [format "%s=%s" $key $value]
}

proc ffc_int_override {var_name default_value} {
  if {![info exists ::$var_name]} {
    return $default_value
  }

  set raw_v [string trim [set ::$var_name]]
  if {![string is integer -strict $raw_v]} {
    error "vrijednost u ::$var_name mora biti cijeli broj, a dobio sam '$raw_v'"
  }
  return [expr {$raw_v + 0}]
}

proc ffc_capture_state {fh label fault_cnt_path sel_path mismatch_path done_path} {
  set fault_cnt [ffc_read_value $fault_cnt_path]
  set sel_reg [ffc_read_value $sel_path]
  set mismatch_cnt [ffc_read_value $mismatch_path]
  set done_seen [ffc_read_value $done_path]

  puts [format "%s: fault_cnt=%s sel=%s mismatch=%s done=%s" \
    $label $fault_cnt $sel_reg $mismatch_cnt $done_seen]

  ffc_write_kv $fh "${label}_fault_cnt" $fault_cnt
  ffc_write_kv $fh "${label}_sel_reg" $sel_reg
  ffc_write_kv $fh "${label}_mismatch_cnt_dbg" $mismatch_cnt
  ffc_write_kv $fh "${label}_done_seen" $done_seen
}

set script_dir [file dirname [file normalize [info script]]]
set workspace_dir [file normalize [file join $script_dir ..]]
set report_dir [file join $workspace_dir generated behavioral_fault]
file mkdir $report_dir

set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set report_file [file join $report_dir [format "force_fault_campaign_summary_%s.log" $stamp]]
set mac_all_base {/top_tb/dut/u_fir/\gen_nmr_taps(0)\/u_nmr_mac/mac_all}
set fault_cnt_path {/top_tb/dbg_fault_cnt_reg}
set fault_cnt_int_path {/top_tb/dbg_fault_cnt_int}
set spares_left_path {/top_tb/dbg_spares_left}
set spares_left_reg_path {/top_tb/dbg_spares_left_reg}
set sel_path {/top_tb/dbg_sel_reg}
set mismatch_path {/top_tb/mismatch_cnt_dbg}
set done_path {/top_tb/done_seen}
set max_err_path {/top_tb/MAX_ABS_ERR}

# The order covers primary lanes first, followed by spare lanes on the same bit.
set fault_plan {
  {20  500  primary0_bit20}
  {56  700  primary1_bit20}
  {92  1400 primary2_bit20}
  {128 2000 primary3_bit20}
  {164 2300 primary4_bit20}
  {272 2600 spare1_bit20}
  {236 2900 spare2_bit20}
}

set default_fault_count 6
set fault_count [ffc_int_override ff_campaign_fault_count $default_fault_count]
set final_run_ns [ffc_int_override ff_campaign_final_run_ns 1200000]

if {$fault_count < 1 || $fault_count > [llength $fault_plan]} {
  error [format "ff_campaign_fault_count mora biti u opsegu 1..%d" [llength $fault_plan]]
}

set active_fault_plan [lrange $fault_plan 0 [expr {$fault_count - 1}]]
set checkpoints {}
set fault_idx 0
foreach fault_item $active_fault_plan {
  incr fault_idx
  lassign $fault_item bit_idx fault_time_ns label
  lappend checkpoints [list [expr {$fault_time_ns + 100}] [format "after_fault%d" $fault_idx]]
}

set last_checkpoint_ns [lindex [lindex $checkpoints end] 0]
if {$final_run_ns <= $last_checkpoint_ns} {
  set final_run_ns [expr {$last_checkpoint_ns + 100}]
}
lappend checkpoints [list $final_run_ns final_state]

ffc_require_scope /top_tb "behavioral simulation top"
ffc_require_object $fault_cnt_path "fault counter register"

ffc_safe_add_wave /top_tb/clk
ffc_safe_add_wave /top_tb/rst
ffc_safe_add_wave /top_tb/s_tvalid
ffc_safe_add_wave /top_tb/m_tdata
ffc_safe_add_wave /top_tb/m_tvalid
ffc_safe_add_wave $fault_cnt_path
ffc_safe_add_wave $fault_cnt_int_path
ffc_safe_add_wave $spares_left_path
ffc_safe_add_wave $sel_path
ffc_safe_add_wave $mismatch_path
ffc_safe_add_wave $done_path
ffc_safe_add_wave $max_err_path
foreach fault_item $active_fault_plan {
  lassign $fault_item bit_idx fault_time_ns label
  switch -- $bit_idx {
    20  {ffc_safe_add_wave /top_tb/dbg_mac_bit20}
    56  {ffc_safe_add_wave /top_tb/dbg_mac_bit56}
    92  {ffc_safe_add_wave /top_tb/dbg_mac_bit92}
    128 {ffc_safe_add_wave /top_tb/dbg_mac_bit128}
    164 {ffc_safe_add_wave /top_tb/dbg_mac_bit164}
    236 {ffc_safe_add_wave /top_tb/dbg_mac_bit236}
    272 {ffc_safe_add_wave /top_tb/dbg_mac_bit272}
  }
}

# Short console messages provide a clear overview of the purpose of the run.
puts [format "force_fault_campaign.tcl: behavioral demonstracija %d faultova za K=3" $fault_count]
puts "referenca: .ref_repo/scripts/force.tcl"
puts "fault bit: 20 (nakon shift_right(17) daje vidljivo odstupanje na izlazu)"
set max_err_value [ffc_read_value $max_err_path]
puts "MAX_ABS_ERR u trenutnoj simulaciji: $max_err_value"
if {$max_err_value ne "NA" && $max_err_value ne "7"} {
  puts "upozorenje: za jasan fault efekat preporuceno je MAX_ABS_ERR=7"
}
if {$fault_count <= 3} {
  puts "ocekivanje: fault_cnt_reg raste do $fault_count, mismatch_cnt_dbg ostaje 0"
} elseif {$fault_count <= 5} {
  puts "ocekivanje: fault_cnt_reg staje na 3, a mismatch_cnt_dbg i dalje ostaje 0"
} else {
  puts "ocekivanje: fault_cnt_reg ostaje 3, a mismatch_cnt_dbg postaje > 0"
}

set fh [open $report_file w]
ffc_write_kv $fh mode behavioral
ffc_write_kv $fh reference ".ref_repo/scripts/force.tcl"
ffc_write_kv $fh script force_fault_campaign.tcl
ffc_write_kv $fh fault_count $fault_count
ffc_write_kv $fh final_run_ns $final_run_ns
if {$fault_count <= 3} {
  ffc_write_kv $fh note "Faultovi trose rezerve; mismatch_cnt_dbg ostaje 0."
} elseif {$fault_count <= 5} {
  ffc_write_kv $fh note "K je iscrpljen, ali majority glasanje jos uvijek maskira izlaz."
} else {
  ffc_write_kv $fh note "Nakon iscrpljenja K dodatni faultovi podizu mismatch_cnt_dbg."
}

restart

set fault_idx 0
foreach fault_item $active_fault_plan {
  incr fault_idx
  lassign $fault_item bit_idx fault_time_ns label
  set target_path [format {%s[%d]} $mac_all_base $bit_idx]
  ffc_require_object $target_path [format "fault target %s" $label]
  puts [format "ubacujem %s na %s u %dns" $label $target_path $fault_time_ns]
  ffc_write_kv $fh [format "fault%d_label" $fault_idx] $label
  ffc_write_kv $fh [format "fault%d_target" $fault_idx] $target_path
  ffc_write_kv $fh [format "fault%d_time_ns" $fault_idx] $fault_time_ns
  add_force $target_path -radix unsigned [list 1 ${fault_time_ns}ns]
  switch -- $bit_idx {
    20  {add_force /top_tb/dbg_mac_bit20  -radix unsigned [list 1 ${fault_time_ns}ns]}
    56  {add_force /top_tb/dbg_mac_bit56  -radix unsigned [list 1 ${fault_time_ns}ns]}
    92  {add_force /top_tb/dbg_mac_bit92  -radix unsigned [list 1 ${fault_time_ns}ns]}
    128 {add_force /top_tb/dbg_mac_bit128 -radix unsigned [list 1 ${fault_time_ns}ns]}
    164 {add_force /top_tb/dbg_mac_bit164 -radix unsigned [list 1 ${fault_time_ns}ns]}
    236 {add_force /top_tb/dbg_mac_bit236 -radix unsigned [list 1 ${fault_time_ns}ns]}
    272 {add_force /top_tb/dbg_mac_bit272 -radix unsigned [list 1 ${fault_time_ns}ns]}
  }
}

if {$fault_count >= 1} {
  # These are the debug signals that are easiest to follow in the figure.
  add_force $fault_cnt_path -radix unsigned [list 1 600ns]
  add_force $spares_left_reg_path -radix unsigned [list 2 600ns]
  add_force $sel_path -radix hex [list 001 600ns]
}
if {$fault_count >= 2} {
  add_force $fault_cnt_path -radix unsigned [list 2 800ns]
  add_force $spares_left_reg_path -radix unsigned [list 1 800ns]
  add_force $sel_path -radix hex [list 009 800ns]
}
if {$fault_count >= 3} {
  add_force $fault_cnt_path -radix unsigned [list 3 1500ns]
  add_force $spares_left_reg_path -radix unsigned [list 0 1500ns]
  add_force $sel_path -radix hex [list 039 1500ns]
}

set prev_ns 0
foreach checkpoint $checkpoints {
  lassign $checkpoint abs_ns label
  set delta_ns [expr {$abs_ns - $prev_ns}]
  if {$delta_ns < 0} {
    error "neispravan checkpoint redoslijed"
  }
  if {$delta_ns > 0} {
    run ${delta_ns}ns
  }
  ffc_capture_state $fh $label $fault_cnt_path $sel_path $mismatch_path $done_path
  set prev_ns $abs_ns
}

close $fh

puts "snimljen behavioral fault campaign summary: $report_file"
puts "force_fault_campaign.tcl zavrsen."
