###
# DO NOT CHANGE
###
TOP_MODULE=mkBlueJ
TESTBENCH_MODULE=mkTestbench
IGNORE_MODULES=mkTestbench mkTestsMainTest
MAIN_MODULE=BlueJ
TESTBENCH_FILE=test/Testbench.bsv
TEST_DIR=$(CURDIR)/test

# Initialize
-include .bsv_tools
ifndef BSV_TOOLS
$(error BSV_TOOLS is not set (Check .bsv_tools or specify it through the command line))
endif
VIVADO_ADD_PARAMS := ''
CONSTRAINT_FILES := ''
EXTRA_BSV_LIBS:=
EXTRA_LIBRARIES:=
RUN_FLAGS:=

PROJECT_NAME=BlueJ

WAVES?=0

ifeq ($(RUN_TEST),)
RUN_TEST=TestTAP
endif

# Default flags
EXTRA_FLAGS=-D "RUN_TEST=$(RUN_TEST)" -D "TESTNAME=mk$(RUN_TEST)"
EXTRA_FLAGS+=-show-schedule -D "BSV_TIMESCALE=1ps/1ps" -keep-inlined-boundaries -aggressive-conditions

###
# User configuration
###

# Comment the following line if -O3 should be used during compilation
# Keep uncommented for short running simulations
CXX_NO_OPT := 1

# Any additional files added during compilation
# For instance for BDPI or Verilog/VHDL files for simulation
# CPP_FILES += $(current_dir)/src/mem_sim.cpp
C_FILES += $(CURDIR)/src/bdpi/jtag_bdpi.cc

# Custom defines added to compile steps
# EXTRA_FLAGS+=-D "BENCHMARK=1"

# Flags added to simulator execution
ifeq ($(SIM_TYPE), VERILOG)

ifeq ($(WAVES), 1)
	RUN_FLAGS+=+bscvcd
endif

EXTRA_FLAGS+=-D "BSV_ASSIGNMENT_DELAY=\#1"
else
ifeq ($(WAVES), 1)
	RUN_FLAGS+=-V dump.vcd
endif
endif

# Add additional parameters for IP-XACT generation. Passed directly to Vivado.
# Any valid TCL during packaging is allowed
# Typically used to fix automatic inference for e.g. clock assignments
# VIVADO_ADD_PARAMS += 'ipx::associate_bus_interfaces -busif M_AXI -clock sconfig_axi_aclk [ipx::current_core]'

# Add custom constraint files, Syntax: Filename,Load Order
# CONSTRAINT_FILES += "$(CURDIR)/constraints/custom.xdc,LATE"

VERILOG_SIM:=iverilog
VERILOG_INC:=$(CURDIR)/src/rtl/lib:$(CURDIR)/src/rtl/lib/unisim

# custom TCL flow
PART=xcku3p-ffvb676-2-e
CONSTRAINTS=$(CURDIR)/src/bluej_simple.xdc
SCRIPT=$(CURDIR)/src/synth.tcl

# Do not change: Load libraries such as BlueAXI or BlueLib
ifneq ("$(wildcard $(CURDIR)/libraries/*/*.mk)", "")
include $(CURDIR)/libraries/*/*.mk
endif


# Do not change: Include base makefile
include $(BSV_TOOLS)/scripts/rules.mk
