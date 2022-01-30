#include "common_asm.inc"

pixel   .req r0
L       .req r1
R       .req r2
LMAP    .req r3
Lh      .req r4
Rh      .req r5
Lx      .req r6
Rx      .req r7
Ldx     .req r8
Rdx     .req r9
N       .req r10
tmp     .req r11
DIVLUT  .req r12
width   .req lr
h       .req N
Ry1     .req tmp
Ry2     .req Rh
Ly1     .req tmp
Ly2     .req Lh
pair    .req DIVLUT
indexA  .req Lh
indexB  .req DIVLUT

.shadow_lightmap:
  .word lightmap + 0x1A00

.global rasterizeS_asm
rasterizeS_asm:
    stmfd sp!, {r4-r11, lr}

    ldr LMAP, .shadow_lightmap

    mov Lh, #0                      // Lh = 0
    mov Rh, #0                      // Rh = 0

.loop:
    mov DIVLUT, #DIVLUT_ADDR

    .calc_left_start:
        cmp Lh, #0
          bne .calc_left_end        // if (Lh != 0) end with left
        ldr N, [L, #VERTEX_PREV]    // N = L->prev
        ldrsh Ly1, [L, #VERTEX_Y]   // Ly1 = L->v.y
        ldrsh Ly2, [N, #VERTEX_Y]   // Ly2 = N->v.y
        subs Lh, Ly2, Ly1           // Lh = Ly2 - Ly1
          blt .exit                 // if (Lh < 0) return
        ldrsh Lx, [L, #VERTEX_X]    // Lx = L->v.x
        cmp Lh, #1                  // if (Lh <= 1) skip Ldx calc
          ble .skip_left_dx
        lsl tmp, Lh, #1
        ldrh tmp, [DIVLUT, tmp]     // tmp = FixedInvU(Lh)

        ldrsh Ldx, [N, #VERTEX_X]
        sub Ldx, Lx
        mul Ldx, tmp                // Ldx = tmp * (N->v.x - Lx)

        .skip_left_dx:
        lsl Lx, #16                 // Lx <<= 16
        mov L, N                    // L = N
        b .calc_left_start
    .calc_left_end:

    .calc_right_start:
        cmp Rh, #0
          bne .calc_right_end       // if (Rh != 0) end with right
        ldr N, [R, #VERTEX_NEXT]    // N = R->next
        ldrsh Ry1, [R, #VERTEX_Y]   // Ry1 = R->v.y
        ldrsh Ry2, [N, #VERTEX_Y]   // Ry2 = N->v.y
        subs Rh, Ry2, Ry1           // Rh = Ry2 - Ry1
          blt .exit                 // if (Rh < 0) return
        ldrsh Rx, [R, #VERTEX_X]    // Rx = R->v.x
        cmp Rh, #1                  // if (Rh <= 1) skip Rdx calc
          ble .skip_right_dx
        lsl tmp, Rh, #1
        ldrh tmp, [DIVLUT, tmp]     // tmp = FixedInvU(Rh)

        ldrsh Rdx, [N, #VERTEX_X]
        sub Rdx, Rx
        mul Rdx, tmp                // Rdx = tmp * (N->v.x - Rx)

        .skip_right_dx:
        lsl Rx, #16                 // Rx <<= 16
        mov R, N                    // R = N
        b .calc_right_start
    .calc_right_end:

    cmp Rh, Lh              // if (Rh < Lh)
      movlt h, Rh           //      h = Rh
      movge h, Lh           // else h = Lh
    sub Lh, h               // Lh -= h
    sub Rh, h               // Rh -= h

  stmfd sp!, {Lh}

.scanline_start:
    asr tmp, Lx, #16                // x1 = (Lx >> 16)
    rsbs width, tmp, Rx, asr #16    // width = (Rx >> 16) - x1
      ble .scanline_end             // if (width <= 0) go next scanline

    add tmp, pixel, tmp             // tmp = pixel + x1

    // 2 bytes alignment (VRAM write requirement)
.align_left:
    tst tmp, #1
      beq .align_right

    ldrh pair, [tmp, #-1]!
    ldrb indexA, [LMAP, pair, lsr #8]
    and pair, #0xFF
    orr pair, indexA, lsl #8
    strh pair, [tmp], #2

    subs width, #1                  // width--
      beq .scanline_end

.align_right:
    tst width, #1
      beq .scanline
    subs width, #1              // width--
    ldrh pair, [tmp, width]
    and indexA, pair, #0xFF
    ldrb indexA, [LMAP, indexA]
    and pair, #0xFF00
    orr pair, indexA
    strh pair, [tmp, width]
      beq .scanline_end         // width == 0

.scanline:
    ldrh pair, [tmp]
    ldrb indexA, [LMAP, pair, lsr #8]
    and pair, #0xFF
    ldrb indexB, [LMAP, pair]
    orr pair, indexB, indexA, lsl #8
    strh pair, [tmp], #2

    subs width, #2
      bne .scanline

.scanline_end:
    add Lx, Ldx                     // Lx += Ldx
    add Rx, Rdx                     // Rx += Rdx
    add pixel, #FRAME_WIDTH         // pixel += FRAME_WIDTH (240)

    subs h, #1
      bne .scanline_start

    ldmfd sp!, {Lh}
    b .loop

.exit:
    ldmfd sp!, {r4-r11, pc}