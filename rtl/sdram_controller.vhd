-- SDRAM controller
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_controller is
	port (
		init,rd_req,wr_req,clk: in std_logic;
		address: in std_logic_vector(23 downto 0);
		cke,cs_b,ras_b,cas_b,we_b,ba_0,ba_1,dqm_l,dqm_h,ready,wait0: out std_logic;
		address_out: out std_logic_vector(12 downto 0);
		data_in: in std_logic_vector(15 downto 0);
		data_out: out std_logic_vector(15 downto 0);
		dbus: inout std_logic_vector(15 downto 0)
	);
end sdram_controller;

architecture sdram_controller_arc of sdram_controller is
type state is (init_s,init_nop1,init_pall,init_nop2,init_ar,init_nop3,init_msr,init_nop4,idle,write_act,write_nop1,write_nop2,write_nop3,write_cas
			   ,read_act,read_nop1,read_cas,read_nop2,read_nop3,ref_nop,ref_nop2,ref);
type cmd is (desl,nop,read1,reada,write1,writea,act,pre,pall,ref,self,mrs,idle1); -- for debug purposes
signal p_s,n_s: state;
signal cnt_setup,cnt_setup_reg: std_logic_vector(15 downto 0);
signal cnt_state_reg: std_logic_vector(3 downto 0);
signal cnt_setup_st,cnt_state_st,cnt_ar_st: std_logic;
signal command: std_logic_vector(7 downto 0);
signal command_nxt:std_logic_vector(7 downto 0);
signal cmd_d,cmd_d_nxt: cmd;
signal cnt_ar,cnt_ar_reg: std_logic_vector(3 downto 0);
signal busy: std_logic;
signal address_out_r: std_logic_vector(12 downto 0);
signal refresh_cnt_reg: std_logic_vector(9 downto 0);
signal stop_cnt_b,end_init,rw_ready,rw_ready_reg,dqm_h_r,dqm_l_r,dbus_in_en,dbus_out_en,data_out_en,ready_temp,dqm_h_temp,dqm_l_temp: std_logic;
signal data_in_reg,data_out_r,test_out,dbus_temp: std_logic_vector(15 downto 0);
--signal dbus_in,dbus_out: std_logic_vector(15 downto 0);
--commands                                            CCRCWBBA
constant cmd_desl  : std_logic_vector(7 downto 0) := "11000000"; -- device deselect
constant cmd_nop   : std_logic_vector(7 downto 0) := "10111000"; -- nop
constant cmd_read  : std_logic_vector(7 downto 0) := "10101000"; -- read
constant cmd_reada : std_logic_vector(7 downto 0) := "10101001"; -- read with auto precharge
constant cmd_write : std_logic_vector(7 downto 0) := "10100000"; -- write
constant cmd_writea: std_logic_vector(7 downto 0) := "10100001"; -- write with auto precharge
constant cmd_act   : std_logic_vector(7 downto 0) := "10011000"; -- bank activate
constant cmd_pre   : std_logic_vector(7 downto 0) := "10010000"; -- precharge
constant cmd_pall  : std_logic_vector(7 downto 0) := "10010001"; -- precharge all banks
constant cmd_ref   : std_logic_vector(7 downto 0) := "10001000"; -- auto refresh
constant cmd_self  : std_logic_vector(7 downto 0) := "10001000"; -- self refresh
constant cmd_mrs   : std_logic_vector(7 downto 0) := "10000000"; -- mode register set

--counts
constant refresh_cnt : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(380,10));

--attribute keep: string;
--attribute keep of data_out_en: signal is "true";

begin

--dbus<= dbus_temp;
--dbus_out <= data_in_reg;
(cke,cs_b,ras_b,cas_b,we_b) <= command(7 downto 3);

--ready <= rw_ready_reg;

--mux for selecting bank bits
bank_select_proc: process (command,address)
begin
	if (command = cmd_read or command = cmd_reada or command = cmd_write or command = cmd_writea or 
		command = cmd_act or command = cmd_pre) then
		(ba_1,ba_0) <= address(23 downto 22);
	else
		(ba_1,ba_0) <= command(2 downto 1);		
	end if;
end process;

--counter for initial delay after cold start
cnt_setup_proc: process(clk)
	begin	
		if (clk'event and clk='1') then
			if (cnt_setup_st = '1') then
				cnt_setup_reg <= cnt_setup;
			else
				if (init='1') then	
					if (cnt_setup_reg = x"0000") then
						cnt_setup_reg <= cnt_setup_reg;
					else
						cnt_setup_reg <= std_logic_vector(unsigned(cnt_setup_reg) - 1);			
					end if;
				end if;
				
			end if;
		end if;
	end process;

--counter for general delays
--reg value corresponds to no. of nops to be added
--at least 1 nop will be added
cnt_state_proc: process(clk,cnt_state_st,init)
	begin
		if (init = '0') then
			cnt_state_reg <= (others => '0');
		elsif (clk'event and clk='1') then
			if (cnt_state_st = '1') then
				if (p_s = init_pall) then
					cnt_state_reg <= x"1";
				elsif (p_s = init_ar) then
					cnt_state_reg <= x"3";
				elsif (p_s = init_msr) then
					cnt_state_reg <= x"1";
				elsif (p_s = read_act) then
					cnt_state_reg <= x"1";
				elsif (p_s = read_cas) then
					cnt_state_reg <= x"2"; -- latency
				elsif (p_s = write_act) then
					cnt_state_reg <= x"1";			
				elsif (p_s = write_cas) then
					cnt_state_reg <= x"2"; -- latency
				elsif (p_s = ref) then
					cnt_state_reg <= x"3";
				end if;
			else
				--if (init='1') then
					if (cnt_state_reg = x"0") then
						cnt_state_reg <= cnt_state_reg;
					else
						cnt_state_reg <= std_logic_vector(unsigned(cnt_state_reg) - 1);		
					end if;
				--end if;
			end if;
		end if;
	end process;

-- refresh counter
cnt_refresh_proc: process (clk)
	begin
		if (clk'event and clk='1') then
			if (end_init = '0' or p_s = ref_nop2) then
				refresh_cnt_reg <= 	refresh_cnt;
			else 
				if (p_s = ref_nop or stop_cnt_b = '0' or p_s = ref) then
					refresh_cnt_reg <= refresh_cnt_reg;
				else
					refresh_cnt_reg <= std_logic_vector(unsigned(refresh_cnt_reg) - 1);
				end if;
			end if;
		end if;
	end process;

-- counter for counting refresh cycles in the init sequence
cnt_ar_reg_proc:process (clk,cnt_ar_st)
	begin
		if (cnt_ar_st = '1') then
			cnt_ar_reg <= x"2";
			elsif (rising_edge(clk)) then
				if (cnt_ar_reg = x"0") then
					cnt_ar_reg <= cnt_ar_reg;
				elsif (p_s = init_ar) then
					cnt_ar_reg <= std_logic_vector(unsigned(cnt_ar_reg) - 1);
				end if;	
		end if;
	end process;

-- logic to stop refresh counter
stop_cnt_b_proc: process(refresh_cnt_reg,busy,p_s)
	begin
		if (refresh_cnt_reg = std_logic_vector(to_unsigned(0,10)) and (busy = '1' or p_s = idle)) then
			stop_cnt_b <= '0';
		else
			stop_cnt_b <= '1';
		end if;
	end process;

-- present state and misc registers
state_proc:process(clk,init)
 begin
	if (init = '0') then
		p_s <= init_s;
 	 	dqm_h <= '1';
	 	dqm_h_temp <= '1';
	 	dqm_l_temp <= '1';
	 	dqm_l <= '1';
	elsif (clk'event and clk='0') then
	 	p_s <= n_s;
	 	command <= command_nxt;
	 	cmd_d <= cmd_d_nxt;
	 	dqm_h <= dqm_h_r;
	 	dqm_h_temp <= dqm_h_r;
	 	dqm_l_temp <= dqm_l_r;
	 	dqm_l <= dqm_l_r;
	end if;
end process;


-- end_init and busy logic
end_init_busy_proc: process(init,clk)
 begin
	if (init = '0') then
		end_init <= '0';
		busy <= '1';
	elsif (rising_edge(clk)) then
		if (p_s = init_nop4 ) then
			busy <= '0';
			end_init <= '1';
		elsif (p_s = read_act or p_s = write_act) then
			busy <= '1';
			end_init <= '1';
		elsif (p_s = idle) then
			busy <= '0';
			end_init <= '1';
		end if;
	end if;
end process;

-- dqm logic
dqm_proc: process(p_s)
begin
	if (p_s = read_cas or p_s = write_cas) then
		dqm_l_r <= '0';
		dqm_h_r <= '0';
	else
		dqm_h_r <= '1';
		dqm_l_r <= '1';		
	end if;
end process;

-- sort out address depending on current state
address_out_proc: process(p_s,command_nxt,address)
begin
	--if (clk'event and clk= '0') then
	case(p_s) is
		when init_msr => 
			address_out_r(10) <= command_nxt(0);
			address_out_r(9 downto 0) <= "1000100000"; -- 1 > single write, 00 > standard operation, 010 > cas latency=2
			  										--  0 > sequential operation 000> burst length = 1
			 address_out_r(12 downto 11) <= "00";
		when read_act =>
			address_out_r<= address(21 downto 9);
		when read_cas =>
			address_out_r<= "00" & command_nxt(0) & '0' & address(8 downto 0);
		when write_act =>	
			address_out_r <= address(21 downto 9);			
		when write_cas =>
			address_out_r<= "00" & command_nxt(0) & '0' & address(8 downto 0);
		when others =>
			address_out_r<= (10 => command_nxt(0), others => '0');
	end case;
	--end if;
end process;

-- address out register
address_out_reg: process(clk)
begin
	if(clk'event and clk='0') then
		--if (busy = '0') then
			address_out <= address_out_r;
		--end if;
	end if;
end process;


-- read write ready reg
rw_ready_reg_proc: process(clk)
begin
	if (rising_edge(clk)) then
		rw_ready_reg <= rw_ready;
	end if;
end process;

--temp ready
ready_temp_proc: process(clk,init)
begin
	if (init = '0') then
--		ready <= '0';
		ready_temp <= '0';
--		wait0 <= '1';
	elsif (falling_edge(clk)) then
--		ready <= rw_ready_reg;
		ready_temp <= rw_ready_reg;
--		wait0 <= not rw_ready_reg;
	end if;
end process;

-- final ready and wait reg
ready_proc: process(clk,init)
begin
	if (init = '0') then
		ready <= '0';
		--ready_temp <= '0';
		wait0 <= '1';
	elsif (falling_edge(clk)) then
		ready <= ready_temp;
		--ready_temp <= rw_ready_reg;
		wait0 <= not ready_temp;
	end if;
end process;

--data in reg
data_in_reg_proc: process(clk)
begin
	if(falling_edge(clk)) then
		--if (busy = '0') then
			data_in_reg <= data_in;
			--data_out <= data_out_r;
		--end if;
	end if;
end process;

-- dbus drivers and control
dbus <= data_in_reg when dbus_out_en = '1' else (others => 'Z' );
data_out_r <= dbus;

data_out_en_proc: process(dqm_h_temp,dqm_l_temp,p_s)
begin
	if (((dqm_l_temp = '0' or dqm_h_temp = '0') and p_s = write_nop2) or p_s = write_cas) then
		dbus_out_en <= '1';
	else
		dbus_out_en <= '0';
	end if;
end process;

-- data out reg
data_out_proc: process(clk)
begin
	if (rising_edge(clk)) then
		if (ready_temp = '1') then
			data_out <= data_out_r;
		end if;
	end if;
end process;

-- next state logic
next_state_proc:process(p_s,cnt_state_reg,cnt_setup_reg,cnt_ar_reg,rd_req,wr_req,refresh_cnt_reg,busy,cnt_ar_st)
begin
	cnt_setup_st <= '0';
	cnt_setup <= (others => '0');
	command_nxt <= cmd_nop;
	cmd_d_nxt <= nop;
	cnt_ar_st <= '0';
	rw_ready <= '0';
	cnt_state_st <= '0';
	cnt_ar <= (others => '0');
	case(p_s) is
----------------------------------------------------------------------------
		--initialisation sequence
		when init_s => 
			cnt_setup_st <= '1';
			cnt_setup <= std_logic_vector(to_unsigned(10000,16)); --200us
			--cnt_setup <= x"0002";
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			n_s <= init_nop1;
		
		when init_nop1 =>
		cnt_setup_st <= '0';
		if (cnt_setup_reg = x"0000") then
			n_s <= init_pall;
		else
			n_s <= init_nop1;
		end if;

		when init_pall =>
			command_nxt <= cmd_pall;
			cmd_d_nxt <= pall;
			cnt_state_st <= '1';
			n_s <= init_nop2;
		
		when init_nop2 =>
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			cnt_state_st <= '0';
		if (cnt_state_reg = x"0") then
			n_s <= init_ar;
			cnt_ar_st <= '1';
		else
			n_s <= init_nop2;
		end if;

		when init_ar =>
			command_nxt <= cmd_ref;
			cmd_d_nxt <= ref;
			cnt_state_st <= '1';
			cnt_ar_st <= '0';
			cnt_ar <= x"2";
			n_s <= init_nop3;
		
		when init_nop3 =>
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			cnt_ar_st <= '0';
			cnt_state_st <= '0';
			if (cnt_state_reg = x"0") then
				if (cnt_ar_reg <= x"0") then
					n_s <= init_msr;
				else
					n_s <= init_ar;					
				end if;
			else
				n_s <= init_nop3;
			end if;

		when init_msr =>
			command_nxt <= cmd_mrs;
			cmd_d_nxt <= mrs;
			cnt_state_st <= '1';
			n_s <= init_nop4;
		--	address_out(9 downto 0) <= "1000110000"; -- 1 > single write, 00 > standard operation, 011 > cas latency=2
													--  0 > sequential operation 000> burst length = 1   

		when init_nop4 =>
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			cnt_state_st <= '0';
			--end_init <= '1';
			if (cnt_state_reg = x"0") then
				n_s <= idle;
			else
				n_s <= init_nop4;
			end if;
-- initialization sequence end here
--------------------------------------------------------------------------------
		when idle =>
			report "idle";
			command_nxt <= cmd_nop;
			cmd_d_nxt <= idle1;
			--busy <= '0';
			if (refresh_cnt_reg = std_logic_vector(to_unsigned(0,10)) and busy = '0') then
				n_s <= ref;
			elsif (rd_req = '1') then
				n_s <= read_act; -- add signal
				--busy <= '1';
			elsif (wr_req = '1') then
				n_s <= write_act; -- add signal
				--busy <= '1';
			else
				n_s <= idle;			
			end if;
--------------------------------------------------------------------------------
-- read sequence
		when read_act =>
			command_nxt <= cmd_act;
			cmd_d_nxt <= act;
			cnt_state_st <= '1';
			rw_ready <= '0';
			n_s <= read_nop1;
			--n_s <= read_cas;
			report "read activate";
		when read_nop1 =>
		 	command_nxt <= cmd_nop;
		 	cmd_d_nxt <= nop;
		 	cnt_state_st <= '0';
		 	if (cnt_state_reg = x"0") then
				n_s <= read_cas;
			else
				n_s <= read_nop1;		 		
		 	end if;
		 when read_cas =>
		 	report "read cas";
		 	command_nxt <= cmd_reada;
		 	cmd_d_nxt <= reada;
		 	cnt_state_st <= '1'; 
		 	n_s <= read_nop2;
		 when read_nop2 =>
		 	command_nxt<= cmd_nop;
		 	cmd_d_nxt <= nop;
		 	cnt_state_st <= '0';
		 	if (cnt_state_reg = x"0" or cnt_state_reg = x"1") then
		 		rw_ready <= '1';
		 	end if;
		 	if (cnt_state_reg = x"0") then
				--rw_ready <= '1';
				n_s <= read_nop3;
			else
				n_s <= read_nop2;		 		
		 	end if;
		 --filler state to accomodate delays in gate level
		when read_nop3 =>
			command_nxt<= cmd_nop;
		 	cmd_d_nxt <= nop;
		 	n_s <= idle;
---------------------------------------------------------------------------------
-- write sequence
		
		when write_act =>
			command_nxt <= cmd_act;
			cmd_d_nxt <= act;
			cnt_state_st <= '1';
			n_s <= write_nop1;
			rw_ready <= '0';		
		when write_nop1 =>
		 	command_nxt <= cmd_nop;
		 	cmd_d_nxt <= nop;
		 	cnt_state_st <= '0';
		 	if (cnt_state_reg = x"0") then
				n_s <= write_cas;
			else
				n_s <= write_nop1;		 		
		 	end if;
		 when write_cas =>
		 	command_nxt <= cmd_writea;
		 	cmd_d_nxt <= writea;
		 	cnt_state_st <= '1';
		 	n_s <= write_nop2;
		 when write_nop2 =>
		 	command_nxt<= cmd_nop;
		 	cmd_d_nxt <= nop;
		 	cnt_state_st <= '0';
		 	if (cnt_state_reg = x"0") then
				n_s <= write_nop3;
				--rw_ready <= '1';
			else
				n_s <= write_nop2;		 		
		 	end if;
		 	if (cnt_state_reg = x"0" or cnt_state_reg = x"1") then
		 		rw_ready <= '1';
		 	end if;
		 --filler state to accomodate delays in gate level
		 when write_nop3 =>
		 	command_nxt <= cmd_nop;
		 	cmd_d_nxt <= nop;
		 	n_s <= idle;
-------------------------------------------------------------------------------
-- refresh sequence

		when ref =>
			command_nxt <= cmd_ref;
			cmd_d_nxt <= ref;
			cnt_state_st <= '1';	
			n_s <= ref_nop;
		
		when ref_nop =>
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			cnt_state_st <= '0';
			if (cnt_state_reg = x"0") then
				n_s <= ref_nop2;
			else
				n_s <= ref_nop;
			end if;
		when ref_nop2 =>
			n_s <= idle;
		when others =>
			null;
	end case;
end process;
end sdram_controller_arc;