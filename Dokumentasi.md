# Dokumentasi Arith Lock

## Ringkasan

Sistem kunci berbasis operasi aritmetika pada Arduino. User menekan tombol yang masing‑masing mengubah nilai akumulasi; ketika akumulasi sama dengan `target value`, device memberikan akses.

## Permasalahan

- Keamanan terhadap observasi visual: keypad konvensional rentan terhadap shoulder surfing karena memeriksa urutan angka. Arith-lock berbasis aritmatika sehingga urutan tombol tidak langsung menunjukkan PIN.
- Logging: Keypad biasa tidak mengirim log interaksi ke sistem pusat dan bekerja sendiri. Proyek ini akan mengirim event via serial setiap interaksi.
- Volatility: Jika data hanya disimpan di RAM akan membuat proteksi hilang jika device dimatikan; EEPROM digunakan untuk menyimpan data penting berupa `target` dan `failcount`.
- Interaksi & UX: indikator yang hanya berupa lampu kurang informatif; layar (LCD) menampilkan status operasi (Standby, Input, Open, Lockout) dan progress kedekatan ke target.

## Tujuan

Menjadi solusi low-cost yang meningkatkan keamanan keypad tradisional dengan cakupan:

- Mengimplementasikan logika aritmetika unik untuk mitigasi shoulder surfing.
- Mengirimkan monitoring/log interaksi ke host via serial.
- Menyimpan `target value` dan `attempt count` di EEPROM untuk persistensi.
- Menyediakan interface layar yang menampilkan feedback dinamis.
- Mendemonstrasikan kemampuan dalam AVR assembly.

## Spesifikasi Teknis

- Serial: UART mengirim event setiap interaksi: `SUCCESS|FAIL|OPEN|CLOSE`, `value`, `attempts`, `tick`.
- Arithmetic: setiap tombol memap nilai delta (contoh: +2, +5, +7, -9). Berhasil jika total == `target`.
- Timer/Lockout: jika sudah melewatio threshold, aktifkan `lockout` selama durasi tertentu dan tampilkan sisa waktu di LCD.
- Interrupt: tombol menggunakan INT0/INT1, ISR mengakumulasi delta dan melempar event ke FSM.
- PWM/Servo: gunakan Timer1 PWM untuk menggerakkan servo ketika `OPEN`.
- EEPROM: simpan `target` dan `failcount`; baca di startup, tulis saat terjadi perubahan penting.
- SPI/I2C: gunakan TWI atau SPI untuk komunikasi ke LCD (pilih driver yang tersedia).

## To Do (Commit Plan)

- [x] Inisialisasi hardware (GPIO, UART, Timer, Interrupt, TWI, SRAM)
- [x] Helper EEPROM (read/write target dan fail count)
- [x] Delay functions dan string boot
- [x] LCD init dan screen helpers (STANDBY, INPUT, OPEN, LOCKOUT, WRONG)
- [x] Serial logging untuk interaksi (LOG_BTN_PRESS, LOG_SUCCESS, LOG_FAIL, LOG_LOCKOUT, LOG_CLOSE)
- [ ] ISR handlers (INT0, INT1, Timer2 compare)
- [ ] Polling dan button state machine (input aritmetika, confirm, clear)
- [ ] Enable main runtime loop (ubah INIT_HALT jadi MAIN_LOOP)
- [ ] Verifikasi build dan uji hardware
