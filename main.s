#define F_CPU 20000000

#include <avr/io.h>
#include <avr/interrupt.h>

#include "defs.h"



; Global routines in this file
.global main
.global __vector_11

; Global routines from other files
.global renderRow



.section .text



; r1  => Always 0

; r13 => Horizontal wave offset

; r14 => Vertical offset

; r15 => Scratch
; r16 => Scratch
; r17 => Scratch

; r18:r19 => Keeps count of rows drawn

; r20 => Horizontal wave sine table index.

; PORTD => 0bXXXXXXVH - Sync bits
; PORTC => 0b__RRGGBB - Color output

; r21 => Vertical sine table index
; r22 => Vertical pixel counter
; r23 => Palette offset
; r24 => Frame counter

; After initialization...
; ZH => Start of sine table
; YH => Start of sine table
; XH => Start of palette table




;**************************************************************************************************
;* Main entry point to the program
;*
main:

    ; Setup TIMER1 in Fast PWM mode and have it trigger an interrupt
    ; when it counts 0x26F clocks.  This is the # of clocks between HSyncs at 20MHz
    ldi     r16,    0b00010000  ; 1<<OCIE1A
    sts     TIMSK1, r16
    ldi     r16,    0b00110011  ; 1<<COM1B1 | 1<<COM1B0 | 1<<WGM11 | 1<<WGM10
    sts     TCCR1A, r16
    ldi     r16,    0b00011001  ; 1<<WGM13 | 1<<WGM12 | 1<<CS10
    sts     TCCR1B, r16
    ldi     r16,    0x02
    sts     OCR1AH, r16
    ldi     r16,    0x6F
    sts     OCR1AL, r16
    sts     TCNT1L, r1
    sts     TCNT1H, r1

    ; Init the output pins
    ldi     r16,  0b00000011
    out     ddrd, r16
    out     portd, r16
    ldi     r16,  0b00111111
    out     ddrc, r16
    out     portc, r1

    ; Load the sine table to RAM at address 0x0100
    ldi     r16, 32                 ; r16 counter
    ldi     ZL,  lo8(sineTable)
    ldi     ZH,  hi8(sineTable)
    ldi     XH,  SINE_H
    clr     XL
1:  lpm     r17, Z+     ; r17 contains current value
    st      X+,  r17
    dec     r16
    brne    1b

    ; Load the palette table to RAM at address 0x0200
    ldi     r16, 16                 ; r16 counter
    ldi     ZL,  lo8(palette)
    ldi     ZH,  hi8(palette)
    ldi     XH,  PALETTE_H
    clr     XL
1:  lpm     r17, Z+     ; r17 contains current value
    st      X+,  r17
    dec     r16
    brne    1b

    ; Initialize variables and enable interrupts (i.e. The TIMER1 trigger interrupt)
;  ldi     ZH, SINE_H
;  ldi     YH, SINE_H
;  ldi     XH, PALETTE_H
    clr     r14
    clr     r18
    clr     r19
    clr     r20
    clr     r21
    ldi     r22, 1
    clr     r23
    ldi     r24, UPDATE_DELAY
    sei

1:  nop
    rjmp    1b



;**************************************************************************************************
;* Horizontal syncronization and row processing.
;*
;* This interrupt vector is called every 31.7us as per the VGA timing standards.
;*
;* Lower the HSync signal for 3.77 us
;* Raise the HSync signal and hang out on the back porch for 1.89 us
;* Enter active video time.
;*
;* Row number and timing
;* [  1,480] = [  0x1,0x1E0] = Active video
;* [481,491] = [0x1E1,0x1EB] = Front porch
;* [492,493] = [0x1EC,0x1ED] = Sync
;* [494,525] = [0x1EE,0x20D] = Back porch
;*
__vector_11:
    sts     TCNT1L, r1   ; (2) Reset TIMER1
    sts     TCNT1H, r1   ; (2)

    out     portc, r1    ; (1) Clear the video output bus
    cbi     portd, 0     ; (2) Lower the HSync bit


; TIMING: From this point until the HSync bit goes high must be 75 cycles.

    ; Increment the row count (3 cycles)
    inc     r19
    brne    1f
    inc     r18

    ; onEnterLine:
    ; Need:  r13 += SINE[ ++r20 % SINE.length ] / 16
    ;  r13 += SINE[ r20 ] / 16
    ;  ZL  =  r13 / 8
    ; This commented out code is an attempt to implement the above algorithm, but is not
    ; in working condition.  This algorithm would sway the plasma back and forth by setting
    ; a horizontal offset on each row.
;   ldi     ZH,  SINE_H
;   ldi     ZL,  r20
;   inc     r20
;   andi    r20, 0b00011111
;   ld      r16, Z
;   swap    r16
;   andi    r16, 0b00001111
;   add     r13, r16
;   mov     r16, r13
;   lsr     r16
;   lsr     r16
;   lsr     r16
;   mov     ZL, r16

    ; DELAY (70 cycles) ; TODO: Replace with the above code to offset each row.
1:  ldi     r16, 23
2:  dec     r16
    brne    2b
    nop

    ; Raise the HSync bit (2 cycles)
    sbi     portd, 0

; TIMING: From this point until the active video time segment is 38 cycles. (Back porch)

    ; If row count <= 480 = 0x01E0, we're on the screen (7 cycles).  Else we're in VBlank (X cycles).
    cpi     r18, 0      ; MSB is 0, we're certainly on the screen/
    breq    4f
    cpi     r18, 2      ; MSB is 2, we're certainly in VBlank
    breq    1f
    cpi     r19, 0xE1   ; MSB is 1, check LSB to see where we are
    brlo    5f

    ; Handle VSync signal: if row=492 then VSync:='0'; if row=494 then VSync:='1'; if row=525 then row:=0;
1:  cpi     r18, 2      ; If MSB is 2, we're in the last few rows
    breq    3f
    cpi     r19, 0xEC   ; Check if we're in row 492
    breq    2f
    cpi     r19, 0xEE   ; Check if we're in row 494
    brne    1f
    sbi     portd, 1    ; We're in row 494. Raise the VSync bit
1:  reti
2:  cbi     portd, 1    ; We're in row 492. Lower the VSync bit
    reti
3:  cpi     r19, 0x0D   ; We're in row 0x2__, check if we're in row 525
    brne    1b
    rcall   lastRow     ; We're in row 525, run some screen reset code.
    reti

4:  nop
    nop
    nop
    nop

    ; We're on the screen, prepare to render the current row. (7/38)
5:  ldi     ZH, SINE_H      ; (1)
;  ldi     YH, SINE_H      ; (1) (only needed when sway algoritm is implemented)
    ldi     XH, PALETTE_H   ; (1)

    ; Increment vertical pixel count, check if we need a new vertical sine value
    dec     r22                      ; (1)
    brne    1f                       ; (1) | (2)
    ldi     r22, VERTICAL_PIXEL_SIZE ; (1) (12/38)

    ; Compute the vertical sine value
    inc     r21             ; (1)
    andi    r21, 0b00011111 ; (1)
    mov     ZL,  r21        ; (1)
    ld      r17, Z          ; (2)
    rjmp    3f              ; (2) Block: (7)

    ; Skip computing a new value, we're on the same vertical pixel as previous row.
1:  ldi     r16, 2 ; (Delay 7)
2:  dec     r16    ; ...
    brne    2b     ; ...
    nop            ; ...

3:  ldi     r16, 2      ; (Delay 6)
4:  dec     r16         ; ...
    brne    4b          ; ...
    clr     ZL          ; (1)
    rcall   renderRow   ; (3) ... (+9 cycles at the destination before a pixel is actually set)
    out     portc, r1   ; Clear the video output bus
    reti



;****************************************************************************************************************
;* This is called when entering active video time for the last
;* scanline in the vertical blank (line 525).
;*
lastRow:
    ; Reset variables
    clr     r18
    clr     r19
    mov     r21, r14
    ldi     r22, 1

    ; Decrement the update delay counter, only update frame if zero.
    dec     r24
    brne    3f
    ldi     r24, UPDATE_DELAY

    ; Rotate the palette
    inc     r23
    andi    r23, 0b00001111
    ldi     r16, 16
    ldi     r17, lo8(palette)
    add     r17, r16
    mov     r15, r17
    ldi     ZL,  lo8(palette)
    ldi     ZH,  hi8(palette)
    add     ZL,  r23
    ldi     XH,  PALETTE_H
    clr     XL
1:  lpm     r17, Z+
    cp      ZL,  r15
    brlo    2f
    ldi     ZL,  lo8(palette)
2:  st      X+,  r17
    dec     r16
    brne    1b

    ; Increment the vertical offset (scroll up)
    ldi     r16, 2
    add     r14, r16
    ldi     r16, 0b00011111
    and     r14, r16

3:  ret




;****************************************************************************************************************
;* LOOK-UP TABLES STORED IN FLASH
;*

sineTable:
    .byte 0x3f, 0x4b, 0x57, 0x62, 0x6b, 0x73, 0x79, 0x7c, 0x7e, 0x7c, 0x79, 0x73, 0x6b, 0x62, 0x57, 0x4b
    .byte 0x3f, 0x32, 0x26, 0x1b, 0x12, 0x0a, 0x04, 0x01, 0x00, 0x01, 0x04, 0x0a, 0x12, 0x1b, 0x26, 0x32

palette:
    .byte 0b00110000 ; 30
    .byte 0b00110100 ; 34
    .byte 0b00111100 ; 3c
    .byte 0b00101100 ; 2c
    .byte 0b00011100 ; 1c
    .byte 0b00001100 ; 0c
    .byte 0b00001101 ; 0d
    .byte 0b00001111 ; 0f
    .byte 0b00001011 ; 0b
    .byte 0b00000111 ; 07
    .byte 0b00000011 ; 03
    .byte 0b00010011 ; 13
    .byte 0b00100011 ; 23
    .byte 0b00110011 ; 33
    .byte 0b00110010 ; 32
    .byte 0b00110001 ; 31
