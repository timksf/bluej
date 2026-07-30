ENTRY(_start)

SECTIONS {
    . = 0;
    .text : { *(.text.init) *(.text*) }
}
