# ⚙️ SOP 1 Unit Mesin Uang & Audit Akun

Dokumen Standar Operasional Prosedur (SOP) ini mengatur siklus hidup, pengawasan harian, dan audit berkala untuk satu **Unit Mesin Uang** di dalam ekosistem **Menuang**.

---

## 1. Daftar Periksa Pra-Operasional (Setup Unit Baru)

Sebelum satu unit dinyatakan aktif, pastikan 5 komponen berikut telah terverifikasi:

- [ ] **Infrastruktur:** 1 PC atau VPS dengan koneksi stabil ke server broker.
- [ ] **Akun Mandiri:** 1 akun trading MT5 atas nama pemilik sendiri (Menuang tidak pernah menerima titipan dana atau mengelola akun pihak lain).
- [ ] **Modal Terukur:** Saldo awal dicatat secara eksplisit di `.env` dan parameter EA (`InpInitialModal`).
- [ ] **Konfigurasi EA:** `Menuang_EA_XAUUSD.mq5` terpasang di chart `XAUUSD` menggunakan preset standar `mql5/Presets/xauusd_unit_standar.set` dan fitur *Algo Trading* aktif.
- [ ] **Jurnal & Monitoring:** Modul Python (`main.py`) telah dikonfigurasi dengan file `.env` lokal (tanpa pernah di-commit ke Git).

---

## 2. Prosedur Operasional Harian

1. **Awal Hari Trading:**
   - Periksa saldo acuan harian (*Daily Start Balance*) dan pastikan tidak ada peringatan risiko aktif dari hari sebelumnya.
   - Pastikan *Auto TP/SL* pada EA berstatus `AKTIF`.
2. **Saat Eksekusi Trading (Manual + Asistensi EA):**
   - Buka posisi sesuai setup **Metode Tabranij**.
   - Pastikan EA atau jembatan Android langsung menyematkan titik SL dan TP pada posisi tersebut.
3. **Penanganan Lapisan Risiko:**
   - **Rugi Harian >= 15% (Peringatan Dini):** Dilarang membuka posisi baru. Biarkan posisi yang masih berjalan mencapai TP/SL yang telah ditetapkan.
   - **Rugi Harian >= 50% (Batas Harian Mutlak):** *Circuit breaker* menutup semua posisi terbuka. Hentikan seluruh aktivitas trading hari itu dan isi formulir evaluasi insiden.
   - **Drawdown Kumulatif >= 70% (Batas Kumulatif):** Nonaktifkan unit, cabut izin eksekusi EA, dan lakukan audit menyeluruh sebelum kembali berlatih di akun demo/cent.

---

## 3. Protokol Audit Akun Mingguan & Bulanan

Setiap akhir pekan dan akhir bulan, pemilik unit wajib melakukan audit mandiri:

1. **Kepatuhan TP/SL:** Apakah 100% transaksi memiliki SL dan TP sejak posisi dibuka?
2. **Disiplin Batas Harian:** Apakah ada upaya membuka posisi baru setelah rugi harian menyentuh 15%?
3. **Verifikasi Syarat Fase 1 → Fase 2 (Replikasi):**
   - Pertumbuhan modal bersih > **200%** dari modal awal.
   - Periode operasional aktif minimal **3 bulan (90 hari)**.
   - Tidak pernah menyentuh batas rugi harian mutlak (**50%**).
   - Anggota telah lulus uji disiplin di akun demo/cent minimal **1 bulan**.
