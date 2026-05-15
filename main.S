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

; EEPROM
.equ EE_TARGET_L,    0x00
.equ EE_TARGET_H,    0x01
.equ EE_FAIL_CNT,    0x02 ; 0 = no fails, 1-3 = fail count, 4 = lockout active
.equ EE_LOCKOUT_FL,  0x03 ; 0 = not in lockout, 1 = in lockout

; !!!TARGET VALUE!!!
.equ DEFAULT_TARGET, 42

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


; ===== Vector Table =======================================================================
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