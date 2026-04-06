library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity fir_filter is
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

    valid_in : in std_logic;

    coef_en : in std_logic;
    coef_in : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);
    coef_addr_i : in  std_logic_vector(log2c(fir_ord+1)-1 downto 0);

    data_in : in std_logic_vector(DATA_WIDTH_IN-1 downto 0);

    valid_out : out std_logic;
    data_out : out std_logic_vector(DATA_WIDTH_OUT-1 downto 0)
  );
end entity fir_filter;

architecture rtl of fir_filter is
  constant ACC_W : natural := 2*DATA_WIDTH_IN;
  constant ZERO_ACC : std_logic_vector(ACC_W-1 downto 0) := (others => '0');
  -- pipeline prati latenciju DSP mac modula
  constant MAC_PIPE_STAGES : natural := 2;

  attribute DONT_TOUCH : string;

  type coef_t is array (0 to fir_ord) of signed(DATA_WIDTH_IN-1 downto 0);
  signal b_s : coef_t := (others => (others => '0'));

  type x_t is array (0 to fir_ord) of signed(DATA_WIDTH_IN-1 downto 0);
  signal x_s : x_t := (others => (others => '0'));

  type tap_t is array (0 to fir_ord) of std_logic_vector(DATA_WIDTH_IN-1 downto 0);
  signal tap_data : tap_t;

  type prod_t is array (0 to fir_ord) of std_logic_vector(ACC_W-1 downto 0);
  signal prod_s : prod_t := (others => (others => '0'));

  -- valid se pomjera da sabiranje krene kad su svi tapovi spremni
  signal valid_pipe : std_logic_vector(MAC_PIPE_STAGES-1 downto 0) := (others => '0');
  signal valid_out_reg : std_logic := '0';

  attribute DONT_TOUCH of gen_nmr_taps : label is "true";
begin

  -- upis koeficijenata
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        b_s <= (others => (others => '0'));
      elsif coef_en = '1' then
        b_s(to_integer(unsigned(coef_addr_i))) <= signed(coef_in);
      end if;
    end if;
  end process;

  tap_data(0) <= data_in;
  gen_tap_data : for i in 1 to fir_ord generate
    -- pomjeranje istorije ulaza po tapovima
    tap_data(i) <= std_logic_vector(x_s(i-1));
  end generate;

  -- po jedan nmr_mac za svaki tap
  gen_nmr_taps : for i in 0 to fir_ord generate
    u_nmr_mac : entity work.nmr_mac
      generic map(
        N => N,
        K => K,
        DATA_WIDTH_IN => DATA_WIDTH_IN
      )
      port map(
        clk => clk,
        rst => rst,
        en => valid_in,
        data_a_i => tap_data(i),
        data_b_i => std_logic_vector(b_s(i)),
        sum_i => ZERO_ACC,
        sum_o => prod_s(i)
      );
  end generate;

  process(clk)
    variable acc : signed(ACC_W-1 downto 0);
    variable y18 : signed(DATA_WIDTH_OUT-1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        x_s <= (others => (others => '0'));
        data_out <= (others => '0');
        valid_pipe <= (others => '0');
        valid_out_reg <= '0';
      else
        valid_out_reg <= valid_pipe(MAC_PIPE_STAGES-1);
        valid_pipe(0) <= valid_in;
        for i in 1 to MAC_PIPE_STAGES-1 loop
          valid_pipe(i) <= valid_pipe(i-1);
        end loop;

        -- sabiranje tek kad izadju dsp rezultati
        if valid_pipe(MAC_PIPE_STAGES-1) = '1' then
          acc := (others => '0');
          for i in 0 to fir_ord loop
            acc := acc + signed(prod_s(i));
          end loop;
          y18 := resize(shift_right(acc, 17), DATA_WIDTH_OUT);
          data_out <= std_logic_vector(y18);
        end if;

        if valid_in = '1' then
          -- istorija ulaza ide ka narednim tapovima
          x_s(0) <= signed(data_in);
          for i in 1 to fir_ord loop
            x_s(i) <= x_s(i-1);
          end loop;
        end if;
      end if;
    end if;
  end process;

  valid_out <= valid_out_reg;

end architecture rtl;
