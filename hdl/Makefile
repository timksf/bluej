NAME=Testbench
MOD=$(NAME) #only change if top module name is different from file name

dirs:
	mkdir -p build
	mkdir -p build/sim

mk$(NAME).ba: $(NAME).bsv dirs
	bsc -bdir build -aggressive-conditions -u -sim -g mk$(MOD) $<

$(NAME)_out: mk$(NAME).ba 
	bsc -bdir build -simdir build/sim -show-schedule -u -sim -e mk$(MOD) -o $@

sim: $(NAME)_out
	./$(NAME)_out -V dump.vcd

clean: 
	rm -rf build build/sim
	rm -f *.ba *.bo *.o *.so *.cxx *.h $(NAME)_out *.sched 