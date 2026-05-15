#define __SFR_OFFSET 0x00
#include "avr/io.h"

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

.section .text
