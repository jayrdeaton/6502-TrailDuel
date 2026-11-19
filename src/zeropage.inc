; =============================================================================
;   zeropage.inc - initial zero-page layout for TrailDuel
; =============================================================================

STATE_TITLE     = 0
STATE_PLAYING   = 1
STATE_ROUNDOVER = 2
STATE_GAMEOVER  = 3
STATE_PAUSED    = 4
STATE_LINKING   = 5             ; looking for the other machine (link.asm)

DIR_UP          = 0
DIR_DOWN        = 1
DIR_LEFT        = 2
DIR_RIGHT       = 3

MODE_1P         = 0
MODE_2P         = 1
MODE_LINK       = 2

TICK_FRAMES     = 5             ; a tick every 5 pictures off a round (the
                                ; title, the end of a round, linking); a
                                ; round's own pace is SPEED's

GAME_STATE      := $3A
GAME_MODE       := $3B
RNG_STATE       := $3C
TICK_COUNTER    := $3D
JOY_STATE       := $3E
PREV_FIRE       := $3F
START_PRESSED   := $4C
FIRE_EDGE       := $4D

P1_X            := $40
P1_Y            := $41
P1_DIR          := $42
P1_NEXT_DIR     := $43
P1_ALIVE        := $44
NEXT_DIR        := P1_NEXT_DIR

P2_X            := $45
P2_Y            := $46
P2_DIR          := $47
P2_NEXT_DIR     := $48
P2_ALIVE        := $49

P1_SCORE        := $4A
P2_SCORE        := $4B

JOY_STATE2      := $4F

OFFSET_LO       := $50
OFFSET_HI       := $51
WORK_PTR        := $52
STR_IDX         := $54
SCAN_TMP        := $55
P1_NEXT_X       := $56
P1_NEXT_Y       := $57
P2_NEXT_X       := $58
P2_NEXT_Y       := $59
AI_DIR_TMP      := $5A
AI_TEST_X       := $5B
AI_TEST_Y       := $5C
HUD_COL         := $5D
MSG_ROW         := $5E
NUM_TMP         := $5F
DIGIT_TMP       := $60
ROUND_RESULT    := $61
P1_COLOR_IDX    := $62
P2_COLOR_IDX    := $63
P1_TRAIL_COLOR  := $64
P2_TRAIL_COLOR  := $65
MENU_P1_PREV    := $66
MENU_P2_PREV    := $67

KB_DIR_P1       := $68   ; DrainKeyboardSplit output: WASD direction (P1)
KB_DIR_P2       := $69   ; DrainKeyboardSplit output: arrow-key direction (P2)
KB_FIRE         := $6A   ; DrainKeyboardSplit output: 1 if either fire key seen
                          ; this call - the byte TrailDuel actually reads,
                          ; since START/pause is one shared action here, not
                          ; per-player
PICKER_TMP      := $6B   ; HandleColorPicker scratch: effective LEFT/RIGHT byte
KB_DIR          := $6C   ; unused output of DrainKeyboardCombined - TrailDuel
                          ; calls DrainKeyboardSplit, not Combined, but the
                          ; library assembles as one unit so KB_DIR must still
                          ; resolve to something
KB_FIRE_P1      := $6D   ; DrainKeyboardSplit output: space seen this call.
                          ; Unused by TrailDuel (no per-player fire action)
                          ; but must resolve to something for the same reason
                          ; as KB_DIR above.
KB_FIRE_P2      := $6E   ; DrainKeyboardSplit output: enter seen this call.
                          ; Unused by TrailDuel, same reason as KB_FIRE_P1.

; --- Text, drawn into the arena a pixel at a time (src/font.asm, DrawChar/DrawText in vdp.asm) ---
TEXT_ROW        := $6F   ; caller-set: top-left Y pixel origin
TEXT_COL        := $70   ; caller-set: top-left X pixel origin (DrawText
                          ; advances this past each character it draws)
TEXT_COLOR      := $71   ; caller-set: TMS_* color for the glyph's pixels
FONT_PTR        := $72   ; 2 bytes, $72-$73: scratch pointer into FontData
FONT_TMP        := $74   ; scratch: char*5 multiply, then each glyph column's
                          ; row-bits (bit0=top row .. bit6=bottom row)
TEXT_ROW_I      := $75   ; scratch: glyph row loop counter, 0-6
TEXT_COL_I      := $76   ; scratch: glyph column loop counter, 0-4
SCAN_TMP2       := $77   ; scratch: second loop counter (DrawColorSwatch's
                          ; origin col; SCAN_TMP alone was already taken)
FONT_HI         := $7A   ; scratch: overflow bit (0 or 1) from DrawChar's
                          ; index*5 multiply, propagated into FONT_PTR's
                          ; high byte -- (char-$20)*5 can reach 290, past
                          ; what one 8-bit add tracks by itself
TEXT_STR_PTR    := $78   ; 2 bytes, $78-$79: DrawText's string pointer --
                          ; deliberately NOT WORK_PTR, since DrawChar calls
                          ; down into PixelSet/ComputePixelAddress, which
                          ; clobbers WORK_PTR for its own shadow-buffer
                          ; addressing on every single pixel plotted

; DrawModeLine/DrawColorLines run every tick on the title screen, but
; should only erase-and-redraw when the value actually changed -- doing
; it unconditionally every tick flickers, since each redraw has to erase
; first (PixelSet only ever turns pixels on). $FF is an impossible value
; for any of these (GAME_MODE is 0/1, a color index is 0-6), so
; DrawTitleScreen resets them to $FF on a fresh entry to force that
; first draw regardless of what the mode/colors happened to be last time.
LAST_GAME_MODE   := $7B
LAST_P1_COLOR_IDX := $7C
LAST_P2_COLOR_IDX := $7D

; SetModeFromInput debounce: MODE now toggles on an UP/DOWN edge (either
; player) instead of a fixed up=1P/down=2P mapping, so it needs the same
; "already acted on this press, wait for release" latch MENU_P1_PREV/
; MENU_P2_PREV use for the color pickers.
MENU_MODE_PREV  := $80

; ComputeP2AIDirection scratch: which perpendicular direction currently
; closes the distance to P1 (DIR_UP/DOWN/LEFT/RIGHT), or $FF if P1 is
; exactly level on the axis that matters (no preference).
AI_PREFERRED_DIR := $81

; vdp.asm: which 16 KB of video memory port A reaches now, a VRAM address, and
; FillLayers' place in the layers' tables
VBANK_NOW       := $82
VADDR           := $83   ; 2 bytes, $83-$84
FL_LAYER        := $85
FL_PASS         := $86
FL_ROW          := $87
FL_COL          := $88
FL_TILE         := $89   ; 2 bytes, $89-$8A

; The arena's tiles in RAM, as the card has them (see vdp.asm): 988 tiles of
; 16 bytes, $2000-$5DBF
SHADOW          = $2000

; link.asm: two machines over the serial port
LINK_ON         := $8B   ; the serial port is ours
LINK_UP         := $8C   ; both machines found, the round under way
LINK_BAD        := $8D   ; why the link can't go on (BAD_*), or 0
LINK_SHOWN      := $8E   ; the LINK_BAD the linking screen shows
HAVE_HELLO      := $8F   ; heard the other machine
PEER_HAS        := $90   ; it has heard this one
MY_SEAT         := $91   ; 0 the left rider, 1 the right
MY_NONCE        := $92   ; 2 bytes, $92-$93
PEER_NONCE      := $94   ; 2 bytes, $94-$95
MY_COLOR        := $96   ; this machine's color pick, and the other's
PEER_COLOR      := $97
SESSION         := $98   ; the pairing a round's INPUT frames belong to
LT              := $99   ; the round's tick
MY_LAST         := $9A   ; the latest tick this machine has a heading for
PEER_LAST       := $9B   ; the latest tick it has the other's heading for
SAMPLED         := $9C   ; this tick's heading taken and sent
LOCAL_DIR       := $9D   ; this machine's player's heading, held
LINK_T          := $9E   ; frames or ticks until the next try
STALL_T         := $9F   ; frames spent waiting on the other machine
RX_HEAD         := $A0   ; the receive ring: filled by SysIrq,
RX_TAIL         := $A1   ; emptied by LinkPoll
PARSE_N         := $A2   ; bytes of FRAME so far
LINK_N          := $A3
CK_A            := $A4
CK_B            := $A5
LINK_S          := $A6
FR_PTR          := $A7   ; 2 bytes, $A7-$A8
OLD_IRQ         := $A9   ; 2 bytes, $A9-$AA: the Kernal's handler
HAVE_OLD        := $AB   ; OLD_TX is a round's last INPUT, to keep sending
TITLE_C1        := $AC   ; the title's colors, put back after a link
TITLE_C2        := $AD
LINK_TMP        := $AE
T_PACK          := $AF
FRAMES_LEFT     := $B0   ; MainLoop: frames until the next tick
FRAME_COUNT     := $B1   ; 2 bytes, $B1-$B2: frames since start-up

RX_BUF          = $0800  ; 256 bytes
FRAME           = $0900  ; the frame coming in
TX_FRAME        = $0910  ; the frame going out
OLD_TX          = $0920  ; the last INPUT frame, to send again
MY_IN           = $0930  ; 8 headings each, by tick & 7
PEER_IN         = $0938
SUMS            = $0940  ; StateSum at each of the last 8 ticks

GPIO_INT_T2     = %00100000  ; the VIA's timer 2 interrupt (not in 6502-VDP.inc)

; sound.asm: the driver's own, as it runs in the interrupt
S_A             := $B3
S_P             := $B4   ; 2 bytes, $B4-$B5
S_B             := $B6
S_C             := $B7

S_REG           = $0A00  ; the SID's registers, as they'll be written each tick
S_RTG           = $0A19  ; counts each voice's restarts
S_PEND          = $0A1C  ; a voice to restart this tick
S_Q             = $0A20  ; 8 requests from the game
S_QH            = $0A28
S_QT            = $0A29
S_BUSY          = $0A2A
S_ON            = $0A2B  ; a sound card and a timer to run it
S_TICKS         = $0A2C  ; 2 bytes
S_FXC           = $0A2E  ; the filter's cutoff, and how fast it closes
S_FXK           = $0A2F
SF_ID           = $0A30  ; each voice's effect, 3 bytes each from here
SF_P            = $0A33
SF_PL           = $0A36
SF_PH           = $0A39
SF_LEFT         = $0A3C
SF_FL           = $0A3F
SF_FH           = $0A42
SF_TL           = $0A45
SF_TH           = $0A48
SF_FLG          = $0A4B
SF_FIL          = $0A4E
S_VARS_END      = $0A51

; The screen is 320 pixels across, so x takes a second byte: bit 8 of each
; rider's x, and of the pixel the drawing routines are given
PX_HI           := $B8   ; bit 8 of the column passed in X
PX_X            := $B9   ; ComputePixelAddress's own copies
PX_Y            := $BA
P1_XH           := $BB
P2_XH           := $BC
P1_NEXT_XH      := $BD
P2_NEXT_XH      := $BE
AI_TEST_XH      := $BF

; The title's menu (game.asm) and the speed
MENU_ROW        := $C0   ; the line the arrows are on: MENU_MODE ...
LAST_MENU_ROW   := $C1
MENU_PREV       := $C2   ; up, down, left and right held last tick (one press, one step)
SPEED           := $C3   ; SPEED_SLOW, _NORMAL or _FAST
LAST_SPEED      := $C4
MY_SPEED        := $C5   ; link.asm: this machine's speed pick, the other's,
PEER_SPEED      := $C6   ; the title's to put back, and the delay for the
TITLE_SPEED     := $C7   ; speed both play at
LDELAY          := $C8

MENU_MODE       = 0
MENU_SPEED      = 1
MENU_P1         = 2
MENU_P2         = 3
MENU_ROWS       = 4

SPEED_SLOW      = 0
SPEED_NORMAL    = 1
SPEED_FAST      = 2
