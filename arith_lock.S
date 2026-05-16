#define __SFR_OFFSET 0x00
#include <avr/io.h>

; ===== DEFS =======================================================================
; Serial
.equ F_CPU,          16000000 ; 16 MHz clock
.equ BAUD,           9600 ; Baud Rate
.equ UBRR_VAL,       (F_CPU / (16 * BAUD)) - 1  ; 103

; State value
.equ STATE_STANDBY,  0
.equ STATE_INPUT,    1
.equ STATE_OPEN,     2
.equ STATE_LOCKOUT,  3

; Security parameters
.equ MAX_ATTEMPTS,   3
.equ LOCKOUT_SECS,   30
.equ OPEN_SECS,      5

; Arithmetic button
.equ STEP_POS_INT0,  2   ; btn_id 1  (PD2)
.equ STEP_NEG_INT1, -2   ; btn_id 2  (PD3)
.equ STEP_POS_PD4,   5   ; btn_id 3
.equ STEP_NEG_PD5,  -5   ; btn_id 4
.equ STEP_POS_PD6,   7   ; btn_id 5
.equ STEP_NEG_PD7,  -7   ; btn_id 6
.equ STEP_POS_PB0,   9   ; btn_id 7
.equ STEP_NEG_PC0,  -9   ; btn_id 8

; EEPROM
.equ EE_TARGET_L,    0x00
.equ EE_TARGET_H,    0x01
.equ EE_FAIL_CNT,    0x02 ; 0 = no fails, 1-3 = fail count, 4 = lockout active
.equ EE_LOCKOUT_FL,  0x03 ; 0 = not in lockout, 1 = in lockout

; !!!TARGET VALUE!!!
.equ DEFAULT_TARGET, 97

; LCD
.equ LCD_ADDR,       0x27 ; I2C address untuk LCD PCF8574
.equ LCD_BL,         0x08 ; Backlight
.equ LCD_EN,         0x04 ; Enable
.equ LCD_RW,         0x02 ; Read/Write
.equ LCD_RS,         0x01 ; Register Select

; Servo
.equ SERVO_LOCKED,   1000 ; 1 ms PWM pulse width(0 degrees) 
.equ SERVO_OPEN,     2000 ; 2 ms PWM pulse width (180 degrees)
.equ ICR1_VAL,       20000 ; 20 ms di 50 Hz untuk servo control
.equ OCR2A_VAL,      249 ; 1 ms pulse width saat 16 MHz dengan prescaler 64

; Registers
.def tmp,        r16
.def tmp2,       r17
.def state,      r18
.def btn_flag,   r19 ; 1 = button ditekan, 0 = released
.def btn_id,     r20 ; 0-7 sesuai pin input

; ===== ADDRESS MAP =======================================================================
.section .bss
current_val_l:   .skip 1 ; Nilai input saat ini (0-99)
current_val_h:   .skip 1 ; Nilai input saat ini (0-99)
target_val_l:    .skip 1 ; Nilai target yang disimpan di EEPROM
target_val_h:    .skip 1 ; Nilai target yang disimpan di EEPROM
fail_count:      .skip 1 ; self-explanatory
lockout_secs:    .skip 1 ; self-explanatory
open_secs:       .skip 1 ; self-explanatory
ms_tick:         .skip 2 ; 16-bit counter untuk timer tick (1 ms per tick)
debounce_ms:     .skip 1 ; self-explanatory
poll_pind_prev:  .skip 1 ; untuk deteksi perubahan tombol
poll_pinb_prev:  .skip 1 ; untuk deteksi perubahan tombol
poll_pinc_prev:  .skip 1 ; untuk deteksi perubahan tombol
lcd_line1:       .skip 17 ; buffer untuk baris pertama LCD
lcd_line2:       .skip 17 ; buffer untuk baris kedua LCD


; ===== VECTOR TABLE =======================================================================
.section .text
.org 0x0000

    rjmp RESET          ; 0x00 RESET


; ===== RESET / INIT =======================================================================
RESET:
    ldi tmp, high(RAMEND) ; Set up stack pointer
    out SPH, tmp
    ldi tmp, low(RAMEND) ; Set up stack pointer
    out SPL, tmp

    clr btn_flag
    clr btn_id
    ldi state, STATE_STANDBY

; General Purpose I/O Init
    ; PD2 and PD3 input with pull-up (buttons)
    sbi DDRD, 0 ; PD0 RX (UART) - input
    sbi DDRD, 1 ; PD1 TX (UART) - output
    cbi DDRD, 2 ; PD2 INT0 - input
    cbi DDRD, 3 ; PD3 INT1 - input
    sbi PORTD, 2 ; Pull-up PD2
    sbi PORTD, 3 ; Pull-up PD3

    ; PB0-PB2 pull-up input (buttons)
    cbi DDRB, 0 ; PB0 - input
    cbi DDRB, 1 ; PB1 - input
    cbi DDRB, 2 ; PB2 - input
    sbi PORTB, 0 ; Pull-up PB0
    sbi PORTB, 1 ; Pull-up PB1
    sbi PORTB, 2 ; Pull-up PB2

    ; PC0-PC5 pull-up input (buttons)
    cbi DDRC, 0 ; PC0 - input
    cbi DDRC, 1 ; PC1 - input
    cbi DDRC, 2 ; PC2 - input
    cbi DDRC, 3 ; PC3 - input
    cbi DDRC, 4 ; PC4 - input
    cbi DDRC, 5 ; PC5 - input
    sbi PORTC, 0 ; Pull-up PC0
    sbi PORTC, 1 ; Pull-up PC1
    sbi PORTC, 2 ; Pull-up PC2
    sbi PORTC, 3 ; Pull-up PC3
    sbi PORTC, 4 ; Pull-up PC4
    sbi PORTC, 5 ; Pull-up PC5

; UART Init
    ldi tmp, high(UBRR_VAL)
    sts UBRR0H, tmp
    ldi tmp, low(UBRR_VAL)
    sts UBRR0L, tmp
    ldi tmp, (1<<RXEN0)|(1<<TXEN0)
    sts UCSR0B, tmp
    ldi tmp, (1<<UCSZ01)|(1<<UCSZ00)
    sts UCSR0C, tmp

; TIMER1 (Servo PWM, 50Hz)
    ldi tmp, high(ICR1_VAL)
    sts ICR1H, tmp
    ldi tmp, low(ICR1_VAL)
    sts ICR1L, tmp
    ldi tmp, high(SERVO_LOCKED)
    sts OCR1AH, tmp
    ldi tmp, low(SERVO_LOCKED)
    sts OCR1AL, tmp
    ldi tmp, (1<<COM1A1)|(1<<WGM11)
    sts TCCR1A, tmp
    ldi tmp, (1<<WGM13)|(1<<WGM12)|(1<<CS11)
    sts TCCR1B, tmp

; TIMER2 (1 ms tick)
    ldi tmp, OCR2A_VAL
    sts OCR2A, tmp
    ldi tmp, (1<<WGM21)
    sts TCCR2A, tmp
    ldi tmp, (1<<CS22)
    sts TCCR2B, tmp
    ldi tmp, (1<<OCIE2A)
    sts TIMSK2, tmp

; Interrupts Init
    ldi tmp, (1<<ISC01)|(1<<ISC11)
    sts EICRA, tmp
    ldi tmp, (1<<INT0)|(1<<INT1)
    out EIMSK, tmp

; TWI (I2C) Init for LCD
    ldi tmp, 72
    sts TWBR, tmp
    ldi tmp, 0
    sts TWSR, tmp
    ldi tmp, (1<<TWEN)
    sts TWCR, tmp

; SRAM INIT - clear all var
    clr tmp
    sts current_val_l, tmp
    sts current_val_h, tmp
    sts fail_count, tmp
    sts lockout_secs, tmp
    sts open_secs, tmp
    sts ms_tick, tmp
    sts ms_tick+1, tmp
    sts debounce_ms, tmp

    in  tmp, PIND
    sts poll_pind_prev, tmp
    in  tmp, PINB
    sts poll_pinb_prev, tmp
    in  tmp, PINC
    sts poll_pinc_prev, tmp

    rcall EEPROM_READ_TARGET
    rcall EEPROM_READ_FAILCNT

    rcall DELAY_100MS
    rcall LCD_INIT
    rcall LCD_CLEAR

    ldi ZL, low(STR_BOOT<<1)
    ldi ZH, high(STR_BOOT<<1)
    rcall UART_PRINT_FLASH

    ldi tmp2, EE_LOCKOUT_FL
    rcall EEPROM_READ_BYTE
    cpi r24, 0xFF
    breq INIT_LOCKOUT

    rcall SCREEN_STANDBY
    sei
    rjmp INIT_HALT

INIT_LOCKOUT:
    ldi state, STATE_LOCKOUT
    ldi tmp, LOCKOUT_SECS
    sts lockout_secs, tmp
    rcall SCREEN_LOCKOUT
    sei

INIT_HALT:
    rjmp INIT_HALT

; ===== EEPROM =======================================================================
EEPROM_READ_TARGET:
    ldi  tmp2, EE_TARGET_L
    rcall EEPROM_READ_BYTE
    cpi  r24, 0xFF
    brne EE_RT_L_OK
    ldi  r24, low(DEFAULT_TARGET)
EE_RT_L_OK:
    sts  target_val_l, r24

    ldi  tmp2, EE_TARGET_H
    rcall EEPROM_READ_BYTE
    cpi  r24, 0xFF
    brne EE_RT_H_OK
    ldi  r24, high(DEFAULT_TARGET)
EE_RT_H_OK:
    sts  target_val_h, r24
    ret

EEPROM_READ_FAILCNT:
    ldi  tmp2, EE_FAIL_CNT
    rcall EEPROM_READ_BYTE
    cpi  r24, 0xFF
    brne EE_RFC_OK
    clr  r24
EE_RFC_OK:
    sts  fail_count, r24
    ret

EEPROM_WRITE_FAILCNT:
    lds  r24, fail_count
    ldi  tmp2, EE_FAIL_CNT
    rcall EEPROM_WRITE_BYTE_R24
    ret

EEPROM_READ_BYTE:
    sbic EECR, EEPE
    rjmp EEPROM_READ_BYTE
    clr  tmp
    out  EEARH, tmp
    out  EEARL, tmp2
    sbi  EECR, EERE
    in   r24, EEDR
    ret

EEPROM_WRITE_BYTE_R24:
EE_WB_WAIT:
    sbic EECR, EEPE
    rjmp EE_WB_WAIT
    clr  tmp
    out  EEARH, tmp
    out  EEARL, tmp2
    out  EEDR, r24
    cli
    sbi  EECR, EEMPE
    sbi  EECR, EEPE
    sei
    ret

; ===== Delay ========================================================================
DELAY_1US_x5:
    ldi  tmp, 26
DLY_1US5_LOOP:
    dec  tmp
    brne DLY_1US5_LOOP
    ret

DELAY_50US:
    ldi  r21, 200
DLY_50US_LOOP:
    dec  r21
    brne DLY_50US_LOOP
    ret

DELAY_1MS:
    ldi  r21, 255
DLY_1MS_LOOP:
    ldi  r20, 31
DLY_1MS_INNER:
    dec  r20
    brne DLY_1MS_INNER
    dec  r21
    brne DLY_1MS_LOOP
    ret

DELAY_2MS:
    rcall DELAY_1MS
    rcall DELAY_1MS
    ret

DELAY_5MS:
    ldi  tmp, 5
DLY_5MS_LOOP:
    rcall DELAY_1MS
    dec  tmp
    brne DLY_5MS_LOOP
    ret

DELAY_50MS:
    ldi  tmp, 50
DLY_50MS_LOOP:
    rcall DELAY_1MS
    dec  tmp
    brne DLY_50MS_LOOP
    ret

DELAY_100MS:
    rcall DELAY_50MS
    rcall DELAY_50MS
    ret

DELAY_1S:
    ldi  tmp, 10
DLY_1S_LOOP:
    rcall DELAY_100MS
    dec  tmp
    brne DLY_1S_LOOP
    ret

; ===== STRINGS ======================================================================= 
STR_BOOT:     .asciz "ARITH LOCK BOOT\r\n"
STR_STANDBY1: .asciz "  ARITH  LOCK  "
STR_STANDBY2: .asciz " Press any key "
STR_VAL:      .asciz "Val: "
STR_DIST:     .asciz "Dist:"
STR_OPEN1:    .asciz "*** OPEN ***   "
STR_OPEN2:    .asciz "Closing in: "
STR_WRONG1:   .asciz "!! WRONG VALUE  "
STR_WRONG2:   .asciz "Attempts left: "
STR_LOCK1:    .asciz "** LOCKED OUT **"
STR_LOCK2:    .asciz "Wait: "
STR_LOG_BTN:  .asciz "[BTN] CurVal="
STR_LOG_OK:   .asciz "[AUTH] SUCCESS - OPEN"
STR_LOG_FAIL: .asciz "[AUTH] FAIL attempt "
STR_LOG_LOCK: .asciz "[AUTH] LOCKOUT TRIGGERED"
STR_LOG_CLOSE:.asciz "[DOOR] CLOSED"


; ===== SERVO ========================================================================
SERVO_OPEN:
    ldi  tmp, high(SERVO_OPEN)
    sts  OCR1AH, tmp
    ldi  tmp, low(SERVO_OPEN)
    sts  OCR1AL, tmp
    ret

SERVO_CLOSE:
    ldi  tmp, high(SERVO_LOCKED)
    sts  OCR1AH, tmp
    ldi  tmp, low(SERVO_LOCKED)
    sts  OCR1AL, tmp
    ret

; ===== LCD/TWI ======================================================================
TWI_START:
    ldi  tmp, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
    sts  TWCR, tmp
TWI_WAIT_S:
    lds  tmp, TWCR
    sbrs tmp, TWINT
    rjmp TWI_WAIT_S
    ret

TWI_STOP:
    ldi  tmp, (1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
    sts  TWCR, tmp
    ret

TWI_WRITE:
    sts  TWDR, r24
    ldi  tmp, (1<<TWINT)|(1<<TWEN)
    sts  TWCR, tmp
TWI_WAIT_W:
    lds  tmp, TWCR
    sbrs tmp, TWINT
    rjmp TWI_WAIT_W
    lds  r25, TWSR
    andi r25, 0xF8
    ret

LCD_SEND_RAW:
    push r24
    rcall TWI_START
    ldi  r24, (LCD_ADDR<<1)
    rcall TWI_WRITE
    pop  r24
    ori  r24, LCD_BL
    rcall TWI_WRITE
    rcall TWI_STOP
    ret

LCD_PULSE_EN:
    push r24
    ori  r24, LCD_EN
    rcall LCD_SEND_RAW
    rcall DELAY_1US_x5
    pop  r24
    andi r24, 0xFB
    rcall LCD_SEND_RAW
    rcall DELAY_1US_x5
    ret

LCD_SEND_NIBBLE:
    push r24
    push r23
    andi r24, 0xF0
    andi r23, 0x01
    or   r24, r23
    rcall LCD_PULSE_EN
    pop  r23
    pop  r24
    ret

LCD_SEND_BYTE:
    push r24
    push r23
    rcall LCD_SEND_NIBBLE
    pop  r23
    pop  r24
    push r24
    push r23
    swap r24
    andi r24, 0xF0
    andi r23, 0x01
    or   r24, r23
    rcall LCD_PULSE_EN
    pop  r23
    pop  r24
    rcall DELAY_50US
    ret

LCD_CMD:
    clr  r23
    rcall LCD_SEND_BYTE
    ret

LCD_DATA:
    ldi  r23, 1
    rcall LCD_SEND_BYTE
    ret

LCD_INIT:
    rcall DELAY_50MS
    ldi  r24, 0x30
    rcall LCD_PULSE_EN
    rcall DELAY_5MS
    ldi  r24, 0x30
    rcall LCD_PULSE_EN
    rcall DELAY_5MS
    ldi  r24, 0x30
    rcall LCD_PULSE_EN
    rcall DELAY_1MS
    ldi  r24, 0x20
    rcall LCD_PULSE_EN
    rcall DELAY_1MS
    ldi  r24, 0x28
    rcall LCD_CMD
    ldi  r24, 0x0C
    rcall LCD_CMD
    ldi  r24, 0x06
    rcall LCD_CMD
    ret

LCD_CLEAR:
    ldi  r24, 0x01
    rcall LCD_CMD
    rcall DELAY_2MS
    ret

LCD_SET_CURSOR:
    cpi  r24, 1
    brne LCD_SET_ROW0
    ori  r25, 0x40
LCD_SET_ROW0:
    ori  r25, 0x80
    mov  r24, r25
    rcall LCD_CMD
    ret

LCD_PRINT_SRAM:
LCD_PRINT_SRAM_LOOP:
    ld   r24, Z+
    tst  r24
    breq LCD_PRINT_SRAM_END
    rcall LCD_DATA
    rjmp LCD_PRINT_SRAM_LOOP
LCD_PRINT_SRAM_END:
    ret

LCD_PRINT_FLASH:
LCD_PRINT_FLASH_LOOP:
    lpm  r24, Z+
    tst  r24
    breq LCD_PRINT_FLASH_END
    rcall LCD_DATA
    rjmp LCD_PRINT_FLASH_LOOP
LCD_PRINT_FLASH_END:
    ret

; ===== SCREEN FUNC ==============================================================
SCREEN_STANDBY:
    rcall LCD_CLEAR
    ldi  ZL, low(STR_STANDBY1<<1)
    ldi  ZH, high(STR_STANDBY1<<1)
    clr  r24
    clr  r25
    rcall LCD_SET_CURSOR
    rcall LCD_PRINT_FLASH
    ldi  ZL, low(STR_STANDBY2<<1)
    ldi  ZH, high(STR_STANDBY2<<1)
    ldi  r24, 1
    clr  r25
    rcall LCD_SET_CURSOR
    rcall LCD_PRINT_FLASH
    ret

SCREEN_INPUT:
    rcall LCD_CLEAR
    clr  r24
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_VAL<<1)
    ldi  ZH, high(STR_VAL<<1)
    rcall LCD_PRINT_FLASH
    lds  r24, current_val_l
    lds  r25, current_val_h
    rcall LCD_PRINT_INT16

    ldi  r24, 1
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_DIST<<1)
    ldi  ZH, high(STR_DIST<<1)
    rcall LCD_PRINT_FLASH

    lds  r22, target_val_l
    lds  r23, target_val_h
    lds  r24, current_val_l
    lds  r25, current_val_h
    sub  r22, r24
    sbc  r23, r25
    tst  r23
    brpl SI_POS
    com  r22
    com  r23
    ldi  tmp, 1
    add  r22, tmp
    adc  r23, r25
SI_POS:
    mov  r24, r22
    mov  r25, r23
    rcall LCD_PRINT_INT16
    ret

SCREEN_OPEN:
    rcall LCD_CLEAR
    clr  r24
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_OPEN1<<1)
    ldi  ZH, high(STR_OPEN1<<1)
    rcall LCD_PRINT_FLASH
    ldi  r24, 1
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_OPEN2<<1)
    ldi  ZH, high(STR_OPEN2<<1)
    rcall LCD_PRINT_FLASH
    lds  r24, open_secs
    clr  r25
    rcall LCD_PRINT_INT16
    ldi  r24, 's'
    rcall LCD_DATA
    ret

SCREEN_WRONG:
    rcall LCD_CLEAR
    clr  r24
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_WRONG1<<1)
    ldi  ZH, high(STR_WRONG1<<1)
    rcall LCD_PRINT_FLASH
    ldi  r24, 1
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_WRONG2<<1)
    ldi  ZH, high(STR_WRONG2<<1)
    rcall LCD_PRINT_FLASH
    ldi  tmp, MAX_ATTEMPTS
    lds  r24, fail_count
    sub  tmp, r24
    mov  r24, tmp
    clr  r25
    rcall LCD_PRINT_INT16
    ret

SCREEN_LOCKOUT:
    rcall LCD_CLEAR
    clr  r24
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_LOCK1<<1)
    ldi  ZH, high(STR_LOCK1<<1)
    rcall LCD_PRINT_FLASH
    ldi  r24, 1
    clr  r25
    rcall LCD_SET_CURSOR
    ldi  ZL, low(STR_LOCK2<<1)
    ldi  ZH, high(STR_LOCK2<<1)
    rcall LCD_PRINT_FLASH
    lds  r24, lockout_secs
    clr  r25
    rcall LCD_PRINT_INT16
    ldi  r24, 's'
    rcall LCD_DATA
    ret

; ===== UTILS =======================================================================
LCD_PRINT_INT16:
    push r16
    push r17
    push r18
    push r19
    push r20
    push r21

    mov  r20, r24
    mov  r21, r25

    tst  r21
    brpl PI16_POS
    ldi  r24, '-'
    rcall LCD_DATA
    com  r20
    com  r21
    ldi  r24, 1
    add  r20, r24
    clr  r24
    adc  r21, r24

PI16_POS:
    clr  r16
    ldi  r17, 0

    tst  r20
    brne PI16_DIVLOOP
    tst  r21
    brne PI16_DIVLOOP
    ldi  r24, '0'
    rcall LCD_DATA
    rjmp PI16_DONE

PI16_DIVLOOP:
    rcall DIV16_BY10
    ldi  r24, '0'
    add  r24, r18
    push r24
    inc  r16
    tst  r20
    brne PI16_DIVLOOP
    tst  r21
    brne PI16_DIVLOOP

PI16_PRINT:
    tst  r16
    breq PI16_DONE
    pop  r24
    rcall LCD_DATA
    dec  r16
    rjmp PI16_PRINT

PI16_DONE:
    pop  r21
    pop  r20
    pop  r19
    pop  r18
    pop  r17
    pop  r16
    ret

; Div r21:r20 by 10 (unsigned)
; Result: r21:r20 = quotient, r18 = remainder
DIV16_BY10:
    push r22
    push r23
    clr  r18
    ldi  r22, 16
DIV10_LOOP:
    lsl  r20
    rol  r21
    rol  r18
    cpi  r18, 10
    brlo DIV10_NOSUB
    subi r18, 10
    ori  r20, 1
DIV10_NOSUB:
    dec  r22
    brne DIV10_LOOP
    pop  r23
    pop  r22
    ret
