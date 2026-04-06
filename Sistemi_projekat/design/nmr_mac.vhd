library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity nmr_mac is
  generic(
    N : natural := 5;
    K : natural := 3;
    DATA_WIDTH_IN : natural := 18
  );
  port(
    clk : in std_logic;
    rst : in std_logic;
    en : in std_logic;

    data_a_i : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);
    data_b_i : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);
    sum_i : in std_logic_vector(2*DATA_WIDTH_IN-1 downto 0);

    sum_o : out std_logic_vector(2*DATA_WIDTH_IN-1 downto 0)
  );
end entity nmr_mac;

architecture rtl of nmr_mac is
  constant ACC_W : natural := 2*DATA_WIDTH_IN;
  constant SEL_W : natural := log2c(K+1);

  attribute DONT_TOUCH : string;
  signal mac_all : std_logic_vector((N+K)*ACC_W-1 downto 0) := (others => '0');
  signal sw_out : std_logic_vector(N*ACC_W-1 downto 0) := (others => '0');
  signal sel : std_logic_vector(N*SEL_W-1 downto 0) := (others => '0');

  signal voted : std_logic_vector(ACC_W-1 downto 0) := (others => '0');

  attribute KEEP : string;

  attribute DONT_TOUCH of gen_macs : label is "true";
  attribute DONT_TOUCH of u_switch : label is "true";
  attribute DONT_TOUCH of u_voter : label is "true";
  attribute DONT_TOUCH of u_cmp : label is "true";
  attribute KEEP of mac_all : signal is "true";
begin

  -- pravi N aktivnih i K rezervnih mac jedinica
  gen_macs : for i in 0 to (N+K-1) generate
    attribute DONT_TOUCH of u_mac : label is "true";
    attribute KEEP of u_mac : label is "true";
  begin
    u_mac : entity work.mac
      generic map(
        DATA_WIDTH_IN => DATA_WIDTH_IN
      )
      port map(
        clk => clk,
        rst => rst,
        en => en,
        data_a_i => data_a_i,
        data_b_i => data_b_i,
        sum_i => sum_i,
        sum_o    => mac_all((i+1)*ACC_W-1 downto i*ACC_W)
      );
  end generate;

  -- sabirnica sa izlazima svih mac replika
  u_switch : entity work.switch
    generic map(
      N => N,
      K => K,
      WIDTH => ACC_W
    )
    port map(
      sel => sel,
      switch_i => mac_all,
      switch_o => sw_out
    );

  -- voter vraca rezultat koji trenutno izgleda ispravno
  u_voter : entity work.voter
    generic map(
      WIDTH => ACC_W,
      N => N
    )
    port map(
      voter_i => sw_out,
      voter_o => voted
    );

  -- comparator azurira mapiranje kad neki primary lane odstupi
  u_cmp : entity work.comparator
    generic map(
      K => K,
      N => N,
      WIDTH => ACC_W
    )
    port map(
      clk => clk,
      rst => rst,
      valid_i => en,
      units_data_i => sw_out,
      voted_data_i => voted,
      sel_o => sel
    );

  -- na kraju izlazi izglasani rezultat
  sum_o <= voted;

end architecture rtl;
