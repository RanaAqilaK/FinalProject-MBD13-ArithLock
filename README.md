# FinalProject-MBD13-ArithLock

Arith Lock adalah sistem keypad yang memitigasi risiko keamanan shoulder surfing dengan menggunakan logika input aritmatika akumulatif, dimana setiap tombol memiliki nilai operasional unik untuk mencapai target value. SIstem ini juga mengimplementasikan logging interaksi via USART, data persisten (target value & attempt count) pada EEPROM, mekanisme lockout otomatis berbasis Timer, dan feedback visual progresif pada LCD I2C.
