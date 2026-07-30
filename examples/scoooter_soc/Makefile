# SPDX-License-Identifier: MIT

TOP_MODULE := mkScoooterSystem
MAIN_MODULE := ScoooterSystem
PROJECT_NAME := ScoooterCmodA7

TESTBENCH_MODULE := mkTestScoooterSoCOOCDTB
TESTBENCH_FILE := $(CURDIR)/test/TestScoooterSoCOOCDTB.bsv
TEST_DIR := $(CURDIR)/test
OUTFILE := scoooter_soc_oocd

BSV_TOOLS ?= $(abspath ../../dep/BSVTools)
SCOOOTER_CORE_DIR := $(abspath ../SCOoOTER/core/src)
SCOOOTER_CORE_DIRS := $(shell find $(SCOOOTER_CORE_DIR) -type d -print)

EXTRA_BSV_LIBS += $(CURDIR)/src
EXTRA_BSV_LIBS += $(abspath ../../hdl/src)
EXTRA_BSV_LIBS += $(abspath ../../hdl/test)
EXTRA_BSV_LIBS += $(abspath ../bluefabric/src)
EXTRA_BSV_LIBS += $(abspath ../bluefabric/src/common)
EXTRA_BSV_LIBS += $(abspath ../bluefabric/src/soc)
EXTRA_BSV_LIBS += $(abspath ../bluefabric/src/ahb)
EXTRA_BSV_LIBS += $(abspath ../bluefabric/src/apb)
EXTRA_BSV_LIBS += $(abspath ../bluefabric/src/axi)
EXTRA_BSV_LIBS += $(abspath ../bluefabric/src/axis)
EXTRA_BSV_LIBS += $(abspath ../bluegpio/src)
EXTRA_BSV_LIBS += $(abspath ../blueuart/hdl/src)
EXTRA_BSV_LIBS += $(abspath ../../dep/bluecsr/src)
EXTRA_BSV_LIBS += $(abspath ../../dep/BlueAXI/src)
EXTRA_BSV_LIBS += $(abspath ../../dep/BlueLib/src)
EXTRA_BSV_LIBS += $(SCOOOTER_CORE_DIRS)

EXTRA_FLAGS += -aggressive-conditions
EXTRA_FLAGS += -keep-inlined-boundaries
EXTRA_FLAGS += -show-schedule
EXTRA_FLAGS += -D "BSV_TIMESCALE=1ns/1ps"
EXTRA_FLAGS += -D "SCOOOTER_NUM_THREADS=1"
EXTRA_FLAGS += -D "SCOOOTER_NUM_CPU=1"

C_FILES += $(abspath ../../hdl/src/bdpi/jtag_bdpi.cc)

VERILOGDIR_EXTRAS += $(CURDIR)/rtl
PART := xc7a35tcpg236-1
SYNTH_ONLY_SCRIPT := $(CURDIR)/synth_only.tcl
BITSTREAM_SCRIPT := $(CURDIR)/synth.tcl
ACTIVE_SCRIPT ?= $(SYNTH_ONLY_SCRIPT)
SCRIPT := $(ACTIVE_SCRIPT)
BITSTREAM_FILE = $(BUILDDIR)/$(PROJECT_NAME)/$(PROJECT_NAME).bit
FLASH_IMAGE = $(BUILDDIR)/$(PROJECT_NAME)/$(PROJECT_NAME).mcs
CFGMEM_PART ?= mx25l3273f-spi-x1_x2_x4

CPU_CONFIG_SOURCE := $(CURDIR)/src/ScoooterCpu.bsv
CONFIG_ADAPTER := $(CURDIR)/src/Config.bsv

$(CONFIG_ADAPTER): $(CPU_CONFIG_SOURCE)
	touch $@

compile_top: $(CONFIG_ADAPTER)

include $(BSV_TOOLS)/scripts/rules.mk

.PHONY: bootrom oocd-sim synth bitstream program flash-image program-flash

bootrom:
	$(MAKE) -C bootrom

compile compile_top: bootrom

oocd-sim: sim
	cd $(BUILDDIR) && ./$(OUTFILE)

synth: bootrom
	$(MAKE) SIM_TYPE=VERILOG ACTIVE_SCRIPT=$(SYNTH_ONLY_SCRIPT) vivado_tcl

bitstream: bootrom
	$(MAKE) SIM_TYPE=VERILOG ACTIVE_SCRIPT=$(BITSTREAM_SCRIPT) vivado_tcl

program:
	vivado -mode batch -source program_bitstream.tcl \
		-tclargs $(BITSTREAM_FILE)

flash-image:
	vivado -mode batch -source create_flash_image.tcl \
		-tclargs $(BITSTREAM_FILE) $(FLASH_IMAGE)

program-flash: flash-image
	vivado -mode batch -source program_flash.tcl \
		-tclargs $(FLASH_IMAGE) $(BITSTREAM_FILE) $(CFGMEM_PART)
