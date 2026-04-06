proc strip_mode_arg {argv_list} {
  set cleaned {}
  set i 0
  while {$i < [llength $argv_list]} {
    set key [lindex $argv_list $i]
    incr i
    if {$key eq "-mode"} {
      if {$i < [llength $argv_list]} {
        incr i
      }
      continue
    }
    lappend cleaned $key
    if {$i < [llength $argv_list]} {
      lappend cleaned [lindex $argv_list $i]
      incr i
    }
  }
  return $cleaned
}

# run.tcl opens an existing project or creates a new one.
set script_dir [file dirname [file normalize [info script]]]
set saved_argv {}
if {[info exists argv]} {
  set saved_argv $argv
}
set argv [concat [list -mode init] [strip_mode_arg $saved_argv]]
set rc [catch {source [file join $script_dir project_flow.tcl]} result opts]
set argv {}
rename strip_mode_arg {}
if {$rc} {
  return -options $opts $result
}
