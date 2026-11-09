# 📘 Buku Panduan Metode Tabranij

> **Menuang — Ekosistem Trading XAUUSD Manual + EA & Manajemen Risiko**  
> *"Air → Teko → Cangkir: Disiplin risiko dulu, profit kemudian."*

---

## Daftar Isi

1. [Bab 1: Filosofi Air, Teko, dan Cangkir](#bab-1-filosofi-air-teko-dan-cangkir)
2. [Bab 2: Karakteristik & Setup XAUUSD (Emas)](#bab-2-karakteristik--setup-xauusd-emas)
3. [Bab 3: Arsitektur & Manajemen Unit "Mesin Uang"](#bab-3-arsitektur--manajemen-unit-mesin-uang)
4. [Bab 4: Integrasi Manual Trading + EA & Bridge Android](#bab-4-integrasi-manual-trading--ea--bridge-android)
5. [Bab 5: Psikologi Risiko & Protokol Evaluasi 3 Lapis](#bab-5-psikologi-risiko--protokol-evaluasi-3-lapis)

---

## Bab 1: Filosofi Air, Teko, dan Cangkir

Metode Tabranij dibangun di atas prinsip kesederhanaan yang mudah diaudit:

- **💧 Air (Sumber Daya):** Modal yang siap hilang, waktu, ilmu, dan kedisiplinan eksekusi.
- **🫖 Teko (Wadah & Pengatur):** Sistem Menuang yang menyaring impuls emosi menggunakan aturan baku, SOP, serta alat bantu otomatis (EA & Risk Guard).
- **☕ Cangkir (Penerima / Unit Mesin Uang):** Satu akun trading mandiri dengan kapasitas risiko yang terukur. Teko menuangkan air sesuai ukuran cangkir—tidak pernah dituang berlebihan hingga tumpah.

---

## Bab 2: Karakteristik & Setup XAUUSD (Emas)

1. **Fokus Satu Instrumen:** Mengenal perilaku volatilitas, likuiditas sesi (Asia, London, New York), dan rentang gerak harian XAUUSD.
2. **Struktur Harga & Area Eksekusi:**
   - Identifikasi struktur tren dan zona keseimbangan harga secara manual.
   - Eksekusi hanya dilakukan ketika rasio imbal hasil terhadap risiko (*Risk-to-Reward*) memenuhi batas standar unit.
3. **Larangan Keras:**
   - Tidak melakukan *averaging* tanpa batas (*martingale* buta) saat harga bergerak berlawanan dengan analisis awal.
   - Setiap posisi wajib memiliki titik *Stop Loss* (SL) dan *Take Profit* (TP) sejak detik pertama posisi terbuka.

---

## Bab 3: Arsitektur & Manajemen Unit "Mesin Uang"

Satu **Unit Mesin Uang** adalah satu paket independen yang terdiri dari:
1. Satu komputer atau VPS terdedikasi.
2. Satu akun broker/platform milik sendiri.
3. Modal terukur yang jelas besarnya (uang dingin / siap hilang).
4. Satu EA (`Menuang_EA_XAUUSD`) dengan parameter `.set` terdokumentasi.
5. Aturan risiko 3 lapis yang tertanam langsung di dalam kode.

**Prinsip Pertumbuhan (Scaling):**
Berkembang artinya **menambah unit baru (cangkir baru)** setelah lulus syarat Fase 1 (pertumbuhan > 200%, berjalan minimal 3 bulan, tanpa pernah menyentuh batas rugi harian mutlak 50%), **bukan** melipatgandakan ukuran lot secara emosional pada satu akun.

---

## Bab 4: Integrasi Manual Trading + EA & Bridge Android

- **Peran Manusia (Trader):** Membaca konteks pasar, menentukan arah, dan mengeksekusi entry pada momen berkualitas.
- **Peran Teknologi (EA & Android Bridge):**
  - Memasang *Auto TP/SL* secara instan begitu posisi manual terbuka di MT5.
  - Menyinkronkan perubahan TP/SL dari perangkat Android secara aman.
  - Memblokir pembukaan posisi baru ketika batas peringatan dini terlewati.

---

## Bab 5: Psikologi Risiko & Protokol Evaluasi 3 Lapis

| Lapisan | Batas | Tindakan Wajib |
|---|---|---|
| **Lapis 1: Peringatan Dini** | Rugi harian mencapai **15%** | Berhenti membuka posisi baru untuk sisa hari tersebut. |
| **Lapis 2: Batas Harian Mutlak** | Rugi harian mencapai **50%** | Seluruh posisi dihentikan, terminal dikunci, dan wajib dilakukan evaluasi jurnal. |
| **Lapis 3: Batas Kumulatif** | Drawdown mencapai **70%** | Unit dimatikan sepenuhnya dan dievaluasi ulang dari tahap akun demo/cent. |

**Aturan Psikologi Utama:**
- Dilarang menyuntikkan modal tambahan (*top-up* impulsif) demi "membalas dendam" atau memulihkan kerugian hari yang sama.
- Setiap perubahan parameter EA wajib dicatat dan diuji di akun demo minimal sesuai prosedur sebelum diterapkan ke unit utama.
