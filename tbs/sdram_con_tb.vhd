library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_con_tb is
end sdram_con_tb;

architecture sdram_con_tb_arc of sdram_con_tb is

signal init,rd_req,wr_req,clk:  std_logic;
signal address: std_logic_vector(23 downto 0);
signal clk_out,cke,cs_b,ras_b,cas_b,we_b,ba_0,ba_1,dqm_l,dqm_h:  std_logic;
signal address_out: std_logic_vector(12 downto 0);
signal data_in:  std_logic_vector(15 downto 0);
signal data_out:  std_logic_vector(15 downto 0);
signal data_in_out:  std_logic_vector(15 downto 0);
begin

uut:entity work.sdram_controller(sdram_controller_arc) port map(init,rd_req,wr_req,clk,address,
	clk_out,cke,cs_b,ras_b,cas_b,we_b,ba_0,ba_1,dqm_l,dqm_h,address_out,data_in,data_in_out);

clock_proc:process
begin
	clk <= '0'; wait for 5 ns;
	clk <= '1'; wait for 5 ns;
end process;

stimulus:process
begin
	init <= '0';
	wait for 20 ns;
	init <= '1';
	wait for 210 ns;
	rd_req <= '1';
	address <= "101010101010101011111111";
	wait for 50 ns;
	rd_req <= '0';
	wait;
end process;
end sdram_con_tb_arc;