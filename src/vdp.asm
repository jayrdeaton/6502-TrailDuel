; =============================================================================
;   vdp.asm - the arena on a 6502-PICOVDP, drawn a pixel at a time
; =============================================================================
;   Everything that knows about the video hardware lives here, so a port to
;   another machine replaces this file. The game draws the arena's border and
;   trails with PixelSetBorder, PixelSetP1Trail/P2Trail and tests it with
;   PixelIsSet, in screen pixels: x 0-319 (low byte in X, bit 8 in PX_HI), y
;   0-239. The title and messages draw with PixelSet, PixelClear and the text
;   routines in a 256 x 192 area centered on the screen (UI_X, UI_Y), where
;   their places fit in a byte. It also moves the riders' head sprites.
;
;   Full mode: 40 x 30 cells of 8 x 8, the whole 320 x 240. The arena's 38 x 26
;   cells (columns 1-38, rows 2-27) each have a tile of their own at 2 bits a
;   pixel, so every pixel has its own color: 1 is player 1's trail, 2 player
;   2's, 3 the border's blue in the ring of cells round the edge and white
;   everywhere inside it, where the text goes. A layer reaches 512 tiles and the
;   arena needs 988, so rows 2-14 are layer 0's and rows 15-27 layer 1's, 494
;   each. The cells round the arena are the frame: black, or red while a linked
;   round waits on the other machine (SetWaiting). Layer 0 is opaque, so the
;   picture is black where nothing is drawn.
;
;   SHADOW, in RAM, holds the same tiles, so PixelIsSet never asks the card.
;   Port A only: the Kernal leaves the card alone in interrupts, so no SEI.
; =============================================================================

.segment "CART"

; Video memory. The layers' tiles each have a 16 KB bank of their own.
V_L0NAME      = $0000              ; 1,200 bytes each, so 2 KB apart
V_L0ATTR      = $0800
V_L1NAME      = $1000
V_L1ATTR      = $1800
V_SPRATTR     = $2000
V_SPRPAT      = $2800
V_L0PAT       = $4000              ; bank 1
V_L1PAT       = $8000              ; bank 2
V_PALETTE     = $3C00              ; in bank 3: entry 0

COLS          = 40
ROWS          = 30
FIRST_COL     = 1                  ; the arena's cells
LAST_COL      = 38
FIRST_ROW     = 2
LAST_ROW      = 27
ARENA_COLS    = LAST_COL - FIRST_COL + 1
LAYER_TILES   = ARENA_COLS * 13
LAYER_BYTES   = LAYER_TILES * 16
LAYER_PAL     = 0                  ; the sub-palettes are entries 0-11
SUB_EDGE      = 0                  ; 3 is the border's blue
SUB_INSIDE    = 1                  ; 3 is white
SUB_FRAME     = 2                  ; 0 is the frame round the arena
FRAME_ENTRY   = SUB_FRAME * 4
UI_X          = 32                 ; where the title's 256 x 192 starts
UI_Y          = 24
HIDE_Y        = 240                ; a sprite here is below the picture
HEAD_ATTR     = $40 | 7            ; in front of layer 1; at 1bpp, entry 15 (white)
BORDER_FG     = TMS_LT_BLUE

VideoRegs:
  .byte VC_REG_MODE1,     $00      ; display off, 8x8 sprites
  .byte VC_REG_MODE0,     $00
  .byte VC_REG_VMODE,     VC_VMODE_FULL
  .byte VC_REG_VBANK,     0
  .byte VC_REG_VINC,      1
  .byte VC_REG_IRQEN,     0
  .byte VC_REG_STATSEL_A, 0
  .byte VC_REG_COLOR,     0
  .byte VC_REG_L0NAME,    V_L0NAME / $400
  .byte VC_REG_L0ATTR,    V_L0ATTR / $400
  .byte VC_REG_L0PAT,     V_L0PAT / $800
  .byte VC_REG_L0SCRX,    0
  .byte VC_REG_L0SCRY,    0
  .byte VC_REG_L0CTRL,    VC_LCTRL_2BPP | VC_LCTRL_ATTR_CELL | VC_LCTRL_ENABLE | VC_LCTRL_OPAQUE
  .byte VC_REG_L0PAL,     LAYER_PAL
  .byte VC_REG_L1NAME,    V_L1NAME / $400
  .byte VC_REG_L1ATTR,    V_L1ATTR / $400
  .byte VC_REG_L1PAT,     V_L1PAT / $800
  .byte VC_REG_L1SCRX,    0
  .byte VC_REG_L1SCRY,    0
  .byte VC_REG_L1CTRL,    VC_LCTRL_2BPP | VC_LCTRL_ATTR_CELL | VC_LCTRL_ENABLE
  .byte VC_REG_L1PAL,     LAYER_PAL
  .byte VC_REG_SPRATTR,   V_SPRATTR / $80
  .byte VC_REG_SPRPAT,    V_SPRPAT / $800
  .byte VC_REG_SPRCOUNT,  2
  .byte VC_REG_SPRCTRL,   VC_SPRCTRL_ENABLE | VC_SPRCTRL_1BPP
  .byte VC_REG_SPRLIMIT,  32
  .byte VC_REG_SPRPAL,    0
VIDEO_REGS = * - VideoRegs

; The sixteen TMS9918 colors as the PICOVDP's default palette has them, $0R, $GB
TmsRgb:
  .byte $00, $00,  $00, $00,  $02, $C4,  $06, $D7
  .byte $05, $5E,  $07, $7F,  $0C, $55,  $04, $EE
  .byte $0F, $55,  $0F, $77,  $0C, $B5,  $0D, $C8
  .byte $02, $A4,  $0C, $5B,  $0C, $CC,  $0F, $FF

; Where each cell row (2-27) and column (1-38) of the arena starts in SHADOW
RowOffLo:
.repeat ROWS, I
  .if I >= FIRST_ROW && I <= LAST_ROW
    .byte <((I - FIRST_ROW) * ARENA_COLS * 16)
  .else
    .byte 0
  .endif
.endrepeat
RowOffHi:
.repeat ROWS, I
  .if I >= FIRST_ROW && I <= LAST_ROW
    .byte >((I - FIRST_ROW) * ARENA_COLS * 16)
  .else
    .byte 0
  .endif
.endrepeat
ColOffLo:
.repeat COLS, I
  .if I >= FIRST_COL && I <= LAST_COL
    .byte <((I - FIRST_COL) * 16)
  .else
    .byte 0
  .endif
.endrepeat
ColOffHi:
.repeat COLS, I
  .if I >= FIRST_COL && I <= LAST_COL
    .byte >((I - FIRST_COL) * 16)
  .else
    .byte 0
  .endif
.endrepeat

; 2-bit pixels, four to a byte, the leftmost highest: what clears pixel n of a
; byte, and each value there
PixClear:
  .byte $3F, $CF, $F3, $FC
PixBits:
  .byte $00, $00, $00, $00
  .byte $40, $10, $04, $01
  .byte $80, $20, $08, $02
PixMask:
  .byte $C0, $30, $0C, $03

; Each layer's first and last cell row
LayerFirst:
  .byte FIRST_ROW, FIRST_ROW + 13
LayerLast:
  .byte FIRST_ROW + 12, LAST_ROW

; VReg - register X to A. Keeps X.
VReg:
  sta VC_REG
  txa
  ora #VC_REG_WRITE
  sta VC_REG
  rts

; VAddr - port A writes from A (low), X (high 6 bits) in the bank VBANK holds.
; Keeps X.
VAddr:
  sta VC_REG
  txa
  ora #VC_ADDR_WRITE
  sta VC_REG
  rts

; SetVBank - which 16 KB of video memory addresses reach, A (0-3). Clobbers X.
SetVBank:
  cmp VBANK_NOW
  beq @done
  sta VBANK_NOW
  ldx #VC_REG_VBANK
  jmp VReg
@done:
  rts

; SetWaiting - A nonzero turns the frame round the arena red, while a linked
; round waits on the other machine; zero puts it back to black. Clobbers X, Y.
SetWaiting:
  pha
  lda #3
  jsr SetVBank
  lda #<(V_PALETTE + FRAME_ENTRY * 2)
  ldx #>(V_PALETTE + FRAME_ENTRY * 2)
  jsr VAddr
  pla
  beq @black
  lda #TMS_MED_RED
  bra @put
@black:
  lda #TMS_BLACK
@put:
  jsr PutRgb
  lda #0
  jmp SetVBank

; WaitFrames - A pictures end.
WaitFrames:
  tax
@frame:
  bit VC_STATUS                    ; bit 7 sets as a picture ends; reading clears it
  bpl @frame
  dex
  bne @frame
  rts

; VideoInit - set the card up, the arena blank and the display on.
VideoInit:
  ldy #0
@regs:
  ldx VideoRegs,y
  lda VideoRegs+1,y
  jsr VReg
  iny
  iny
  cpy #VIDEO_REGS
  bne @regs
  stz VBANK_NOW
  jsr FillLayers
  lda #0
  jsr SetWaiting
  jsr ClearScreen
  jsr InitHeadSprites
  lda #VC_MODE1_DISP               ; display on, 8x8 sprites
  ldx #VC_REG_MODE1
  jmp VReg

; FillLayers - both layers' name and attribute tables: the arena's cells in a
; layer's rows take its tiles 1-494 in order, every other cell tile 0, which is
; blank. The ring of cells round the arena's edge takes the border's
; sub-palette, and the cells outside it, on layer 0, the frame's.
FillLayers:
  stz FL_LAYER
@layer:
  stz FL_PASS                      ; 0 the names, 1 the attributes
@pass:
  lda FL_LAYER
  asl a
  asl a
  asl a
  asl a                            ; the second layer's tables are $1000 on
  ldx FL_PASS
  beq @names
  ora #>V_L0ATTR
  bra @at
@names:
  ora #>V_L0NAME
@at:
  tax
  lda #0
  jsr VAddr
  lda #1
  sta FL_TILE
  stz FL_TILE+1
  stz FL_ROW
@row:
  stz FL_COL
@cell:
  jsr ArenaCell
  bcs @arena
  ; outside the arena: the frame on layer 0, nothing on layer 1
  lda FL_PASS
  beq @blank
  lda FL_LAYER
  bne @blank
  lda #SUB_FRAME
  bra @write
@arena:
  ldx FL_LAYER
  lda FL_ROW
  cmp LayerFirst,x
  bcc @blank
  lda LayerLast,x
  cmp FL_ROW
  bcc @blank
  lda FL_PASS
  bne @attr
  lda FL_TILE
  bra @put
@attr:
  lda #SUB_EDGE
  ldx FL_COL
  cpx #FIRST_COL
  beq @edge
  cpx #LAST_COL
  beq @edge
  ldx FL_ROW
  cpx #FIRST_ROW
  beq @edge
  cpx #LAST_ROW
  beq @edge
  lda #SUB_INSIDE
@edge:
  ldx FL_TILE+1                    ; tiles past 255 take the attribute's top bit
  beq @put
  ora #$80
@put:
  sta VC_DATA
  inc FL_TILE
  bne @next
  inc FL_TILE+1
  bra @next
@blank:
  lda #0
@write:
  sta VC_DATA
@next:
  inc FL_COL
  lda FL_COL
  cmp #COLS
  beq @rowDone
  jmp @cell
@rowDone:
  inc FL_ROW
  lda FL_ROW
  cmp #ROWS
  beq @tableDone
  jmp @row
@tableDone:
  inc FL_PASS
  lda FL_PASS
  cmp #2
  beq @layerDone
  jmp @pass
@layerDone:
  inc FL_LAYER
  lda FL_LAYER
  cmp #2
  beq @done
  jmp @layer
@done:
  rts

; ArenaCell - carry set if cell (FL_COL, FL_ROW) is one of the arena's.
ArenaCell:
  lda FL_COL
  cmp #FIRST_COL
  bcc @no
  cmp #LAST_COL + 1
  bcs @no
  lda FL_ROW
  cmp #FIRST_ROW
  bcc @no
  cmp #LAST_ROW + 1
  bcs @no
  sec
  rts
@no:
  clc
  rts

; SetPalette - the sub-palettes from the players' trail colors: 1 is player 1,
; 2 player 2, and 3 the border's blue round the edge and white inside it. Entry
; 0, value 0 of the first, is black for the empty arena. The frame's entry is
; SetWaiting's. The head sprites' white is entry 15, which stays as the card
; has it.
SetPalette:
  lda #3
  jsr SetVBank
  lda #<V_PALETTE
  ldx #>V_PALETTE
  jsr VAddr
  lda #BORDER_FG
  jsr PutSub
  lda #TMS_WHITE
  jsr PutSub
  lda #0
  jmp SetVBank

; PutSub - a sub-palette: nothing, the two trails, then color A.
PutSub:
  pha
  lda #TMS_BLACK
  jsr PutRgb
  lda P1_TRAIL_COLOR
  jsr PutRgb
  lda P2_TRAIL_COLOR
  jsr PutRgb
  pla
  ; falls through

; PutRgb - TMS color A's palette entry.
PutRgb:
  asl a
  tay
  lda TmsRgb,y
  sta VC_DATA
  lda TmsRgb+1,y
  sta VC_DATA
  rts

; ClearScreen - an empty arena: SHADOW and both layers' tiles.
ClearScreen:
  lda #<SHADOW
  sta WORK_PTR
  lda #>SHADOW
  sta WORK_PTR+1
  ldx #>(LAYER_BYTES * 2 + 255)
  lda #0
  tay
@ramPage:
  sta (WORK_PTR),y
  iny
  bne @ramPage
  inc WORK_PTR+1
  dex
  bne @ramPage

  lda #1
@bank:
  pha
  jsr SetVBank
  lda #0
  tax
  jsr VAddr
  ldx #>(LAYER_BYTES + 16 + 255)
  lda #0
  tay
@vramPage:
  sta VC_DATA
  iny
  bne @vramPage
  dex
  bne @vramPage
  pla
  inc a
  cmp #3
  bne @bank
  lda #0
  jmp SetVBank

; DrawBorder - the arena's edge, a pixel wide all round.
DrawBorder:
  lda #<ARENA_MIN_X
  sta FL_TILE
  lda #>ARENA_MIN_X
  sta FL_TILE+1
@across:
  lda FL_TILE+1
  sta PX_HI
  ldx FL_TILE
  lda #ARENA_MIN_Y
  jsr PixelSetBorder
  lda #ARENA_MAX_Y
  jsr PixelSetBorder
  inc FL_TILE
  bne @nextX
  inc FL_TILE+1
@nextX:
  lda FL_TILE
  cmp #<(ARENA_MAX_X + 1)
  bne @across
  lda FL_TILE+1
  cmp #>(ARENA_MAX_X + 1)
  bne @across

  lda #ARENA_MIN_Y + 1
  sta SCAN_TMP
@down:
  stz PX_HI
  ldx #<ARENA_MIN_X
  lda SCAN_TMP
  jsr PixelSetBorder
  lda #>ARENA_MAX_X
  sta PX_HI
  ldx #<ARENA_MAX_X
  lda SCAN_TMP
  jsr PixelSetBorder
  inc SCAN_TMP
  lda SCAN_TMP
  cmp #ARENA_MAX_Y
  bne @down
  rts

; --- The riders' heads: a white pixel each, as sprites ---

InitHeadSprites:
  lda #0
  jsr SetVBank
  lda #<V_SPRPAT
  ldx #>V_SPRPAT
  jsr VAddr
  lda #%10000000                   ; pattern 0: the top left pixel
  sta VC_DATA
  ldx #7
@rows:
  stz VC_DATA
  dex
  bne @rows
  lda #<V_SPRATTR
  ldx #>V_SPRATTR
  jsr VAddr
  jsr HideHead
  ; falls through

HideHead:
  lda #HIDE_Y
  sta VC_DATA
  stz VC_DATA
  stz VC_DATA
  stz VC_DATA
  rts

UpdateHeadSprites:
  lda #0
  jsr SetVBank
  lda #<V_SPRATTR
  ldx #>V_SPRATTR
  jsr VAddr
  lda P1_ALIVE
  beq @hide1
  lda P1_XH
  sta PX_HI
  lda P1_Y
  ldx P1_X
  jsr PutHead
  bra @second
@hide1:
  jsr HideHead
@second:
  lda P2_ALIVE
  beq HideHead
  lda P2_XH
  sta PX_HI
  lda P2_Y
  ldx P2_X
  ; falls through

; PutHead - a head sprite's slot, at row A, column X (bit 8 in PX_HI).
PutHead:
  cmp #HIDE_Y
  bcs HideHead
  sta VC_DATA
  stx VC_DATA
  stz VC_DATA
  lda PX_HI
  beq @low
  lda #HEAD_ATTR | VC_ATTR_BIT8    ; the attribute's top bit is X's bit 8
  bra @attr
@low:
  lda #HEAD_ATTR
@attr:
  sta VC_DATA
  rts

; --- Pixels ---

; ComputePixelAddress - where pixel (X, A) lives. In: A = row, X = column's
; low byte, PX_HI = its bit 8. Out: carry clear, WORK_PTR = its byte in
; SHADOW, OFFSET_LO/HI = that byte's place in SHADOW, NUM_TMP = which of the
; byte's four pixels it is; or carry set if it's outside the arena's cells.
; Keeps X. Clobbers: A, Y, PX_X, PX_Y
ComputePixelAddress:
  sta PX_Y
  stx PX_X
  lsr a
  lsr a
  lsr a
  cmp #FIRST_ROW
  bcc @out
  cmp #LAST_ROW + 1
  bcs @out
  tay
  txa
  lsr a
  lsr a
  lsr a
  ldx PX_HI
  beq @col
  ora #$20                         ; past 255: 32 cells on
@col:
  cmp #FIRST_COL
  bcc @out
  cmp #LAST_COL + 1
  bcs @out
  tax
  lda RowOffLo,y
  clc
  adc ColOffLo,x
  sta OFFSET_LO
  lda RowOffHi,y
  adc ColOffHi,x
  sta OFFSET_HI
  lda PX_Y                         ; two bytes a row
  and #7
  asl a
  sta NUM_TMP
  lda PX_X                         ; four pixels a byte
  and #4
  lsr a
  lsr a
  ora NUM_TMP
  clc
  adc OFFSET_LO
  sta OFFSET_LO
  bcc @in
  inc OFFSET_HI
@in:
  lda OFFSET_LO
  clc
  adc #<SHADOW
  sta WORK_PTR
  lda OFFSET_HI
  adc #>SHADOW
  sta WORK_PTR+1
  lda PX_X
  and #3
  sta NUM_TMP
  ldx PX_X
  clc
  rts
@out:
  ldx PX_X
  sec
  rts

; PlotValue - the pixel ComputePixelAddress found to value A (0-3), in SHADOW
; and on the card. Clobbers: A, X, Y, VADDR
PlotValue:
  asl a
  asl a
  ora NUM_TMP
  tay
  ldx NUM_TMP
  lda (WORK_PTR)
  and PixClear,x
  ora PixBits,y
  sta (WORK_PTR)
  ; The arena's first LAYER_BYTES are layer 0's tiles in bank 1, the rest
  ; layer 1's in bank 2, each after its blank tile 0.
  lda OFFSET_LO
  sec
  sbc #<LAYER_BYTES
  sta VADDR
  lda OFFSET_HI
  sbc #>LAYER_BYTES
  bcs @second
  lda OFFSET_LO
  sta VADDR
  lda OFFSET_HI
  ldy #1
  bra @bank
@second:
  ldy #2
@bank:
  sta VADDR+1
  tya
  jsr SetVBank
  lda VADDR
  clc
  adc #16
  pha
  lda VADDR+1
  adc #0
  tax
  pla
  jsr VAddr
  lda (WORK_PTR)
  sta VC_DATA
  rts

; PixelSetP1Trail / PixelSetP2Trail - a pixel of a player's trail.
; In: A = row, X = column, PX_HI = column's bit 8.
; Clobbers: A, X, Y, plus what PlotValue clobbers
PixelSetP1Trail:
  ldy #1
  bra PlotTrail
PixelSetP2Trail:
  ldy #2
PlotTrail:
  sty DIGIT_TMP
  jsr ComputePixelAddress
  bcs @done
  lda DIGIT_TMP
  jmp PlotValue
@done:
  rts

; PixelSetBorder - a pixel of the arena's border, at row A, column X (bit 8 in
; PX_HI). Keeps X and Y.
PixelSetBorder:
  phx
  phy
  jsr ComputePixelAddress
  bcs PixelDone
  lda #3
  bra PixelPlot

; UiPixel - pixel (X, A) of the title's 256 x 192 area as a screen pixel: A = row,
; X = column's low byte, PX_HI = its bit 8.
UiPixel:
  clc
  adc #UI_Y
  pha
  txa
  clc
  adc #UI_X
  tax
  lda #0
  adc #0
  sta PX_HI
  pla
  rts

; PixelSet - pixel (X, A) of the title's area in TMS color Y: a player's trail
; color is that player's value, and white or any other color is 3, white
; inside the arena. Keeps X and Y. Clobbers: A, DIGIT_TMP, WORK_PTR,
; OFFSET_LO/HI, NUM_TMP, PX_X/Y/HI, VADDR
PixelSet:
  phx
  phy
  sty DIGIT_TMP
  jsr UiPixel
  jsr ComputePixelAddress
  bcs PixelDone
  lda DIGIT_TMP
  ldy #3
  cmp #TMS_WHITE
  beq @have
  ldy #1
  cmp P1_TRAIL_COLOR
  beq @have
  iny
  cmp P2_TRAIL_COLOR
  beq @have
  iny
@have:
  tya
PixelPlot:
  jsr PlotValue
PixelDone:
  ply
  plx
  rts

; PixelClear - pixel (X, A) of the title's area back to nothing. Keeps X and Y.
PixelClear:
  phx
  phy
  jsr UiPixel
  jsr ComputePixelAddress
  bcs PixelDone
  lda #0
  bra PixelPlot

; EraseRect - clear a TEXT_ROW_I x TEXT_COL_I block of the title's area.
; In: A = top row, X = left column, TEXT_ROW_I = height, TEXT_COL_I = width
; Clobbers: A, X, Y, SCAN_TMP, SCAN_TMP2, FONT_HI, TEXT_COLOR, TEXT_ROW_I,
;   TEXT_COL_I, plus what PixelClear clobbers
EraseRect:
  sta SCAN_TMP               ; origin row
  stx SCAN_TMP2               ; origin col
  lda TEXT_ROW_I
  sta FONT_HI                  ; height
  lda TEXT_COL_I
  sta TEXT_COLOR                ; width

  stz TEXT_ROW_I
@rowLoop:
  stz TEXT_COL_I
@colLoop:
  lda TEXT_COL_I
  clc
  adc SCAN_TMP2
  tax
  lda TEXT_ROW_I
  clc
  adc SCAN_TMP
  jsr PixelClear

  inc TEXT_COL_I
  lda TEXT_COL_I
  cmp TEXT_COLOR
  bne @colLoop

  inc TEXT_ROW_I
  lda TEXT_ROW_I
  cmp FONT_HI
  bne @rowLoop
  rts

; PixelIsSet - A = 1 (Z clear) if screen pixel (X, A), bit 8 of X in PX_HI, is
; drawn, 0 (Z set) if not. Outside the arena's cells counts as drawn. Keeps X
; and Y.
PixelIsSet:
  phx
  phy
  jsr ComputePixelAddress
  bcs @set
  ldx NUM_TMP
  lda (WORK_PTR)
  and PixMask,x
  beq @clear
@set:
  ply
  plx
  lda #1
  rts
@clear:
  ply
  plx
  lda #0
  rts

; --- Text, drawn into the arena a pixel at a time ---

DrawChar:
  cmp #' '
  bcc @done
  cmp #('Z'+1)
  bcs @done

  sec
  sbc #' '                 ; A = (char - ' '), index into FontData
  sta FONT_TMP
  asl a
  asl a
  clc
  adc FONT_TMP              ; A = (index*5) mod 256; carry = the bit this
                             ; 8-bit add lost -- index*5 reaches 290 for
                             ; 'Z', past what one byte holds, and that
                             ; overflow bit has to reach FONT_PTR's high
                             ; byte, not just get thrown away by a clc
  stz FONT_HI
  bcc @noHi
  inc FONT_HI
@noHi:

  clc
  adc #<FontData
  sta FONT_PTR
  lda FONT_HI
  adc #>FontData
  sta FONT_PTR+1

  stz TEXT_COL_I
@colLoop:
  ldy TEXT_COL_I
  lda (FONT_PTR),y
  sta FONT_TMP

  stz TEXT_ROW_I
@rowLoop:
  ldx TEXT_ROW_I
  lda FONT_TMP
  and FontBitMask,x
  beq @rowSkip

  lda TEXT_ROW_I
  clc
  adc TEXT_ROW
  pha
  lda TEXT_COL_I
  clc
  adc TEXT_COL
  tax
  pla
  ldy TEXT_COLOR
  jsr PixelSet

@rowSkip:
  inc TEXT_ROW_I
  lda TEXT_ROW_I
  cmp #7
  bne @rowLoop

  inc TEXT_COL_I
  lda TEXT_COL_I
  cmp #5
  bne @colLoop

@done:
  rts

FontBitMask:
  .byte $01, $02, $04, $08, $10, $20, $40

; -----------------------------------------------------------------------------
; DrawText - plot a null-terminated string, one glyph every 6 pixels (5 wide
; plus 1 blank column of spacing).
; In:  TEXT_STR_PTR = string pointer, TEXT_ROW/TEXT_COL = origin, TEXT_COLOR
;      Deliberately NOT WORK_PTR -- DrawChar calls down into PixelSet /
;      ComputePixelAddress, which clobbers WORK_PTR for its own shadow-
;      buffer addressing on every pixel, so the string pointer needs its
;      own zero-page home that survives those nested calls.
; Out: TEXT_COL is left just past the string's last character
; Clobbers: A, X, Y, STR_IDX, plus everything DrawChar clobbers
; -----------------------------------------------------------------------------
DrawText:
  stz STR_IDX
@loop:
  ldy STR_IDX
  lda (TEXT_STR_PTR),y
  beq @done
  jsr DrawChar
  lda TEXT_COL
  clc
  adc #6
  sta TEXT_COL
  inc STR_IDX
  jmp @loop
@done:
  rts

; -----------------------------------------------------------------------------
; DrawCharBig - like DrawChar, but each font pixel becomes a 2x2 block
; (10x14 pixels per glyph instead of 5x7), for a title that reads as an
; actual title instead of just another line of body text. Reuses FontData
; as-is rather than needing a second, separately-authored big font.
; In:  A = ASCII character code (space through 'Z')
;      TEXT_ROW/TEXT_COL = top-left pixel origin, TEXT_COLOR = TMS_* color
; Out: none
; Clobbers: A, X, Y, FONT_PTR, FONT_TMP, FONT_HI, TEXT_ROW_I, TEXT_COL_I,
;   SCAN_TMP, SCAN_TMP2
; -----------------------------------------------------------------------------
DrawCharBig:
  cmp #' '
  bcc @done
  cmp #('Z'+1)
  bcs @done

  sec
  sbc #' '
  sta FONT_TMP
  asl a
  asl a
  clc
  adc FONT_TMP
  stz FONT_HI
  bcc @noHi
  inc FONT_HI
@noHi:

  clc
  adc #<FontData
  sta FONT_PTR
  lda FONT_HI
  adc #>FontData
  sta FONT_PTR+1

  stz TEXT_COL_I
@colLoop:
  ldy TEXT_COL_I
  lda (FONT_PTR),y
  sta FONT_TMP

  stz TEXT_ROW_I
@rowLoop:
  ldx TEXT_ROW_I
  lda FONT_TMP
  and FontBitMask,x
  beq @rowSkip

  lda TEXT_ROW_I               ; SCAN_TMP = scaled absolute row (top of
  asl a                          ; this font pixel's 2x2 block)
  clc
  adc TEXT_ROW
  sta SCAN_TMP
  lda TEXT_COL_I               ; SCAN_TMP2 = scaled absolute col (left
  asl a                          ; of this font pixel's 2x2 block)
  clc
  adc TEXT_COL
  sta SCAN_TMP2

  lda SCAN_TMP
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP
  clc
  adc #1
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP
  clc
  adc #1
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

@rowSkip:
  inc TEXT_ROW_I
  lda TEXT_ROW_I
  cmp #7
  bne @rowLoop

  inc TEXT_COL_I
  lda TEXT_COL_I
  cmp #5
  bne @colLoop

@done:
  rts

; -----------------------------------------------------------------------------
; DrawTextBig - DrawText's counterpart for DrawCharBig: one glyph every 12
; pixels (10 wide plus 2 blank columns of spacing) instead of 6.
; In:  TEXT_STR_PTR = string pointer, TEXT_ROW/TEXT_COL = origin, TEXT_COLOR
; Out: TEXT_COL is left just past the string's last character
; -----------------------------------------------------------------------------
DrawTextBig:
  stz STR_IDX
@loop:
  ldy STR_IDX
  lda (TEXT_STR_PTR),y
  beq @done
  jsr DrawCharBig
  lda TEXT_COL
  clc
  adc #12
  sta TEXT_COL
  inc STR_IDX
  jmp @loop
@done:
  rts

; -----------------------------------------------------------------------------
; DrawColorSwatch - fill a small 7x7 pixel block with a solid color, used to
; preview a player's selected trail color on the title screen. 7px to match
; the font's own glyph height, so the swatch reads as sitting on the same
; line as the "P1:"/"P2:" text instead of an arbitrary size. Reuses
; DrawChar's TEXT_ROW_I/TEXT_COL_I as generic loop counters, safe since the
; two routines are never active at the same time.
; In: A = top-left row, X = top-left col, Y = TMS_* color
; Out: none
; Clobbers: A, X, Y, SCAN_TMP, SCAN_TMP2, TEXT_ROW_I, TEXT_COL_I, TEXT_COLOR,
;   plus everything PixelSet clobbers
; -----------------------------------------------------------------------------
DrawColorSwatch:
  sta SCAN_TMP               ; origin row
  stx SCAN_TMP2               ; origin col
  sty TEXT_COLOR

  stz TEXT_ROW_I
@rowLoop:
  stz TEXT_COL_I
@colLoop:
  lda TEXT_COL_I
  clc
  adc SCAN_TMP2
  tax                          ; X = this pixel's absolute column
  lda TEXT_ROW_I
  clc
  adc SCAN_TMP                 ; A = this pixel's absolute row
  ldy TEXT_COLOR
  jsr PixelSet

  inc TEXT_COL_I
  lda TEXT_COL_I
  cmp #7
  bne @colLoop

  inc TEXT_ROW_I
  lda TEXT_ROW_I
  cmp #7
  bne @rowLoop
  rts

; -----------------------------------------------------------------------------
; DrawLeftTriangle / DrawRightTriangle - a small 3x5 "you can go this way"
; affordance: a solid filled arrowhead coming to a single-pixel point, not
; the font's thin </> glyphs, either side of the title menu's line.
; In: A = top row, X = left col, Y = color
; Out: none
; Clobbers: A, X, Y, SCAN_TMP, SCAN_TMP2, TEXT_COLOR, plus everything
;   PixelSet clobbers
; -----------------------------------------------------------------------------
DrawLeftTriangle:
  sta SCAN_TMP               ; top row
  stx SCAN_TMP2               ; left col
  sty TEXT_COLOR

  lda SCAN_TMP                ; row0, col+2
  ldx SCAN_TMP2
  inx
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row1, col+1
  clc
  adc #1
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row1, col+2
  clc
  adc #1
  ldx SCAN_TMP2
  inx
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row2, col+0
  clc
  adc #2
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row2, col+1
  clc
  adc #2
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row2, col+2
  clc
  adc #2
  ldx SCAN_TMP2
  inx
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row3, col+1
  clc
  adc #3
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row3, col+2
  clc
  adc #3
  ldx SCAN_TMP2
  inx
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row4, col+2
  clc
  adc #4
  ldx SCAN_TMP2
  inx
  inx
  ldy TEXT_COLOR
  jsr PixelSet
  rts

DrawRightTriangle:
  sta SCAN_TMP               ; top row
  stx SCAN_TMP2               ; left col
  sty TEXT_COLOR

  lda SCAN_TMP                ; row0, col+0
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row1, col+0
  clc
  adc #1
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row1, col+1
  clc
  adc #1
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row2, col+0
  clc
  adc #2
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row2, col+1
  clc
  adc #2
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row2, col+2
  clc
  adc #2
  ldx SCAN_TMP2
  inx
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row3, col+0
  clc
  adc #3
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row3, col+1
  clc
  adc #3
  ldx SCAN_TMP2
  inx
  ldy TEXT_COLOR
  jsr PixelSet

  lda SCAN_TMP                ; row4, col+0
  clc
  adc #4
  ldx SCAN_TMP2
  ldy TEXT_COLOR
  jsr PixelSet
  rts
