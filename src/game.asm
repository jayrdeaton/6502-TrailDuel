; =============================================================================
;   game.asm - pixel-precision TrailDuel game loop
; =============================================================================

.segment "CART"

NewGame:
  lda #MODE_1P
  sta GAME_MODE
  lda #4                    ; TrailFgColorTable[4] = LT_BLUE
  sta P1_COLOR_IDX
  lda #1                    ; TrailFgColorTable[1] = LT_YELLOW
  sta P2_COLOR_IDX
  stz MENU_ROW
  stz MENU_PREV
  lda #SPEED_NORMAL
  sta SPEED
  jsr ApplySelectedTrailColors
  lda #$2A
  sta RNG_STATE
  jsr DrawTitleScreen
  rts

Tick:
  lda #TICK_FRAMES                ; until the next tick, unless a linked round
  sta FRAMES_LEFT                 ; is waiting on the other machine
  lda GAME_STATE
  cmp #STATE_TITLE
  bne :+
  jmp TickTitle
:
  cmp #STATE_PLAYING
  bne :+
  jmp TickPlaying
:
  cmp #STATE_PAUSED
  bne :+
  jmp TickPaused
:
  cmp #STATE_GAMEOVER
  bne :+
  jmp TickGameOver
:
  cmp #STATE_LINKING
  bne :+
  jmp TickLinking
:
  jmp TickDone

TickTitle:
  jsr MenuInput
  lda FIRE_EDGE
  bne :+
  jmp TickDone
:
  lda GAME_MODE
  cmp #MODE_LINK
  bne :+
  jmp EnterLink
:
  jsr StartRound
  rts

TickGameOver:
  lda GAME_MODE
  cmp #MODE_LINK
  bne :+
  lda LINK_ON
  beq :+
  jmp LinkOver
:
  lda FIRE_EDGE
  bne :+
  jmp TickDone
:
  jsr SndSelect
  jmp DrawTitleScreen

; Frames a tick at each speed: 20, 30 and 60 pixels a second
SpeedFrames:
  .byte 3, 2, 1

TickPaused:
  lda FIRE_EDGE
  bne :+
  jmp TickDone
:
  lda #STATE_PLAYING
  sta GAME_STATE
  jmp SndSelect

TickPlaying:
  ldx SPEED                       ; the round's pace: frames to the next tick
  lda SpeedFrames,x
  sta FRAMES_LEFT
  lda GAME_MODE
  cmp #MODE_LINK
  bne @here
  jmp TickLink
@here:
  lda FIRE_EDGE
  beq @playAdvance
  lda #STATE_PAUSED
  sta GAME_STATE
  jmp SndSelect

@playAdvance:
  lda GAME_MODE
  cmp #MODE_1P
  bne @skipAi
  jsr ComputeP2AIDirection
@skipAi:
  ; falls through

; PlayTick - the riders turn, move and crash, each as its NEXT_DIR asks.
PlayTick:
  jsr ApplyRequestedTurns

  jsr ComputeNextPositions

  lda P1_NEXT_X
  cmp P2_NEXT_X
  bne @notHeadOn
  lda P1_NEXT_XH
  cmp P2_NEXT_XH
  bne @notHeadOn
  lda P1_NEXT_Y
  cmp P2_NEXT_Y
  bne @notHeadOn
  stz P1_ALIVE
  stz P2_ALIVE
  jmp ResolveRound

; Collision is whether the pixel ahead is already drawn (PixelIsSet): a
; trail, either rider's own included, or the border.
@notHeadOn:
  lda P1_NEXT_Y
  cmp #240                        ; past the top wraps round to here
  bcs P1CollisionDead
  ldx P1_NEXT_XH
  stx PX_HI
  ldx P1_NEXT_X
  jsr PixelIsSet
  beq P1CollisionClear
P1CollisionDead:
  stz P1_ALIVE
P1CollisionClear:

  lda P2_NEXT_Y
  cmp #240
  bcs P2CollisionDead
  ldx P2_NEXT_XH
  stx PX_HI
  ldx P2_NEXT_X
  jsr PixelIsSet
  beq P2CollisionClear
P2CollisionDead:
  stz P2_ALIVE
P2CollisionClear:

ResolveRound:
  lda P1_ALIVE
  beq ResolveP1Dead
  lda P2_ALIVE
  beq ResolveP2DeadOnly

  jsr CommitP1Move
  jsr CommitP2Move
  jsr UpdateHeadSprites
  rts

ResolveP1Dead:
  lda P2_ALIVE
  beq ResolveBothDead
  lda #2                   ; P1 crashed -> P2 wins (ROUND_RESULT names the
  sta ROUND_RESULT           ; WINNER, not who died -- this was backwards
                              ; before: P1 dying set ROUND_RESULT=1, which
                              ; DrawGameOverScreen reads as "P1 wins"
  lda #STATE_GAMEOVER
  sta GAME_STATE
  jsr SndCrash
  jsr DrawGameOverScreen
  rts

ResolveP2DeadOnly:
  lda #1                   ; P2 crashed -> P1 wins
  sta ROUND_RESULT
  lda #STATE_GAMEOVER
  sta GAME_STATE
  jsr SndCrash
  jsr DrawGameOverScreen
  rts

ResolveBothDead:
  lda #3
  sta ROUND_RESULT
  lda #STATE_GAMEOVER
  sta GAME_STATE
  jsr SndCrash
  jsr DrawGameOverScreen

TickDone:
  rts

StartRound:
  lda #0
  jsr SetIOMode
  jsr ClearScreen
  jsr DrawBorder

  stz ROUND_RESULT

  ; A quarter of the way in from each side, halfway down
  lda #<P1_START_X
  sta P1_X
  lda #>P1_START_X
  sta P1_XH
  lda #START_Y
  sta P1_Y
  lda #DIR_RIGHT
  sta P1_DIR
  sta P1_NEXT_DIR
  lda #$01
  sta P1_ALIVE

  lda #<P2_START_X
  sta P2_X
  lda #>P2_START_X
  sta P2_XH
  lda #START_Y
  sta P2_Y
  lda #DIR_LEFT
  sta P2_DIR
  sta P2_NEXT_DIR
  lda #$01
  sta P2_ALIVE

  lda P1_XH
  sta PX_HI
  lda P1_Y
  ldx P1_X
  jsr PixelSetP1Trail

  lda P2_XH
  sta PX_HI
  lda P2_Y
  ldx P2_X
  jsr PixelSetP2Trail

  lda #STATE_PLAYING
  sta GAME_STATE
  jsr UpdateHeadSprites
  jmp SndGo

; -----------------------------------------------------------------------------
; DrawTitleScreen - always a full wipe and fresh redraw, drawn into the arena
; the same way the trails are. Reached both at initial boot (over an
; already-blank arena) and after a game over (over the frozen final trails
; under the result) -- wiping only at one of those call sites would leave
; the other showing stale content underneath.
; -----------------------------------------------------------------------------
DrawTitleScreen:
  jsr ClearScreen
  jsr DrawBorder
  jsr InitHeadSprites             ; both heads hidden

  lda #58
  sta TEXT_ROW
  lda #72                     ; "TRAIL DUEL" is 10 cells of 12px, so the
  sta TEXT_COL                ; words start at 72 and 144
  lda #TMS_WHITE
  sta TEXT_COLOR
  lda #<TitleLine1
  sta TEXT_STR_PTR
  lda #>TitleLine1
  sta TEXT_STR_PTR+1
  jsr DrawTextBig
  jsr DrawTitleDecoration
  jsr DrawMenu
  lda #144
  ldx #<TitleLine4
  ldy #>TitleLine4
  jsr CenterText

  lda #STATE_TITLE
  sta GAME_STATE
  rts

; -----------------------------------------------------------------------------
; DrawTitleDecoration - the title underlined in each player's trail color:
; "TRAIL" in P1's, "DUEL" in P2's, so the title screen reads as the same
; game rather than a bolted-on splash, right from the two-word split the
; name already has. Each line is drawn in its player's value, so a new color
; pick recolors it through the palette.
; -----------------------------------------------------------------------------
DrawTitleDecoration:
  jsr DrawP1Underline
  jmp DrawP2Underline

; -----------------------------------------------------------------------------
; DrawP1Underline - erases and redraws the underline beneath "TRAIL" (row
; 74) in P1's trail color, with a single white lead pixel at its rightmost
; end, closest to P2's line, so the two read as racing toward each other
; across the gap between the words. White outright, not a brighter tint of
; the trail color -- a picked color's "bright" tier (used by the head
; sprites) is sometimes identical to its own trail color (light blue/light
; yellow have no brighter tier above them), which made the lead invisible
; for those picks. The body is columns 72-127 and the lead pixel 128.
; Erases first, so the line comes out the same whatever was there.
; Clobbers: A, X, Y, SCAN_TMP, SCAN_TMP2, TEXT_COLOR, TEXT_ROW_I, TEXT_COL_I,
;   plus everything PixelSet/PixelClear clobber
; -----------------------------------------------------------------------------
DrawP1Underline:
  lda #1
  sta TEXT_ROW_I
  lda #57
  sta TEXT_COL_I
  lda #74
  ldx #72
  jsr EraseRect

  ldy P1_TRAIL_COLOR
  sty TEXT_COLOR
  stz TEXT_COL_I
@bodyLoop:
  lda TEXT_COL_I
  clc
  adc #72
  tax
  lda #74
  ldy TEXT_COLOR
  jsr PixelSet
  inc TEXT_COL_I
  lda TEXT_COL_I
  cmp #56                     ; body is cols 72-127; the lead pixel is at 128
  bne @bodyLoop

  lda #74
  ldx #128
  ldy #TMS_WHITE
  jsr PixelSet
  rts

; -----------------------------------------------------------------------------
; DrawP2Underline - same idea as DrawP1Underline, for the line beneath
; "DUEL" (row 74) in P2's trail color. Its white lead pixel is at the
; LEFTMOST end instead -- P2's line faces P1's across the gap, so the lead
; has to point the other way for the two to race toward each other rather
; than both pointing right. The lead pixel is column 143, in the gap
; between the words, and the body spans the word's full width at 144-189.
; Clobbers: A, X, Y, SCAN_TMP, SCAN_TMP2, TEXT_COLOR, TEXT_ROW_I, TEXT_COL_I,
;   plus everything PixelSet/PixelClear clobber
; -----------------------------------------------------------------------------
DrawP2Underline:
  lda #1
  sta TEXT_ROW_I
  lda #47
  sta TEXT_COL_I
  lda #74
  ldx #143
  jsr EraseRect

  lda #74
  ldx #143
  ldy #TMS_WHITE
  jsr PixelSet

  ldy P2_TRAIL_COLOR
  sty TEXT_COLOR
  lda #1
  sta TEXT_COL_I
@bodyLoop:
  lda TEXT_COL_I
  clc
  adc #143
  tax
  lda #74
  ldy TEXT_COLOR
  jsr PixelSet
  inc TEXT_COL_I
  lda TEXT_COL_I
  cmp #47
  bne @bodyLoop
  rts

; -----------------------------------------------------------------------------
; DrawGameOverScreen - per Jay: the win screen IS the gameplay screen, with
; the result text drawn directly on top of the frozen final trail
; positions. No full clear -- draws straight into whatever is already in
; the arena. A (or space) returns to the title screen, where
; DrawTitleScreen's own full wipe takes over.
; Erases a margin around its own text first, though (unlike the rest of
; the frozen field, which is deliberately left alone) -- the result text
; lands wherever the round happened to end, maybe right across a trail.
; The erase box is padded well past the glyphs themselves (not just their
; tight bounding box) so the text reads as sitting in its own clear space
; instead of packed right up against whatever trail happened to end nearby.
; Vertically centered on the 192px-tall field (row 93, so the 7px-tall
; glyphs sit on rows 93-99, centered on row 96) rather than a fixed row
; that happened to work for one particular round's trail shapes.
; Hides both head sprites first -- the frozen trails are deliberate,
; but the crash never reaches UpdateHeadSprites's "both alive" branch
; (see ResolveRound), so without this a dead player's sprite is left
; showing at its last pre-crash position instead of hidden, floating
; uselessly next to the actual crash site drawn in the arena.
; -----------------------------------------------------------------------------
DrawGameOverScreen:
  jsr InitHeadSprites

  lda ROUND_RESULT
  cmp #3
  bcc @winner
  ldx #<WinnerDraw
  ldy #>WinnerDraw
  cmp #3
  beq @haveWinner
  ldx #<TxtOutOfSync             ; RESULT_SYNC: two linked machines disagreed
  ldy #>TxtOutOfSync
  bra @haveWinner
@winner:
  ldx GAME_MODE
  cpx #MODE_LINK
  beq @link
  ldx #<WinnerP1
  ldy #>WinnerP1
  cmp #1
  beq @haveWinner
  ldx #<WinnerP2
  ldy #>WinnerP2
  bra @haveWinner
@link:
  sec                             ; the winner's seat is ROUND_RESULT - 1
  sbc #1
  ldx #<TxtYouWin
  ldy #>TxtYouWin
  cmp MY_SEAT
  beq @haveWinner
  ldx #<TxtYouLose
  ldy #>TxtYouLose
@haveWinner:
  phx
  phy

  lda #19                   ; 7px glyph height + 6px margin top/bottom
  sta TEXT_ROW_I
  lda #98                   ; 78px longest string ("PLAYER 1/2 WINS", 13
  sta TEXT_COL_I              ; chars x 6px) + 10px margin each side
  lda #87
  ldx #79
  jsr EraseRect

  ply
  plx
  lda #93
  jsr CenterText
  ; falls through

; RoundSting - the win sting when a person at this machine won the round, the
; draw's otherwise: a double crash, the CPU winning, or the other machine's
; player in a link.
RoundSting:
  lda ROUND_RESULT
  cmp #1
  beq @first
  cmp #2
  bne @draw
  lda GAME_MODE                   ; the second rider won
  cmp #MODE_1P
  beq @draw
  cmp #MODE_LINK
  bne @win
  lda MY_SEAT
  bne @win
  bra @draw
@first:
  lda GAME_MODE
  cmp #MODE_LINK
  bne @win
  lda MY_SEAT
  beq @win
@draw:
  jmp SndDraw
@win:
  jmp SndWin

; CenterText - the string X (low), Y (high) in white on row A, centered
; across the screen. Clobbers what DrawText does.
CenterText:
  sta TEXT_ROW
  stx TEXT_STR_PTR
  sty TEXT_STR_PTR+1
  ldy #0
@len:
  lda (TEXT_STR_PTR),y
  beq @counted
  iny
  bra @len
@counted:
  sty TEXT_COL                    ; 6 pixels a character: start half of
  tya                             ; that left of the middle
  asl a
  clc
  adc TEXT_COL
  sta TEXT_COL
  lda #128
  sec
  sbc TEXT_COL
  sta TEXT_COL
  lda #TMS_WHITE
  sta TEXT_COLOR
  jmp DrawText

; -----------------------------------------------------------------------------
; The title's menu: MODE, SPEED and each player's color, one to a line.
; Up and down (either stick, W/S or the arrows) move the arrows from line to
; line; left and right change the line they're on. A color shows as a swatch
; drawn in that player's value, so a new pick recolors it through the palette
; with nothing to redraw.
; -----------------------------------------------------------------------------
MENU_LABEL_END = 128              ; the labels end here
MENU_VALUE     = 140              ; and the values start here
MENU_WIDTH     = 36               ; the widest value, NORMAL
MENU_LEFT      = 134              ; the arrows' columns
MENU_RIGHT     = MENU_VALUE + MENU_WIDTH + 3

MenuRowY:
  .byte 90, 101, 112, 123
MenuLabels:
  .word ModeLabel, SpeedLabel, P1ColorLabel, P2ColorLabel
ModeNames:
  .word Mode1P, Mode2P, ModeLink
SpeedNames:
  .word SpeedSlow, SpeedNormal, SpeedFast
DirBits:                          ; DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT
  .byte JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT

; DrawMenu - every line, and the arrows on MENU_ROW.
DrawMenu:
  ldx #0
@line:
  phx
  txa
  asl a
  tay
  lda MenuLabels,y
  sta TEXT_STR_PTR
  lda MenuLabels+1,y
  sta TEXT_STR_PTR+1
  jsr TextLength                  ; right-aligned to MENU_LABEL_END
  sta TEXT_COL
  asl a
  clc
  adc TEXT_COL
  asl a                           ; 6 pixels a character
  eor #$FF
  sec
  adc #MENU_LABEL_END
  sta TEXT_COL
  lda MenuRowY,x
  sta TEXT_ROW
  lda #TMS_WHITE
  sta TEXT_COLOR
  jsr DrawText
  pla
  pha
  jsr DrawValue
  plx
  inx
  cpx #MENU_ROWS
  bne @line
  lda MENU_ROW
  jmp ShowArrows

; TextLength - A = the length of the string at TEXT_STR_PTR. Keeps X.
TextLength:
  ldy #0
@char:
  lda (TEXT_STR_PTR),y
  beq @done
  iny
  bra @char
@done:
  tya
  rts

; DrawValue - line A's value, over whatever was there.
DrawValue:
  pha
  tax
  lda MenuRowY,x
  sta TEXT_ROW
  lda #7
  sta TEXT_ROW_I
  lda #MENU_WIDTH
  sta TEXT_COL_I
  lda TEXT_ROW
  ldx #MENU_VALUE
  jsr EraseRect
  pla
  cmp #MENU_P1
  bcs @swatch
  ldx GAME_MODE
  cmp #MENU_MODE
  beq @name
  ldx SPEED
  txa
  asl a
  tay
  lda SpeedNames,y
  sta TEXT_STR_PTR
  lda SpeedNames+1,y
  bra @text
@name:
  txa
  asl a
  tay
  lda ModeNames,y
  sta TEXT_STR_PTR
  lda ModeNames+1,y
@text:
  sta TEXT_STR_PTR+1
  lda #MENU_VALUE
  sta TEXT_COL
  lda #TMS_WHITE
  sta TEXT_COLOR
  jmp DrawText
@swatch:
  ldy P1_TRAIL_COLOR
  cmp #MENU_P1
  beq @drawSwatch
  ldy P2_TRAIL_COLOR
@drawSwatch:
  lda TEXT_ROW
  ldx #MENU_VALUE
  jmp DrawColorSwatch

; ShowArrows / HideArrows - the left and right arrows either side of line A's
; value.
ShowArrows:
  tax
  lda MenuRowY,x
  inc a
  pha
  ldx #MENU_LEFT
  ldy #TMS_WHITE
  jsr DrawLeftTriangle
  pla
  ldx #MENU_RIGHT
  ldy #TMS_WHITE
  jmp DrawRightTriangle

HideArrows:
  tax
  lda MenuRowY,x
  inc a
  pha
  lda #5
  sta TEXT_ROW_I
  lda #3
  sta TEXT_COL_I
  pla
  pha
  ldx #MENU_LEFT
  jsr EraseRect
  lda #5
  sta TEXT_ROW_I
  lda #3
  sta TEXT_COL_I
  pla
  ldx #MENU_RIGHT
  jmp EraseRect

; MenuInput - a step for each new press of up, down, left or right on either
; stick or key cluster.
MenuInput:
  lda JOY_STATE                   ; active low: held on either stick
  and JOY_STATE2
  eor #$FF
  and #(JOY_UP | JOY_DOWN | JOY_LEFT | JOY_RIGHT)
  sta PICKER_TMP
  ldx KB_DIR_P1                   ; and keys seen this tick
  jsr KeyBit
  ldx KB_DIR_P2
  jsr KeyBit
  lda MENU_PREV                   ; only what wasn't held last tick
  eor #$FF
  and PICKER_TMP
  ldx PICKER_TMP
  stx MENU_PREV
  bit #JOY_UP
  bne @up
  bit #JOY_DOWN
  bne @down
  bit #JOY_LEFT
  bne @left
  bit #JOY_RIGHT
  bne @right
  rts
@up:
  lda MENU_ROW
  jsr HideArrows
  dec MENU_ROW
  bpl @moved
  lda #MENU_ROWS - 1
  sta MENU_ROW
  bra @moved
@down:
  lda MENU_ROW
  jsr HideArrows
  inc MENU_ROW
  lda MENU_ROW
  cmp #MENU_ROWS
  bcc @moved
  stz MENU_ROW
@moved:
  jsr SndSelect
  lda MENU_ROW
  jmp ShowArrows
@left:
  lda MENU_ROW
  cmp #MENU_P1
  bne @notP1Left
  jmp DecP1Color
@notP1Left:
  cmp #MENU_P2
  bne @notP2Left
  jmp DecP2Color
@notP2Left:
  lda #$FF                        ; one back
  bra @change
@right:
  lda MENU_ROW
  cmp #MENU_P1
  bne @notP1Right
  jmp IncP1Color
@notP1Right:
  cmp #MENU_P2
  bne @notP2Right
  jmp IncP2Color
@notP2Right:
  lda #1                          ; one on
@change:
  ldx MENU_ROW                    ; MODE or SPEED, three choices each, round
  bne @speed
  clc
  adc GAME_MODE
  jsr Wrap3
  sta GAME_MODE
  bra @changed
@speed:
  clc
  adc SPEED
  jsr Wrap3
  sta SPEED
@changed:
  jsr SndSelect
  lda MENU_ROW
  jmp DrawValue

; Wrap3 - A, one past either end of 0-2, back round.
Wrap3:
  bpl @notUnder
  lda #2
  rts
@notUnder:
  cmp #3
  bcc @done
  lda #0
@done:
  rts

; KeyBit - the joystick bit for key direction X (a DIR_*, or KB_DIR_NONE) into
; PICKER_TMP.
KeyBit:
  cpx #KB_DIR_NONE
  beq @none
  lda DirBits,x
  ora PICKER_TMP
  sta PICKER_TMP
@none:
  rts

; -----------------------------------------------------------------------------
; IncP1Color/DecP1Color/IncP2Color/DecP2Color - cycle a player's trail
; color index, skipping past whatever the OTHER player currently has
; selected. Same-colored trails are only distinguishable by the head
; sprites (both flat white, independent of trail color), not by the
; trail itself, so letting both players land on the same color is a real
; way to confuse yourself for no benefit -- worth blocking outright rather
; than leaving it as a footgun, since 6 of 7 colors are still available
; either way. Only ever skips one extra step: landing on a clash after a
; single +1/-1 move can only happen once before moving away from it.
; -----------------------------------------------------------------------------
IncP1Color:
  jsr SndSelect
  lda P1_COLOR_IDX
  cmp #6
  bne @p1Inc
  stz P1_COLOR_IDX
  bra @p1Clash
@p1Inc:
  inc P1_COLOR_IDX
@p1Clash:
  lda P1_COLOR_IDX
  cmp P2_COLOR_IDX
  bne @p1Done
  lda P1_COLOR_IDX
  cmp #6
  bne @p1Inc2
  stz P1_COLOR_IDX
  jmp ApplySelectedTrailColors
@p1Inc2:
  inc P1_COLOR_IDX
@p1Done:
  jmp ApplySelectedTrailColors

DecP1Color:
  jsr SndSelect
  lda P1_COLOR_IDX
  bne @p1Dec
  lda #6
  sta P1_COLOR_IDX
  bra @p1Clash
@p1Dec:
  dec P1_COLOR_IDX
@p1Clash:
  lda P1_COLOR_IDX
  cmp P2_COLOR_IDX
  bne @p1Done
  lda P1_COLOR_IDX
  bne @p1Dec2
  lda #6
  sta P1_COLOR_IDX
  jmp ApplySelectedTrailColors
@p1Dec2:
  dec P1_COLOR_IDX
@p1Done:
  jmp ApplySelectedTrailColors

IncP2Color:
  jsr SndSelect
  lda P2_COLOR_IDX
  cmp #6
  bne @p2Inc
  stz P2_COLOR_IDX
  bra @p2Clash
@p2Inc:
  inc P2_COLOR_IDX
@p2Clash:
  lda P2_COLOR_IDX
  cmp P1_COLOR_IDX
  bne @p2Done
  lda P2_COLOR_IDX
  cmp #6
  bne @p2Inc2
  stz P2_COLOR_IDX
  jmp ApplySelectedTrailColors
@p2Inc2:
  inc P2_COLOR_IDX
@p2Done:
  jmp ApplySelectedTrailColors

DecP2Color:
  jsr SndSelect
  lda P2_COLOR_IDX
  bne @p2Dec
  lda #6
  sta P2_COLOR_IDX
  bra @p2Clash
@p2Dec:
  dec P2_COLOR_IDX
@p2Clash:
  lda P2_COLOR_IDX
  cmp P1_COLOR_IDX
  bne @p2Done
  lda P2_COLOR_IDX
  bne @p2Dec2
  lda #6
  sta P2_COLOR_IDX
  jmp ApplySelectedTrailColors
@p2Dec2:
  dec P2_COLOR_IDX
@p2Done:
  jmp ApplySelectedTrailColors

ApplySelectedTrailColors:
  ldx P1_COLOR_IDX
  lda TrailFgColorTable,x
  sta P1_TRAIL_COLOR

  ldx P2_COLOR_IDX
  lda TrailFgColorTable,x
  sta P2_TRAIL_COLOR
  jmp SetPalette

TitleLine1:
  .byte "TRAIL DUEL",0

TitleLine4:
  .byte "A: START",0

WinnerP1:
  .byte "PLAYER 1 WINS",0

WinnerP2:
  .byte "PLAYER 2 WINS",0

WinnerDraw:
  .byte "DOUBLE CRASH",0

ModeLabel:
  .byte "MODE:",0
SpeedLabel:
  .byte "SPEED:",0
Mode1P:
  .byte "1P",0
Mode2P:
  .byte "2P",0
ModeLink:
  .byte "LINK",0
SpeedSlow:
  .byte "SLOW",0
SpeedNormal:
  .byte "NORMAL",0
SpeedFast:
  .byte "FAST",0

TxtYouWin:
  .byte "YOU WIN",0

TxtYouLose:
  .byte "YOU LOSE",0

TxtOutOfSync:
  .byte "OUT OF SYNC",0

P1ColorLabel:
  .byte "P1:",0

P2ColorLabel:
  .byte "P2:",0

; One saturated, vivid shade per hue -- rendered every candidate shade to
; the screen and looked at them side by side rather than going by name.
; Result: for red and yellow specifically, the "light" tier is the pastel
; one (salmon, pale khaki) and the "medium"/"dark" tier is the more vivid,
; saturated look (true red, golden yellow) -- backwards from what the
; names suggest. Blue's the exception: LT_BLUE reads as a rich periwinkle,
; not pastel, so it stays over DK_BLUE. Green only offers MED_GREEN as the
; vivid pick over the minty LT_GREEN. CYAN and MAGENTA only come in one
; (already vivid) shade. GRAY rounds it out as a neutral -- WHITE was
; considered too, but it's close enough to GRAY to not read as a distinct
; option, and would've meant the lead pixel/head sprite (both hardcoded
; white) blending into that one trail color instead of standing out.
TrailFgColorTable:
  .byte TMS_MED_RED, TMS_DK_YELLOW, TMS_MED_GREEN, TMS_CYAN, TMS_LT_BLUE, TMS_MAGENTA, TMS_GRAY

; -----------------------------------------------------------------------------
; ApplyRequestedTurns - each rider takes the heading asked for at once, unless
; it's straight back the way it came (DIR_UP/DIR_DOWN and DIR_LEFT/DIR_RIGHT
; differ only in bit 0). A person's turn blips; the CPU's doesn't.
; -----------------------------------------------------------------------------
ApplyRequestedTurns:
  lda P1_DIR
  eor #1                          ; straight back
  cmp P1_NEXT_DIR
  beq @p2
  lda P1_NEXT_DIR
  cmp P1_DIR
  beq @p2
  sta P1_DIR
  jsr SndTurn
@p2:
  lda P2_DIR
  eor #1
  cmp P2_NEXT_DIR
  beq @done
  lda P2_NEXT_DIR
  cmp P2_DIR
  beq @done
  sta P2_DIR
  lda GAME_MODE
  cmp #MODE_1P
  beq @done                       ; the CPU turns quietly
  jsr SndTurn
@done:
  rts

; -----------------------------------------------------------------------------
; ComputeP2LeftTurn / ComputeP2RightTurn -- the 90-degree turn-candidate
; tables, factored out so ComputeP2AIDirection can try them in either
; order (see the coin flip there). In: P2_DIR. Out: A = the candidate
; direction for that turn from the current heading.
;
; Each case returns immediately after its lda instead of falling through
; to a shared exit via bne. The old inline right-turn table used that
; fall-through idiom and it broke for DIR_UP, which is 0: "lda #DIR_UP /
; bne @rightReady" never branches when A is 0, so the LEFT-heading case
; silently fell through into DIR_DOWN instead of DIR_UP -- P2 never even
; tried its "up" escape when heading left. Returning per-case avoids that
; class of bug rather than reproducing it here.
; -----------------------------------------------------------------------------
ComputeP2LeftTurn:
  lda P2_DIR
  cmp #DIR_UP
  bne @lNotUp
  lda #DIR_LEFT
  rts
@lNotUp:
  lda P2_DIR
  cmp #DIR_DOWN
  bne @lNotDown
  lda #DIR_RIGHT
  rts
@lNotDown:
  lda P2_DIR
  cmp #DIR_LEFT
  bne @lNotLeft
  lda #DIR_DOWN
  rts
@lNotLeft:
  lda #DIR_UP
  rts

ComputeP2RightTurn:
  lda P2_DIR
  cmp #DIR_UP
  bne @rNotUp
  lda #DIR_RIGHT
  rts
@rNotUp:
  lda P2_DIR
  cmp #DIR_DOWN
  bne @rNotDown
  lda #DIR_LEFT
  rts
@rNotDown:
  lda P2_DIR
  cmp #DIR_LEFT
  bne @rNotLeft
  lda #DIR_UP
  rts
@rNotLeft:
  lda #DIR_DOWN
  rts

; -----------------------------------------------------------------------------
; DirTowardP1 -- which of the two directions perpendicular to P2's
; CURRENT heading closes the distance to P1 on the axis that matters.
; P2_DIR horizontal -> compares Y (result is DIR_UP/DIR_DOWN). P2_DIR
; vertical -> compares X (result is DIR_LEFT/DIR_RIGHT). Out: A = that
; direction, or $FF if P1 is exactly level with P2 on that axis (no
; preference either way).
; -----------------------------------------------------------------------------
DirTowardP1:
  lda P2_DIR
  cmp #DIR_LEFT
  beq @axisIsY
  cmp #DIR_RIGHT
  beq @axisIsY

  ; P2 currently vertical -- compare X, all 9 bits.
  lda P1_X
  cmp P2_X
  bne @xDiffer
  lda P1_XH
  cmp P2_XH
  beq @tied
@xDiffer:
  lda P1_X
  cmp P2_X
  lda P1_XH
  sbc P2_XH
  bcc @wantLeft
  lda #DIR_RIGHT
  rts
@wantLeft:
  lda #DIR_LEFT
  rts

@axisIsY:
  ; P2 currently horizontal -- compare Y.
  lda P1_Y
  cmp P2_Y
  beq @tied
  bcc @wantUp
  lda #DIR_DOWN
  rts
@wantUp:
  lda #DIR_UP
  rts

@tied:
  lda #$FF
  rts

; -----------------------------------------------------------------------------
; ComputeP2AIDirection -- picks P2_NEXT_DIR from three candidates:
; continue straight, turn left, turn right.
;
; Continuing straight is preferred whenever it's safe -- but not
; absolutely: about 1 time in 16, even a safe straight run gets
; second-guessed and a turn is looked for anyway. Without this, P2 was a
; pure wall-follower that never changed course unless a wall forced it
; to, which is exactly what made it feel predictable and never actually
; came at P1 -- it only ever reacted to geometry, never to the other
; player.
;
; When a turn IS being considered (forced or not), left and right used
; to be a flat coin flip. Now DirTowardP1 picks whichever turn actually
; closes the distance to P1 on the relevant axis, and that's preferred
; about 3 times out of 4 -- not always, since an AI that beelines for
; the player with zero variance is its own kind of predictable, and the
; remaining 1-in-4 (or ties, where neither side is objectively better)
; falls back to the old plain coin flip.
; -----------------------------------------------------------------------------
ComputeP2AIDirection:
  lda P2_DIR
  sta AI_DIR_TMP
  jsr IsDirectionSafeP2
  bcc @pickTurn

  ; Continuing straight is safe -- usually just take it, but roll a
  ; small chance to look for a turn anyway.
  jsr AdvanceRng
  and #$0F
  bne @keepCurrent

@pickTurn:
  jsr DirTowardP1
  sta AI_PREFERRED_DIR
  cmp #$FF
  beq @coinFlip
  jsr AdvanceRng
  and #3
  cmp #3
  beq @coinFlip
  jsr ComputeP2LeftTurn
  cmp AI_PREFERRED_DIR
  beq @tryLeftFirst
  jmp @tryRightFirst

@coinFlip:
  jsr AdvanceRng
  lsr a
  bcs @tryRightFirst

@tryLeftFirst:
  jsr ComputeP2LeftTurn
  sta AI_DIR_TMP
  jsr IsDirectionSafeP2
  bcs @useAiDir
  jsr ComputeP2RightTurn
  sta AI_DIR_TMP
  jsr IsDirectionSafeP2
  bcs @useAiDir
  jmp @noSafeTurn

@tryRightFirst:
  jsr ComputeP2RightTurn
  sta AI_DIR_TMP
  jsr IsDirectionSafeP2
  bcs @useAiDir
  jsr ComputeP2LeftTurn
  sta AI_DIR_TMP
  jsr IsDirectionSafeP2
  bcs @useAiDir

@noSafeTurn:
  ; No safe turn found: keep current.
  lda P2_DIR
  sta P2_NEXT_DIR
  rts

@keepCurrent:
  lda P2_DIR
  sta P2_NEXT_DIR
  rts

@useAiDir:
  lda AI_DIR_TMP
  sta P2_NEXT_DIR
  rts

; -----------------------------------------------------------------------------
; IsDirectionSafeP2 - In: AI_DIR_TMP = candidate direction, from P2_X/P2_Y.
; Out: carry set if safe, clear if not.
; A turn is checked one pixel ahead. Carrying straight on is checked 8 pixels
; ahead, so the CPU looks for a way out while there's still room to turn,
; rather than twitching away a pixel from the wall, and does so the same on
; either axis.
; -----------------------------------------------------------------------------
IsDirectionSafeP2:
  lda P2_X
  sta AI_TEST_X
  lda P2_XH
  sta AI_TEST_XH
  lda P2_Y
  sta AI_TEST_Y
  lda #1
  ldx AI_DIR_TMP
  cpx P2_DIR
  bne @steps
  lda #8
@steps:
  sta SCAN_TMP2
@step:
  lda AI_DIR_TMP
  jsr StepTest
  lda AI_TEST_Y
  cmp #240                        ; past the top wraps round to here too
  bcs @blocked
  ldx AI_TEST_XH
  stx PX_HI
  ldx AI_TEST_X
  jsr PixelIsSet
  bne @blocked
  dec SCAN_TMP2
  bne @step
  sec
  rts
@blocked:
  clc
  rts

; StepTest - AI_TEST_X/AI_TEST_Y a pixel on in direction A (x with its
; bit 8 in AI_TEST_XH).
StepTest:
  cmp #DIR_UP
  bne @notUp
  dec AI_TEST_Y
  rts
@notUp:
  cmp #DIR_DOWN
  bne @notDown
  inc AI_TEST_Y
  rts
@notDown:
  cmp #DIR_LEFT
  bne @right
  lda AI_TEST_X
  bne @lowLeft
  dec AI_TEST_XH
@lowLeft:
  dec AI_TEST_X
  rts
@right:
  inc AI_TEST_X
  bne @done
  inc AI_TEST_XH
@done:
  rts

ComputeNextPositions:
  lda P1_X
  sta P1_NEXT_X
  lda P1_XH
  sta P1_NEXT_XH
  lda P1_Y
  sta P1_NEXT_Y

  lda P1_DIR
  cmp #DIR_UP
  bne @p1NotUp
  dec P1_NEXT_Y
@p1NotUp:
  lda P1_DIR
  cmp #DIR_DOWN
  bne @p1NotDown
  inc P1_NEXT_Y
@p1NotDown:
  lda P1_DIR
  cmp #DIR_LEFT
  bne @p1NotLeft
  lda P1_NEXT_X
  bne @p1Low
  dec P1_NEXT_XH
@p1Low:
  dec P1_NEXT_X
@p1NotLeft:
  lda P1_DIR
  cmp #DIR_RIGHT
  bne @p1Done
  inc P1_NEXT_X
  bne @p1Done
  inc P1_NEXT_XH
@p1Done:

  lda P2_X
  sta P2_NEXT_X
  lda P2_XH
  sta P2_NEXT_XH
  lda P2_Y
  sta P2_NEXT_Y

  lda P2_DIR
  cmp #DIR_UP
  bne @p2NotUp
  dec P2_NEXT_Y
@p2NotUp:
  lda P2_DIR
  cmp #DIR_DOWN
  bne @p2NotDown
  inc P2_NEXT_Y
@p2NotDown:
  lda P2_DIR
  cmp #DIR_LEFT
  bne @p2NotLeft
  lda P2_NEXT_X
  bne @p2Low
  dec P2_NEXT_XH
@p2Low:
  dec P2_NEXT_X
@p2NotLeft:
  lda P2_DIR
  cmp #DIR_RIGHT
  bne @p2Done
  inc P2_NEXT_X
  bne @p2Done
  inc P2_NEXT_XH
@p2Done:
  rts

CommitP1Move:
  lda P1_NEXT_X
  sta P1_X
  lda P1_NEXT_XH
  sta P1_XH
  sta PX_HI
  lda P1_NEXT_Y
  sta P1_Y
  ldx P1_X
  jmp PixelSetP1Trail

CommitP2Move:
  lda P2_NEXT_X
  sta P2_X
  lda P2_NEXT_XH
  sta P2_XH
  sta PX_HI
  lda P2_NEXT_Y
  sta P2_Y
  ldx P2_X
  jmp PixelSetP2Trail
