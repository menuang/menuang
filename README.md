<div align="center">

<img width="100%" src="https://capsule-render.vercel.app/api?type=waving&height=220&color=gradient&text=Menuang&fontSize=55&fontAlignY=35&desc=Air%20%E2%86%92%20Teko%20%E2%86%92%20Cangkir&descAlignY=58&animation=fadeIn" />

<br/>
<img src="https://readme-typing-svg.demolab.com/?font=Fira+Code&weight=500&size=22&duration=2800&pause=900&center=true&vCenter=true&width=780&lines=Trading+XAUUSD+manual+dibantu+EA;Modal+dan+akun+milik+sendiri;Sumber+Daya+%20%E2%86%92%20+Wadah+%20%E2%86%92%20+Pembagian;Disiplin+risiko+dulu%2C+profit+kemudian" />

[![GitHub](https://img.shields.io/badge/-menuang-181717?style=flat-square&logo=github)](https://github.com/menuang)
[![MQL5](https://img.shields.io/badge/-Menuang_di_MQL5-0A66C2?style=flat-square)](https://www.mql5.com/en/users/getbos)
![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)
![Status](https://img.shields.io/badge/status-active%20development-green?style=flat-square)
![Market](https://img.shields.io/badge/market-XAUUSD%20%7C%20Forex%20%7C%20Crypto-orange?style=flat-square)

</div>

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🫖 Tentang Menuang

**Menuang** adalah komunitas dan perusahaan trading yang membangun "mesin uang" secara sederhana: manusia, teknologi, dan keuangan yang dijaga tetap ringkas dan mudah diaudit.

Filosofi namanya sederhana:

| | Peran | Dalam Menuang |
|---|---|---|
| 💧 **Air** | Sumber daya | Modal, waktu, ilmu, dan disiplin |
| 🫖 **Teko** | Wadah dan pengatur | Menuang: aturan, metode, alat, dan cadangan |
| ☕ **Cangkir** | Penerima | Satu unit **Mesin Uang**, yaitu setiap anggota dengan akunnya sendiri |

Teko mengisi cangkir **sesuai kapasitasnya**. Tidak dituang terus sampai tumpah. Itulah cara kami memandang risiko.

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🎯 Apa yang Kami Kerjakan

- Trading **XAUUSD (emas)** secara **manual**, dibantu **EA (Expert Advisor)**
- Dikerjakan bersama **tim dan anggota**, setiap orang memakai **modal dan akun miliknya sendiri**
- Mengembangkan alat bantu dan metode, bukan menjanjikan hasil

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🧱 Model Bisnis

| Model | Isi |
|---|---|
| **A. Trading modal sendiri** | Tim dan anggota trading dengan dana masing-masing |
| **B. Produk dan pembelajaran** | EA, alat bantu, dan panduan trading untuk dipakai di akun milik pengguna sendiri |

**Yang tidak kami lakukan:**
- ❌ Menerima titipan atau menghimpun dana anggota atau pihak lain
- ❌ Menjanjikan atau menjamin keuntungan
- ❌ Mengelola akun orang lain

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## ⚙️ Unit "Mesin Uang"

Satu unit adalah paket yang bisa diulang:

1. 🖥️ Satu komputer atau VPS
2. 🏦 Satu akun broker/platform milik sendiri
3. 💵 Modal yang jelas besarnya
4. 🤖 Satu EA dengan parameter terdokumentasi
5. 🛡️ Aturan risiko yang tertanam di kode

Berkembang artinya **menambah unit**, bukan memperbesar lot atau leverage pada satu akun.

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🏗️ Arsitektur Sistem & Repositori

```text
menuang/
├── mql5/
│   ├── Experts/            # Source code EA MT5 (Auto TP/SL & Risk Guard)
│   ├── Include/            # Library manajemen risiko MQL5
│   └── Presets/            # File .set parameter terstandarisasi
├── config/                 # Konfigurasi sistem & parameter unit
├── core/
│   ├── engine.py           # Mesin pemantau & automasi
│   ├── risk_manager.py     # Kalkulasi lot, drawdown guard, & circuit breaker
│   └── portfolio.py        # Pelacakan kinerja unit & jurnal akun
├── connectors/             # Integrasi MT5, API, & bridge TP/SL Android
├── journal/                # Pencatatan log transaksi & audit performa
├── notifications/          # Peringatan real-time (Telegram / Android)
├── docs/                   # Buku Panduan Metode Tabranij & SOP Unit
└── main.py                 # Entry point utilitas dan monitoring
```

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 📈 Pasar dan Platform

- **Instrumen utama:** XAUUSD
- **Platform yang dipertimbangkan:** Exness, XM, Hyperliquid, dan sejenisnya
- ⚠️ Memeriksa legalitas dan izin platform adalah tanggung jawab masing-masing. Di Indonesia, pialang berjangka berizin dapat dicek di [Bappebti](https://www.bappebti.go.id/), dan penyelenggara perdagangan aset kripto berizin di [OJK](https://ojk.go.id/). Kerugian di platform tanpa izin tidak mendapat perlindungan regulator lokal.

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🛡️ Aturan Risiko

| Lapisan | Aturan |
|---|---|
| Peringatan dini | Rugi harian mencapai **15%** → berhenti membuka posisi baru |
| **Batas harian mutlak** | Rugi harian **50%** → semua berhenti, lalu evaluasi |
| Batas kumulatif | Drawdown **70%** → unit dimatikan dan dievaluasi |

Prinsip tambahan:
- Hanya uang yang siap hilang
- Tidak menambah modal untuk "memulihkan" kerugian
- Setiap perubahan EA dicatat dan diuji dulu di akun demo

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🪜 Tahapan Pengembangan

| Fase | Fokus | Syarat naik |
|---|---|---|
| **1. Fondasi** | Satu unit, modal kecil, pencatatan lengkap | Modal tumbuh di atas **200%**, ditambah syarat konsistensi: **periode minimum 3 bulan berjalan dan drawdown harian tidak pernah menyentuh batas mutlak (50%)** |
| **2. Replikasi** | Menambah unit dan anggota | **SOP satu unit tervalidasi penuh, jurnal trading teraudit rapi, dan anggota lulus uji disiplin di akun demo/cent minimal 1 bulan** |
| **3. Produk** | Merapikan EA, alat, dan panduan untuk dibagikan | **EA bebas bug kritis, jembatan TP/SL Android berjalan stabil, dan Buku Panduan Metode Tabranij selesai disusun** |

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🧭 Kepatuhan dan Transparansi

- Status saat ini: **dalam tahap pengembangan**, aspek hukum dan pajak belum difinalkan
- Rencana: konsultasi hukum dan pajak **sebelum** jumlah anggota bertambah
- Menuang tidak menerima titipan dana, sehingga setiap anggota bertanggung jawab atas akun dan keputusan trading-nya sendiri

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🛠️ Operasional & Penggunaan Cepat

- **Kode dan dokumentasi:** GitHub
- **Pengembangan dengan bantuan:** AI
- **Infrastruktur web:** Cloudflare
- 🔐 **Keamanan:** API key, password, dan kredensial broker **tidak pernah** disimpan di repositori. Gunakan variabel lingkungan atau secrets, dan `.gitignore` sejak awal.

```bash
# Clone repositori
git clone https://github.com/menuang/menuang.git
cd menuang

# Siapkan environment Python untuk monitoring & jurnal
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Salin konfigurasi environment
cp .env.example .env

# Jalankan monitoring unit Mesin Uang
python main.py --mode monitor --pair XAUUSD
```

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🧳 Jejak Perjalanan

Kami, <a href="https://www.mql5.com/en/users/getbos">**ScalerPip**</a>, trading di MT4 sejak tahun 2010 dan mulai fokus di MT5 pada tahun 2026. Kami pernah memakai berbagai broker, di antaranya InstaForex, Euromax, Primus, FBS, Exness, Tickmill, XM, RoboForex, FxPro, Monex, dan lainnya.

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

- 📊 2026: bersama tim, satu akun tumbuh dari sekitar $60 menjadi sekitar $1.400 dalam kurang lebih 3 bulan
- 🔄 21 September 2026: memulai lagi dari saldo $5
- 📱 Membuat TP/SL otomatis yang terintegrasi dengan Android 
- 📘 Menyusun buku panduan trading dengan metode Tabranij
- 🌱 Ini masih permulaan. Langkah selanjutnya: membangun tim trading
- +62 813-5757-0188 vy
- +62 852-0539-9018 pf
- +62 858-4754-7901 dy
- +62 882-2251-9061 fd
- +62 812-3445-556 pr

> Angka di atas adalah catatan perjalanan akun kami sendiri. **Bukan jaminan, proyeksi, atau hasil yang bisa diharapkan siapa pun.**

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## 🤝 Mari Terhubung

Terbuka untuk berdiskusi tentang:

`Trading XAUUSD` `Expert Advisor MT5` `Manajemen Risiko` `Metode Tabranij` `Membangun Tim Trading`

[![GitHub](https://img.shields.io/badge/-Follow_on_GitHub-181717?style=flat-square&logo=github)](https://github.com/menuang)
[![Email](https://img.shields.io/badge/-Send_an_Email-EA4335?style=flat-square&logo=gmail&logoColor=white)](mailto:surga@mail.grokbot.com)

<img width="1080" height="4" alt="br-animated-line" src="https://user-images.githubusercontent.com/74038190/212284115-f47cd8ff-2ffb-4b04-b5bf-4d1c14c0247f.gif" />

## ⚠️ Peringatan Risiko

Trading emas dan instrumen berleverage berisiko tinggi dan dapat menyebabkan kehilangan seluruh modal. Hasil masa lalu tidak menjamin hasil di masa depan. Isi repositori ini bukan nasihat investasi, hukum, atau pajak.

<br/>

<img width="100%" src="https://capsule-render.vercel.app/api?type=waving&height=120&color=gradient&section=footer" />
