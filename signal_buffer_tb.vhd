
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity signal_buffer_tb is
end entity signal_buffer_tb;

architecture tb_arch of signal_buffer_tb is
  -- Component declaration
  component signal_buffer
    generic (NUM_ELEMENTS: integer; -- Number of elements in the buffer
             WIDTH:        integer); -- Number of bits in each element
    port (
        clk : in std_logic;
        rst : in std_logic;
        rd_en  : in std_logic;
        wr_en  : in std_logic;
        wr_data : in std_logic_vector(WIDTH-1 downto 0);
        rd_data : out std_logic_vector(NUM_ELEMENTS*WIDTH-1 downto 0);
        empty : out std_logic;
        full : out std_logic
    );
  end component signal_buffer;

  -- Constants
  constant NUM_ELEMENTS : integer := 3;
  constant WIDTH        : integer := 16;

  -- Signals
  signal clk : std_logic := '0';
  signal clk_en : std_logic := '1';
  signal rst : std_logic := '0';
  signal rd_en : std_logic := '0';
  signal wr_en : std_logic := '0';
  signal input : std_logic_vector (WIDTH-1 downto 0);

  signal full_flag : std_logic;
  signal empty_flag : std_logic;
  signal output : std_logic_vector(NUM_ELEMENTS*WIDTH-1 downto 0);

begin

    clk <= not clk and clk_en after 5 ns; -- Define Clock

    U_SIGNAL_BUFF : signal_buffer
        generic map (
            NUM_ELEMENTS => NUM_ELEMENTS,
            WIDTH => WIDTH)
        port map (
            clk => clk,
            rst => rst,
            rd_en => rd_en,
            wr_en => wr_en,
            wr_data => input,
            rd_data => output,
            empty => empty_flag,
            full => full_flag
        );

    process
    begin

        rst <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        rst <= '0';
        wait until rising_edge(clk);
        
        -- wr_en <= '1';
        -- for i in 0 to NUM_ELEMENTS-1 loop 
        for i in 0 to 350 loop 
            input <= std_logic_vector(to_unsigned(i, WIDTH));
            if (i mod 2 = 0) then
                wr_en <= '1';
            else
                wr_en <= '0';
            end if;
            wait until rising_edge(clk);

            -- PROBLEM: currently FULL flag shows up even when the odd input is given.
            --          Output is still changing 


            -- if (i = 26) then
            --     rd_en <= '1';
            --     wait until rising_edge(clk);
            --     rd_en <= '0';
            -- end if;

        end loop;

        if (full_flag = '1') then
            report "Wrote all 128 elements and full flag showed up";
        end if;

        clk_en <= '0'; -- Stop the clock
        report "Tests completed.";
        wait;

    end process;
    

    


end architecture tb_arch;
