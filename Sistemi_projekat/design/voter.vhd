library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity voter_core is
  generic(
    WIDTH : natural := 18;
    N : natural := 5
  );
  port(
    voter_i : in std_logic_vector(N*WIDTH-1 downto 0);
    voter_o : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity voter_core;

architecture rtl of voter_core is
begin

  process(voter_i)
    variable ones : integer;
    variable vote_v : std_logic_vector(WIDTH-1 downto 0);
  begin
    -- majority glasanje po bitovima
    for bit_idx in 0 to WIDTH-1 loop
      ones := 0;

      for mod_idx in 0 to N-1 loop
        if voter_i(mod_idx*WIDTH + bit_idx) = '1' then
          ones := ones + 1;
        end if;
      end loop;

      if ones > (N/2) then
        vote_v(bit_idx) := '1';
      else
        vote_v(bit_idx) := '0';
      end if;
    end loop;

    voter_o <= vote_v;
  end process;

end architecture rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity voter is
  generic(
    WIDTH : natural := 18;
    N : natural := 5
  );
  port(
    voter_i : in std_logic_vector(N*WIDTH-1 downto 0);
    voter_o : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity voter;

architecture rtl of voter is
  constant REPLICA_CNT : natural := 6;
  constant PAIR_CNT : natural := 3;

  subtype word_t is std_logic_vector(WIDTH-1 downto 0);
  type word_array_t is array (0 to PAIR_CNT-1) of word_t;

  attribute DONT_TOUCH : string;
  attribute KEEP : string;

  signal replica_votes : std_logic_vector(REPLICA_CNT*WIDTH-1 downto 0) := (others => '0');
  signal pair_votes : std_logic_vector(PAIR_CNT*WIDTH-1 downto 0) := (others => '0');
  signal pair_valid : std_logic_vector(PAIR_CNT-1 downto 0) := (others => '0');

  function tdr_vote(
    pair_votes_i : std_logic_vector(PAIR_CNT*WIDTH-1 downto 0);
    pair_valid_i : std_logic_vector(PAIR_CNT-1 downto 0)
  ) return word_t is
    variable pair_word_v : word_array_t := (others => (others => '0'));
    variable first_valid_v : word_t := (others => '0');
    variable valid_cnt_v : natural := 0;
  begin
    -- izdvaja samo parove koji su se medjusobno slozili
    for i in 0 to PAIR_CNT-1 loop
      pair_word_v(i) := pair_votes_i((i+1)*WIDTH-1 downto i*WIDTH);

      if pair_valid_i(i) = '1' then
        if valid_cnt_v = 0 then
          first_valid_v := pair_word_v(i);
        end if;
        valid_cnt_v := valid_cnt_v + 1;
      end if;
    end loop;

    if valid_cnt_v = 0 then
      return (others => '0');
    elsif valid_cnt_v = 1 then
      return first_valid_v;
    elsif (pair_valid_i(0) = '1') and (pair_valid_i(1) = '1') and (pair_word_v(0) = pair_word_v(1)) then
      return pair_word_v(0);
    elsif (pair_valid_i(0) = '1') and (pair_valid_i(2) = '1') and (pair_word_v(0) = pair_word_v(2)) then
      return pair_word_v(0);
    elsif (pair_valid_i(1) = '1') and (pair_valid_i(2) = '1') and (pair_word_v(1) = pair_word_v(2)) then
      return pair_word_v(1);
    else
      return first_valid_v;
    end if;
  end function;

  attribute KEEP of replica_votes : signal is "true";
  attribute KEEP of pair_votes : signal is "true";
  attribute KEEP of pair_valid : signal is "true";
begin

  gen_pairs : for pair_idx in 0 to PAIR_CNT-1 generate
    attribute DONT_TOUCH of u_core_a : label is "true";
    attribute DONT_TOUCH of u_core_b : label is "true";
    attribute KEEP of u_core_a : label is "true";
    attribute KEEP of u_core_b : label is "true";
  begin
    -- svaki par ima dvije iste majority kopije
    u_core_a : entity work.voter_core
      generic map(
        WIDTH => WIDTH,
        N => N
      )
      port map(
        voter_i => voter_i,
        voter_o => replica_votes((2*pair_idx+1)*WIDTH-1 downto 2*pair_idx*WIDTH)
      );

    u_core_b : entity work.voter_core
      generic map(
        WIDTH => WIDTH,
        N => N
      )
      port map(
        voter_i => voter_i,
        voter_o => replica_votes((2*pair_idx+2)*WIDTH-1 downto (2*pair_idx+1)*WIDTH)
      );

    pair_votes((pair_idx+1)*WIDTH-1 downto pair_idx*WIDTH) <=
      replica_votes((2*pair_idx+1)*WIDTH-1 downto 2*pair_idx*WIDTH);

    -- par je dobar samo ako se obje kopije slazu
    pair_valid(pair_idx) <= '1'
      when replica_votes((2*pair_idx+1)*WIDTH-1 downto 2*pair_idx*WIDTH) =
           replica_votes((2*pair_idx+2)*WIDTH-1 downto (2*pair_idx+1)*WIDTH)
      else '0';
  end generate;

  -- finalna odluka ide samo kroz validne parove
  voter_o <= tdr_vote(pair_votes, pair_valid);

end architecture rtl;
