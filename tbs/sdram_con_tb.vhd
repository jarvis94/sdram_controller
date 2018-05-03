library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_con_tb is
end sdram_con_tb;

architecture sdram_con_tb_arc of sdram_con_tb is

component sdram_controller is
	port (
		init,rd_req,wr_req,clk: in std_logic;
		address: in std_logic_vector(23 downto 0);
		cke,cs_b,ras_b,cas_b,we_b,ba_0,ba_1,dqm_l,dqm_h,ready,wait0: out std_logic;
		address_out: out std_logic_vector(12 downto 0);
		data_in: in std_logic_vector(15 downto 0);
		data_out: out std_logic_vector(15 downto 0);
		dbus: inout std_logic_vector(15 downto 0)
	);
end component;


signal init,rd_req,wr_req,clk,ready,wait0:  std_logic;
signal address: std_logic_vector(23 downto 0);
signal clk_out,cke,cs_b,ras_b,cas_b,we_b,ba_0,ba_1,dqm_l,dqm_h:  std_logic;
signal address_out: std_logic_vector(12 downto 0);
signal data_in:  std_logic_vector(15 downto 0);
signal data_out:  std_logic_vector(15 downto 0);
signal dbus:  std_logic_vector(15 downto 0);
constant clk_period: time := 20 ns;
begin

--uut:sdram_controller port map(init,rd_req,wr_req,clk,address,
--	cke,cs_b,ras_b,cas_b,we_b,ba_0,ba_1,dqm_l,dqm_h,ready,address_out,data_in,data_out,dbus);


uut: sdram_controller port map(
		init => init,
		rd_req => rd_req,
		wr_req => wr_req,
		clk => clk,
		address => address,
		cke => cke,
		cs_b => cs_b,
		ras_b => ras_b,
		cas_b => cas_b,
		we_b => we_b,
		ba_0 => ba_0,
		ba_1 => ba_1,
		dqm_l => dqm_l,
		dqm_h => dqm_h,
		ready => ready,
		wait0 => wait0, 
		address_out => address_out,
		data_in => data_in,
		data_out => data_out,
		dbus => dbus
	);

clock_proc:process
begin
	clk <= '0'; wait for clk_period/2;
	clk <= '1'; wait for clk_period/2;
end process;

stimulus:process
begin
	init <= '0';
	wait for 20 ns;
	init <= '1';
	wait for 210 ns;
	rd_req <= '1';
	address <= "101010101010101011111111";
	dbus <= x"000F";
	wait until ready = '1';
	wait for clk_period/2;
	--wait for 200 ns;
	dbus <= (others => 'Z');
	wr_req <= '1';
	address <= "111010101010101011111111";
	data_in <= x"1111";
	rd_req <= '0';
	wait until ready = '1';
	wait for clk_period/2;
	address <= "111010101010101011111111";
	data_in <= x"FFFF";
	rd_req <= '0';
	wait until ready = '1';
	wr_req <= '0';
	wait;
end process;
end sdram_con_tb_arc;