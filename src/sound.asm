; =============================================================================
;   sound.asm - sound effects on the SID, and the interrupt handler
; =============================================================================
;   The sounds of Trap, TrailDuel's version in DuelTastic, rebuilt for the
;   SID's three voices (tools/build-sound.mjs holds them): a blip as a person
;   turns, the menu's select, a chord as a round starts, the crash, and the
;   win and draw stings. An effect takes the voice it prefers, or another, and
;   a louder one can take a voice from a quieter one. There's no music.
;
;   A timer interrupt (the VIA's timer 2, on the GPIO card) runs SoundTick 60
;   times a second from bank 0, so the sound keeps time however busy the game
;   is. The game only leaves requests in a queue. This fixed-bank half holds
;   those calls and the interrupt handler.
; =============================================================================

.segment "CART"

TIMER_FRAME   = 16600              ; a 60th of a second, less the time to restart it

; SoundInit - at start-up, with interrupts still off: silence, take over the
; interrupt, and start the timer if there's a sound card and a GPIO card.
SoundInit:
  ldx #S_VARS_END - S_REG - 1
@clear:
  stz S_REG,x
  dex
  bpl @clear
  lda IRQ_PTR
  sta OLD_IRQ
  lda IRQ_PTR+1
  sta OLD_IRQ+1
  lda #<SysIrq
  sta IRQ_PTR
  lda #>SysIrq
  sta IRQ_PTR+1
  lda HW_PRESENT
  and #HW_SID
  beq @done
  ldx #$18
@sid:
  stz SID_V1_FREQ_LO,x
  dex
  bpl @sid
  lda HW_PRESENT
  and #HW_GPIO
  beq @done
  lda #1
  sta S_ON
  lda GPIO_ACR
  and #%11011111                   ; timer 2 counts clock cycles
  sta GPIO_ACR
  lda #GPIO_IER_SET | GPIO_INT_T2
  sta GPIO_IER
  lda #<TIMER_FRAME
  sta GPIO_T2CL
  lda #>TIMER_FRAME
  sta GPIO_T2CH
@done:
  rts

; SysIrq - the machine's interrupt handler from now on, as 6502-HexFleet's: serial
; bytes while linked, the keyboard as the Kernal handles it, and the sound
; timer. While linked, a received byte goes into the link's ring, which also
; keeps it out of the keyboard buffer. The sound runs with interrupts back on,
; so a long tick can't make the serial port lose a byte. A BRK is the Kernal's.
SysIrq:
  pha
  phx
  phy
  tsx
  lda $104,x                       ; the saved flags
  and #$10
  bne @brk
  lda LINK_ON
  beq @keys
  lda SC_STATUS
  and #SC_STATUS_RDRF
  beq @keys
  lda SC_DATA
  ldx RX_HEAD
  sta RX_BUF,x
  inc RX_HEAD
@keys:
  lda HW_PRESENT
  and #HW_GPIO
  beq @exit
  lda GPIO_IFR
  and #GPIO_INT_CB1
  beq @ps2
  lda GPIO_PORTB                   ; the matrix keyboard
  jsr WriteBuffer
  bra @timer
@ps2:
  lda GPIO_IFR
  and #GPIO_INT_CA1
  beq @timer
  lda GPIO_PORTA                   ; a PS/2 keyboard
  jsr WriteBuffer
@timer:
  lda S_ON
  beq @exit
  lda GPIO_IFR
  and #GPIO_INT_T2
  beq @exit
  lda #<TIMER_FRAME
  sta GPIO_T2CL
  lda #>TIMER_FRAME
  sta GPIO_T2CH                    ; also clears the flag
  lda S_BUSY
  bne @exit                        ; the last tick is still running
  inc S_BUSY
  cli
  jsr SoundTick
  sei
  stz S_BUSY
@exit:
  ply
  plx
  pla
  rti
@brk:
  ply
  plx
  pla
  jmp (OLD_IRQ)

; --- What the game calls. These keep X and Y. ---

; SoundRequest - leave request A for the next tick.
SoundRequest:
  phx
  ldx S_ON
  beq @done
  ldx S_QH
  sta S_Q,x
  inx
  cpx #8
  bcc @stored
  ldx #0
@stored:
  stx S_QH
@done:
  plx
  rts

.macro SOUND name, effect
name:
  lda #effect
  jmp SoundRequest
.endmacro

SOUND SndTurn, SFX_TURN
SOUND SndSelect, SFX_SELECT
SOUND SndGo, SFX_GO
SOUND SndCrash, SFX_CRASH
SOUND SndWin, SFX_WIN
SOUND SndDraw, SFX_DRAW

; =============================================================================
;   The driver, in bank 0, which TrailDuel never switches away from. Everything
;   here runs in the interrupt, so it keeps to its own memory.
; =============================================================================

.segment "BANK00"

.include "sounddata.inc"

VoiceBase:
  .byte 0, 7, 14
VoiceBit:
  .byte 1, 2, 4

SoundTick:
  inc S_TICKS
  bne @counted
  inc S_TICKS+1
@counted:
  jsr TakeRequests
  ldx #2
@effect:
  jsr EffectTick
  dex
  bpl @effect
  jsr FilterTick
  ; --- everything to the chip at once ---
  ldx #2
@retrigger:
  lda S_PEND,x
  beq @noRetrigger
  stz S_PEND,x
  inc S_RTG,x
  ldy VoiceBase,x
  lda S_REG+4,y
  and #$FE
  sta SID_V1_FREQ_LO+4,y           ; let go first, so the note starts again
@noRetrigger:
  dex
  bpl @retrigger
  ldx #$18
@copy:
  lda S_REG,x
  sta SID_V1_FREQ_LO,x
  dex
  bpl @copy
  rts

TakeRequests:
  ldx S_QT
  cpx S_QH
  beq @done
  lda S_Q,x
  inx
  cpx #8
  bcc @stored
  ldx #0
@stored:
  stx S_QT
  jsr EffectStart
  bra TakeRequests
@done:
  rts

; CanTake - carry set if an effect of priority S_A may have voice X.
CanTake:
  lda SF_ID,x
  beq @yes
  lda S_A
  cmp SF_P,x                       ; carry set if it matters as much or more
  rts
@yes:
  sec
  rts

; EffectStart - effect A on the voice it prefers, or its other choice, then
; the effect that goes with it on another voice. Keeps X.
EffectStart:
  phx
  tay
  lda FxPrio,y
  sta S_A
  ldx FxVoice,y
  jsr CanTake
  bcs @take
  lda FxOther,y
  beq @done
  dec a
  tax
  jsr CanTake
  bcc @done
@take:
  tya
  sta SF_ID,x
  lda S_A
  sta SF_P,x
  lda FxLo,y
  sta SF_PL,x
  lda FxHi,y
  sta SF_PH,x
  stz SF_LEFT,x
  lda FxPair,y
  beq @done
  jsr EffectStart
@done:
  plx
  rts

; EffectEnd - voice X lets go.
EffectEnd:
  lda SF_ID,x
  beq @done
  stz SF_ID,x
  stz SF_FIL,x
  ldy VoiceBase,x
  lda S_REG+4,y
  and #$FE
  sta S_REG+4,y
@done:
  rts

; EffectTick - voice X's effect, one frame on.
EffectTick:
  lda SF_ID,x
  beq @done
  lda SF_LEFT,x
  bne @run
  jsr NextStep
  lda SF_ID,x
  beq @done
@run:
  dec SF_LEFT,x
  lda SF_FLG,x
  and #$0F
  beq @write
  jsr SlidePitch
@write:
  ldy VoiceBase,x
  lda SF_FL,x
  sta S_REG,y
  lda SF_FH,x
  sta S_REG+1,y
@done:
  rts

; NextStep - load voice X's next step, or end the effect. A step is 12 bytes:
; frames, control, AD, SR, pitch, target pitch, flags, pulse width, cutoff and
; how fast it closes.
NextStep:
  lda SF_PL,x
  sta S_P
  lda SF_PH,x
  sta S_P+1
  lda (S_P)
  bne @step
  jmp EffectEnd
@step:
  sta SF_LEFT,x
  phx
  lda VoiceBase,x
  tax
  ldy #1
  lda (S_P),y
  sta S_REG+4,x
  iny
  lda (S_P),y
  sta S_REG+5,x
  iny
  lda (S_P),y
  sta S_REG+6,x
  ldy #9
  lda (S_P),y
  sta S_REG+3,x
  stz S_REG+2,x
  plx
  ldy #8
  lda (S_P),y
  sta SF_FLG,x
  bmi @kept                        ; carries on from the last pitch
  ldy #4
  lda (S_P),y
  sta SF_FL,x
  iny
  lda (S_P),y
  sta SF_FH,x
  iny
  lda (S_P),y
  sta SF_TL,x
  iny
  lda (S_P),y
  sta SF_TH,x
@kept:
  ldy #10
  lda (S_P),y
  beq @noFilter
  sta S_FXC
  iny
  lda (S_P),y
  sta S_FXK
  lda #1
@noFilter:
  sta SF_FIL,x
  lda SF_FLG,x
  and #$10
  beq @noRetrigger
  lda #1
  sta S_PEND,x
@noRetrigger:
  lda S_P
  clc
  adc #12
  sta SF_PL,x
  lda S_P+1
  adc #0
  sta SF_PH,x
  rts

; SlidePitch - voice X's pitch a share of the way to its target.
SlidePitch:
  lda SF_TL,x
  sec
  sbc SF_FL,x
  sta S_B
  lda SF_TH,x
  sbc SF_FH,x
  sta S_C
  lda SF_FLG,x                     ; shifted right by the slide's amount
  and #$0F
  tay
@shift:
  lda S_C
  cmp #$80
  ror S_C
  ror S_B
  dey
  bne @shift
  lda S_B
  ora S_C
  beq @arrive
  lda SF_FL,x
  clc
  adc S_B
  sta SF_FL,x
  lda SF_FH,x
  adc S_C
  sta SF_FH,x
  rts
@arrive:
  lda SF_TL,x
  sta SF_FL,x
  lda SF_TH,x
  sta SF_FH,x
  rts

; FilterTick - the voices whose effects ask for it go through the low-pass
; filter, its cutoff closing as the effect goes on; the rest go straight out.
FilterTick:
  stz S_C
  ldx #2
@voice:
  lda SF_ID,x
  beq @next
  lda SF_FIL,x
  beq @next
  lda VoiceBit,x
  ora S_C
  sta S_C
@next:
  dex
  bpl @voice
  lda S_C
  beq @route
  lda S_FXC
  sta S_REG+$16
  stz S_REG+$15
  ldx S_FXK
  beq @route
@close:
  lsr a
  dex
  bne @close
  inc a
  eor #$FF
  sec
  adc S_FXC
  cmp #20
  bcs @closed
  lda #20
@closed:
  sta S_FXC
@route:
  lda S_C
  ora #$20                         ; a little resonance
  sta S_REG+$17
  lda #SID_FILT_LP | 15
  sta S_REG+$18
  rts
