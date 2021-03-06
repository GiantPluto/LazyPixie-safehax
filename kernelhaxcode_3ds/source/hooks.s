.arm
.cpu        mpcore

.section    .data.hooks, "aw", %progbits

.align      2
.type       kernelSvcHandlerHook, %function
.global     kernelSvcHandlerHook

// Note: compatible with both kext & original kernel handler
kernelSvcHandlerHook:
    push    {r0, r1}

    // Allow access to all SVCs
    mvn     r0, #1
    str     r0, [sp, #4+0]
    str     r0, [sp, #4+4]
    str     r0, [sp, #4+8]
    str     r0, [sp, #4+12]

    // "Allow debug" flag
    mov     r0, #1
    strb    r0, [sp, #4+16+1]

    pop     {r0, r1}
    ldr     pc, [pc, #(originalKernelSvcHandler - . - 8)]

.pool
.global     originalKernelSvcHandler
originalKernelSvcHandler:
    .word   0xCAFECAFE

.align      2
.type       kernelFirmlaunchHook1, %function
.global     kernelFirmlaunchHook1
kernelFirmlaunchHook1:
    add     lr, #4
    push    {r5, lr}

    push    {r0-r3, r12, lr}
    bl      kernCopySections
    pop     {r0-r3, r12, lr}

    // Get PXI regs base
    ldr     r2, [pc, #(kernelFirmlaunchHook1PxiRegsOffset - . - 8)]
    ldr     r1, [r5, r2]

    // Tell Process9 to terminate (pxi:mc 0x10000)
    mov     r0, #0
    bl      _pxiSendWord
    bl      _pxiTriggerSync9Irq
    mov     r0, #0x10000
    bl      _pxiSendWord

    // Ignore the reply
    bl      _pxiReceiveWord
    bl      _pxiReceiveWord
    bl      _pxiReceiveWord

    // Hooked firmlaunch PXI writes
    ldr     r0, =0x44836
    bl      _pxiSendWord

    pop     {r5, pc}

// r1 = reg base
_pxiTriggerSync9Irq:
    ldrb    r2, [r1, #3]
    orr     r2, #(1 << 6)
    strb    r2, [r1, #3]
    bx      lr

_pxiSendWord:
    ldrh    r2, [r1, #4]
    tst     r2, #(1 << 1)
    bne     _pxiSendWord
    str     r0, [r1, #8]
    bx      lr

_pxiReceiveWord:
    ldrh    r2, [r1, #4]
    tst     r2, #(1 << 8)
    bne     _pxiReceiveWord
    ldr     r0, [r1, #12]
    bx      lr

.pool

.global     kernelFirmlaunchHook1PxiRegsOffset
kernelFirmlaunchHook1PxiRegsOffset:
    .word 0xDADADADA

.type       kernelFirmlaunchHook2, %function
.global     kernelFirmlaunchHook2

kernelFirmlaunchHook2:
    // Copy hook to 0x1FFFFC00 which is the normal location, to avoid getting overwritten
    ldr     r4, =0x1FFFFC00
    mov     r0, r4
    adr     r1, _kernelFirmlaunchHook2Start
    adr     r2, kernelFirmlaunchHook2End
    sub     r2, r1
    bl      _memcpy32
    bx      r4
.pool

_kernelFirmlaunchHook2Start:
    ldr     r2, =0x1FFFFFFC
    mov     r1, #0
    str     r1, [r2]

    ldr     r0, =0x10163008 // PXI_SEND
    ldr     r1, =0x44846
    str     r1, [r0]        // Tell P9 we're ready

    // Wait for P9 to finish its job & chainload
    _waitForEpLoop:
        ldr     r0, [r2]
        cmp     r0, #0
        beq     _waitForEpLoop

    // Jump
    ldr     pc, =0x22000000

_memcpy32:
    add     r2, r0, r2
    _memcpy32_loop:
        ldr     r3, [r1], #4
        str     r3, [r0], #4
        cmp     r0, r2
        blo     _memcpy32_loop
    bx      lr
.pool
kernelFirmlaunchHook2End:

.global     kernelFirmlaunchHook2Size
kernelFirmlaunchHook2Size:
    .word kernelFirmlaunchHook2End - kernelFirmlaunchHook2
