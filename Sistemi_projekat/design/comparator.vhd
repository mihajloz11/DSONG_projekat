library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity comparator is
  generic(
    K : natural := 3;
    N : natural := 5;
    WIDTH : natural := 18
  );
  port(
    clk : in std_logic;
    rst : in std_logic;
    valid_i : in std_logic;
    units_data_i : in  std_logic_vector(N*WIDTH-1 downto 0);
    voted_data_i : in  std_logic_vector(WIDTH-1 downto 0);
    sel_o : out std_logic_vector(N*log2c(K+1)-1 downto 0)
  );
end entity comparator;

architecture rtl of comparator is
  constant SEL_W : natural := log2c(K+1);

  -- sel_reg cuva koji izlaz je trenutno dodijeljen svakom lane-u
  signal sel_reg : std_logic_vector(N*SEL_W-1 downto 0) := (others => '0');
  -- fault_cnt_reg govori koliko je spare modula vec zauzeto
  signal fault_cnt_reg : unsigned(SEL_W-1 downto 0) := (others => '0');
begin

  process(clk)
    variable sel_next : std_logic_vector(N*SEL_W-1 downto 0);
    variable fault_cnt_next : unsigned(SEL_W-1 downto 0);
    variable unit_word : std_logic_vector(WIDTH-1 downto 0);
    variable lane_sel : unsigned(SEL_W-1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sel_reg <= (others => '0');
        fault_cnt_reg <= (others => '0');
      elsif valid_i = '1' then
        sel_next := sel_reg;
        fault_cnt_next := fault_cnt_reg;
        -- poredi svaki aktivni lane sa izglasanim rezultatom
        for i in 0 to N-1 loop
          unit_word := units_data_i((i+1)*WIDTH-1 downto i*WIDTH);
          lane_sel  := unsigned(sel_next((i+1)*SEL_W-1 downto i*SEL_W));

          -- ako primary lane odstupi, prebaci na spare
          if (lane_sel = 0) and (unit_word /= voted_data_i) then
            if to_integer(fault_cnt_next) < K then
              fault_cnt_next := fault_cnt_next + 1;
              sel_next((i+1)*SEL_W-1 downto i*SEL_W) := std_logic_vector(fault_cnt_next);
            end if;
          end if;
        end loop;

        sel_reg <= sel_next;
        fault_cnt_reg <= fault_cnt_next;
      end if;
    end if;
  end process;

  sel_o <= sel_reg;

end architecture rtl;
