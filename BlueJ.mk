# BSVTools library integration for BlueJ.
BLUEJ_MAKE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
BLUEJ_ROOT := $(abspath $(BLUEJ_MAKE_DIR))
BLUEJ_SRC := $(BLUEJ_ROOT)/hdl/src

EXTRA_BSV_LIBS += $(BLUEJ_SRC)
C_FILES += $(BLUEJ_SRC)/bdpi/jtag_bdpi.cc
VERILOGDIR_EXTRAS += $(BLUEJ_SRC)/rtl

$(info Adding BlueJ from $(BLUEJ_SRC))
