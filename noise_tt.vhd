

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;
ENTITY noise_tt IS
	PORT
	(	
		LDATA, RDATA		: IN std_logic_vector(15 downto 0); -- parallel external data inputs( we need to feed this data from memory) 
		clk, Reset 	: IN std_logic; 
		INITIALISE_FINISH 		: OUT std_logic;   -- intialisation of codec finishes
		adc_full 			: OUT std_logic;   -- if you are using ADC also. 
		data_over 			: OUT std_logic; -- sample sync pulse
		AUD_MCLK 			: OUT std_logic; -- Codec master clock OUTPUT( the clock which is used by codec to synchronize communication and data processing)
		AUD_BCLK 			: IN std_logic; -- Digital Audio bit clock  ( bit transmission clock)
		AUD_ADCDAT 			: IN std_logic;
		AUD_DACDAT 			: OUT std_logic; -- DAC data line ( data input line to COdec from FPGA)
		AUD_DACLRCK			: IN std_logic; -- DAC data left/right select 
		AUD_ADCLRCK 		: IN std_logic; -- DAC data left/right select
		I2C_SDAT 			: OUT std_logic; -- serial interface data line
		I2C_SCLK 			: OUT std_logic;  -- serial interface clock
		ADCDATA 				: OUT std_logic_vector(31 downto 0)
	);
END noise_tt;

ARCHITECTURE Behavorial OF noise_tt IS

TYPE I2C_state is (initialize, start, b0, b1, b2, b3, b4, b5, b6, b7, b_ack, 
					a0, a1, a2, a3, a4, a5, a6, a7, a_ack,
					d0, d1, d2, d3, d4, d5, d6, d7, d_ack,
					b_stop0, b_stop1, b_end);
					

signal Bcount : integer range 0 to 31;
signal adc_count : integer range 0 to 32;
signal word_count : integer range 0 to 12;
signal LRDATA : std_logic_vector(31 downto 0); -- stores L&R data
signal state, next_state : I2C_state;
signal SCI_ADDR, SCI_WORD1, SCI_WORD2 : std_logic_vector(7 downto 0);

signal i2c_counter : unsigned(9 downto 0); 
signal SCLK_int, init_over, sck0, sck1, count_en, word_reset : std_logic;
signal SCLK_inhibit : std_logic;

signal dack0, dack1, bck0, bck1, adck0, adck1, flag, flag1 : std_logic;
signal adc_reg_val : std_logic_vector(31 downto 0);

CONSTANT word_limit : integer := 8;

type rom_type is array (0 to word_limit) of std_logic_vector(7 downto 0);

constant SCI_REG_ROM : rom_type := (    --- configuration register address
	x"12", -- Deactivate, R9
	x"01", -- Mute L/R, Load Simul, R0
	x"05", -- Headphone volume - R2
	x"08", -- DAC Unmute, R4
	x"0A", -- DAC Stuff, R5
	x"0C", -- More DAC stuff, R6
	x"0E", -- Format, R7
	x"10", -- Normal Mode, R8
	x"12"  -- Reactivate, R9
);

constant SCI_DAT_ROM : rom_type := (      -- corresponding configuration data
	"00000000", -- Deactivate - R9
	"00011111", -- ADC L/R Volume - R0 
	"11110101", -- Headphone volume - R2 
	"11010000", -- Select DAC - R4
	"00000101", -- Turn off de-emphasis,  Off with HPF, unmute; - R5
	"01100000", -- Device power on, ADC/DAC power on - R6
	"01000011", -- Master, 16-bits, DSP mode;- R7
	"00000000", -- Normal, 8kHz - R8 
	"00000001" -- Reactivate - R9
);
	

BEGIN

	SCI_ADDR <= "00110100"; -- Device I2C address
	
	-- Load new L/R channel data on the rising edge of DACLRCK.
	-- Decrease sample count
	DACData : process(Clk, Reset, LDATA, RDATA, dack0, dack1, Bcount, flag1)
	begin
		if (Reset = '0') then
			LRDATA <= (OTHERS=>'0'); 
			Bcount <= 31;

		elsif(rising_edge(Clk)) then
			if (dack0 = '1' and dack1 = '0') then -- Rising edge
				LRDATA <= LDATA & RDATA;
				Bcount <= 31;
				flag1 <= '1';
			elsif (bck0 = '1' and bck1 = '0' and flag1 = '1') then
				flag1 <= '0';
			elsif (bck0 = '0' and bck1 = '1') then -- BCLK falling edge
					Bcount <= Bcount - 1;
			end if;
		end if;
	end process;
	
	
	I2C_Cnt : process(Clk, Reset)   ---- Clock counter
	begin
		if (Reset = '0') then
			i2c_counter <= (OTHERS => '0'); 
		elsif (rising_edge(Clk)) then
			i2c_counter <= i2c_counter + 1; 
		end if;
	end process;
	

	-- SCLK clock
	SCLK : process(Clk, Reset, SCLK_int)
	begin
		if (Reset = '0') then
			sck0 <= '0';
			sck1 <= '0';
		elsif(rising_edge(Clk)) then
			sck1 <= sck0;
			sck0 <= SCLK_int;
		end if;
	end process;
	
	
	DALRCK : process(Clk, Reset, AUD_DACLRCK) -- Left right DALRCK
	begin
		if (Reset = '0') then
				dack0 <= '0';
				dack1 <= '0';
		elsif(rising_edge(Clk)) then
			dack1 <= dack0;
			dack0 <= AUD_DACLRCK;
		end if;
	end process;
	
	
	ADCLRCK : process(Clk, Reset, AUD_DACLRCK) -- left right ADCLRCK
	begin
		if (Reset = '0') then
			adck0 <= '0';
			adck1 <= '0';
		elsif(rising_edge(Clk)) then
			adck1 <= adck0;
			adck0 <= AUD_ADCLRCK;
		end if;
	end process;
	
	
	BCLK  : process(Clk, Reset, AUD_BCLK) --  BCLK
	begin
		if (Reset = '0') then
			bck0 <= '0';
			bck1 <= '0';
		elsif(rising_edge(Clk)) then
			bck1 <= bck0;
			bck0 <= AUD_BCLK;
		end if;
	end process;
	
	
	word_cnt : process(SCLK_int, Count_EN, Reset, word_reset) -- number of actual transmitted configuration data frames.
	begin
		if (Reset = '0' or word_reset = '1') then
			word_count <= 0;
		elsif(falling_edge(SCLK_int)) then
			if (Count_EN = '1') then
				word_count <= word_count + 1;
			else
				word_count <= word_count;
			end if;
		end if;
	end process;
	
	state_machine : process(Clk, Reset)
	begin
		if (Reset = '0') then
			state <= initialize;
		elsif(rising_edge(Clk)) then
			state <= next_state;
		end if;
	end process;
	
	-- Implement I2C process, one step at a time. The state machine is designed to 
	-- progresses through states on the falling edge of SCLK.
	next_state_i2c : process(Clk, state, SCLK_int, sck0, sck1, word_count)
	begin
		word_reset <= '0';
		case state is
			when initialize =>
				if (SCLK_INT = '1') then
					next_state <= start;
				else
					next_state <= initialize;
				end if;
			when start =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b0; -- Start condition
				else
					next_state <= start;
				end if;
			when b0 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b1;
				else
					next_state <= b0;
				end if;
			when b1 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b2;
				else
					next_state <= b1;
				end if;
			when b2 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b3;
				else
					next_state <= b2;
				end if;
			when b3 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b4;
				else
					next_state <= b3;
				end if;
			when b4 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b5;
				else
					next_state <= b4;
				end if;
			when b5 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b6;
				else
					next_state <= b5;
				end if;
			when b6 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b7;
				else
					next_state <= b6;
				end if;
			when b7 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= b_ack;
				else
					next_state <= b7;
				end if;
			when b_ack =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a0; -- First ack.
				else
					next_state <= b_ack;
				end if;
			when a0 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a1;
				else
					next_state <= a0;
				end if;
			when a1 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a2;
				else
					next_state <= a1;
				end if;
			when a2 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a3;
				else
					next_state <= a2;
				end if;
			when a3 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a4;
				else
					next_state <= a3;
				end if;
			when a4 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a5;
				else
					next_state <= a4;
				end if;
			when a5 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a6;
				else
					next_state <= a5;
				end if;
			when a6 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a7;
				else
					next_state <= a6;
				end if;
			when a7 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= a_ack;
				else
					next_state <= a7;
				end if;
			when a_ack =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d0; -- Second ack
				else
					next_state <= a_ack;
				end if;
			when d0 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d1;
				else
					next_state <= d0;
				end if;
			when d1 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d2;
				else
					next_state <= d1;
				end if;
			when d2 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d3;
				else
					next_state <= d2;
				end if;
			when d3 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d4;
				else
					next_state <= d3;
				end if;
			when d4 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d5;
				else
					next_state <= d4;
				end if;
			when d5 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d6;
				else
					next_state <= d5;
				end if;
			when d6 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d7;
				else
					next_state <= d6;
				end if;
			when d7 =>
				if (sck0 = '0' and sck1 = '1') then
					next_state <= d_ack; -- Last ack
				else
					next_state <= d7;
				end if;
			when d_ack =>
				-- Check to see if we've transmitted the correct number
				-- of words. If so, done. If not, transmit more.
				if (sck0 = '0' and sck1 = '1') then
					if (word_count = word_limit+1) then
						next_state <= b_stop0;
					else
						next_state <= initialize;
					end if;
				else
					next_state <= d_ack;
				end if;
			when b_stop0 =>
				-- If we're done, generate a stop condition
				if (SCLK_INT = '1') then
					next_state <= b_stop1;
				else
					next_state <= b_stop0;
				end if;
			when b_stop1 =>
				next_state <= b_end;
			when b_end =>
				next_state <= b_end;
				word_reset <= '1';
		end case;
	end process;
	
	outputs_i2c : process(state, SCI_ADDR, word_count)
	begin
		init_over <= '0';
		count_en <= '0';
		sclk_inhibit <= '0';
		case state is
			when initialize =>
				I2C_SDAT <= '1'; -- SDAT starts high
			when start =>
				I2C_SDAT <= '0'; -- SDAT falling edge
			when b0 =>
				I2C_SDAT <= SCI_ADDR(7);
			when b1 =>
				I2C_SDAT <= SCI_ADDR(6);
			when b2 =>
				I2C_SDAT <= SCI_ADDR(5);
			when b3 =>
				I2C_SDAT <= SCI_ADDR(4);
			when b4 =>
				I2C_SDAT <= SCI_ADDR(3);
			when b5 =>
				I2C_SDAT <= SCI_ADDR(2);
			when b6 =>
				I2C_SDAT <= SCI_ADDR(1);
			when b7 =>
				I2C_SDAT <= SCI_ADDR(0);
			when b_ack =>
				I2C_SDAT <= 'Z';
			when a0 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(7);
			when a1 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(6);
			when a2 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(5);
			when a3 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(4);
			when a4 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(3);
			when a5 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(2);
			when a6 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(1);
			when a7 =>
				I2C_SDAT <= SCI_REG_ROM(word_count)(0);
			when a_ack =>
				I2C_SDAT <= 'Z';
			when d0 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(7);
			when d1 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(6);
			when d2 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(5);
			when d3 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(4);
			when d4 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(3);
			when d5 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(2);
			when d6 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(1);
			when d7 =>
				I2C_SDAT <= SCI_DAT_ROM(word_count)(0);
			when d_ack =>
				I2C_SDAT <= 'Z';
				count_en <= '1';
			when b_stop0 =>
				-- Keep SDAT at low until SCLK goes high
				I2C_SDAT <= '0';
			when b_stop1 =>
				-- SCLK is high, so SDAT has a rising edge
				I2C_SDAT <= '1';
				sclk_inhibit <= '1';
			when b_end =>
				I2C_SDAT <= '1';
				init_over <= '1';
				sclk_inhibit <= '1';
		end case;
	end process;

	adc_proc : process(Clk, bck0, bck1, adc_reg_val, adck0, adck1, Reset, adc_count, flag)
	begin
		if (Reset = '0') then
			adc_reg_val <= (OTHERS => '0'); 
			adc_count <= 31;
			adc_full <= '0';
		elsif(rising_edge(Clk)) then
			adc_reg_val(adc_count) <= AUD_ADCDAT;
			adc_full <= '0';
			if (adc_count = 0) then
				adc_full <= '1';
			end if;
			
			if (adck0 = '1' and adck1 = '0') then -- Rising edge
				adc_count <= 31; -- Read in more new ADC data on a ADCLRC rising edge
			elsif ( (not (adc_count = 0)) and bck0 = '0' and bck1 = '1') then -- Falling edge
					adc_count <= adc_count - 1; -- When not feeding with new data, shift new bit in
			end if;
			
		end if;
	end process;
			
	
	SCLK_int <= I2C_counter(9) or SCLK_inhibit; -- SCLK = CLK / 512 = 97.65 kHz ~= 100 kHz
	--SCLK_int <= I2C_counter(3) or SCLK_inhibit; -- For simulation only
	AUD_MCLK <= I2C_counter(2); -- MCLK = CLK / 4
	I2C_SCLK <= SCLK_int;

	AUD_DACDAT <= LRDATA(Bcount);
	data_over <= flag1;
	initialise_finish <= init_over;
	ADCDATA <= adc_reg_val;
			
end Behavorial;