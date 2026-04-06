library ieee;
use ieee.std_logic_1164.all;

package util_pkg is
  -- vraca koliko bita treba za indeks ili selektor
  function log2c(n : integer) return integer;
end util_pkg;

package body util_pkg is
  function log2c(n : integer) return integer is
    variable m : integer;
    variable p : integer;
  begin
    m := 0;
    p := 1;
    -- ide na prvu stepen dvojke koja pokriva n
    while p < n loop
      m := m + 1;
      p := p * 2;
    end loop;
    return m;
  end log2c;
end util_pkg;
