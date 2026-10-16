# BSVTools library integration for BlueJ.
ifndef BLUEJ_MK_INCLUDED
BLUEJ_MK_INCLUDED := 1

BLUEJ_MAKE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
BLUEJ_ROOT := $(abspath $(BLUEJ_MAKE_DIR))
BLUEJ_SRC := $(BLUEJ_ROOT)/hdl/src
BLUEJ_DEPS := $(BLUEJ_ROOT)/dep

# Prefer the project's libraries, falling back to bundled dependencies.
BLUEJ_BLUEAXI_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueAXI.mk) $(BLUEJ_DEPS)/BlueAXI/BlueAXI.mk)
include $(BLUEJ_BLUEAXI_MK)
BLUEJ_BLUECSR_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueCSR.mk) $(BLUEJ_DEPS)/bluecsr/BlueCSR.mk)
include $(BLUEJ_BLUECSR_MK)
BLUEJ_BLUEXLNX_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueXilinx.mk $(BLUEJ_DEPS)/bluexlnx/BlueXilinx.mk))
ifneq ($(BLUEJ_BLUEXLNX_MK),)
include $(BLUEJ_BLUEXLNX_MK)
else
# Older BlueXilinx checkouts do not provide a make fragment.
EXTRA_BSV_LIBS += $(BLUEJ_DEPS)/bluexlnx/src
endif

EXTRA_BSV_LIBS += $(BLUEJ_SRC)
C_FILES += $(BLUEJ_SRC)/bdpi/jtag_bdpi.cc
VERILOGDIR_EXTRAS += $(BLUEJ_SRC)/rtl

$(info Adding BlueJ from $(BLUEJ_SRC))

endif
