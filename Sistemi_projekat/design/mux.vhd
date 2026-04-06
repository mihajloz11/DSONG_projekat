library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity mux is
  generic(
    WIDTH : natural := 18;
    N : natural := 4
  );
  port(
    sel : in std_logic_vector(log2c(N)-1 downto 0);
    x_i : in std_logic_vector(N*WIDTH-1 downto 0);
    y_o : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity mux;

architecture rtl of mux is
begin

  process(sel, x_i)
    variable idx : integer;
  begin
    y_o <= (others => '0');

    -- bira jedan word iz spakovanog ulaza
    idx := to_integer(unsigned(sel));
    if (idx >= 0) and (idx < N) then
      -- redoslijed je primary pa spare izvori
      y_o <= x_i((N-idx)*WIDTH-1 downto (N-idx-1)*WIDTH);
    end if;
  end process;

end architecture rtl;
