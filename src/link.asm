; =============================================================================
;   link.asm - two machines, one duel, over the serial port
; =============================================================================
;   Each machine plays the whole round, both riders, from the same start, and
;   the two stay in step by trading each tick's turns: a rider's heading is
;   all one machine needs from the other. A machine takes its own player's
;   heading for tick t at tick t - LDELAY and sends it at once, so it's
;   usually there before the other machine needs it. A machine that doesn't
;   have the other's heading for a tick yet waits, and after half a second
;   its border goes red; A then gives up and goes back to the title.
;
;   Everything is sent as 11-byte frames: $A5, type, a byte, 6 bytes, a 2-byte
;   check, as in 6502-HexFleet's link. A frame that arrives damaged is dropped.
;     HELLO  finds the other machine: who it is, its color and speed, how far
;            along. Both play at the first seat's speed.
;     INPUT  a machine's headings for its last 8 ticks, a check of the round
;            as it stood LDELAY ticks back, and which pairing it's from.
;   Every INPUT carries 8 ticks, and two machines are never more than
;   2 x LDELAY (6 at most) apart, so a lost one costs nothing once a later one gets
;   through. A waiting machine sends its latest again every LINK_RESEND
;   frames. Received bytes go into a ring from the interrupt (SysIrq, in
;   sound.asm), so nothing is lost while the screen is being drawn.
; =============================================================================

.segment "CART"

FRAME_SYNC    = $A5
FRAME_SIZE    = 11
FR_HELLO      = 1
FR_INPUT      = 2
LINK_VERSION  = 2                  ; 2: HELLO carries the speed
; Ticks between taking a heading and using it (LDELAY), by speed: about 50 ms
; at each, the time a frame takes to cross and be read, with room to spare
LinkDelays:
  .byte 1, 2, 3
LINK_RESEND   = 3                  ; frames between tries while waiting
HELLO_RESEND  = 4                  ; ticks between tries while looking
WAIT_SHOW     = 30                 ; frames of waiting before the border goes red
POLL_BYTES    = 40                 ; bytes handled a frame at most
BAD_SYNC      = 1                  ; LINK_BAD
BAD_VERSION   = 2
BAD_NOSERIAL  = 3
RESULT_SYNC   = 4                  ; ROUND_RESULT: the machines disagreed

TxtLinking:    .byte "LINKING", 0
TxtWaitFor:    .byte "WAITING FOR THE", 0
TxtOtherCart:  .byte "OTHER CART", 0
TxtCancel:     .byte "A: CANCEL", 0
TxtBack:       .byte "A: BACK", 0
TxtNoSerial:   .byte "NO SERIAL CARD", 0
TxtWrongCart:  .byte "OTHER BUILD", 0

; --- Starting up ---

; LinkInit - at start-up: not linked, and the serial port quiet until a link
; starts. SoundInit has already put SysIrq (sound.asm) in charge of interrupts.
LinkInit:
  stz LINK_ON
  stz LINK_UP
  stz HAVE_OLD
  ; falls through

; SerialQuiet - no serial interrupts: another machine calling must not reach
; the keyboard buffer while this one isn't linked.
SerialQuiet:
  lda HW_PRESENT
  and #HW_SC
  beq @done
  lda SC_CMD
  ora #SC_CMD_RXIRQ_OFF
  sta SC_CMD
@done:
  rts

; --- Looking for the other machine ---

; EnterLink - A on LINK, or after a linked round: show the linking screen and
; start looking. A rematch keeps the link on, with the colors as picked.
EnterLink:
  jsr SndSelect
  lda #STATE_LINKING
  sta GAME_STATE
  stz LINK_UP
  stz LINK_BAD
  stz LINK_SHOWN
  stz HAVE_HELLO
  stz PEER_HAS
  lda #1
  sta LINK_T
  lda LINK_ON
  bne @look
  lda P1_COLOR_IDX                 ; the title's colors, to put back after
  sta TITLE_C1
  sta MY_COLOR
  lda P2_COLOR_IDX
  sta TITLE_C2
  lda SPEED
  sta TITLE_SPEED
  sta MY_SPEED
  lda HW_PRESENT
  and #HW_SC
  bne @card
  lda #BAD_NOSERIAL
  sta LINK_BAD
  jmp DrawLinkScreen
@card:
  sei
  stz RX_HEAD
  stz RX_TAIL
  jsr InitSC                       ; 8-N-1, 19200 baud, receive interrupt on
  cli
  stz PARSE_N
  lda #1
  sta LINK_ON
@look:
  jsr NewNonce
  jmp DrawLinkScreen

; LinkOff - back to a machine on its own, with the title's colors as they were.
LinkOff:
  lda LINK_ON
  beq @done
  stz LINK_ON
  stz LINK_UP
  stz HAVE_OLD
  jsr SerialQuiet
  lda TITLE_C1
  sta P1_COLOR_IDX
  lda TITLE_C2
  sta P2_COLOR_IDX
  lda TITLE_SPEED
  sta SPEED
  jsr ApplySelectedTrailColors
@done:
  lda #0
  jmp SetWaiting

NewNonce:
  lda FRAME_COUNT                  ; when this machine got here: the other
  eor RX_HEAD                      ; one almost certainly didn't at the same frame
  sta MY_NONCE
  lda FRAME_COUNT+1
  sta MY_NONCE+1
  rts

DrawLinkScreen:
  jsr ClearScreen
  jsr DrawBorder
  jsr InitHeadSprites
  lda LINK_BAD
  sta LINK_SHOWN
  bne @failed
  lda #72
  ldx #<TxtLinking
  ldy #>TxtLinking
  jsr CenterText
  lda #92
  ldx #<TxtWaitFor
  ldy #>TxtWaitFor
  jsr CenterText
  lda #102
  ldx #<TxtOtherCart
  ldy #>TxtOtherCart
  jsr CenterText
  lda #126
  ldx #<TxtCancel
  ldy #>TxtCancel
  jmp CenterText
@failed:
  ldx #<TxtNoSerial
  ldy #>TxtNoSerial
  cmp #BAD_VERSION
  bne @say
  ldx #<TxtWrongCart
  ldy #>TxtWrongCart
@say:
  lda #88
  jsr CenterText
  lda #110
  ldx #<TxtBack
  ldy #>TxtBack
  jmp CenterText

; TickLinking - a tick on the linking screen.
TickLinking:
  lda FIRE_EDGE
  beq @look
  jsr SndSelect
  jsr LinkOff
  jmp DrawTitleScreen
@look:
  lda LINK_BAD
  beq @fine
  cmp LINK_SHOWN                   ; the other machine turned out to be another
  beq @done                        ; build: say so, once
  jmp DrawLinkScreen
@fine:
  lda HAVE_HELLO
  beq @resend
  lda PEER_HAS
  bne LinkGo
@resend:
  dec LINK_T
  bne @done
  lda #HELLO_RESEND
  sta LINK_T
  jsr SendHello
  lda HAVE_OLD                     ; the other machine may still be waiting
  beq @done                        ; on our last turns of the round before
  jmp SendOld
@done:
  rts

; LinkGo - both machines know each other: the lower number takes the first
; seat, the left, and each seat its machine's color, the second moved on one
; if they're the same. Then the round starts.
LinkGo:
  lda #1
  sta LINK_UP
  stz HAVE_OLD
  ldx #1
  lda MY_NONCE
  cmp PEER_NONCE
  lda MY_NONCE+1
  sbc PEER_NONCE+1
  bcs @seat
  ldx #0
@seat:
  stx MY_SEAT
  lda MY_NONCE
  eor MY_NONCE+1
  eor PEER_NONCE
  eor PEER_NONCE+1
  sta SESSION                      ; the same on both machines
  lda MY_COLOR
  ldy PEER_COLOR
  cpx #0
  beq @colors
  lda PEER_COLOR
  ldy MY_COLOR
@colors:
  sta P1_COLOR_IDX
  cpy P1_COLOR_IDX
  bne @differ
  iny
  cpy #7
  bcc @differ
  ldy #0
@differ:
  sty P2_COLOR_IDX
  jsr ApplySelectedTrailColors
  lda MY_SPEED                     ; the first seat's speed
  ldx MY_SEAT
  beq @speed
  lda PEER_SPEED
@speed:
  sta SPEED
  tax
  lda LinkDelays,x
  sta LDELAY
  jsr SendHello
  jsr StartRound
  ; Ticks before LDELAY take each rider as it starts.
  stz LT
  stz SAMPLED
  stz STALL_T
  lda LDELAY
  dec a
  sta MY_LAST
  sta PEER_LAST
  lda #DIR_RIGHT
  ldy #DIR_LEFT
  ldx MY_SEAT
  beq @dirs
  lda #DIR_LEFT
  ldy #DIR_RIGHT
@dirs:
  sta LOCAL_DIR
  ldx LDELAY
  dex
@fill:
  sta MY_IN,x
  pha
  tya
  sta PEER_IN,x
  pla
  dex
  bpl @fill
  lda #$FF
  sta P1_NEXT_DIR
  sta P2_NEXT_DIR
  jsr StateSum
  sta SUMS
  lda #LINK_RESEND
  sta LINK_T
  rts

; --- A linked round ---

; TickLink - a tick of a linked round, or another try at one: called every
; frame while it waits on the other machine.
TickLink:
  lda LINK_BAD
  beq @fine
  jmp LinkBroken
@fine:
  ; This machine's player steers with either stick or either key cluster:
  ; whichever moved since the last look (PollInput and PollInputP2 only
  ; write a heading when one is held).
  lda P1_NEXT_DIR
  cmp #$FF
  bne @local
  lda P2_NEXT_DIR
  cmp #$FF
  beq @sample
@local:
  sta LOCAL_DIR
@sample:
  lda #$FF
  sta P1_NEXT_DIR
  sta P2_NEXT_DIR
  lda SAMPLED                      ; once a tick: our heading for LDELAY on
  bne @peer
  inc SAMPLED
  lda LT
  clc
  adc LDELAY
  sta MY_LAST
  and #7
  tax
  lda LOCAL_DIR
  sta MY_IN,x
  jsr SendInput
  lda #LINK_RESEND
  sta LINK_T
@peer:
  lda PEER_LAST                    ; the other machine's heading for this tick?
  sec
  sbc LT
  bpl @go
  ; Not yet: try again next frame, and send ours again now and then.
  lda #1
  sta FRAMES_LEFT
  lda STALL_T
  cmp #255
  beq @long
  inc STALL_T
  lda STALL_T
  cmp #WAIT_SHOW
  bne @long
  lda #1
  jsr SetWaiting
@long:
  lda STALL_T
  cmp #WAIT_SHOW
  bcc @resend
  lda FIRE_EDGE                    ; given up on
  beq @resend
  jsr SndSelect
  jsr LinkOff
  jmp DrawTitleScreen
@resend:
  dec LINK_T
  bne @wait
  lda #LINK_RESEND
  sta LINK_T
  jmp SendOld
@wait:
  rts

@go:
  lda STALL_T
  cmp #WAIT_SHOW
  bcc @calm
  lda #0
  jsr SetWaiting
@calm:
  stz STALL_T
  lda LT
  and #7
  tax
  lda MY_IN,x
  ldy PEER_IN,x
  ldx MY_SEAT
  beq @put
  sta LINK_TMP
  tya
  ldy LINK_TMP
@put:
  sta P1_NEXT_DIR
  sty P2_NEXT_DIR
  jsr PlayTick
  lda #$FF
  sta P1_NEXT_DIR
  sta P2_NEXT_DIR
  inc LT
  stz SAMPLED
  jsr StateSum
  pha
  lda LT
  and #7
  tax
  pla
  sta SUMS,x
  rts

; StateSum - A = a check of the round as it stands at tick LT.
StateSum:
  lda LT
  clc
  adc P1_X
  adc P1_XH
  adc P1_Y
  adc P1_DIR
  adc P1_ALIVE
  adc P2_X
  adc P2_XH
  adc P2_Y
  adc P2_DIR
  adc P2_ALIVE
  rts

; LinkBroken - the two machines disagree about the round: stop and say so.
LinkBroken:
  lda #0
  jsr SetWaiting
  lda #RESULT_SYNC
  sta ROUND_RESULT
  lda #STATE_GAMEOVER
  sta GAME_STATE
  jmp DrawGameOverScreen

; LinkOver - a tick after a linked round: keep our last headings going out, in
; case the other machine is still waiting on them. A starts another round, or
; after a disagreement goes back to the title.
LinkOver:
  dec LINK_T
  bne @fire
  lda #HELLO_RESEND
  sta LINK_T
  jsr SendOld
@fire:
  lda FIRE_EDGE
  beq @done
  lda ROUND_RESULT
  cmp #RESULT_SYNC
  beq @quit
  lda #1
  sta HAVE_OLD
  jmp EnterLink
@quit:
  jsr SndSelect
  jsr LinkOff
  jmp DrawTitleScreen
@done:
  rts

; --- Sending ---

; SendFrame - TX_FRAME, with its sync and check.
SendFrame:
  lda #FRAME_SYNC
  sta TX_FRAME
  lda #<TX_FRAME
  ldx #>TX_FRAME
  jsr FrameCheck
  lda CK_A
  sta TX_FRAME + FRAME_SIZE - 2
  lda CK_B
  sta TX_FRAME + FRAME_SIZE - 1
  ldx #0
@send:
  lda TX_FRAME,x
  jsr SendByte
  inx
  cpx #FRAME_SIZE
  bne @send
  rts

; SendOld - the last INPUT frame again.
SendOld:
  ldx #0
@send:
  lda OLD_TX,x
  jsr SendByte
  inx
  cpx #FRAME_SIZE
  bne @send
  rts

; FrameCheck - CK_A, CK_B = the check of the frame at A (low), X (high). Two
; sums, the second over the first, so a frame put together from the pieces of
; two others, after a lost byte, doesn't pass by chance.
FrameCheck:
  sta FR_PTR
  stx FR_PTR+1
  lda #$5A
  sta CK_A
  lda #$A5
  sta CK_B
  ldy #1
@byte:
  lda (FR_PTR),y
  clc
  adc CK_A
  sta CK_A
  clc
  adc CK_B
  sta CK_B
  iny
  cpy #FRAME_SIZE - 2
  bne @byte
  rts

; SendByte - A out of the serial port, once the last byte has gone. Not the
; Kernal's routine: while it waits it puts arriving bytes in the keyboard
; buffer, where they'd read as key presses. Here they go in the ring. Keeps X.
SendByte:
  pha
  sei
@wait:
  lda SC_STATUS
  sta LINK_S
  and #SC_STATUS_RDRF
  beq @noByte
  phx
  lda SC_DATA
  ldx RX_HEAD
  sta RX_BUF,x
  inc RX_HEAD
  plx
@noByte:
  lda LINK_S
  and #SC_STATUS_TDRE
  beq @wait
  pla
  sta SC_DATA
  cli
  rts

; SendHello - who this machine is, its color, and how far along: 0 looking,
; 1 has heard the other machine, 2 has started.
SendHello:
  lda #FR_HELLO
  sta TX_FRAME+1
  stz TX_FRAME+2
  lda MY_NONCE
  sta TX_FRAME+3
  lda MY_NONCE+1
  sta TX_FRAME+4
  lda MY_COLOR
  sta TX_FRAME+5
  lda LINK_UP
  beq @notUp
  lda #2
  bra @stage
@notUp:
  lda HAVE_HELLO
@stage:
  sta TX_FRAME+6
  lda #LINK_VERSION
  sta TX_FRAME+7
  lda MY_SPEED
  sta TX_FRAME+8
  jmp SendFrame

; SendInput - our headings for ticks MY_LAST back to MY_LAST - 7, two bits
; each, the newest lowest: MY_LAST to MY_LAST - 3 in one byte, the four
; before that in the next. Kept in OLD_TX to send again.
SendInput:
  lda #FR_INPUT
  sta TX_FRAME+1
  lda MY_LAST
  sta TX_FRAME+2
  sec
  sbc #3
  sta LINK_TMP                     ; the oldest tick in this byte
  ldy #3
@byte:
  stz T_PACK
  ldx #4
@turn:
  asl T_PACK
  asl T_PACK
  phx
  lda LINK_TMP
  and #7
  tax
  lda MY_IN,x
  plx
  and #3
  ora T_PACK
  sta T_PACK
  inc LINK_TMP
  dex
  bne @turn
  lda T_PACK
  sta TX_FRAME,y
  lda LINK_TMP                     ; on to the four before
  sec
  sbc #8
  sta LINK_TMP
  iny
  cpy #5
  bne @byte
  lda LT                           ; the round as it stands now, LDELAY
  and #7                           ; before MY_LAST
  tax
  lda SUMS,x
  sta TX_FRAME+5
  lda SESSION
  sta TX_FRAME+6
  stz TX_FRAME+7
  stz TX_FRAME+8
  jsr SendFrame
  ldx #FRAME_SIZE - 1
@keep:
  lda TX_FRAME,x
  sta OLD_TX,x
  dex
  bpl @keep
  rts

; --- Receiving ---

; LinkPoll - take what has arrived, a limited amount a frame.
LinkPoll:
  lda LINK_ON
  beq @done
  lda #POLL_BYTES
  sta LINK_N
@next:
  ldx RX_TAIL
  cpx RX_HEAD
  beq @done
  lda RX_BUF,x
  inc RX_TAIL
  ldx PARSE_N
  bne @inFrame
  cmp #FRAME_SYNC
  bne @count
@inFrame:
  sta FRAME,x
  inx
  stx PARSE_N
  cpx #FRAME_SIZE
  bne @count
  stz PARSE_N
  jsr FrameOk
  bcc @damaged
  jsr TakeFrame
  bra @count
@damaged:
  jsr Resync
@count:
  dec LINK_N
  bne @next
@done:
  rts

; FrameOk - carry set if the frame that just came in passes its check.
FrameOk:
  lda #<FRAME
  ldx #>FRAME
  jsr FrameCheck
  lda CK_A
  cmp FRAME + FRAME_SIZE - 2
  bne @bad
  lda CK_B
  cmp FRAME + FRAME_SIZE - 1
  bne @bad
  sec
  rts
@bad:
  clc
  rts

; Resync - a frame that failed its check starts again from the next sync byte
; inside it. After a lost byte that's the start of the frame behind it, which
; would otherwise be lost as well. A sync byte that turns out to be data fails
; its check in turn and the search moves on.
Resync:
  ldx #1
@find:
  lda FRAME,x
  cmp #FRAME_SYNC
  beq @found
  inx
  cpx #FRAME_SIZE
  bne @find
  rts                              ; none: wait for the next one
@found:
  ldy #0
@move:
  lda FRAME,x
  sta FRAME,y
  iny
  inx
  cpx #FRAME_SIZE
  bne @move
  sty PARSE_N
  rts

; TakeFrame - act on a frame that passed its check.
TakeFrame:
  lda FRAME+1
  cmp #FR_HELLO
  beq TakeHello
  cmp #FR_INPUT
  beq TakeInput
  rts

TakeInput:
  lda LINK_UP
  beq @done
  lda GAME_STATE
  cmp #STATE_PLAYING
  bne @done
  lda FRAME+6
  cmp SESSION
  bne @done                        ; from an earlier round
  ; Its check, if this machine has been at that tick in the last eight.
  lda FRAME+2
  sec
  sbc LDELAY
  sta LINK_TMP
  lda LT
  sec
  sbc LINK_TMP
  cmp #8
  bcs @headings
  lda LINK_TMP
  and #7
  tax
  lda SUMS,x
  cmp FRAME+5
  beq @headings
  lda #BAD_SYNC
  sta LINK_BAD
  rts
@headings:
  lda FRAME+2                      ; anything newer than we have?
  sec
  sbc PEER_LAST
  beq @done
  bmi @done
  lda FRAME+2
  sta LINK_TMP
  lda FRAME+3
  jsr Unpack4
  lda FRAME+4
  jsr Unpack4
  lda FRAME+2
  sta PEER_LAST
@done:
  rts

; Unpack4 - four headings from A into PEER_IN, for LINK_TMP and the three
; ticks before it; LINK_TMP moves back four.
Unpack4:
  sta T_PACK
  ldy #4
@turn:
  lda LINK_TMP
  and #7
  tax
  lda T_PACK
  and #3
  sta PEER_IN,x
  lsr T_PACK
  lsr T_PACK
  dec LINK_TMP
  dey
  bne @turn
  rts

TakeHello:
  lda FRAME+7
  cmp #LINK_VERSION
  beq @version
  lda GAME_STATE
  cmp #STATE_LINKING
  bne @done
  lda #BAD_VERSION
  sta LINK_BAD
  rts
@version:
  lda LINK_UP
  beq @looking
  ; Already playing: it may not know yet.
  lda FRAME+3
  cmp PEER_NONCE
  bne @done
  lda FRAME+4
  cmp PEER_NONCE+1
  bne @done
  lda FRAME+6
  cmp #2
  bcs @done
  jmp SendHello
@looking:
  lda GAME_STATE
  cmp #STATE_LINKING
  bne @done
  lda FRAME+3
  cmp MY_NONCE
  bne @other
  lda FRAME+4
  cmp MY_NONCE+1
  bne @other
  stz HAVE_HELLO                   ; the same number: both pick again
  stz PEER_HAS
  jmp NewNonce
@other:
  lda FRAME+3
  sta PEER_NONCE
  lda FRAME+4
  sta PEER_NONCE+1
  lda FRAME+5
  cmp #7
  bcc @color
  lda #0
@color:
  sta PEER_COLOR
  lda FRAME+8
  cmp #3
  bcc @speed
  lda #SPEED_NORMAL
@speed:
  sta PEER_SPEED
  lda #1
  sta HAVE_HELLO
  lda FRAME+6
  beq @answer
  lda #1
  sta PEER_HAS
@done:
  rts
@answer:
  jmp SendHello
