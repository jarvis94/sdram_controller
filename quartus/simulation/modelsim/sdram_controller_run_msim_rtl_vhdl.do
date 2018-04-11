transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vcom -93 -work work {/home/vineesh/Desktop/705_project/sdram_controller_git/rtl/sdram_controller.vhd}

vcom -93 -work work {/home/vineesh/Desktop/705_project/sdram_controller_git/quartus/../tbs/sdram_con_tb.vhd}

vsim -t 1ps -L altera -L lpm -L sgate -L altera_mf -L altera_lnsim -L cycloneive -L rtl_work -L work -voptargs="+acc"  sdram_con_tb

add wave *
add wave -position insertpoint  \
sim:/sdram_con_tb/uut/*

view structure
view signals
run 300 us
