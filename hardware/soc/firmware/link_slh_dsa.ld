ENTRY(_start)

MEMORY
{
    BOOT_RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
    WORK_RAM (rw)  : ORIGIN = 0x00010000, LENGTH = 108K
    VAULT_RAM (rw) : ORIGIN = 0x0002d000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
    } > BOOT_RAM

    .data : { *(.data*) *(.sdata*) } > BOOT_RAM
    __boot_image_end = .;

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > WORK_RAM

    ASSERT(__boot_image_end <= 0x00010000,
           "SLH firmware code/data exceeds initialized 64 KiB boot RAM")
    .vault (NOLOAD) : ALIGN(4) {
        __vault_start = .; *(.vault*) . = ALIGN(4); __vault_end = .;
    } > VAULT_RAM
    ASSERT(__bss_end <= 0x0002b000,
           "SLH work buffers overlap private service stack")
    ASSERT(__vault_end <= 0x0002e000,"Private vault overflow")

    ASSERT(_start == 0x00000000,
           "CPU reset vector must contain _start at address zero")
    /DISCARD/ : { *(.comment*) *(.riscv.attributes*) *(.note*) }
}
