proc parse_cli_args {defaults argv_list} {
  set opts $defaults
  set i 0
  while {$i < [llength $argv_list]} {
    set raw_key [lindex $argv_list $i]
    incr i
    if {![string match -* $raw_key]} {
      error "ocekivana opcija sa '-', a dobio sam '$raw_key'"
    }
    if {$i >= [llength $argv_list]} {
      error "fali vrijednost za '$raw_key'"
    }

    set key [string range $raw_key 1 end]
    set val [lindex $argv_list $i]
    incr i

    if {![dict exists $opts $key]} {
      error "nepoznata opcija '$raw_key'"
    }
    dict set opts $key $val
  }
  return $opts
}

proc opt_to_bool {raw_val} {
  set v [string tolower [string trim $raw_val]]
  return [expr {$v in {"1" "true" "yes" "on"}}]
}

proc current_project_xpr {} {
  if {[llength [get_projects -quiet]] == 0} {
    return ""
  }
  set p [current_project]
  set pf ""
  if {![catch {set pf [get_property PROJECT_FILE $p]}] && $pf ne ""} {
    return [file normalize $pf]
  }
  set dir ""
  set name ""
  catch {set dir [get_property DIRECTORY $p]}
  catch {set name [get_property NAME $p]}
  if {$dir ne "" && $name ne ""} {
    return [file normalize [file join $dir "${name}.xpr"]]
  }
  return ""
}

proc effective_project_xpr {fallback_xpr} {
  set active_xpr [current_project_xpr]
  if {$active_xpr ne ""} {
    return $active_xpr
  }
  return $fallback_xpr
}

proc cleanup_xsim_state {project_dir} {
  catch {exec taskkill /F /IM xsim.exe /T}
  catch {exec taskkill /F /IM xsimk.exe /T}
  catch {exec taskkill /F /IM xelab.exe /T}
  foreach log_file [glob -nocomplain [file join $project_dir *.sim sim_1 * xsim simulate.log]] {
    catch {file delete -force $log_file}
  }
}

proc safe_launch_simulation {project_dir} {
  catch {close_sim -force}
  cleanup_xsim_state $project_dir
  after 400

  if {[catch {launch_simulation} sim_err]} {
    if {[string first "simulate.log" $sim_err] >= 0} {
      puts "simulate.log je zakljucan, pokusavam cleanup xsim procesa i retry..."
      cleanup_xsim_state $project_dir
      after 400
      catch {close_sim -force}
      launch_simulation
    } else {
      error $sim_err
    }
  }
}

proc is_gui_session {} {
  set in_gui 0
  catch {set in_gui [is_gui_mode]}
  return $in_gui
}

proc file_in_fileset {fileset_obj file_path} {
  set norm_target [file normalize $file_path]
  foreach existing [get_files -quiet -of_objects $fileset_obj] {
    if {![catch {set norm_existing [file normalize $existing]}]} {
      if {$norm_existing eq $norm_target} {
        return 1
      }
    }
  }
  return 0
}

proc ensure_file_in_fileset {fileset_obj file_path} {
  if {![file exists $file_path]} {
    error "nije pronadjen fajl: $file_path"
  }
  if {![file_in_fileset $fileset_obj $file_path]} {
    add_files -fileset [get_property NAME $fileset_obj] -norecurse $file_path
  }
}

proc sync_fileset_exact {fileset_obj desired_files} {
  set fileset_name [get_property NAME $fileset_obj]
  set existing [get_files -quiet -of_objects $fileset_obj]
  if {[llength $existing] > 0} {
    remove_files -fileset $fileset_name $existing
  }
  foreach f $desired_files {
    ensure_file_in_fileset $fileset_obj $f
  }
}

proc sync_project_layout {workspace_dir} {
  set rtl_dir [file join $workspace_dir design]
  set sim_dir [file join $workspace_dir sim]
  set data_dir [file join $workspace_dir files]
  set xdc_path [file join $workspace_dir constraint constraint.xdc]

  set rtl_files [list \
    [file join $rtl_dir util_pkg.vhd] \
    [file join $rtl_dir mac.vhd] \
    [file join $rtl_dir mux.vhd] \
    [file join $rtl_dir switch.vhd] \
    [file join $rtl_dir voter.vhd] \
    [file join $rtl_dir comparator.vhd] \
    [file join $rtl_dir nmr_mac.vhd] \
    [file join $rtl_dir fir_filter.vhd] \
    [file join $rtl_dir top.vhd] \
  ]
  set sim_vhdl_files [list \
    [file join $sim_dir txt_util.vhd] \
    [file join $sim_dir top_tb.vhd] \
  ]
  set sim_data_files [list \
    [file join $data_dir input_18b.txt] \
    [file join $data_dir coef_18b.txt] \
    [file join $data_dir expected_18b.txt] \
  ]

  set src_fs [get_filesets sources_1]
  set sim_fs [get_filesets sim_1]
  set constr_fs [get_filesets constrs_1]

  set_property target_language VHDL [current_project]
  catch {set_property board_part digilentinc.com:zybo:part0:2.0 [current_project]}

  sync_fileset_exact $constr_fs [list $xdc_path]
  sync_fileset_exact $src_fs $rtl_files
  sync_fileset_exact $sim_fs [concat $sim_vhdl_files $sim_data_files]

  foreach f $sim_data_files {
    catch {set_property file_type {Text} [get_files $f]}
  }

  # The top module and testbench are used in all flows.
  set_property top top $src_fs
  set_property SOURCE_SET sources_1 $sim_fs
  set_property top top_tb $sim_fs
  set_property top_lib xil_defaultlib $sim_fs
  set_property generic "MAX_ABS_ERR=7 STOP_ON_MISMATCH=false REPORT_MISMATCH_WARN=false" $sim_fs

  update_compile_order -fileset sources_1
  update_compile_order -fileset sim_1

  catch {save_project}
}

proc open_or_create_project {xpr_path recreate} {
  set project_dir [file dirname $xpr_path]
  set project_name [file rootname [file tail $xpr_path]]
  set part_name "xc7z010clg400-1"

  set opened_here 0

  if {[llength [get_projects -quiet]] > 0} {
    set open_xpr [current_project_xpr]
    if {$open_xpr ne "" && $open_xpr ne $xpr_path} {
      set norm_workspace [file normalize $::workspace_dir]
      if {[string first $norm_workspace $open_xpr] == 0} {
        puts "napomena: vec je otvoren projekat iz istog workspace-a, koristim njega:"
        puts "aktivni projekat: $open_xpr"
      } else {
        error "otvoren je drugi projekat: $open_xpr"
      }
    }
  }

  if {[llength [get_projects -quiet]] == 0} {
    if {$recreate || ![file exists $xpr_path]} {
      # Create a new XPR if it does not exist.
      file mkdir $project_dir
      create_project $project_name $project_dir -part $part_name -force
    } else {
      if {[catch {open_project $xpr_path} open_err]} {
        puts "upozorenje: projekat nije mogao da se otvori, pokusavam rekreaciju..."
        puts "razlog: $open_err"
        catch {close_project}
        file mkdir $project_dir
        create_project $project_name $project_dir -part $part_name -force
      }
    }
    set opened_here 1
  } elseif {$recreate} {
    close_project
    file mkdir $project_dir
    create_project $project_name $project_dir -part $part_name -force
    set opened_here 1
  }

  sync_project_layout $::workspace_dir
  return $opened_here
}

set script_dir [file dirname [file normalize [info script]]]
set workspace_dir [file normalize [file join $script_dir ..]]
set default_xpr [file normalize [file join $workspace_dir project Sistemi_projekat Sistemi_projekat.xpr]]
set in_gui [is_gui_session]

set defaults [dict create \
  xpr $default_xpr \
  mode init \
  jobs 4 \
  run_ns 1200000 \
  recreate 0 \
]

set opts [parse_cli_args $defaults $argv]
set xpr_path [file normalize [dict get $opts xpr]]
set mode [string tolower [dict get $opts mode]]
set jobs [expr {[dict get $opts jobs] + 0}]
set run_ns [expr {[dict get $opts run_ns] + 0}]
set recreate [opt_to_bool [dict get $opts recreate]]

file mkdir [file join $workspace_dir generated analysis_reports]
set opened_here [open_or_create_project $xpr_path $recreate]
set xpr_path [effective_project_xpr $xpr_path]
set project_dir [file dirname $xpr_path]
set analysis_dir [file join $workspace_dir generated analysis_reports]

if {$mode eq "init"} {
  puts "projekat je otvoren/sinhronizovan."
} elseif {$mode eq "sim"} {
  set sim_fs [get_filesets sim_1]
  set_property top top_tb $sim_fs
  set_property generic "MAX_ABS_ERR=7 STOP_ON_MISMATCH=false REPORT_MISMATCH_WARN=false" $sim_fs
  safe_launch_simulation $project_dir
  restart
  run ${run_ns}ns
  if {!$in_gui} {
    close_sim -force
  }
} elseif {$mode eq "synth"} {
  catch {reset_run synth_1}
  launch_runs synth_1 -jobs $jobs
  wait_on_run synth_1
  open_run synth_1
  report_utilization -file [file join $analysis_dir util_synth_manual.rpt]
} elseif {$mode eq "impl"} {
  catch {reset_run impl_1}
  launch_runs impl_1 -to_step route_design -jobs $jobs
  wait_on_run impl_1
  open_run impl_1
  report_utilization -file [file join $analysis_dir util_impl_manual.rpt]
  report_timing_summary -delay_type max -max_paths 10 -file [file join $analysis_dir timing_impl_manual.rpt]
} else {
  error "nepoznat -mode '$mode' (init|sim|synth|impl)"
}

puts "flow zavrsen."

if {$opened_here && !$in_gui} {
  close_project
}
