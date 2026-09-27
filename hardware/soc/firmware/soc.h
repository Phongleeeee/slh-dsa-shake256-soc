#ifndef PICORV32_SLH_SOC_H
#define PICORV32_SLH_SOC_H

#include <stdint.h>
#include "../../drivers/slh_dsa_shake_accel.h"

#define SOC_RAM_BYTES       0x00030000u
#define SOC_SHAKE_BASE      0x00030000u
#define SOC_UART_BASE       0x00031000u
#define SOC_TIMER_BASE      0x00032000u
#define SOC_DMA_BASE        0x00033000u

#define SOC_UART_DATA       0x00u
#define SOC_UART_STATUS     0x04u
#define SOC_UART_BAUD_DIV   0x08u
#define SOC_UART_IRQ_ENABLE 0x0cu
#define SOC_UART_IRQ_STATUS 0x10u

#define SOC_TIMER_MTIME_LO  0x00u
#define SOC_TIMER_MTIME_HI  0x04u
#define SOC_TIMER_CMP_LO    0x08u
#define SOC_TIMER_CMP_HI    0x0cu
#define SOC_TIMER_CONTROL   0x10u
#define SOC_GPIO_OUT        0x14u
#define SOC_TIMER_STATUS    0x18u

#define SOC_DMA_CONTROL     0x00u
#define SOC_DMA_STATUS      0x04u
#define SOC_DMA_SRC         0x08u
#define SOC_DMA_DST         0x0cu
#define SOC_DMA_LENGTH      0x10u
#define SOC_DMA_CONFIG      0x14u
#define SOC_DMA_FAULT       0x18u
#define SOC_DMA_PT_INDEX    0x20u
#define SOC_DMA_PT_VPN      0x24u
#define SOC_DMA_PT_PPN      0x28u
#define SOC_DMA_PT_FLAGS    0x2cu
#define SOC_DMA_TLB_CTRL    0x30u

#define SOC_DMA_BUSY        (1u << 0)
#define SOC_DMA_DONE        (1u << 1)
#define SOC_DMA_ERROR       (1u << 2)
#define SOC_DMA_START       (1u << 0)
#define SOC_DMA_CLEAR       (1u << 1)
#define SOC_DMA_TYPE_M2M    0u
#define SOC_DMA_MODE_BURST  0u
#define SOC_DMA_CONFIG_WORD(type, mode, burst_words) \
    ((((uint32_t)(burst_words)) << 8) | (((uint32_t)(mode)) << 2) | (type))

static inline volatile uint32_t *soc_mmio(uint32_t address)
{
    return (volatile uint32_t *)(uintptr_t)address;
}

static inline void soc_uart_putc(char c)
{
    volatile uint32_t *uart = soc_mmio(SOC_UART_BASE);
    while ((uart[SOC_UART_STATUS >> 2] & 1u) == 0u) {}
    uart[SOC_UART_DATA >> 2] = (uint8_t)c;
}

static inline void soc_gpio_write(uint32_t value)
{
    soc_mmio(SOC_TIMER_BASE)[SOC_GPIO_OUT >> 2] = value;
}

#endif
