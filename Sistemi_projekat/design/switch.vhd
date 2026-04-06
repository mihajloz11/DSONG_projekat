library ieee;
use ieee.std_logic_1164.all;

use work.util_pkg.all;

entity switch is
  generic(
    N : natural := 5;
    K : natural := 3;
    WIDTH : natural := 18
  );
  port(
    sel : in std_logic_vector(N*log2c(K+1)-1 downto 0);
    switch_i : in  std_logic_vector((N+K)*WIDTH-1 downto 0);
    switch_o : out std_logic_vector(N*WIDTH-1 downto 0)
  );
end entity switch;

architecture rtl of switch is
  type mux_in_arr_t is array(0 to N-1) of std_logic_vector((K+1)*WIDTH-1 downto 0);
  signal mux_in_arr : mux_in_arr_t;

  type mux_out_arr_t is array(0 to N-1) of std_logic_vector(WIDTH-1 downto 0);
  signal mux_out_arr : mux_out_arr_t;

begin
  gen_inputs : for i in 0 to N-1 generate
    -- svaki lane dobija svoj primary i sve spare izlaze
    mux_in_arr(i) <= switch_i((i+1)*WIDTH-1 downto i*WIDTH) &
                     switch_i((N+K)*WIDTH-1 downto N*WIDTH);
  end generate;

  gen_muxes : for i in 0 to N-1 generate
    -- sel za svaki lane bira da li ostaje primary ili ide na spare
    u_mux : entity work.mux
      generic map(
        WIDTH => WIDTH,
        N     => K+1
      )
      port map(
        sel => sel((i + 1)*log2c(K + 1)-1 downto i*log2c(K + 1)),
        x_i => mux_in_arr(i),
        y_o => mux_out_arr(i)
      );

    -- vraca se samo N aktivnih izlaza prema voteru
    switch_o((i+1)*WIDTH-1 downto i*WIDTH) <= mux_out_arr(i);
  end generate;

end architecture rtl;
