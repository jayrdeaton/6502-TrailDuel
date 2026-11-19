; =============================================================================
;   arena.asm - the arena's bounds, in screen pixels
; =============================================================================
;   The border runs along these four lines; the riders move inside them. The
;   screen is 320 x 240, so x takes 9 bits.

ARENA_MIN_X  = 8
ARENA_MAX_X  = 311
ARENA_MIN_Y  = 16
ARENA_MAX_Y  = 223

; Where the riders start: a quarter of the way in from each side, halfway down,
; facing each other
P1_START_X   = 84
P2_START_X   = 235
START_Y      = 120
