-- SDRAM controller
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_controller is
	port (
		init,rd_req,wr_req,clk: in std_logic;
		address: in std_logic_vector(23 downto 0);
		clk_out,cke,cs_b,ras_b,cas_b,we_b,ba_0,ba_1,dqm_l,dqm_h: out std_logic;
		address_out: out std_logic_vector(12 downto 0);
		data_in: in std_logic_vector(15 downto 0);
		data_out: out std_logic_vector(15 downto 0);
		data_in_out: inout std_logic_vector(15 downto 0)
	);
end sdram_controller;

architecture sdram_controller_arc of sdram_controller is
type state is (init_s,init_nop1,init_pall,init_nop2,init_ar,init_nop3,init_msr,init_nop4,idle);
type cmd is (desl,nop,read1,reada,write1,writea,act,pre,pall,ref,self,mrs,idle1); -- for debug purposes
signal p_s,n_s: state;
signal cnt_setup,cnt_setup_reg: std_logic_vector(15 downto 0);
signal cnt_state,cnt_state_reg: std_logic_vector(3 downto 0);
signal cnt_setup_st,cnt_state_st,cnt_ar_st: std_logic;
signal command: std_logic_vector(7 downto 0);
signal command_nxt:std_logic_vector(7 downto 0);
signal cmd_d,cmd_d_nxt: cmd;
signal cnt_ar: std_logic_vector(3 downto 0);
signal busy: std_logic;

--commands				                              CCRCWBBA
constant cmd_desl  : std_logic_vector(7 downto 0) := "11------"; -- device deselect
constant cmd_nop   : std_logic_vector(7 downto 0) := "10111---"; -- nop
constant cmd_read  : std_logic_vector(7 downto 0) := "10101--0"; -- read
constant cmd_reada : std_logic_vector(7 downto 0) := "10101--1"; -- read with auto precharge
constant cmd_write : std_logic_vector(7 downto 0) := "10100--0"; -- write
constant cmd_writea: std_logic_vector(7 downto 0) := "10100--1"; -- write with auto precharge
constant cmd_act   : std_logic_vector(7 downto 0) := "10011---"; -- bank activate
constant cmd_pre   : std_logic_vector(7 downto 0) := "10010--0"; -- precharge
constant cmd_pall  : std_logic_vector(7 downto 0) := "10010--1"; -- precharge all banks
constant cmd_ref   : std_logic_vector(7 downto 0) := "10001---"; -- auto refresh
constant cmd_self  : std_logic_vector(7 downto 0) := "10001---"; -- self refresh
constant cmd_mrs   : std_logic_vector(7 downto 0) := "10000000"; -- mode register set


begin


(cke,cs_b,ras_b,cas_b,we_b) <= command(7 downto 3);

--mux for selecting bank bits
bank_select_proc: process (command)
begin
	if (command = cmd_read or command = cmd_reada or command = cmd_write or command = cmd_writea or 
		command = cmd_act or command = cmd_pre) then
		(ba_1,ba_0) <= address(23 downto 22);
	else
		(ba_1,ba_0) <= command(2 downto 1);		
	end if;
end process;

-- mux for selecting bank bits
a10_select_proc: process (command)
begin
	if (command = cmd_act) then
		address_out(10) <= address(10);
	else
		address_out(10) <= command(0);
	end if;
end process;

--counter for initial delay
cnt_setup_proc: process(init,clk,cnt_setup_st)
	begin	
		if (clk'event and clk='1') then
			if (cnt_setup_st = '1') then
				cnt_setup_reg <= cnt_setup;
				--if (cnt_setup_reg = x"0000") then
				--	cnt_setup_reg <= cnt_setup_reg;
			else
					if (init='1') then	
						if (cnt_setup_reg = x"0000") then
							cnt_setup_reg <= cnt_setup_reg;
						else
							cnt_setup_reg <= std_logic_vector(unsigned(cnt_setup_reg) - 1);			
						end if;
					end if;
				--end if;
			end if;
		end if;
	end process;

--counter for general delays
cnt_state_proc: process(init,clk)
	begin
		if (clk'event and clk='1') then
			if (cnt_state_st = '1') then
				cnt_state_reg <= cnt_state;
--				if (cnt_state_reg = x"00") then
--					cnt_state_reg <= cnt_state;
			else
					if (init='1') then
						if (cnt_state_reg = x"0") then
							cnt_state_reg <= cnt_state_reg;
						else
							cnt_state_reg <= std_logic_vector(unsigned(cnt_state_reg) - 1);		
						end if;
					end if;
--				end if;
			end if;
		end if;
	end process;




state_proc:process(clk,init)
begin
	if (init = '0') then
		p_s <= init_s;
		busy <= '1';
	elsif (clk'event and clk='0') then
	 	p_s <= n_s;
	 	command <= command_nxt;
	 	cmd_d <= cmd_d_nxt;
	else
		p_s <= p_s;
		command <= command;
		cmd_d <= cmd_d;
	end if;
end process;


next_state_proc:process(p_s,cnt_state_reg,cnt_setup_reg,cnt_ar)
begin
	case(p_s) is
		--initialisation sequence
		when init_s => 
			cnt_setup_st <= '1';
			cnt_setup <= x"4E20";
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
			cnt_state <= x"1";
			n_s <= init_nop2;
		
		when init_nop2 =>
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			cnt_state_st <= '0';
		if (cnt_state_reg = x"0") then
			n_s <= init_ar;
			cnt_ar_st <= '0';
			cnt_ar <= x"7";
		else
			n_s <= init_nop2;
		end if;

		when init_ar =>
			command_nxt <= cmd_ref;
			cmd_d_nxt <= ref;
			cnt_state_st <= '1';
			--cnt_ar_st <= '0';
			cnt_state <= x"6";
			if (cnt_ar_st = '1') then
				cnt_ar <= std_logic_vector(unsigned(cnt_ar) - 1);
				cnt_ar_st <= '0';	
			end if;
			
			n_s <= init_nop3;
		
		when init_nop3 =>
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			cnt_state_st <= '0';
			if (cnt_state_reg = x"0") then
				if (cnt_ar <= x"0") then
					n_s <= init_msr;
				else
					n_s <= init_ar;
					cnt_ar_st <= '1';
					--cnt_ar <= std_logic_vector(unsigned(cnt_ar) - 1);					
				end if;
			else
				n_s <= init_nop3;
			end if;

		when init_msr =>
			command_nxt <= cmd_mrs;
			cmd_d_nxt <= mrs;
			cnt_state_st <= '1';
			cnt_state <= x"1";
			n_s <= init_nop4;
			address_out(9 downto 0) <= "1000110000"; -- 1 > single write, 00 > standard operation, 011 > cas latency=3
													--  0 > sequential operation 000> burst length = 1   

		when init_nop4 =>
			command_nxt <= cmd_nop;
			cmd_d_nxt <= nop;
			cnt_state_st <= '0';
			if (cnt_state_reg = x"0") then
				n_s <= idle;
			else
				n_s <= init_nop4;
			end if;
-- initialization sequence end here
		

		when idle =>
			cmd_d_nxt <= idle1;
			busy <= '0';
		when others =>
			null;
	end case;
end process;
end sdram_controller_arc;