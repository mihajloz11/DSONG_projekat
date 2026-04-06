library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNIMACRO;
use UNIMACRO.vcomponents.all;

entity mac is
  generic(
    DATA_WIDTH_IN : natural := 18;
    DATA_WIDTH_OUT : natural := 36
  );
  port(
    clk : in std_logic;
    rst : in std_logic;
    en : in std_logic;

    data_a_i : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);
    data_b_i : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);
    sum_i : in std_logic_vector(DATA_WIDTH_OUT-1 downto 0);

    sum_o : out std_logic_vector(DATA_WIDTH_OUT-1 downto 0)
  );
end entity mac;

architecture rtl of mac is
  constant DSP_P_W : natural := 48;

  signal data_a_masked : std_logic_vector(DATA_WIDTH_IN-1 downto 0) := (others => '0');
  signal data_b_masked : std_logic_vector(DATA_WIDTH_IN-1 downto 0) := (others => '0');
  signal sum_ext : std_logic_vector(DSP_P_W-1 downto 0) := (others => '0');
  signal dsp_p : std_logic_vector(DSP_P_W-1 downto 0) := (others => '0');
begin
  assert DATA_WIDTH_IN <= 18
    report "mac requires DATA_WIDTH_IN <= 18 for DSP48-based implementation"
    severity failure;

  assert DATA_WIDTH_OUT <= DSP_P_W
    report "mac requires DATA_WIDTH_OUT <= 48 for DSP48-based implementation"
    severity failure;

  -- kad en padne, ulaz se maskira na nulu
  data_a_masked <= data_a_i when en = '1' else (others => '0');
  data_b_masked <= data_b_i when en = '1' else (others => '0');
  -- zbir se siri na 48 bita jer tako radi dsp makro
  sum_ext <= std_logic_vector(resize(signed(sum_i), DSP_P_W));

  -- latencija 2 je bitna zbog uslova zadatka
  u_macc : MACC_MACRO
    generic map(
      DEVICE => "7SERIES",
      LATENCY => 2,
      WIDTH_A => DATA_WIDTH_IN,
      WIDTH_B => DATA_WIDTH_IN,
      WIDTH_P => DSP_P_W
    )
    port map(
      P => dsp_p,
      A => data_a_masked,
      ADDSUB => '1',
      B => data_b_masked,
      CARRYIN => '0',
      CE => '1',
      CLK => clk,
      LOAD => '1',
      LOAD_DATA => sum_ext,
      RST => rst
    );

  -- na izlazu se uzima samo korisna sirina akumulatora
  sum_o <= dsp_p(DATA_WIDTH_OUT-1 downto 0);
end architecture rtl;
