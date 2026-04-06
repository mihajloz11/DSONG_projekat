# osnovni takt za top clk
# period je podesen blizu granice da wns bude oko nule za default konfiguraciju
create_clock -add -name sys_clk_pin -period 18.3 -waveform {0 9.15} [get_ports {clk}]
