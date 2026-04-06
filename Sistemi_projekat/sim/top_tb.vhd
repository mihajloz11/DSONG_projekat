library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.txt_util.all;
use work.util_pkg.all;

entity top_tb is
  generic(
    MAX_ABS_ERR : integer := 7;
    STOP_ON_MISMATCH : boolean := true;
    REPORT_MISMATCH_WARN : boolean := true
  );
end entity;

architecture tb of top_tb is
  constant DATA_WIDTH : natural := 18;
  constant fir_ord : natural := 5;
  constant N : natural := 5;
  constant K : natural := 3;
  constant ACC_W : natural := 2*DATA_WIDTH;
  constant SEL_W : natural := log2c(K+1);

  constant Tclk : time := 10 ns;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal coef_en : std_logic := '0';
  signal coef_addr : std_logic_vector(log2c(fir_ord+1)-1 downto 0) := (others => '0');
  signal coef_in : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal s_tdata : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal s_tvalid : std_logic := '0';
  signal s_tready : std_logic;
  signal s_tlast : std_logic := '0';
  signal m_tdata : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal m_tvalid : std_logic;
  signal m_tready : std_logic := '1';
  signal m_tlast : std_logic;

  signal processing_done : std_logic;
  signal done_seen : std_logic := '0';
  signal mismatch_cnt_dbg : integer := 0;

  -- fault demo helper signali.
  -- Tcl skripte ih pune kroz add_force kako bi u wave-u bilo lako vidljivo:
  -- broj potrosenih rezervi, preostale rezerve i fault marker bitovi.
  signal dbg_fault_cnt_reg : std_logic_vector(SEL_W-1 downto 0) := (others => '0');
  signal dbg_spares_left_reg : std_logic_vector(SEL_W-1 downto 0) := std_logic_vector(to_unsigned(K, SEL_W));
  signal dbg_fault_cnt_int : integer := 0;
  signal dbg_spares_left : integer := K;
  signal dbg_sel_reg : std_logic_vector(N*SEL_W-1 downto 0) := (others => '0');
  signal dbg_mac_bit20  : std_logic := '0';
  signal dbg_mac_bit56  : std_logic := '0';
  signal dbg_mac_bit92  : std_logic := '0';
  signal dbg_mac_bit128 : std_logic := '0';
  signal dbg_mac_bit164 : std_logic := '0';
  signal dbg_mac_bit236 : std_logic := '0';
  signal dbg_mac_bit272 : std_logic := '0';
  file f_in : text open read_mode is "input_18b.txt";
  file f_coef : text open read_mode is "coef_18b.txt";
  file f_exp : text open read_mode is "expected_18b.txt";
begin

  dut : entity work.top
    port map(
      clk => clk,
      rst => rst,

      coef_en => coef_en,
      coef_addr => coef_addr,
      coef_in => coef_in,

      s_axis_tdata => s_tdata,
      s_axis_tvalid => s_tvalid,
      s_axis_tready => s_tready,
      s_axis_tlast => s_tlast,

      m_axis_tdata => m_tdata,
      m_axis_tvalid => m_tvalid,
      m_axis_tready => m_tready,
      m_axis_tlast => m_tlast,
      processing_done => processing_done
    );

  clk <= not clk after Tclk/2;

  dbg_fault_cnt_int <= to_integer(unsigned(dbg_fault_cnt_reg));
  dbg_spares_left <= to_integer(unsigned(dbg_spares_left_reg));

  p_stim : process
    variable L : line;
    variable s : string(1 to DATA_WIDTH);
  begin
    rst      <= '1';
    s_tvalid <= '0';
    s_tlast <= '0';
    coef_en <= '0';

    wait for 5*Tclk;
    wait until rising_edge(clk);
    rst <= '0';
    for i in 0 to fir_ord loop
      if endfile(f_coef) then
        report "Coefficient file ended too early!" severity failure;
      end if;

      readline(f_coef, L);
      read(L, s);
      coef_in <= to_std_logic_vector(s);
      coef_addr <= std_logic_vector(to_unsigned(i, coef_addr'length));
      coef_en <= '1';
      wait until rising_edge(clk);
    end loop;
    coef_en <= '0';
    wait until rising_edge(clk);
    while not endfile(f_in) loop
      readline(f_in, L);
      read(L, s);

      s_tdata <= to_std_logic_vector(s);
      s_tvalid <= '1';
      if endfile(f_in) then
        s_tlast <= '1';
      else
        s_tlast <= '0';
      end if;

      loop
        wait until rising_edge(clk);
        exit when s_tready = '1';
      end loop;
    end loop;

    s_tvalid <= '0';
    s_tlast <= '0';

    wait until done_seen = '1';
    wait for 10*Tclk;
    report "Verification DONE!" severity note;
    wait;
  end process;

  p_check : process
    variable L      : line;
    variable s : string(1 to DATA_WIDTH);
    variable exp_v : std_logic_vector(DATA_WIDTH-1 downto 0);
    variable diff_v : integer;
    variable idx : natural := 0;
    variable mismatch_cnt : natural := 0;
  begin
    wait until rst = '0';
    mismatch_cnt_dbg <= 0;

    while true loop
      wait until rising_edge(clk);

      if (m_tvalid = '1') and (m_tready = '1') then
        if endfile(f_exp) then
          report "Expected file ended too early at sample " & integer'image(idx) severity failure;
        end if;

        readline(f_exp, L);
        read(L, s);
        exp_v := to_std_logic_vector(s);

        diff_v := abs(to_integer(signed(exp_v)) - to_integer(signed(m_tdata)));
        if diff_v > MAX_ABS_ERR then
          mismatch_cnt := mismatch_cnt + 1;
          mismatch_cnt_dbg <= mismatch_cnt;
          if STOP_ON_MISMATCH then
            report "Mismatch at sample " & integer'image(idx) &
                   " exp=" & integer'image(to_integer(signed(exp_v))) &
                   " got=" & integer'image(to_integer(signed(m_tdata))) &
                   " diff=" & integer'image(diff_v)
              severity failure;
          elsif REPORT_MISMATCH_WARN then
            report "Mismatch at sample " & integer'image(idx) &
                   " exp=" & integer'image(to_integer(signed(exp_v))) &
                   " got=" & integer'image(to_integer(signed(m_tdata))) &
                   " diff=" & integer'image(diff_v)
              severity warning;
          end if;
        end if;

        idx := idx + 1;
      end if;

      if processing_done = '1' then
        if not endfile(f_exp) then
          report "Expected file has remaining samples after TLAST handshake." severity warning;
        end if;
        mismatch_cnt_dbg <= mismatch_cnt;
        report "Total mismatches: " & integer'image(mismatch_cnt) severity note;
        done_seen <= '1';
        exit;
      end if;
    end loop;

    wait;
  end process;

end architecture;
