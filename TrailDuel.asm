; =============================================================================
;   TrailDuel.asm - cartridge entry point and main loop
; =============================================================================
;   TrailDuel for the AC6502 ACE with a 6502-PICOVDP on BIOS 2.x, as a 128 KB
;   Flash Cart. Everything fits the cart's fixed 8 KB.
; =============================================================================

.setcpu "65C02"

.include "6502-VDP.inc"
.include "src/zeropage.inc"
.include "src/arena.asm"
.include "src/vdp.asm"
.include "src/font.asm"
.include "src/rng.asm"
.include "src/input.asm"
.include "src/sound.asm"
.include "src/link.asm"
.include "src/game.asm"

.segment "CART"

CartReset:
  ldx #$FF
  txs                              ; KernalInit doesn't reset the stack
  jsr KernalInit
  jsr KernalVersion
  cmp #2
  bcc @wrongMachine
  lda HW_PRESENT
  and #HW_VID                      ; set on BIOS 2.x only for a PICOVDP
  bne @ready
@wrongMachine:
  ldx #0
@message:
  lda NeedsMsg,x
  beq @halt
  phx
  jsr Chrout
  plx
  inx
  bra @message
@halt:
  bra @halt

@ready:
  stz FRAME_COUNT
  stz FRAME_COUNT+1
  lda #0
  jsr SetIOMode                    ; the keyboard, for Chrin
  jsr SoundInit                    ; our interrupt handler, and the sound timer
  jsr LinkInit                     ; the serial port quiet
  cli                              ; KernalInit leaves interrupts off, and the
                                   ; keyboard is read in them
  jsr VideoInit
  jsr NewGame

; A tick every TICK_FRAMES pictures, or every picture while a linked round
; waits on the other machine; serial bytes are taken every picture.
MainLoop:
  jsr PollInput
  jsr PollInputP2
  jsr Tick
@frame:
  lda #1
  jsr WaitFrames
  inc FRAME_COUNT
  bne @counted
  inc FRAME_COUNT+1
@counted:
  jsr LinkPoll
  dec FRAMES_LEFT
  bne @frame
  jmp MainLoop

NeedsMsg:
  .byte "NEEDS BIOS 2 AND A 6502-PICOVDP", 0

; Through the RAM vectors KernalInit points at the Kernal's own handlers,
; which read the keyboard.
IrqTrampoline:
  jmp (IRQ_PTR)

NmiTrampoline:
  jmp (NMI_PTR)

.segment "VECTORS"
.word NmiTrampoline
.word CartReset
.word IrqTrampoline
