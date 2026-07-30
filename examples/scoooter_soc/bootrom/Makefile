SCOOOTER_CLANG ?= clang
SCOOOTER_LLD ?= ld.lld
LLVM_OBJCOPY ?= llvm-objcopy

boot.hex: boot.S boot.ld
	$(SCOOOTER_CLANG) --target=riscv32-unknown-elf -march=rv32i -mabi=ilp32 -c boot.S -o boot.o
	$(SCOOOTER_LLD) -flavor gnu -m elf32lriscv -T boot.ld boot.o -o boot.elf
	$(LLVM_OBJCOPY) -O binary boot.elf boot.bin
	od -An -tx4 -w4 -v boot.bin | tr -d ' ' > boot.hex

.PHONY: clean
clean:
	rm -f boot.o boot.elf boot.bin boot.hex
