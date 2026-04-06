library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity top is
  generic(
    DATA_WIDTH_IN : natural := 18;
    DATA_WIDTH_OUT : natural := 18;
    fir_ord : natural := 5;
    N : natural := 5;
    K : natural := 3
  );
  port(
    clk : in std_logic;
    rst : in std_logic;

    coef_en   : in std_logic;
    coef_addr : in std_logic_vector(log2c(fir_ord+1)-1 downto 0);
    coef_in   : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);

    s_axis_tdata : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);
    s_axis_tvalid : in std_logic;
    s_axis_tready : out std_logic;
    s_axis_tlast : in std_logic;

    m_axis_tdata : out std_logic_vector(DATA_WIDTH_OUT-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in std_logic;
    m_axis_tlast : out std_logic;
    processing_done : out std_logic
  );
end entity;

architecture rtl of top is
  -- prati internu latenciju fir jezgra za tlast signal
  constant STREAM_LATENCY : natural := 2;

  signal s_ready : std_logic;
  signal xfer : std_logic;

  signal filt_v : std_logic;
  signal filt_y : std_logic_vector(DATA_WIDTH_OUT-1 downto 0);
  signal last_pipe : std_logic_vector(STREAM_LATENCY-1 downto 0) := (others => '0');
  signal last_out_reg : std_logic := '0';
  signal m_last_i : std_logic;
  signal m_valid_i : std_logic;
begin

  -- axi handshake na ulazu
  s_ready <= m_axis_tready;
  s_axis_tready <= s_ready;
  -- novi uzorak ulazi samo kad su valid i ready zajedno
  xfer <= s_axis_tvalid and s_ready;

  u_fir : entity work.fir_filter
    generic map(
      DATA_WIDTH_IN => DATA_WIDTH_IN,
      DATA_WIDTH_OUT => DATA_WIDTH_OUT,
      fir_ord => fir_ord,
      N => N,
      K => K
    )
    port map(
      clk => clk,
      rst => rst,
      valid_in => xfer,
      coef_en => coef_en,
      coef_in => coef_in,
      coef_addr_i => coef_addr,
      data_in => s_axis_tdata,
      valid_out => filt_v,
      data_out => filt_y
    );

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        last_pipe <= (others => '0');
        last_out_reg <= '0';
      else
        -- tlast prati latenciju fir-a
        last_out_reg <= last_pipe(STREAM_LATENCY-1);
        last_pipe(0) <= xfer and s_axis_tlast;
        for i in 1 to STREAM_LATENCY-1 loop
          last_pipe(i) <= last_pipe(i-1);
        end loop;
      end if;
    end if;
  end process;

  -- izlazni axi samo prenosi podatke i valid iz filtra
  m_valid_i <= filt_v;
  m_last_i  <= last_out_reg and m_valid_i;
  m_axis_tdata <= filt_y;
  m_axis_tvalid <= m_valid_i;
  m_axis_tlast <= m_last_i;
  processing_done <= m_valid_i and m_axis_tready and m_last_i;

end architecture rtl;
