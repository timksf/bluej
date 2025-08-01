NAME=Testbench
MOD=$(NAME) #only change if top module name is different from file name

BSC_FLAGS+=-aggressive-conditions -no-warn-action-shadowing

# -remove-dollar

dirs:
	mkdir -p build
	mkdir -p build/sim

mk$(NAME).ba: $(NAME).bsv dirs
	bsc -bdir build $(BSC_FLAGS) -u -sim -g mk$(MOD) $<

$(NAME)_out: mk$(NAME).ba 
	bsc -bdir build -simdir build/sim -show-schedule -u -sim -e mk$(MOD) -o $@

sim: $(NAME)_out
	./$(NAME)_out -V dump.vcd

$(NAME)_outv: 
	bsc -vsim iverilog -u -elab -verilog -vsearch rtl -bdir build $(BSC_FLAGS) -o $@

simv: $(NAME)_outv
	./$(NAME)_out +bscvcd dump.vcd

clean: 
	rm -rf build build/sim
	rm -f *.ba *.bo *.o *.so *.cxx *.h $(NAME)_out *.sched 