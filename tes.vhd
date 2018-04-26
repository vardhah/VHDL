LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;
ENTITY tes IS
	PORT
	(	
		
		clk,in_signal, in1, in2 : IN std_logic;       -- 50 MHZ clock and input signal of keyboard/from component
		xout  : out std_logic               -- at GPIO
	);
end tes; 

architecture b of tes is 

 signal i2c_counter : unsigned(24 downto 0); 
 signal x,y,z: std_logic :='1';
 signal k,l,m : std_logic := '0';
 signal a, b,d: std_logic :='0';
 signal h : std_logic;  
 begin
 I2C_Count : process(Clk)
variable c : integer :=0;	
	begin
		 
counter:	if (rising_edge(Clk)) then
			i2c_counter <= i2c_counter + 1; 
		end if;
	 
  
Signal_read: 
  if clk'event and clk='1' then  	 
    
	 if in_signal ='1' then                  --- signal 1 input
	      x<='0';
			c := 0; 
		end if; 
	  if x='0' then
		 if c<5e7 then         -- every time some one press the key to jump, the sound will beep for 1 sec,
	     c := C+1;             -- change value of C to change time duration. 
		  k<= '1';  
	    else
	     x <= '1';
		  k<= '0'; 
	    end if; 
	  end if; 
	 
	 if in1 ='1' then                         --- signal 2 input
	      y<='0';
			c := 0; 
		end if; 
	 if y='0' then
		 if c<5e7 then         -- every time some one press the key to jump, the sound will beep for 1 sec,
	     c := C+1; 
		  l<= '1';  
	    else
	     y <= '1';
		  l<= '0'; 
	    end if; 
	  end if; 
	
	if in2 ='1' then                         --- signal 2 input
	      z<='0';
			c := 0; 
		end if; 
	 if z='0' then
		 if c<5e7 then         -- every time some one press the key to jump, the sound will beep for 1 sec,
	     c := C+1; 
		  m<= '1';  
	    else
	     z <= '1';
		  m<= '0'; 
	    end if; 
	  end if; 
	
  if (i2c_counter(22) = '1') then 
	   h<= i2c_counter(13) or i2c_counter(12) or i2c_counter(18) or i2c_counter(17) or i2c_counter(16) or i2c_counter(15) or i2c_counter(14) ;
	else
	   h <= not(i2c_counter(13) or i2c_counter(12) or i2c_counter(18) or i2c_counter(17) or i2c_counter(16) or i2c_counter(15) or i2c_counter(14));
	 end if;
	
	a <= h and m;
	
	b <= i2c_counter(13) and k;
	
	
	d <= (i2c_counter(20) or i2c_counter(15)) and  l; 

	
   xout <= a or b or d ; 	       --- out put pin of all three signals
	 end if;  
	
end process; 	


end architecture b;
