NAME=Testbench
MOD=$(NAME) #only change if top module name is different from file name

SOURCES_BDPI:=$(wildcard bdpi/*.cc)
OBJ_BDPI:=$(wildcard bdpi/*.o)

BSC_DIRS+=-bdir build -simdir build/sim
BSC_FLAGS+=-show-schedule -elab -aggressive-conditions -no-warn-action-shadowing -keep-inlined-boundaries -suppress-warnings G0010
# -remove-dollar

dirs:
	mkdir -p build
	mkdir -p build/sim
	mkdir -p build/verilog

mk$(NAME).ba: $(NAME).bsv dirs
	bsc -bdir build $(BSC_FLAGS) -u -sim -g mk$(MOD) $<

$(NAME)_out: mk$(NAME).ba
	make -C bdpi
	bsc $(BSC_DIRS) -show-schedule -u -sim -e mk$(MOD) -o $@ $(OBJ_BDPI)

sim: $(NAME)_out
	./$(NAME)_out 

vcd: $(NAME)_out
	./$(NAME)_out -V dump.vcd

$(NAME)_outv: $(NAME).bsv dirs
	make -C bdpi
	bsc $(BSC_DIRS) -vdir build/verilog -show-schedule -vsearch rtl:+ -verilog $(BSC_FLAGS) -u -g mk$(MOD) $<
	bsc $(BSC_DIRS) -vdir build/verilog -vsim iverilog -vsearch rtl:+ -e mk$(MOD) -o $@ $(OBJ_BDPI)

simv: $(NAME)_outv
	./$(NAME)_outv +bscvcd

clean: 
	make -C bdpi clean
	rm -rf build build/sim
	rm -rf obj_dir*/
	rm -f *_outv *_out
	rm -f *.ba *.bo *.o *.so *.cxx *.h $(NAME)_out $(NAME)_outv *.sched