"""Generate the dependency-free RV32I boot/self-test image for the SoC.

The checked-in source tree intentionally does not require a RISC-V compiler for
the first board test.  This tiny encoder emits only the instructions used by
the boot probe.  The production C firmware can later replace this image.
"""

from pathlib import Path


class RV32:
    def __init__(self):
        self.words = []
        self.labels = {}
        self.fixups = []

    @property
    def pc(self):
        return 4 * len(self.words)

    def emit(self, word):
        self.words.append(word & 0xFFFFFFFF)

    def label(self, name):
        if name in self.labels:
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = self.pc

    @staticmethod
    def _i(opcode, funct3, rd, rs1, imm):
        return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    def lui(self, rd, imm20):
        self.emit(((imm20 & 0xFFFFF) << 12) | (rd << 7) | 0x37)

    def addi(self, rd, rs1, imm):
        self.emit(self._i(0x13, 0, rd, rs1, imm))

    def andi(self, rd, rs1, imm):
        self.emit(self._i(0x13, 7, rd, rs1, imm))

    def lw(self, rd, rs1, imm):
        self.emit(self._i(0x03, 2, rd, rs1, imm))

    def sw(self, rs2, rs1, imm):
        u = imm & 0xFFF
        self.emit(((u >> 5) << 25) | (rs2 << 20) | (rs1 << 15) |
                  (2 << 12) | ((u & 0x1F) << 7) | 0x23)

    def branch(self, funct3, rs1, rs2, label):
        self.fixups.append((len(self.words), "b", label, funct3, rs1, rs2))
        self.emit(0)

    def beq(self, rs1, rs2, label):
        self.branch(0, rs1, rs2, label)

    def bne(self, rs1, rs2, label):
        self.branch(1, rs1, rs2, label)

    def jal(self, rd, label):
        self.fixups.append((len(self.words), "j", label, rd, 0, 0))
        self.emit(0)

    def li(self, rd, value):
        value &= 0xFFFFFFFF
        signed = value if value < 0x80000000 else value - 0x100000000
        if -2048 <= signed <= 2047:
            self.addi(rd, 0, signed)
            return
        upper = (value + 0x800) >> 12
        lower = (value - (upper << 12)) & 0xFFFFFFFF
        if lower & 0x80000000:
            lower -= 0x100000000
        self.lui(rd, upper)
        self.addi(rd, rd, lower)

    def resolve(self):
        for index, kind, label, a, b, c in self.fixups:
            if label not in self.labels:
                raise ValueError(f"undefined label: {label}")
            pc = 4 * index
            offset = self.labels[label] - pc
            if kind == "b":
                if offset & 1 or not -4096 <= offset <= 4094:
                    raise ValueError(f"branch range: {label}")
                imm = offset & 0x1FFF
                word = (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25)
                word |= (c << 20) | (b << 15) | (a << 12)
                word |= (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63
            else:
                if offset & 1 or not -(1 << 20) <= offset < (1 << 20):
                    raise ValueError(f"jal range: {label}")
                imm = offset & 0x1FFFFF
                rd = a
                word = (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21)
                word |= (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12)
                word |= (rd << 7) | 0x6F
            self.words[index] = word & 0xFFFFFFFF


def write_uart(a, text, prefix):
    # x3 = UART base, x5/x6 temporaries.
    for n, ch in enumerate(text.encode("ascii")):
        wait = f"{prefix}_tx_{n}"
        a.label(wait)
        a.lw(5, 3, 4)
        a.andi(5, 5, 1)
        a.beq(5, 0, wait)
        a.li(5, ch)
        a.sw(5, 3, 0)


def emit_word_writes(a, base_reg, start_offset, words):
    for i, word in enumerate(words):
        a.li(5, word)
        a.sw(5, base_reg, start_offset + 4 * i)


def packed_words(first_byte, count):
    return [sum((first_byte + 4*i + j) << (8*j) for j in range(4))
            for i in range(count)]


def build():
    a = RV32()
    # x1 SHAKE=0x30000, x3 UART=0x31000, x4 TIMER/GPIO=0x32000,
    # x7 DMA=0x33000, x8/x9 are DMA source/destination buffers.
    a.li(1, 0x00030000)
    a.li(3, 0x00031000)
    a.li(4, 0x00032000)
    a.li(7, 0x00033000)
    a.li(8, 0x00010000)
    a.li(9, 0x00020000)
    a.li(5, 4)
    a.sw(5, 4, 0x14)
    write_uart(a, "SLH-SOC BOOT\r\n", "boot")

    a.lw(5, 1, 0xA8)
    a.li(6, 0x534C4802)
    a.bne(5, 6, "fail")
    a.lw(5, 1, 0xB4)
    a.li(6, 0x0001003F)
    a.bne(5, 6, "fail")

    # DMA-side IOMMU: identity-map source VPN 0x10 and destination VPN 0x20.
    for index, vpn in enumerate((0x10, 0x20)):
        a.li(5, index)
        a.sw(5, 7, 0x20)
        a.li(5, vpn)
        a.sw(5, 7, 0x24)
        a.sw(5, 7, 0x28)
        a.li(5, 7)  # valid + read + write; write commits the PTE.
        a.sw(5, 7, 0x2C)
    a.li(5, 1)
    a.sw(5, 7, 0x30)  # invalidate stale TLB entries

    dma_pattern = [0x13579BDF, 0x2468ACE0, 0x534C482D, 0x444D4121]
    emit_word_writes(a, 8, 0, dma_pattern)
    emit_word_writes(a, 9, 0, [0, 0, 0, 0])

    a.li(5, 2)
    a.sw(5, 7, 0x00)  # clear sticky DONE/FAULT
    a.li(5, 0x00010000)
    a.sw(5, 7, 0x08)
    a.li(5, 0x00020000)
    a.sw(5, 7, 0x0C)
    a.li(5, 16)
    a.sw(5, 7, 0x10)
    a.li(5, 0x400)  # M2M + burst mode + four words per burst
    a.sw(5, 7, 0x14)
    a.li(5, 1)
    a.sw(5, 7, 0x00)

    a.label("dma_poll")
    a.lw(5, 7, 0x04)
    a.andi(6, 5, 4)
    a.bne(6, 0, "fail")
    a.andi(6, 5, 2)
    a.beq(6, 0, "dma_poll")
    for i, word in enumerate(dma_pattern):
        a.lw(5, 9, 4*i)
        a.li(6, word)
        a.bne(5, 6, "fail")
    # Clear the original and require a second, reverse DMA transfer to
    # restore it. This tests RAM1 -> RAM2 -> RAM1 rather than a CPU copy.
    emit_word_writes(a, 8, 0, [0, 0, 0, 0])
    a.li(5, 2)
    a.sw(5, 7, 0x00)
    a.li(5, 0x00020000)
    a.sw(5, 7, 0x08)
    a.li(5, 0x00010000)
    a.sw(5, 7, 0x0C)
    a.li(5, 1)
    a.sw(5, 7, 0x00)
    a.label("dma_return_poll")
    a.lw(5, 7, 0x04)
    a.andi(6, 5, 4)
    a.bne(6, 0, "fail")
    a.andi(6, 5, 2)
    a.beq(6, 0, "dma_return_poll")
    for i, word in enumerate(dma_pattern):
        a.lw(5, 8, 4*i)
        a.li(6, word)
        a.bne(5, 6, "fail")
    a.li(5, 12)
    a.sw(5, 4, 0x14)
    write_uart(a, "DMA RAM1 -> RAM2 -> RAM1 PASS\r\n", "dma_pass")

    a.li(5, 8)
    a.sw(5, 4, 0x14)
    emit_word_writes(a, 1, 0x08, packed_words(0x00, 8))
    emit_word_writes(a, 1, 0x28, packed_words(0xA0, 8))
    emit_word_writes(a, 1, 0x48, packed_words(0x40, 8))
    a.li(5, 1)
    a.sw(5, 1, 0x00)

    a.label("poll")
    a.lw(5, 1, 0x04)
    a.andi(6, 5, 8)
    a.bne(6, 0, "fail")
    a.andi(6, 5, 2)
    a.beq(6, 0, "poll")

    expected = [0x4B6645DE, 0x5227F38E, 0x29490562, 0x8577DF7D,
                0xEE72B5BF, 0x9239982C, 0xBE16B146, 0x29EF9DDF]
    for i, word in enumerate(expected):
        a.lw(5, 1, 0x88 + 4*i)
        a.li(6, word)
        a.bne(5, 6, "fail")

    a.li(5, 8)  # ZEROIZE after consuming the digest.
    a.sw(5, 1, 0x00)
    a.li(5, 1)
    a.sw(5, 4, 0x14)
    write_uart(a, "SLH F PASS\r\n", "pass")
    a.label("done")
    a.jal(0, "done")

    a.label("fail")
    a.li(5, 2)
    a.sw(5, 4, 0x14)
    write_uart(a, "SLH F FAIL\r\n", "fail")
    a.label("failed_stop")
    a.jal(0, "failed_stop")

    a.resolve()
    return a.words


if __name__ == "__main__":
    out = Path(__file__).with_name("soc_boot.mem")
    words = build()
    out.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
    print(f"wrote {len(words)} RV32I words to {out}")
