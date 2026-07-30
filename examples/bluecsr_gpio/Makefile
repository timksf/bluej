BSC ?= bsc

BUILD_DIR := build
SIM_DIR := sim
TOP := mkTestGPIO
EXE := $(BUILD_DIR)/$(TOP)
BSV_PATH := src:test:../../dep/bluecsr/src:+
SOURCES := $(wildcard src/*.bsv) $(wildcard test/*.bsv)

.PHONY: all sim clean

all: $(EXE)

$(BUILD_DIR)/$(TOP).ba: $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(BSC) -p $(BSV_PATH) -bdir $(BUILD_DIR) -sim -u -g $(TOP) test/TestGPIO.bsv

$(EXE): $(BUILD_DIR)/$(TOP).ba
	@mkdir -p $(SIM_DIR)
	$(BSC) -p $(BSV_PATH) -bdir $(BUILD_DIR) -simdir $(SIM_DIR) -sim -e $(TOP) -o $@

sim: $(EXE)
	./$(EXE)

clean:
	rm -rf $(BUILD_DIR) $(SIM_DIR)
