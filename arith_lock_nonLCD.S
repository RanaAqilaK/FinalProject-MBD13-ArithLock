#define __SFR_OFFSET 0x00
#include <avr/io.h>

.global main

; ===== DEFS =======================================================================
; Serial
.equ BAUD,            115200                    ; Baud Rate
.equ UBRR_VAL,        16                        ; For 16 MHz with U2X0 = 1 (2.1% error)

; State value
.equ STATE_STANDBY,   0
.equ STATE_INPUT,     1
.equ STATE_OPEN,      2
.equ STATE_LOCKOUT,   3

; Security parameters
.equ MAX_ATTEMPTS,    3
.equ LOCKOUT_SECS,    30
.equ OPEN_SECS,       5
.equ DEBOUNCE_MS,     100                       ; Debounce duration

; Arithmetic button
.equ STEP_POS_INT0,   2                         ; btn_id 1  (PD2)
.equ STEP_NEG_INT1,  -2                         ; btn_id 2  (PD3)
.equ STEP_POS_PD4,    5                         ; btn_id 3  (PD4)
.equ STEP_NEG_PD5,   -5                         ; btn_id 4  (PD5)
.equ STEP_POS_PD6,    7                         ; btn_id 5  (PD6)
.equ STEP_NEG_PD7,   -7                         ; btn_id 6  (PD7)
.equ STEP_POS_PB0,    9                         ; btn_id 7  (PB0)
.equ STEP_NEG_PB1,   -9                         ; btn_id 8  (PB1)

; EEPROM
.equ EE_TARGET_L,    0x00
.equ EE_TARGET_H,    0x01
.equ EE_FAIL_CNT,    0x02                       ; 0 = no fails, 1-3 = fail count, 4 = lockout active
.equ EE_LOCKOUT_FL,  0x03                       ; 0 = not in lockout, 1 = in lockout

; !!!TARGET VALUE!!!
.equ DEFAULT_TARGET, 97

; LCD
.equ LCD_ADDR,       0x27                       ; I2C address for LCD PCF8574
.equ LCD_BL,         0x08                       ; Backlight
.equ LCD_EN,         0x04                       ; Enable
.equ LCD_RW,         0x02                       ; Read/Write
.equ LCD_RS,         0x01                       ; Register Select

; Servo
.equ SERVO_LOCKED_POS, 1200                     ; 1.2 ms PWM pulse width
.equ SERVO_OPEN_POS,   2000                     ; 2 ms PWM pulse width (180 degrees)
.equ ICR1_VAL,        20000                     ; 20 ms di 50 Hz untuk servo control
.equ OCR2A_VAL,      249                        ; 1 ms pulse width saat 16 MHz dengan prescaler 64

; Registers
#define tmp        r16
#define tmp2       r17
#define state      r18
#define btn_flag   r19
#define btn_id     r20

; ===== ADDRESS MAP =======================================================================
.section .bss
current_val_l:   .skip 1                        ; Current input value (0-99)
current_val_h:   .skip 1                        ; Current input value (0-99)
target_val_l:    .skip 1                        ; Target value stored in EEPROM
target_val_h:    .skip 1                        ; Target value stored in EEPROM
fail_count:      .skip 1                        ; self-explanatory
lockout_secs:    .skip 1                        ; self-explanatory
open_secs:       .skip 1                        ; self-explanatory
ms_tick:         .skip 2                        ; 16-bit counter untuk timer tick (1 ms per tick)
debounce_ms:     .skip 1                        ; self-explanatory
reset_cause:     .skip 1                        ; MCUSR snapshot (reset cause)

.section .text

; ===== RESET / INIT =======================================================================
main:
RESET:
    ; Disable watchdog to prevent reset loop (if WDT fuse enabled)
    wdr
    in   tmp, MCUSR
    sts  reset_cause, tmp
    clr  tmp
    out  MCUSR, tmp
    ldi  tmp, (1<<WDCE)|(1<<WDE)
    sts  WDTCSR, tmp
    ldi  tmp, 0x00
    sts  WDTCSR, tmp

    ; Stack pointer
    ldi  tmp, hi8(RAMEND)
    out  SPH, tmp
    ldi  tmp, lo8(RAMEND)
    out  SPL, tmp

    ; Enable global pull-ups
    in   tmp, MCUCR
    andi tmp, (0xFF ^ (1<<PUD))
    out  MCUCR, tmp

    ; Clear state registers
    clr  btn_flag                               ; btn_flag = 0
    clr  btn_id                                 ; btn_id   = 0
    ldi  state, STATE_STANDBY                   ; state    = STANDBY

    ; General Purpose I/O Init
    ; PD0 RX (UART) - input
    ; PD1 TX (UART) - output
    ; PD2 and PD3 input with pull-up (buttons)
    cbi  DDRD, 0
    sbi  DDRD, 1
    cbi  DDRD, 2
    cbi  DDRD, 3
    sbi  PORTD, 2
    sbi  PORTD, 3
    ; PD4-PD7 pull-up input (buttons)
    cbi  DDRD, 4
    cbi  DDRD, 5
    cbi  DDRD, 6
    cbi  DDRD, 7
    sbi  PORTD, 4
    sbi  PORTD, 5
    sbi  PORTD, 6
    sbi  PORTD, 7

    ; PB0, PB1, PB3, PB4 pull-up input (buttons)
    cbi  DDRB, 0
    cbi  DDRB, 1
    cbi  DDRB, 3
    cbi  DDRB, 4
    sbi  PORTB, 0
    sbi  PORTB, 1
    sbi  PORTB, 3
    sbi  PORTB, 4
    ; PB2 output (servo)
    sbi  DDRB, 2
    cbi  PORTB, 2

    ; UART Init
    ldi  tmp, hi8(UBRR_VAL)
    sts  UBRR0H, tmp
    ldi  tmp, lo8(UBRR_VAL)
    sts  UBRR0L, tmp
    ldi  tmp, (1<<U2X0)
    sts  UCSR0A, tmp
    ldi  tmp, (1<<RXEN0)|(1<<TXEN0)
    sts  UCSR0B, tmp
    ldi  tmp, (1<<UCSZ01)|(1<<UCSZ00)
    sts  UCSR0C, tmp

    ; Print reset cause for debugging
    ldi  ZL, lo8(STR_RST)
    ldi  ZH, hi8(STR_RST)
    rcall UART_PRINT_FLASH
    lds  r24, reset_cause
    rcall UART_PRINT_HEX8
    rcall UART_CRLF

    ; TIMER1 (Servo PWM, 50Hz)
    ldi  tmp, hi8(ICR1_VAL)
    sts  ICR1H, tmp
    ldi  tmp, lo8(ICR1_VAL)
    sts  ICR1L, tmp
    ldi  tmp, hi8(SERVO_LOCKED_POS)
    sts  OCR1AH, tmp
    ldi  tmp, lo8(SERVO_LOCKED_POS)
    sts  OCR1AL, tmp
    ldi  tmp, (1<<WGM11)
    sts  TCCR1A, tmp
    ldi  tmp, (1<<WGM13)|(1<<WGM12)|(1<<CS11)
    sts  TCCR1B, tmp
    ldi  tmp, (1<<OCIE1A)|(1<<TOIE1)
    sts  TIMSK1, tmp

    ; TIMER2 (1 ms tick)
    ldi  tmp, OCR2A_VAL
    sts  OCR2A, tmp
    ldi  tmp, (1<<WGM21)
    sts  TCCR2A, tmp
    ldi  tmp, (1<<CS22)
    sts  TCCR2B, tmp
    ldi  tmp, (1<<OCIE2A)
    sts  TIMSK2, tmp

    ; STOP Timer0 (may be left running by Arduino bootloader)
    clr  tmp
    out  TCCR0B, tmp                            ; Stop Timer0 clock
    out  TCCR0A, tmp                            ; Reset Timer0 mode
    sts  TIMSK0, tmp                            ; Disable all Timer0 interrupts

    ; Clear ALL pending timer interrupt flags (write 1 to clear)
    ldi  tmp, 0xFF
    out  TIFR0, tmp                             ; Clear Timer0 flags
    out  TIFR1, tmp                             ; Clear Timer1 flags
    out  TIFR2, tmp                             ; Clear Timer2 flags

    ; Interrupts Init (external interrupts off, buttons are polled)
    ldi  tmp, 0
    out  EIMSK, tmp
    ; Clear external interrupt flags too
    ldi  tmp, (1<<INTF0)|(1<<INTF1)
    out  EIFR, tmp

    ; TWI (I2C) Init for LCD
    ldi  tmp, 72
    sts  TWBR, tmp
    ldi  tmp, 0
    sts  TWSR, tmp
    ldi  tmp, (1<<TWEN)
    sts  TWCR, tmp

    ; SRAM INIT - clear all var
    clr  tmp
    sts  current_val_l, tmp
    sts  current_val_h, tmp
    sts  fail_count, tmp
    sts  lockout_secs, tmp
    sts  open_secs, tmp
    sts  ms_tick, tmp
    sts  ms_tick+1, tmp
    sts  debounce_ms, tmp

    rcall EEPROM_READ_TARGET
    rcall EEPROM_READ_FAILCNT

    rcall DELAY_100MS
    rcall LCD_INIT
    rcall LCD_CLEAR

    ldi  ZL, lo8(STR_BOOT)
    ldi  ZH, hi8(STR_BOOT)
    rcall UART_PRINT_FLASH

    ldi  tmp2, EE_LOCKOUT_FL
    rcall EEPROM_READ_BYTE                      ; hasil di r24
    cpi  r24, 0xFF
    brne INIT_LOCKOUT_CHK
    clr  r24
INIT_LOCKOUT_CHK:
    tst  r24
    brne INIT_LOCKOUT

    rcall SCREEN_STANDBY
    sei
    rjmp MAIN_LOOP

INIT_LOCKOUT:
    ldi  state, STATE_LOCKOUT
    ldi  tmp, LOCKOUT_SECS
    sts  lockout_secs, tmp
    rcall SCREEN_LOCKOUT
    sei

; ===== MAIN LOOP =======================================================================
MAIN_LOOP:
    rcall POLL_BUTTONS
    rcall CHECK_SECOND_TICK
    tst   btn_flag                              ; btn_flag
    breq  MAIN_LOOP
    clr   btn_flag                              ; clear btn_flag
    rcall HANDLE_BUTTON
    rcall WAIT_RELEASE
    rjmp  MAIN_LOOP

; ===== Interrupts (ISR) =======================================================================

; INT0 = BTN+2 - PD2
.global INT0_vect
INT0_vect:
    push tmp
    in   tmp, SREG
    push tmp
    lds  tmp, debounce_ms
    tst  tmp
    brne INT0_SKIP
    ldi  tmp, DEBOUNCE_MS
    sts  debounce_ms, tmp
    ldi  btn_id, 1                              ; btn_id = 1
    ldi  btn_flag, 1                            ; btn_flag = 1
INT0_SKIP:
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

; INT1 = BTN-2 - PD3
.global INT1_vect
INT1_vect:
    push tmp
    in   tmp, SREG
    push tmp
    lds  tmp, debounce_ms
    tst  tmp
    brne INT1_SKIP
    ldi  tmp, DEBOUNCE_MS
    sts  debounce_ms, tmp
    ldi  btn_id, 2                              ; btn_id = 2
    ldi  btn_flag, 1                            ; btn_flag = 1
INT1_SKIP:
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

; Timer2 Compare Match A 1 ms tick
.global TIMER2_COMPA_vect
TIMER2_COMPA_vect:
    push tmp
    in   tmp, SREG
    push tmp

    ; Debounce countdown
    lds  tmp, debounce_ms
    tst  tmp
    breq T2_SKIP_DEBOUNCE
    dec  tmp
    sts  debounce_ms, tmp
T2_SKIP_DEBOUNCE:

    ; Increment 16-bit ms_tick
    lds  tmp, ms_tick
    inc  tmp
    sts  ms_tick, tmp
    brne T2_NO_CARRY
    lds  tmp, ms_tick+1
    inc  tmp
    sts  ms_tick+1, tmp
T2_NO_CARRY:

    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

; Timer1 Compare Match A (end of servo pulse)
.global TIMER1_COMPA_vect
TIMER1_COMPA_vect:
    push tmp
    in   tmp, SREG
    push tmp
    cbi  PORTB, 2
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

; Timer1 Overflow (start of servo pulse)
.global TIMER1_OVF_vect
TIMER1_OVF_vect:
    push tmp
    in   tmp, SREG
    push tmp
    sbi  PORTB, 2
    pop  tmp
    out  SREG, tmp
    pop  tmp
    reti

; ===== BUTTON POLLING & INPUT ========================================================================
POLL_BUTTONS:
    ; Skip if debounce active or event already pending
    lds  tmp, debounce_ms
    tst  tmp
    brne POLL_EXIT
    tst  btn_flag                               ; btn_flag
    brne POLL_EXIT

    ; ---- PIND: PD2=+2, PD3=-2, PD4=+5, PD5=-5, PD6=+7, PD7=-7 ----
    sbic PIND, 2
    rjmp POLL_CHK_PD3
    ldi  btn_id, 1                              ; btn_id = 1 (+2)
    rjmp POLL_SET_FLAG
POLL_CHK_PD3:
    sbic PIND, 3
    rjmp POLL_CHK_PD4
    ldi  btn_id, 2                              ; btn_id = 2 (-2)
    rjmp POLL_SET_FLAG
POLL_CHK_PD4:
    sbic PIND, 4
    rjmp POLL_CHK_PD5
    ldi  btn_id, 3                              ; btn_id = 3 (+5)
    rjmp POLL_SET_FLAG
POLL_CHK_PD5:
    sbic PIND, 5
    rjmp POLL_CHK_PD6
    ldi  btn_id, 4                              ; btn_id = 4 (-5)
    rjmp POLL_SET_FLAG
POLL_CHK_PD6:
    sbic PIND, 6
    rjmp POLL_CHK_PD7
    ldi  btn_id, 5                              ; btn_id = 5 (+7)
    rjmp POLL_SET_FLAG
POLL_CHK_PD7:
    sbic PIND, 7
    rjmp POLL_CHK_PB0
    ldi  btn_id, 6                              ; btn_id = 6 (-7)
    rjmp POLL_SET_FLAG

    ; ---- PINB: PB0=+9, PB1=-9, PB3=CONFIRM, PB4=CLEAR ----
POLL_CHK_PB0:
    sbic PINB, 0
    rjmp POLL_CHK_PB1
    ldi  btn_id, 7                              ; btn_id = 7 (+9)
    rjmp POLL_SET_FLAG
POLL_CHK_PB1:
    sbic PINB, 1
    rjmp POLL_CHK_PB3
    ldi  btn_id, 8                              ; btn_id = 8 (-9)
    rjmp POLL_SET_FLAG
POLL_CHK_PB3:
    sbic PINB, 3
    rjmp POLL_CHK_PB4
    ldi  btn_id, 9                              ; btn_id = 9 (CONFIRM)
    rjmp POLL_SET_FLAG
POLL_CHK_PB4:
    sbic PINB, 4
    rjmp POLL_EXIT
    ldi  btn_id, 10                             ; btn_id = 10 (CLEAR)

POLL_SET_FLAG:
    ldi  tmp, DEBOUNCE_MS
    sts  debounce_ms, tmp
    ldi  btn_flag, 1                            ; btn_flag = 1

POLL_EXIT:
    ret

; ===== WAIT FOR RELEASE ============================================================
; Wait until the last pressed button is released (pin returns HIGH)
WAIT_RELEASE:
    cpi  btn_id, 1
    brne WR_CHK2
WR_PD2:
    sbis PIND, 2
    rjmp WR_PD2
    rjmp WR_DEBOUNCE_RET
WR_CHK2:
    cpi  btn_id, 2
    brne WR_CHK3
WR_PD3:
    sbis PIND, 3
    rjmp WR_PD3
    rjmp WR_DEBOUNCE_RET
WR_CHK3:
    cpi  btn_id, 3
    brne WR_CHK4
WR_PD4:
    sbis PIND, 4
    rjmp WR_PD4
    rjmp WR_DEBOUNCE_RET
WR_CHK4:
    cpi  btn_id, 4
    brne WR_CHK5
WR_PD5:
    sbis PIND, 5
    rjmp WR_PD5
    rjmp WR_DEBOUNCE_RET
WR_CHK5:
    cpi  btn_id, 5
    brne WR_CHK6
WR_PD6:
    sbis PIND, 6
    rjmp WR_PD6
    rjmp WR_DEBOUNCE_RET
WR_CHK6:
    cpi  btn_id, 6
    brne WR_CHK7
WR_PD7:
    sbis PIND, 7
    rjmp WR_PD7
    rjmp WR_DEBOUNCE_RET
WR_CHK7:
    cpi  btn_id, 7
    brne WR_CHK8
WR_PB0:
    sbis PINB, 0
    rjmp WR_PB0
    rjmp WR_DEBOUNCE_RET
WR_CHK8:
    cpi  btn_id, 8
    brne WR_CHK9
WR_PB1:
    sbis PINB, 1
    rjmp WR_PB1
    rjmp WR_DEBOUNCE_RET
WR_CHK9:
    cpi  btn_id, 9
    brne WR_CHK10
WR_PB3:
    sbis PINB, 3
    rjmp WR_PB3
    rjmp WR_DEBOUNCE_RET
WR_CHK10:
    cpi  btn_id, 10
    brne WR_DONE
WR_PB4:
    sbis PINB, 4
    rjmp WR_PB4
    rjmp WR_DEBOUNCE_RET
WR_DONE:
    ret

WR_DEBOUNCE_RET:
    ldi  tmp, DEBOUNCE_MS
    sts  debounce_ms, tmp
    ret

; ===== HANDLE_BUTTON & STATE MACHINE ========================================================================
HANDLE_BUTTON:
    cpi  state, STATE_STANDBY
    brne HB_CHK_INPUT
    ; Transisi STANDBY -> INPUT, reset nilai
    ldi  state, STATE_INPUT
    clr  tmp
    sts  current_val_l, tmp
    sts  current_val_h, tmp
    rcall SCREEN_INPUT
    rjmp HB_DO_ARITH

HB_CHK_INPUT:
    cpi  state, STATE_INPUT
    brne HB_CHK_OPEN
    rjmp HB_DO_ARITH

HB_CHK_OPEN:
    cpi  state, STATE_OPEN
    brne HB_LOCKOUT_JMP
    ; In OPEN state only CLEAR is processed
    cpi  btn_id, 10                             ; btn_id == CLEAR?
    brne HB_OPEN_RET
    rjmp HB_DO_CLEAR
HB_OPEN_RET:
    ret

HB_LOCKOUT_JMP:
    rjmp HB_LOCKOUT_CHK

HB_LOCKOUT_CHK:
    ; STATE_LOCKOUT: ignore all input
    ret

HB_DO_ARITH:
    cpi  btn_id, 9                              ; CONFIRM?
    brne HB_CHK_CLEAR
    rjmp HB_DO_CONFIRM
HB_CHK_CLEAR:
    cpi  btn_id, 10                             ; CLEAR?
    brne HB_DO_ARITH_CONT
    rjmp HB_DO_CLEAR

HB_DO_ARITH_CONT:

    ; Determine delta based on btn_id
    ldi  r24, 0
    ldi  r25, 0

    cpi  btn_id, 1
    brne HB_CHK2
    ldi  r24, lo8(STEP_POS_INT0)                ; +2
    ldi  r25, hi8(STEP_POS_INT0)
    rjmp HB_ADD_DELTA

HB_CHK2:
    cpi  btn_id, 2
    brne HB_CHK3
    ldi  r24, lo8(STEP_NEG_INT1)                ; -2
    ldi  r25, hi8(STEP_NEG_INT1)
    rjmp HB_ADD_DELTA

HB_CHK3:
    cpi  btn_id, 3
    brne HB_CHK4
    ldi  r24, lo8(STEP_POS_PD4)                 ; +5
    ldi  r25, hi8(STEP_POS_PD4)
    rjmp HB_ADD_DELTA

HB_CHK4:
    cpi  btn_id, 4
    brne HB_CHK5
    ldi  r24, lo8(STEP_NEG_PD5)                 ; -5
    ldi  r25, hi8(STEP_NEG_PD5)
    rjmp HB_ADD_DELTA

HB_CHK5:
    cpi  btn_id, 5
    brne HB_CHK6
    ldi  r24, lo8(STEP_POS_PD6)                 ; +7
    ldi  r25, hi8(STEP_POS_PD6)
    rjmp HB_ADD_DELTA

HB_CHK6:
    cpi  btn_id, 6
    brne HB_CHK7
    ldi  r24, lo8(STEP_NEG_PD7)                 ; -7
    ldi  r25, hi8(STEP_NEG_PD7)
    rjmp HB_ADD_DELTA

HB_CHK7:
    cpi  btn_id, 7
    brne HB_CHK8
    ldi  r24, lo8(STEP_POS_PB0)                 ; +9
    ldi  r25, hi8(STEP_POS_PB0)
    rjmp HB_ADD_DELTA

HB_CHK8:
    cpi  btn_id, 8
    brne HB_DO_ARITH_END
    ldi  r24, lo8(STEP_NEG_PB1)                 ; -9
    ldi  r25, hi8(STEP_NEG_PB1)

HB_ADD_DELTA:
    lds  r22, current_val_l
    lds  r23, current_val_h
    add  r22, r24
    adc  r23, r25
    sts  current_val_l, r22
    sts  current_val_h, r23
    rcall SCREEN_INPUT
    rcall LOG_BTN_PRESS

HB_DO_ARITH_END:
    ret

HB_DO_CONFIRM:
    ; Compare current_val == target_val
    lds  r22, current_val_l
    lds  r23, current_val_h
    lds  r24, target_val_l
    lds  r25, target_val_h
    cp   r22, r24
    cpc  r23, r25
    brne HB_WRONG

    ; === BENAR ===
    clr  tmp
    sts  fail_count, tmp
    rcall EEPROM_WRITE_FAILCNT
    clr  r24                                    ; tulis 0 ke EE_LOCKOUT_FL
    ldi  tmp2, EE_LOCKOUT_FL
    rcall EEPROM_WRITE_BYTE_R24
    rcall SERVO_OPEN
    ldi  state, STATE_OPEN
    ldi  tmp, OPEN_SECS
    sts  open_secs, tmp
    clr  tmp
    sts  ms_tick,   tmp
    sts  ms_tick+1, tmp
    rcall SCREEN_OPEN
    rcall LOG_SUCCESS
    ret

HB_WRONG:
    lds  tmp, fail_count
    inc  tmp
    sts  fail_count, tmp
    rcall EEPROM_WRITE_FAILCNT
    rcall LOG_FAIL
    lds  tmp, fail_count
    cpi  tmp, MAX_ATTEMPTS
    brsh HB_LOCKOUT
    rcall SCREEN_WRONG
    rcall DELAY_1S
    ldi  state, STATE_STANDBY
    rcall SCREEN_STANDBY
    ret

HB_LOCKOUT:
    ldi  r24, 1
    ldi  tmp2, EE_LOCKOUT_FL
    rcall EEPROM_WRITE_BYTE_R24
    ldi  state, STATE_LOCKOUT
    ldi  tmp, LOCKOUT_SECS
    sts  lockout_secs, tmp
    clr  tmp
    sts  ms_tick,   tmp
    sts  ms_tick+1, tmp
    rcall SCREEN_LOCKOUT
    rcall LOG_LOCKOUT
    ret

HB_DO_CLEAR:
    clr  tmp
    sts  current_val_l, tmp
    sts  current_val_h, tmp
    ldi  state, STATE_STANDBY
    rcall SCREEN_STANDBY
    ret

; ===== CHECK_SECOND_TICK ====================================================================
CHECK_SECOND_TICK:
    cli
    lds  r24, ms_tick
    lds  r25, ms_tick+1
    sei
    ; Compare ms_tick >= 1000
    cpi  r24, lo8(1000)
    ldi  tmp, hi8(1000)
    cpc  r25, tmp
    brlo CST_EXIT

    ; Reset counter
    clr  tmp
    cli
    sts  ms_tick,   tmp
    sts  ms_tick+1, tmp
    sei

    cpi  state, STATE_OPEN
    breq CST_OPEN
    cpi  state, STATE_LOCKOUT
    breq CST_LOCKOUT
    ret

CST_OPEN:
    lds  tmp, open_secs
    dec  tmp
    sts  open_secs, tmp
    tst  tmp
    brne CST_OPEN_UPDATE
    ; Time = zero -> close
    rcall SERVO_CLOSE
    ldi  state, STATE_STANDBY
    rcall SCREEN_STANDBY
    rcall LOG_CLOSE
    ret
CST_OPEN_UPDATE:
    rcall SCREEN_OPEN
    ret

CST_LOCKOUT:
    lds  tmp, lockout_secs
    dec  tmp
    sts  lockout_secs, tmp
    tst  tmp
    brne CST_LOCK_UPDATE
    ; Lockout done -> reset
    clr  tmp
    sts  fail_count, tmp
    rcall EEPROM_WRITE_FAILCNT
    clr  r24
    ldi  tmp2, EE_LOCKOUT_FL
    rcall EEPROM_WRITE_BYTE_R24
    ldi  state, STATE_STANDBY
    rcall SCREEN_STANDBY
    ret
CST_LOCK_UPDATE:
    rcall SCREEN_LOCKOUT
CST_EXIT:
    ret

; ===== SERVO ========================================================================
SERVO_OPEN:
    ldi  tmp, hi8(SERVO_OPEN_POS)
    sts  OCR1AH, tmp
    ldi  tmp, lo8(SERVO_OPEN_POS)
    sts  OCR1AL, tmp
    ret

SERVO_CLOSE:
    ldi  tmp, hi8(SERVO_LOCKED_POS)
    sts  OCR1AH, tmp
    ldi  tmp, lo8(SERVO_LOCKED_POS)
    sts  OCR1AL, tmp
    ret

; ===== LCD/TWI ======================================================================
TWI_START:
    ret
;    ldi  tmp, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
;    sts  TWCR, tmp
;TWI_WAIT_S:
;    lds  tmp, TWCR
;    sbrs tmp, TWINT
;    rjmp TWI_WAIT_S
;    ret

TWI_STOP:
    ret
;    ldi  tmp, (1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
;    sts  TWCR, tmp
;    ret

TWI_WRITE:
    ret
;    sts  TWDR, r24
;    ldi  tmp, (1<<TWINT)|(1<<TWEN)
;    sts  TWCR, tmp
;TWI_WAIT_W:
;    lds  tmp, TWCR
;    sbrs tmp, TWINT
;    rjmp TWI_WAIT_W
;    lds  r25, TWSR
;    andi r25, 0xF8
;    ret

LCD_SEND_RAW:
    ret
;    push r24
;    rcall TWI_START
;    ldi  r24, (LCD_ADDR<<1)
;    rcall TWI_WRITE
;    pop  r24
;    ori  r24, LCD_BL                            ; backlight always on
;    rcall TWI_WRITE
;    rcall TWI_STOP
;    ret

; Pulse EN: send r24 with EN=1 then EN=0
LCD_PULSE_EN:
    ret
;    push r24
;    ori  r24, LCD_EN
;    rcall LCD_SEND_RAW
;    rcall DELAY_1US_x5
;    pop  r24
;    andi r24, 0xFB                              ; clear EN
;    rcall LCD_SEND_RAW
;    rcall DELAY_1US_x5
;    ret

; Send nibble: upper 4-bit r24 as data, r23 bit0 = RS
LCD_SEND_NIBBLE:
    ret
;    push r24
;    push r23
;    andi r24, 0xF0
;    andi r23, 0x01
;    or   r24, r23
;    rcall LCD_PULSE_EN
;    pop  r23
;    pop  r24
;    ret

; Send full byte to LCD: r24=data, r23=RS (0=cmd, 1=data char)
LCD_SEND_BYTE:
    ret
;    push r24
;    push r23
;    rcall LCD_SEND_NIBBLE                       ; high nibble first
;    pop  r23
;    pop  r24
;    push r24
;    push r23
;    swap r24                                    ; move low nibble to upper position
;    andi r24, 0xF0
;    andi r23, 0x01
;    or   r24, r23
;    rcall LCD_PULSE_EN                          ; send low nibble
;    pop  r23
;    pop  r24
;    rcall DELAY_50US
;    ret

LCD_CMD:
    ret
;    clr  r23
;    rcall LCD_SEND_BYTE
;    ret

LCD_DATA:
    ret
;    ldi  r23, 1
;    rcall LCD_SEND_BYTE
;    ret

; Inisialisasi LCD
LCD_INIT:
    ret
;    rcall DELAY_50MS
;    ldi  r24, 0x30
;    rcall LCD_PULSE_EN
;    rcall DELAY_5MS
;    ldi  r24, 0x30
;    rcall LCD_PULSE_EN
;    rcall DELAY_5MS
;    ldi  r24, 0x30
;    rcall LCD_PULSE_EN
;    rcall DELAY_1MS
;    ldi  r24, 0x20
;    rcall LCD_PULSE_EN
;    rcall DELAY_1MS
;    ldi  r24, 0x28
;    rcall LCD_CMD
;    ldi  r24, 0x0C
;    rcall LCD_CMD
;    ldi  r24, 0x06
;    rcall LCD_CMD
;    ret

LCD_CLEAR:
    ret
;    ldi  r24, 0x01
;    rcall LCD_CMD
;    rcall DELAY_2MS
;    ret

LCD_SET_CURSOR:
    ret
;    cpi  r24, 1
;    brne LCD_SET_ROW0
;    ori  r25, 0x40
;LCD_SET_ROW0:
;    ori  r25, 0x80
;    mov  r24, r25
;    rcall LCD_CMD
;    ret

LCD_PRINT_FLASH:
    ret
;LCD_PRINT_FLASH_LOOP:
;    lpm  r24, Z+
;    tst  r24
;    breq LCD_PRINT_FLASH_END
;    rcall LCD_DATA
;    rjmp LCD_PRINT_FLASH_LOOP
;LCD_PRINT_FLASH_END:
;    ret

LCD_PRINT_SRAM:
    ret
;LCD_PRINT_SRAM_LOOP:
;    ld   r24, Z+
;    tst  r24
;    breq LCD_PRINT_SRAM_END
;    rcall LCD_DATA
;    rjmp LCD_PRINT_SRAM_LOOP
;LCD_PRINT_SRAM_END:
;    ret

; ===== SCREEN FUNC ==============================================================
SCREEN_STANDBY:
    ret
;    rcall LCD_CLEAR
;    clr  r24
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_STANDBY1)
;    ldi  ZH, hi8(STR_STANDBY1)
;    rcall LCD_PRINT_FLASH
;    ldi  r24, 1
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_STANDBY2)
;    ldi  ZH, hi8(STR_STANDBY2)
;    rcall LCD_PRINT_FLASH
;    ret

SCREEN_INPUT:
    ret
;    rcall LCD_CLEAR
;    clr  r24
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_VAL)
;    ldi  ZH, hi8(STR_VAL)
;    rcall LCD_PRINT_FLASH
;    lds  r24, current_val_l
;    lds  r25, current_val_h
;    rcall LCD_PRINT_INT16
;
;    ldi  r24, 1
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_DIST)
;    ldi  ZH, hi8(STR_DIST)
;    rcall LCD_PRINT_FLASH
;
;    lds  r22, target_val_l
;    lds  r23, target_val_h
;    lds  r24, current_val_l
;    lds  r25, current_val_h
;    sub  r22, r24
;    sbc  r23, r25
;    tst  r23
;    brpl SI_POS
;    com  r22
;    com  r23
;    ldi  tmp, 1
;    add  r22, tmp
;    clr  tmp
;    adc  r23, tmp
;SI_POS:
;    mov  r24, r22
;    mov  r25, r23
;    rcall LCD_PRINT_INT16
;    ret

SCREEN_OPEN:
    ret
;    rcall LCD_CLEAR
;    clr  r24
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_OPEN1)
;    ldi  ZH, hi8(STR_OPEN1)
;    rcall LCD_PRINT_FLASH
;    ldi  r24, 1
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_OPEN2)
;    ldi  ZH, hi8(STR_OPEN2)
;    rcall LCD_PRINT_FLASH
;    lds  r24, open_secs
;    clr  r25
;    rcall LCD_PRINT_INT16
;    ldi  r24, 's'
;    rcall LCD_DATA
;    ret

SCREEN_WRONG:
    ret
;    rcall LCD_CLEAR
;    clr  r24
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_WRONG1)
;    ldi  ZH, hi8(STR_WRONG1)
;    rcall LCD_PRINT_FLASH
;    ldi  r24, 1
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_WRONG2)
;    ldi  ZH, hi8(STR_WRONG2)
;    rcall LCD_PRINT_FLASH
;    ldi  tmp, MAX_ATTEMPTS
;    lds  r24, fail_count
;    sub  tmp, r24
;    mov  r24, tmp
;    clr  r25
;    rcall LCD_PRINT_INT16
;    ret

SCREEN_LOCKOUT:
    ret
;    rcall LCD_CLEAR
;    clr  r24
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_LOCK1)
;    ldi  ZH, hi8(STR_LOCK1)
;    rcall LCD_PRINT_FLASH
;    ldi  r24, 1
;    clr  r25
;    rcall LCD_SET_CURSOR
;    ldi  ZL, lo8(STR_LOCK2)
;    ldi  ZH, hi8(STR_LOCK2)
;    rcall LCD_PRINT_FLASH
;    lds  r24, lockout_secs
;    clr  r25
;    rcall LCD_PRINT_INT16
;    ldi  r24, 's'
;    rcall LCD_DATA
;    ret

; ===== UTILS =======================================================================
LCD_PRINT_INT16:
    ret
;    push tmp
;    push tmp2
;    push state
;    push btn_flag
;    push btn_id
;    push r21
;
;    mov  btn_id, r24
;    mov  r21, r25
;
;    tst  r21
;    brpl PI16_POS
;    ldi  r24, '-'
;    rcall LCD_DATA
;    com  btn_id
;    com  r21
;    ldi  r24, 1
;    add  btn_id, r24
;    clr  r24
;    adc  r21, r24
;
;PI16_POS:
;    clr  tmp
;
;    tst  btn_id
;    brne PI16_DIVLOOP
;    tst  r21
;    brne PI16_DIVLOOP
;    ldi  r24, '0'
;    rcall LCD_DATA
;    rjmp PI16_DONE
;
;PI16_DIVLOOP:
;    rcall DIV16_BY10
;    ldi  r24, '0'
;    add  r24, state
;    push r24
;    inc  tmp
;    tst  btn_id
;    brne PI16_DIVLOOP
;    tst  r21
;    brne PI16_DIVLOOP
;
;PI16_PRINT:
;    tst  tmp
;    breq PI16_DONE
;    pop  r24
;    push tmp
;    rcall LCD_DATA
;    pop  tmp
;    dec  tmp
;    rjmp PI16_PRINT
;
;PI16_DONE:
;    pop  r21
;    pop  btn_id
;    pop  btn_flag
;    pop  state
;    pop  tmp2
;    pop  tmp
;    ret

; Div r21:btn_id by 10 (unsigned)
; Result: r21:btn_id = quotient, state = remainder
DIV16_BY10:
    push r22
    push r23
    clr  state
    ldi  r22, 16
DIV10_LOOP:
    lsl  btn_id
    rol  r21
    rol  state
    cpi  state, 10
    brlo DIV10_NOSUB
    subi state, 10
    ori  btn_id, 1
DIV10_NOSUB:
    dec  r22
    brne DIV10_LOOP
    pop  r23
    pop  r22
    ret

; ===== UART ========================================================================
UART_TX:
    lds  tmp, UCSR0A
    sbrs tmp, UDRE0
    rjmp UART_TX
    sts  UDR0, r24
    ret

UART_PRINT_FLASH:
    lpm  r24, Z+
    tst  r24
    breq UART_PRINT_FLASH_END
    rcall UART_TX
    rjmp UART_PRINT_FLASH
UART_PRINT_FLASH_END:
    ret

UART_PRINT_SRAM:
    ld   r24, Z+
    tst  r24
    breq UART_PRINT_SRAM_END
    rcall UART_TX
    rjmp UART_PRINT_SRAM
UART_PRINT_SRAM_END:
    ret

; Print 8-bit hex in r24 via UART
UART_PRINT_HEX8:
    push r24
    swap r24
    andi r24, 0x0F
    rcall UART_PRINT_HEX_NIBBLE
    pop  r24
    andi r24, 0x0F
    rcall UART_PRINT_HEX_NIBBLE
    ret

UART_PRINT_HEX_NIBBLE:
    cpi  r24, 10
    brlo UART_HEX_DIGIT
    subi r24, 10
    ldi  tmp, 'A'
    add  r24, tmp
    rcall UART_TX
    ret
UART_HEX_DIGIT:
    ldi  tmp, '0'
    add  r24, tmp
    rcall UART_TX
    ret

; Print signed 16-bit r25:r24 via UART
UART_PRINT_INT16:
    push state
    push btn_id
    push r21
    push tmp
    mov  btn_id, r24
    mov  r21, r25
    tst  r21
    brpl UART_PI16_POS
    ldi  r24, '-'
    rcall UART_TX
    com  btn_id
    com  r21
    ldi  r24, 1
    add  btn_id, r24
    clr  r24
    adc  r21, r24
UART_PI16_POS:
    clr  tmp
    tst  btn_id
    brne UART_PI16_LOOP
    tst  r21
    brne UART_PI16_LOOP
    ldi  r24, '0'
    rcall UART_TX
    pop  tmp
    pop  r21
    pop  btn_id
    pop  state
    ret
UART_PI16_LOOP:
    rcall DIV16_BY10
    ldi  r24, '0'
    add  r24, state
    push r24
    inc  tmp
    tst  btn_id
    brne UART_PI16_LOOP
    tst  r21
    brne UART_PI16_LOOP
UART_PI16_PRINT:
    tst  tmp
    breq UART_PI16_DONE
    pop  r24
    push tmp
    rcall UART_TX
    pop  tmp
    dec  tmp
    rjmp UART_PI16_PRINT
UART_PI16_DONE:
    pop  tmp
    pop  r21
    pop  btn_id
    pop  state
    ret

UART_CRLF:
    ldi  r24, '\r'
    rcall UART_TX
    ldi  r24, '\n'
    rcall UART_TX
    ret

; ===== LOGGING =======================================================================
LOG_BTN_PRESS:
    ldi  ZL, lo8(STR_LOG_BTN)
    ldi  ZH, hi8(STR_LOG_BTN)
    rcall UART_PRINT_FLASH
    lds  r24, current_val_l
    lds  r25, current_val_h
    rcall UART_PRINT_INT16
    rcall UART_CRLF
    ret

LOG_SUCCESS:
    ldi  ZL, lo8(STR_LOG_OK)
    ldi  ZH, hi8(STR_LOG_OK)
    rcall UART_PRINT_FLASH
    rcall UART_CRLF
    ret

LOG_FAIL:
    ldi  ZL, lo8(STR_LOG_FAIL)
    ldi  ZH, hi8(STR_LOG_FAIL)
    rcall UART_PRINT_FLASH
    lds  r24, fail_count
    clr  r25
    rcall UART_PRINT_INT16
    ldi  r24, '/'
    rcall UART_TX
    ldi  r24, MAX_ATTEMPTS
    clr  r25
    rcall UART_PRINT_INT16
    rcall UART_CRLF
    ret

LOG_LOCKOUT:
    ldi  ZL, lo8(STR_LOG_LOCK)
    ldi  ZH, hi8(STR_LOG_LOCK)
    rcall UART_PRINT_FLASH
    rcall UART_CRLF
    ret

LOG_CLOSE:
    ldi  ZL, lo8(STR_LOG_CLOSE)
    ldi  ZH, hi8(STR_LOG_CLOSE)
    rcall UART_PRINT_FLASH
    rcall UART_CRLF
    ret

; ===== EEPROM =======================================================================
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
    out  EEDR,  r24
    cli
    sbi  EECR, EEMPE
    sbi  EECR, EEPE
    sei
    ret

EEPROM_READ_TARGET:
    ldi  tmp2, EE_TARGET_L
    rcall EEPROM_READ_BYTE
    cpi  r24, 0xFF
    brne EE_RT_L_OK
    ldi  r24, lo8(DEFAULT_TARGET)
EE_RT_L_OK:
    sts  target_val_l, r24

    ldi  tmp2, EE_TARGET_H
    rcall EEPROM_READ_BYTE
    cpi  r24, 0xFF
    brne EE_RT_H_OK
    ldi  r24, hi8(DEFAULT_TARGET)
EE_RT_H_OK:
    sts  target_val_h, r24
    ret

; Load fail count from EEPROM
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
    wdr
    ldi  tmp2, 31
DLY_1MS_INNER:
    dec  tmp2
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
    ldi  r24, 10
DLY_1S_LOOP:
    rcall DELAY_100MS
    dec  r24
    brne DLY_1S_LOOP
    ret

; ===== STRINGS =======================================================================
STR_BOOT:     .asciz "ARITH LOCK BOOT\r\n"
STR_STANDBY1: .asciz "  ARITH  LOCK  "
STR_STANDBY2: .asciz " Press any key "
STR_VAL:      .asciz "Val: "
STR_DIST:     .asciz "Dist:"
STR_OPEN1:    .asciz "*** OPEN *** "
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
STR_RST:      .asciz "RST="

; ===== END OF ARITH LOCK =======================================================================
