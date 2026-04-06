proc is_gui_session {} {
  set in_gui 0
  catch {set in_gui [is_gui_mode]}
  return $in_gui
}

set workspace_dir [file normalize [file join [file dirname [info script]] ..]]
set rpt_dir [file join $workspace_dir generated analysis_reports]
file mkdir $rpt_dir
set in_gui [is_gui_session]
set orig_xpr ""
if {$in_gui && [llength [get_projects -quiet]] > 0} {
  catch {set orig_xpr [file normalize [get_property PROJECT_FILE [current_project]]]}
}

set part "xc7z010clg400-1"
set period_ns 10.0
if {[info exists ::env(PERIOD_NS)] && [string trim $::env(PERIOD_NS)] ne ""} {
  set period_ns [expr {double($::env(PERIOD_NS))}]
}

# List of N,K combinations for analysis.
set cfg_list {
  {3 1}
  {5 1}
  {5 3}
  {7 3}
}
if {[info exists ::env(NK_CFGS)] && [string trim $::env(NK_CFGS)] ne ""} {
  set cfg_list {}
  foreach item [split $::env(NK_CFGS) ";"] {
    set t [string trim $item]
    if {$t eq ""} {
      continue
    }
    if {![regexp {^([0-9]+),([0-9]+)$} $t -> n_val k_val]} {
      error "los format u NK_CFGS: '$t' (treba N,K;N,K)"
    }
    lappend cfg_list [list $n_val $k_val]
  }
}

set srcs [list \
  "$workspace_dir/design/util_pkg.vhd" \
  "$workspace_dir/design/mac.vhd" \
  "$workspace_dir/design/mux.vhd" \
  "$workspace_dir/design/switch.vhd" \
  "$workspace_dir/design/voter.vhd" \
  "$workspace_dir/design/comparator.vhd" \
  "$workspace_dir/design/nmr_mac.vhd" \
  "$workspace_dir/design/fir_filter.vhd" \
  "$workspace_dir/design/top.vhd" \
]

set csv_file "$rpt_dir/nk_summary.csv"
set csv_mode "w"
if {[info exists ::env(NK_APPEND)] && $::env(NK_APPEND) eq "1"} {
  set csv_mode "a"
}

set need_header 1
if {$csv_mode eq "a" && [file exists $csv_file] && [file size $csv_file] > 0} {
  set need_header 0
}

set fp [open $csv_file $csv_mode]
if {$need_header} {
  puts $fp "N,K,synth_status,impl_status,synth_LUT,synth_FF,synth_DSP,impl_LUT,impl_FF,impl_DSP,WNS_ns,est_Fmax_MHz"
}
close $fp

proc append_csv {path line} {
  set f [open $path a]
  puts $f $line
  close $f
}

proc read_util_metrics {rpt_path} {
  set lut "NA"
  set ff "NA"
  set dsp "NA"

  if {![file exists $rpt_path]} {
    return [list $lut $ff $dsp]
  }

  set f [open $rpt_path r]
  set txt [read $f]
  close $f

  foreach line [split $txt "\n"] {
    if {[regexp {^\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} $line -> v]} {
      set lut $v
    }
    if {[regexp {^\|\s*Slice Registers\*?\s*\|\s*([0-9]+)\s*\|} $line -> v]} {
      set ff $v
    }
    if {[regexp {^\|\s*DSPs\*?\s*\|\s*([0-9]+)\s*\|} $line -> v]} {
      set dsp $v
    }
  }

  return [list $lut $ff $dsp]
}

foreach cfg $cfg_list {
  lassign $cfg N K
  puts "=== analiza N=$N K=$K period=${period_ns}ns ==="

  # Everything runs in a temporary project so the open XPR is not modified.
  catch {close_project -quiet}
  catch {close_design}

  create_project -in_memory -part $part
  foreach s $srcs {
    read_vhdl $s
  }

  set gen_str "DATA_WIDTH_IN=18 DATA_WIDTH_OUT=18 fir_ord=5 N=$N K=$K"

  set synth_status "OK"
  set impl_status "NA"
  set synth_lut "NA"
  set synth_ff "NA"
  set synth_dsp "NA"
  set impl_lut "NA"
  set impl_ff "NA"
  set impl_dsp "NA"
  set wns "NA"
  set fmax "NA"

  if {[catch {synth_design -top top -part $part -generic $gen_str} serr]} {
    puts "sinteza pala za N=$N K=$K"
    puts $serr
    set synth_status "FAIL"
    append_csv $csv_file "$N,$K,$synth_status,$impl_status,$synth_lut,$synth_ff,$synth_dsp,$impl_lut,$impl_ff,$impl_dsp,$wns,$fmax"
    continue
  }

  set synth_util_rpt "$rpt_dir/util_synth_N${N}_K${K}.rpt"
  report_utilization -file $synth_util_rpt
  lassign [read_util_metrics $synth_util_rpt] synth_lut synth_ff synth_dsp

  if {[catch {
    create_clock -name clk -period $period_ns [get_ports clk]
    opt_design
    place_design
    phys_opt_design
    route_design
  } ierr]} {
    puts "implementacija pala za N=$N K=$K"
    puts $ierr
    set impl_status "FAIL"
    append_csv $csv_file "$N,$K,$synth_status,$impl_status,$synth_lut,$synth_ff,$synth_dsp,$impl_lut,$impl_ff,$impl_dsp,$wns,$fmax"
    continue
  }

  set impl_status "OK"
  set impl_util_rpt "$rpt_dir/util_impl_N${N}_K${K}.rpt"
  report_utilization -file $impl_util_rpt
  lassign [read_util_metrics $impl_util_rpt] impl_lut impl_ff impl_dsp

  set timing_rpt "$rpt_dir/timing_impl_N${N}_K${K}.rpt"
  report_timing_summary -delay_type max -max_paths 10 -file $timing_rpt

  set tpaths [get_timing_paths -delay_type max -max_paths 1]
  if {[llength $tpaths] > 0} {
    set wns_raw [get_property SLACK [lindex $tpaths 0]]
    if {$wns_raw ne ""} {
      set wns [format "%.3f" $wns_raw]
      set tmin [expr {$period_ns - $wns_raw}]
      if {$tmin > 0.0} {
        set fmax [format "%.3f" [expr {1000.0 / $tmin}]]
      }
    }
  }

  append_csv $csv_file "$N,$K,$synth_status,$impl_status,$synth_lut,$synth_ff,$synth_dsp,$impl_lut,$impl_ff,$impl_dsp,$wns,$fmax"
}

puts "gotovo: $csv_file"
if {$in_gui} {
  if {$orig_xpr ne "" && [file exists $orig_xpr]} {
    # Restore the previously opened project after the analysis is finished.
    catch {close_project -quiet}
    catch {open_project $orig_xpr}
  }
} else {
  catch {close_project -quiet}
}
