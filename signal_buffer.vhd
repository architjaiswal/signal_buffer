-- Archit Jaiswal
-- Entity: Signal Buffer 128 elements (16 bit each)

-- Functionality description:
-- 1. It will be reading one (16-bit) element at a time from the FIFO which performs clock domain crossing to fetch data from DRAM and bring it to the datapath CLK

-- 2. Whenever the FIFO is ready to give an element, it will assert 'wr_en' and give data to 'wr_data' signal. If the buffer is full then 'full' signal will be set to inform the FIFO that it needs to stop because the buffer is full and data has not been read by the pipeline/datapath. 

-- NOTE: 128 elements forms a window of input to the datapath that performs 1-D convolution. Therefore, it is a sliding window buffer. Meaning one element is used multiple times in different pipelines and only one element needs to be evicted to form a "new windows" for another pipeline.  

-- 3. Everytime a write occurs from FIFO, a counter will be incremented to know when a window of data is ready for the pipeline to start computation. Empty signal means that the buffer is not yet loaded with "fresh" 128 elements to form a complete window and tells the pipeline that a new window is not ready yet, so do not read anything. 

-- 4. Once the 128 elements are ready, the buffer will set the full flag to tell the FIFO to pause writing and remove the empty flag to tell the pipeline that now it has a complete window loaded (not empty) and the pipeline should consider reading the data in buffer. 

-- 5. This buffer passes the entire bit vector (128 elements * 16 bits = 2048 bits) down to the datapath/pipeline. When the pipeline has read the data, it will acknowledge to buffer by setting the rd_en, so buffer knows that the data it contains is now old and it needs to load new elements from the FIFO.  

-- 6. rd_en will decrement the counter to 127 which will lead to the empty flag and the removal of full flag. Due to this, the FIFO will get notified that now the buffer is not full and it may pull the wr_en to write more data to the buffer.

----------------------------------------------------------------------------------

----------------------- COUNTER ENTITY ------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity counter is
    generic (MAX_COUNT_NUMBER: integer := 127); -- it will count from 0 to 127, so total 128 times
    port (
        clk : in std_logic;
        rst : in std_logic;
        add_one : in std_logic;
        subtract_one : in std_logic;
        -- output : out std_logic_vector(integer(ceil(log2(real(MAX_COUNT_NUMBER+1))))-1 downto 0)
        output : out std_logic -- single bit output (will be 1 when the count reaches MAX_COUNT_NUMBER
    );
end counter;

architecture BHV of counter is

    constant NUM_BITS : positive := integer(ceil(log2(real(MAX_COUNT_NUMBER+1))));
    signal count_r : unsigned(NUM_BITS-1 downto 0);

begin

    process(clk, rst)
    begin

        if (rst = '1') then
            count_r <= (others => '0');
        
        elsif (rising_edge(clk)) then
            if (add_one = '1') then
                if (count_r = MAX_COUNT_NUMBER) then
                    count_r <= to_unsigned(0, NUM_BITS);
                else
                    count_r <= count_r + 1;
                end if;
            end if;

            if (subtract_one = '1') then
                if (count_r /= 0) then
                    count_r <= count_r - 1;
                end if;
            end if;
        end if;

    end process;

    -- output <= std_logic_vector(count_r); -- uncomment when counter needs to output the number
    output <= '1' when count_r = MAX_COUNT_NUMBER else '0';

end BHV;

----------------------- REGISTER ENTITY ------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity reg is
    generic (WIDTH: integer := 16); -- Number of bits in the register
    port (
        clk : in std_logic;
        rst : in std_logic;
        en : in std_logic;
        input : in std_logic_vector(WIDTH-1 downto 0);
        output : out std_logic_vector(WIDTH-1 downto 0)
        );
end reg;

architecture BHV of reg is 
begin
    process (clk, rst)
    begin
        if (rst = '1') then
            output <= (others => '0');
        elsif (rising_edge(clk)) then
            if (en = '1') then
                output <= input;
            end if;
        end if;
    end process;
end BHV;
----------------------------------------------------------------------------------


---------------------- SIGNAL BUFFER Entiry --------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
-- use work.user_pkg.all; -- UNCOMMENT IT LATER

entity signal_buffer is
    generic (NUM_ELEMENTS: integer := 128; -- Number of elements in the buffer
             WIDTH:        integer := 16); -- Number of bits in each element
    port ( 
        clk : in std_logic;
        rst : in std_logic;
        rd_en  : in std_logic;  -- Just to get acknowledgement from the reader that it has read the current content of the buffer and now is the time to move on and load in the new element
        wr_en  : in std_logic;  -- Control for writing the data into this buffer
        wr_data : in std_logic_vector(WIDTH-1 downto 0);
        rd_data : out std_logic_vector(NUM_ELEMENTS*WIDTH-1 downto 0);
        empty : out std_logic;
        full : out std_logic
    );
end signal_buffer;

architecture Behavioral of signal_buffer is

    -- Defining an array of elements -- COMMENT ALL OF THESE LATER BECAUSE ALREADY PRESENT IN user_pkg.vhd
    -- constant C_KERNEL_SIZE           : positive := 128; 
    -- constant C_SIGNAL_WIDTH          : positive := 16;
    -- subtype SIGNAL_WIDTH_RANGE is natural range C_SIGNAL_WIDTH-1 downto 0;
    -- type window is array(0 to C_KERNEL_SIZE) of std_logic_vector(SIGNAL_WIDTH_RANGE);
    
    subtype SIGNAL_WIDTH_RANGE is natural range WIDTH-1 downto 0;
    type window is array(0 to NUM_ELEMENTS) of std_logic_vector(SIGNAL_WIDTH_RANGE);

    -- Creating an instance of array
    signal data_array : window;
    signal has_complete_window : std_logic;
    signal pipeline_in : std_logic_vector(rd_data'range);

begin

    U_REG : for i in 0 to NUM_ELEMENTS-1 generate
        U_REG : entity work.reg
            generic map(WIDTH => WIDTH)
            port map(
                clk => clk,
                rst => rst,
                en  => wr_en,
                input  => data_array(i),
                output => data_array(i+1)
            );
    end generate;

    U_DATAPATH_COUNTER : entity work.counter
    generic map(MAX_COUNT_NUMBER => NUM_ELEMENTS)
    port map(
        clk => clk,
        rst => rst,
        add_one => wr_en,
        subtract_one => rd_en,
        output => has_complete_window
    );

    empty <= not has_complete_window;
    
    -- full  <=     has_complete_window; -- This is the normal way of implementing it. Correct, but slower then the following logic

    full  <= has_complete_window and not rd_en; -- trying to increase the throughtput as suggested in signal buffer example


    -- put pipeline inputs into a big vector (i.e., "vectorize")
    U_VECTORIZE : for i in 0 to NUM_ELEMENTS-1 generate
    pipeline_in((i+1)*WIDTH-1 downto i*WIDTH) <= data_array(i);
    end generate;

    data_array(0) <= wr_data when wr_en = '1' else data_array(0);
    
    rd_data <= pipeline_in;

end Behavioral;
