-- Archit Jaiswal
-- Entity: Signal Buffer 128 elements (16 bit each)

-- Functionality description:
-- 1. It will be reading one (16-bit) element at a time from the FIFO which performs clock domain crossing to fetch data from DRAM and bring it to the datapath CLK

-- 2. Whenever the FIFO is ready to give an element, it will assert 'wr_en' and give data to 'wr_data' signal. If the buffer is full then 'full' signal will be set to inform the FIFO that it needs to stop because the buffer is full and data has not been read by the pipeline/datapath. 

-- NOTE: 128 elements forms a window of input to the datapath that performs 1-D convolution. Therefore, it is a sliding window buffer. Meaning one element is used multiple times in different pipelines and only one element needs to be evicted to form a 'new windows' for another pipeline.  

-- 3. Everytime a write occurs from FIFO, a counter will be incremented to know when a window of data is ready for the pipeline to start computation. Empty signal means that the buffer is not yet loaded with "fresh" 128 elements to form a complete window and tells the pipeline that a new window is not ready yet, so do not read anything. 

-- 4. Once the 128 elements are ready, the buffer will set the full flag to tell the FIFO to pause writing and remove the empty flag to tell the pipeline that now it has a complete window loaded (not empty) and the pipeline should consider reading the data in buffer. 

-- 5. This buffer passes the entire bit vector (128 elements * 16 bits = 2048 bits) down to the datapath/pipeline. When the pipeline has read the data, it will acknowledge to buffer by setting the 'rd_en', so buffer knows that the data it contains is now old and it needs to load new elements from the FIFO.  

-- 6. 'rd_en' will decrement the counter to 127 which will lead to the empty flag and the removal of full flag. Due to this, the FIFO will get notified that now the buffer is not full and it may pull the wr_en to write more data to the buffer.

----------------------------------------------------------------------------------


---------------------- SIGNAL BUFFER Entiry --------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
-- use work.user_pkg.all; -- UNCOMMENT IT LATER

entity signal_buffer is
    generic (NUM_ELEMENTS: integer          := 128; -- Number of elements in the buffer
             WIDTH:        integer          := 16;
             RESET_VALUE:  std_logic_vector := ""); -- Number of bits in each element
    port ( 
        clk : in std_logic;
        rst : in std_logic;
        rd_en  : in std_logic;  -- Just to get acknowledgement from the reader that it has read the current content of the buffer and now is the time to move on and load in the new element
        wr_en  : in std_logic;  -- Control for writing the data into this buffer
        wr_data : in std_logic_vector(WIDTH-1 downto 0); -- INPUT DATA | coming from the FIFO
        rd_data : out std_logic_vector(NUM_ELEMENTS*WIDTH-1 downto 0); -- OUTPUT DATA | going to the pipeline/datapath to compute the 1D convolution
        empty : out std_logic;
        full : out std_logic
    );
end signal_buffer;

architecture Behavioral of signal_buffer is

    -- Instantiate a counter
    component counter
        generic (MAX_COUNT_NUMBER: integer); -- it will count from 0 to 127, so total 128 times
        port (
            clk : in std_logic;
            rst : in std_logic;
            add_one : in std_logic;
            subtract_one : in std_logic;
            output : out std_logic -- single bit output (will be 1 when the count reaches MAX_COUNT_NUMBER)
        );
    end component;

    signal has_complete_window : std_logic; -- It means buffer has a fresh window of elements waiting to be read. Full will not be asserted in the case where wr_en and rd_en both are ON and buffer is simultanously loaded with new elements

    signal full_internal       : std_logic; -- This will be be used to ignore the inputs if the buffer is full and not increment the counter
    signal empty_internal       : std_logic; -- This will be be used to ignore subtracting the counter if the buffer is empty

    signal valid_wr : std_logic;
    signal valid_rd : std_logic;

begin

    -- handle a special case of having buffer of element size zero
    U_NUM_ELEMENT_EQ_0: if NUM_ELEMENTS = 0 generate
        rd_data <= wr_data; 
    end generate U_NUM_ELEMENT_EQ_0;

    U_NUM_ELEMENTS_GT_0: if NUM_ELEMENTS > 0 generate
        -- Defining an array of elements 
        subtype SIGNAL_WIDTH_RANGE is natural range WIDTH-1 downto 0;
        type window is array(0 to NUM_ELEMENTS-1) of std_logic_vector(SIGNAL_WIDTH_RANGE);
        
        -- Creating an instance of array
        signal data_array : window;
        signal vectorized_output : std_logic_vector(rd_data'range); -- A vector of all bits of all elements (NUM_ELEMENTS * WIDTH = A long bit vector)

    begin

        process (clk, rst)
        begin
            if (rst = '1') then
                -- Check if the user wants to set some fixed value upon resetting it, otherwise set it to the default (others <= '0')
                if (RESET_VALUE /= "") then
                    for i in 0 to NUM_ELEMENTS-1 loop
                        data_array(i) <= RESET_VALUE;
                    end loop;
                else
                    for i in 0 to NUM_ELEMENTS-1 loop
                        data_array(i) <= (others => '0');
                    end loop;
                end if;

            elsif (rising_edge(clk)) then
                if (wr_en = '1' and full_internal = '0') then
                    data_array(0) <= wr_data;
                end if;

                if (NUM_ELEMENTS > 1) then
                    for i in 0 to NUM_ELEMENTS-2 loop
                        if (wr_en = '1' and full_internal = '0') then
                            data_array(i+1) <= data_array(i);
                        end if;
                    end loop;
                end if;
            end if;
        end process;

        -- put pipeline inputs into a big vector (i.e., "vectorize")
        U_VECTORIZE : for i in 0 to NUM_ELEMENTS-1 generate
            vectorized_output((i+1)*WIDTH-1 downto i*WIDTH) <= data_array(i);
        end generate;

        rd_data <= vectorized_output;

    end generate U_NUM_ELEMENTS_GT_0;

    
    U_DATAPATH_COUNTER : counter
    generic map(MAX_COUNT_NUMBER => NUM_ELEMENTS)
    port map(
        clk => clk,
        rst => rst,
        add_one => valid_wr,
        subtract_one => valid_rd,
        output => has_complete_window
    );

    empty <= not has_complete_window;
    empty_internal <= not has_complete_window;

    full  <= has_complete_window and not rd_en; -- if rd_en is asserted then the data will be read right away and the buffer will be not full. 
    -- full <= has_complete_windows; This will only give half of the bandwidth because when the buffer is full, the FIFO will stop and continue until it is not full. This will keep oscilating and will be slower. 
    full_internal <= has_complete_window and not rd_en; -- This is a copy of "full" because old VHDL does not allows outputs to be read inside the design

    -- Make sure that the read and write signals are valid before sending them to the counter otherwise the flags will be wrong
    valid_wr <= wr_en and not full_internal;  
    valid_rd <= rd_en and not empty_internal;
    

end Behavioral;
