; =============================================================================
;   input.asm - TrailDuel input shim using 6502-Lib polling
; =============================================================================
;   Joystick-first, keyboard-fallback: PollInput reads both joystick ports
;   via 6502-Lib's PollJoy1/PollJoy2 and drains the keyboard once a tick;
;   each player then takes their own stick's direction, falling back to the
;   keyboard split (WASD=P1, arrows=P2) only when that stick shows no
;   direction at all this poll (including when no GPIO card is fitted).
;   PollInputP2, which runs after PollInput in MainLoop, reuses the same
;   reads rather than draining an already-empty Chrin buffer.
;
;   A bike always advances forward every tick regardless of input - turning
;   is a discrete heading change, not something that needs to be held to
;   keep moving - so unlike Pong's paddles, no hold/decay layer is needed
;   here: DrainKeyboardSplit's per-tick "last direction seen" result is the
;   same sticky-until-changed semantics the joystick-only code already had.
; =============================================================================

.include "../../6502-Lib/include/input.inc"
.include "../../6502-Lib/core/input.asm"

; -----------------------------------------------------------------------------
; PollInput - P1: joystick 1 first, WASD fallback when idle. Also reads
; joystick 2 and drains the keyboard (once, for both players), and ORs A on
; either joystick, space or enter into START_PRESSED, independent of the
; direction priority.
; -----------------------------------------------------------------------------
PollInput:
	stz START_PRESSED

	jsr PollJoy1
	jsr PollJoy2
	jsr DrainKeyboardSplit

	lda JOY_STATE
	and #(JOY_UP | JOY_DOWN | JOY_LEFT | JOY_RIGHT)
	cmp #(JOY_UP | JOY_DOWN | JOY_LEFT | JOY_RIGHT)
	beq @kbDir                ; joystick idle on all 4 directions -> fallback

	lda JOY_STATE
	and #JOY_UP
	bne @jNotUp
	lda #DIR_UP
	sta NEXT_DIR
@jNotUp:
	lda JOY_STATE
	and #JOY_DOWN
	bne @jNotDown
	lda #DIR_DOWN
	sta NEXT_DIR
@jNotDown:
	lda JOY_STATE
	and #JOY_LEFT
	bne @jNotLeft
	lda #DIR_LEFT
	sta NEXT_DIR
@jNotLeft:
	lda JOY_STATE
	and #JOY_RIGHT
	bne @jNotRight
	lda #DIR_RIGHT
	sta NEXT_DIR
@jNotRight:
	jmp @doneDir

@kbDir:
	lda KB_DIR_P1
	cmp #KB_DIR_NONE
	beq @doneDir
	sta NEXT_DIR
@doneDir:

	; Fire/A: OR'd independently of direction priority - A held on either
	; joystick, or space or enter seen this drain, sets START_PRESSED.
	lda JOY_STATE
	and JOY_STATE2                ; active low: pressed on either stick
	and #JOY_A
	bne @checkKbFire
	lda #1
	sta START_PRESSED
	jmp @doneFire
@checkKbFire:
	lda KB_FIRE
	beq @doneFire
	lda #1
	sta START_PRESSED
@doneFire:

	lda #$00
	sta FIRE_EDGE
	lda PREV_FIRE
	bne @noEdge
	lda START_PRESSED
	beq @noEdge
	inc FIRE_EDGE
@noEdge:
	lda START_PRESSED
	sta PREV_FIRE
	rts

; -----------------------------------------------------------------------------
; PollInputP2 - P2: joystick 2 first (read by PollInput), arrow-key fallback
; when idle. Always run, whatever GAME_MODE says: on the title screen GAME_MODE
; is only the mode picked so far, and MenuInput reads
; player 2's stick there too. During 1P play ComputeP2AIDirection overwrites
; P2_NEXT_DIR right after this on every path, so a stick in port 2 can't steer
; the CPU.
; -----------------------------------------------------------------------------
PollInputP2:
	lda JOY_STATE2
	and #(JOY_UP | JOY_DOWN | JOY_LEFT | JOY_RIGHT)
	cmp #(JOY_UP | JOY_DOWN | JOY_LEFT | JOY_RIGHT)
	beq @kbDir                ; joystick idle on all 4 directions -> fallback

	lda JOY_STATE2
	and #JOY_UP
	bne @notUp
	lda #DIR_UP
	sta P2_NEXT_DIR
@notUp:
	lda JOY_STATE2
	and #JOY_DOWN
	bne @notDown
	lda #DIR_DOWN
	sta P2_NEXT_DIR
@notDown:
	lda JOY_STATE2
	and #JOY_LEFT
	bne @notLeft
	lda #DIR_LEFT
	sta P2_NEXT_DIR
@notLeft:
	lda JOY_STATE2
	and #JOY_RIGHT
	bne @done
	lda #DIR_RIGHT
	sta P2_NEXT_DIR
	rts

@kbDir:
	lda KB_DIR_P2
	cmp #KB_DIR_NONE
	beq @done
	sta P2_NEXT_DIR
@done:
	rts
