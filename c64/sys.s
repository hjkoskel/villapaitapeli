; Low-level C64 support for Sakarin villapaitapeli:
;   - system init: RAM vectors, KERNAL banked out, raster IRQ, VIC bank 3
;   - ZX02 decompressor (port of DMSC's zx02-optim.asm, MIT licence)
;   - 4-bit $D418 sample player on CIA2 timer A NMI
;   - sweater overlay blitter
;   - keyboard/joystick reading
;
; Memory configuration while running: $01 = $35 (RAM, I/O, RAM), so all
; vectors are read from RAM at $FFFA-$FFFF.

        .include "build/assets.inc"
        .import  popax
        .export  _sys_init, _unzx02, _snd_play, _snd_stop, _read_input
        .export  _sweater_draw
        .export  _frame, _snd_done, _vic_d011, _vic_d016

SCREEN  = $C000
SWBUF   = $C400
BGBUF   = $D000                 ; RAM under I/O, 11 * 320 bytes
BGCBUF  = BGBUF + SW_ROWS*320   ; 11 * 40 colour bytes
BITMAP  = $E000

.segment "ZEROPAGE"
zx_offhi: .res 1
zx_src:   .res 2
zx_dst:   .res 2
zx_bitr:  .res 1
zx_pntr:  .res 2

sw_col:   .res 1
sw_sc:    .res 1
sw_c:     .res 1
sw_r:     .res 1
sw_t:     .res 1
sw_hi:    .res 1
rowbm:    .res 2
rowbg:    .res 2
rowscr:   .res 2
rowbgc:   .res 2
tptr:     .res 2
cptr:     .res 2
inkp:     .res 2
maskp:    .res 2
dst:      .res 2
bgp:      .res 2
in_bits:  .res 1

.segment "DATA"
_frame:    .byte 0
_snd_done: .byte 1
_vic_d011: .byte $2B            ; bitmap, screen off, 25 rows, yscroll 3
_vic_d016: .byte $08            ; 40 columns, xscroll 0

.segment "CODE"

; ---------------------------------------------------------------------------
; void __fastcall__ sys_init(unsigned char pal)
_sys_init:
        sei
        tax
        lda     #<196           ; PAL: 985248 / 5000 Hz - 1
        ldy     #0
        cpx     #0
        bne     :+
        lda     #<204           ; NTSC: 1022727 / 5000 Hz - 1
:       sta     $DD04
        sty     $DD05

        lda     #$7F            ; no CIA interrupts
        sta     $DC0D
        sta     $DD0D
        lda     $DC0D
        lda     $DD0D
        lda     #0
        sta     $DD0E
        sta     $DC0E

        lda     #<irq           ; RAM vectors (KERNAL goes out next)
        sta     $FFFE
        lda     #>irq
        sta     $FFFF
        lda     #<nmi_stub
        sta     $FFFA
        lda     #>nmi_stub
        sta     $FFFB
        lda     #$35
        sta     $01

        ; VIC: bank 3, screen $C000, bitmap $E000, white border
        lda     $DD02
        ora     #$03
        sta     $DD02
        lda     $DD00
        and     #$FC
        sta     $DD00
        lda     #$08
        sta     $D018
        lda     #1
        sta     $D020
        lda     #0
        sta     $D015           ; no sprites
        lda     _vic_d016
        sta     $D016
        lda     _vic_d011
        sta     $D011
        lda     #251            ; raster IRQ in the lower border
        sta     $D012
        lda     #1
        sta     $D01A
        sta     $D019

        ; SID: voices give a constant DC level so $D418 works on 8580 too
        ldx     #$18
        lda     #0
:       sta     $D400,x
        dex
        bpl     :-
        lda     #$F0            ; sustain F
        sta     $D406
        sta     $D40D
        sta     $D414
        lda     #$49            ; pulse + test + gate
        sta     $D404
        sta     $D40B
        sta     $D412
        ldx     #0              ; ramp volume 0 -> 8 to avoid a click
ramp:   stx     $D418
        ldy     #0
:       nop
        nop
        dey
        bne     :-
        inx
        cpx     #9
        bne     ramp
        cli
        rts

irq:    pha
        lda     $D019
        sta     $D019
        inc     _frame
        lda     _vic_d016
        sta     $D016
        lda     _vic_d011
        sta     $D011
        pla
nmi_stub:
        rti

; ---------------------------------------------------------------------------
; void __fastcall__ unzx02(const void *src, void *dst)
_unzx02:
        sta     zx_dst
        stx     zx_dst+1
        jsr     popax
        sta     zx_src
        stx     zx_src+1
        lda     #0
        sta     zx_offhi
        lda     #$80
        sta     zx_bitr
        lda     #$FF
        sta     zx_pntr
        ldy     #0
        ldx     #0

decode_literal:
        inx
        jsr     get_elias
cop0:   lda     (zx_src),y
        inc     zx_src
        bne     :+
        inc     zx_src+1
:       sta     (zx_dst),y
        inc     zx_dst
        bne     :+
        inc     zx_dst+1
:       dex
        bne     cop0
        asl     zx_bitr
        bcs     new_offset

        inx
        jsr     get_elias
zx_copy:
        lda     zx_dst+1
        sbc     zx_offhi        ; C=0 from get_elias
        sta     zx_pntr+1
cop1:   ldy     zx_dst
        lda     (zx_pntr),y
        ldy     #0
        sta     (zx_dst),y
        inc     zx_dst
        bne     :+
        inc     zx_dst+1
        inc     zx_pntr+1
:       dex
        bne     cop1
        asl     zx_bitr
        bcc     decode_literal

new_offset:
        inx
        jsr     get_elias
        beq     zx_exit         ; 0 = end of data
        dex
        txa
        lsr     a
        sta     zx_offhi
        lda     (zx_src),y
        inc     zx_src
        bne     :+
        inc     zx_src+1
:       ror     a
        eor     #$FF
        sta     zx_pntr
        ldx     #1
        jsr     elias_skip1
        inx
        bcc     zx_copy

elias_get:
        asl     zx_bitr
        rol     a
        tax
get_elias:
        asl     zx_bitr
        bne     elias_skip1
        lda     (zx_src),y
        inc     zx_src
        bne     :+
        inc     zx_src+1
:       rol     a
        sta     zx_bitr
elias_skip1:
        txa
        bcs     elias_get
zx_exit:
        rts

; ---------------------------------------------------------------------------
; Sample player: 4-bit samples, two per byte, high nibble first.
; void __fastcall__ snd_play(const void *start, const void *end)
_snd_play:
        pha
        txa
        pha
        jsr     _snd_stop
        pla
        sta     endhi+1
        pla
        sta     endlo+1
        jsr     popax
        sta     p_hi+1
        sta     p_lo+1
        stx     p_hi+2
        stx     p_lo+2
        lda     #0
        sta     _snd_done
        lda     #<nmi_hi
        sta     $FFFA
        lda     #>nmi_hi
        sta     $FFFB
        lda     #$11            ; force load + start, continuous
        sta     $DD0E
        lda     #$81            ; timer A NMI on
        sta     $DD0D
        rts

; void snd_stop(void)
_snd_stop:
        lda     #$7F
        sta     $DD0D
        lda     #0
        sta     $DD0E
        lda     $DD0D           ; ack a pending NMI
        lda     #<nmi_stub
        sta     $FFFA
        lda     #>nmi_stub
        sta     $FFFB
        lda     #8              ; DC midpoint
        sta     $D418
        lda     #1
        sta     _snd_done
        rts

nmi_hi: pha
        lda     $DD0D
p_hi:   lda     $FFFF
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     $D418
        lda     #<nmi_lo
        sta     $FFFA
        lda     #>nmi_lo
        sta     $FFFB
        pla
        rti

nmi_lo: pha
        lda     $DD0D
p_lo:   lda     $FFFF
        and     #$0F
        sta     $D418
        lda     #<nmi_hi
        sta     $FFFA
        lda     #>nmi_hi
        sta     $FFFB
        inc     p_hi+1
        inc     p_lo+1
        bne     :+
        inc     p_hi+2
        inc     p_lo+2
:       lda     p_lo+1
endlo:  cmp     #0
        bne     :+
        lda     p_lo+2
endhi:  cmp     #0
        bne     :+
        lda     #$7F            ; end of clip
        sta     $DD0D
        lda     #<nmi_stub
        sta     $FFFA
        lda     #>nmi_stub
        sta     $FFFB
        lda     #1
        sta     _snd_done
:       pla
        rti

; ---------------------------------------------------------------------------
; unsigned char read_input(void)
; bit 0: first button  (1, E, N, joystick up)
; bit 1: second button (2, J, Y, joystick down)
; bit 2: confirm       (space, return, fire)
.macro KEY col, row, bit
        lda     #col
        sta     $DC00
        lda     $DC01
        and     #row
        bne     :+
        lda     in_bits
        ora     #bit
        sta     in_bits
:
.endmacro

_read_input:
        lda     #$FF
        sta     $DC00
        lda     $DC00           ; joystick 2, active low
        eor     #$FF
        tax
        and     #$03            ; up -> bit 0, down -> bit 1
        sta     in_bits
        txa
        and     #$10
        beq     :+
        lda     in_bits
        ora     #4
        sta     in_bits
:       KEY     $7F, $01, 1     ; 1
        KEY     $FD, $40, 1     ; E
        KEY     $EF, $80, 1     ; N
        KEY     $7F, $08, 2     ; 2
        KEY     $EF, $04, 2     ; J
        KEY     $F7, $02, 2     ; Y
        KEY     $7F, $10, 4     ; space
        KEY     $FE, $02, 4     ; return
        lda     #$FF
        sta     $DC00
        lda     in_bits
        ldx     #0
        rts

; ---------------------------------------------------------------------------
; void __fastcall__ sweater_draw(signed char col)
; Draws the sweater with its left edge at cell column col over the stage
; background saved in BGBUF/BGCBUF (see sweater_begin in main.c), and
; restores the background in columns 0..col-1. No sound may be playing:
; I/O is banked out while the RAM under it is read.
.macro ADD16 var, val
        clc
        lda     var
        adc     #<(val)
        sta     var
        lda     var+1
        adc     #>(val)
        sta     var+1
.endmacro

.macro SET16 var, val
        lda     #<(val)
        sta     var
        lda     #>(val)
        sta     var+1
.endmacro

_sweater_draw:
        sta     sw_col
        sei
        lda     #$34
        sta     $01
        SET16   rowbm, BITMAP + SW_ROW0*320
        SET16   rowbg, BGBUF
        SET16   rowscr, SCREEN + SW_ROW0*40
        SET16   rowbgc, BGCBUF
        SET16   tptr, SWBUF + SW_T
        SET16   cptr, SWBUF + SW_C
        SET16   inkp, SWBUF + SW_INK
        SET16   maskp, SWBUF + SW_MASK
        lda     #SW_ROWS
        sta     sw_r

sw_row: lda     sw_col          ; restore columns 0..col-1
        bmi     sw_norest
        beq     sw_norest
        sta     sw_c
        lda     #0
        sta     sw_sc
sw_rest:
        jsr     cellptrs
        ldy     #7
:       lda     (bgp),y
        sta     (dst),y
        dey
        bpl     :-
        ldy     sw_sc
        lda     (rowbgc),y
        sta     (rowscr),y
        inc     sw_sc
        dec     sw_c
        bne     sw_rest
sw_norest:
        lda     sw_col
        sta     sw_sc
        lda     #SW_COLS
        sta     sw_c

sw_cell:
        ldy     #0
        lda     (tptr),y
        sta     sw_t
        lda     sw_sc
        cmp     #40
        bcs     sw_next         ; off screen (negative columns are >= 128)
        jsr     cellptrs
        lda     sw_t
        beq     sw_t0
        cmp     #1
        beq     sw_t1
        ldy     #7              ; edge cell: (bg & ~mask) | ink
:       lda     (maskp),y
        eor     #$FF
        and     (bgp),y
        ora     (inkp),y
        sta     (dst),y
        dey
        bpl     :-
        bmi     sw_color
sw_t1:  ldy     #7              ; opaque cell
:       lda     (inkp),y
        sta     (dst),y
        dey
        bpl     :-
sw_color:
        ldy     #0
        lda     (cptr),y
        ldy     sw_sc
        cmp     #0
        bne     :+
        lda     (rowbgc),y
:       sta     (rowscr),y
        jmp     sw_next
sw_t0:  ldy     #7              ; transparent cell: background
:       lda     (bgp),y
        sta     (dst),y
        dey
        bpl     :-
        ldy     sw_sc
        lda     (rowbgc),y
        sta     (rowscr),y

sw_next:
        lda     sw_t
        beq     :+
        ADD16   inkp, 8
        lda     sw_t
        cmp     #2
        bne     :+
        ADD16   maskp, 8
:       inc     tptr
        bne     :+
        inc     tptr+1
:       inc     cptr
        bne     :+
        inc     cptr+1
:       inc     sw_sc
        dec     sw_c
        beq     :+
        jmp     sw_cell
:
        ADD16   rowbm, 320
        ADD16   rowbg, 320
        ADD16   rowscr, 40
        ADD16   rowbgc, 40
        dec     sw_r
        beq     :+
        jmp     sw_row
:       lda     #$35
        sta     $01
        cli
        rts

; dst = rowbm + sc*8, bgp = rowbg + sc*8
cellptrs:
        lda     #0
        sta     sw_hi
        lda     sw_sc
        asl     a
        rol     sw_hi
        asl     a
        rol     sw_hi
        asl     a
        rol     sw_hi
        tax
        clc
        adc     rowbm
        sta     dst
        lda     sw_hi
        adc     rowbm+1
        sta     dst+1
        txa
        clc
        adc     rowbg
        sta     bgp
        lda     sw_hi
        adc     rowbg+1
        sta     bgp+1
        rts
