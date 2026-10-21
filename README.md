# 🚀 SE Mine Operations - Lubetruck & Water Truck Management System

Aplikasi manajemen operasional tambang terpadu untuk monitoring dan penjadwalan armada **Lubetruck (LT)** dan **Water Truck (WT)** secara realtime dengan efisiensi tinggi, arsitektur *dual-cloud*, dan fitur PWA (*Progressive Web App*).

---

## 📋 Daftar Isi
1. [Fitur Utama](#-fitur-utama)
2. [Arsitektur Sistem](#-arsitektur-sistem)
3. [Daftar Role & Hak Akses](#-daftar-role--hak-akses)
4. [Akun Bawaan (Default Credentials)](#-akun-bawaan-default-credentials)
5. [Panduan Setup Database Supabase](#-panduan-setup-database-supabase)
6. [Panduan Setup Google Drive & Apps Script](#-panduan-setup-google-drive--apps-script)
7. [Panduan Deployment ke GitHub](#-panduan-deployment-ke-github)
8. [Struktur Berkas Proyek](#-struktur-berkas-proyek)

---

## ✨ Fitur Utama

* **Penjadwalan Otomatis & Fleksibel**:
  * Penjadwalan periodik Lubetruck (Small Digger, Medium Digger, Big Digger, Support, dll.).
  * Penjadwalan Water Truck (Washing Coal & Non-Coal) per shift dan kluster.
  * Dukungan jadwal 1 bulan penuh (*monthly batch schedule*).
* **Monitoring Realtime Zero-Refetch**:
  * Integrasi WebSocket Supabase Realtime dengan *SingleChannel Guard* (0 KB extra egress).
  * Pembaruan data instan di seluruh perangkat tim lapangan dan base control tanpa perlu refresh.
* **Monitoring Air Cleaner & Fitur Replace**:
  * Tracking siklus 6x penyemprotan saringan udara per unit.
  * Fitur **Replace Komponen** khusus untuk **Admin** dan **Tim Track** dengan formulir upload **Evidence Foto** langsung ke Google Drive.
  * Reset siklus otomatis ke 0 setelah pergantian komponen selesai diverifikasi.
* **Audit & Ketercapaian (ACH / Non-ACH / PICA)**:
  * Evaluasi status ketercapaian harian (ACH, Pending Lemparan, Non-ACH).
  * Pengisian formulir PICA (*Problem Identification & Corrective Action*) terstruktur.
* **Manajemen Data Master Lengkap**:
  * Master Populasi Unit (Alat Berat Komatsu, Caterpillar, Hitachi, dll.).
  * Master Armada (LT & WT) dan Alokasi Kluster Wilayah (Selatan, Tengah, Utara, ROM, Workshop).
  * Master Roster Operator & Pengawas Tambang.
  * Master Kontak Produksi dengan integrasi chat WhatsApp instan.
  * Manajemen Akun Pegawai multi-role.
* **Form Order Lapangan & Job Request**:
  * Permintaan servis darurat dari user lapangan/driver.
  * Validasi dan eksekusi order oleh Base Control dan Planner.

---

## 🏗️ Arsitektur Sistem

Aplikasi ini menggunakan pendekatan **Dual-Cloud Architecture**:
1. **Supabase (PostgreSQL & Realtime WebSockets)**:
   * Menyimpan data transaksional (jadwal, riwayat pekerjaan, monitoring air cleaner, data master, akun).
   * Menangani *Row Level Security (RLS)* dan broadcast perubahan data secara realtime.
   * Strategi *Hot-Window Fetch* (14 hari terakhir + pekerjaan aktif) untuk memangkas penggunaan kuota egress hingga 98%.
2. **Google Drive & Google Apps Script**:
   * Bertindak sebagai *media storage* gratis berkapasitas besar untuk foto hasil servis (ACH) dan foto bukti pergantian komponen (Air Cleaner Evidence).
   * Otomatis mencatat tautan langsung (*direct link*) dan formula pratinjau thumbnail ke Google Spreadsheet.

---

## 👥 Daftar Role & Hak Akses

| Role | Kode Role | Akses Fitur Utama |
| :--- | :--- | :--- |
| **Administrator** | `admin` | Full control: Penjadwalan, edit master data, hapus massal, manajemen akun, audit PICA, reset & replace air cleaner. |
| **Tim Track** | `track` | Dashboard operasional, Job Request, Form Order, Riwayat Pekerjaan, PICA, serta **Akses Khusus Replace Komponen Air Cleaner & Upload Evidence**. |
| **Base Control** | `basecontrol` | Dispatcher radio room: Dashboard pencapaian, validasi Job Request, Form Order Lapangan, Riwayat Pekerjaan, Monitoring Air Cleaner (View-only), PICA. |
| **Oilman (MP LT)** | `mp_lt` | Eksekusi servis Lubetruck, input realisasi waktu & durasi, upload foto bukti kerja (ACH). |
| **Washingman (MP WT)** | `mp_wt` | Eksekusi pencucian unit Water Truck, input realisasi, upload foto bukti kerja. |
| **User Pemohon** | `user` | Permintaan order servis lapangan (top up oli, greasing, cuci unit). |

---

## 🔑 Akun Bawaan (Default Credentials)

Untuk inisialisasi awal saat database baru dipasang:

| NRP / Username | Password | Role | Keterangan |
| :--- | :--- | :--- | :--- |
| `admin` | `admin123` | Administrator | Akun Administrator / Planner |
| `track` | `track123` | Tim Track | Akun Petugas Lapangan Tim Track |

---

## 🗄️ Panduan Setup Database Supabase

1. Buat project baru di [Supabase](https://supabase.com/).
2. Buka menu **SQL Editor** pada dashboard Supabase.
3. Buka file [`schema.sql`](./schema.sql) dari repositori ini, salin seluruh kodenya, lalu tempelkan ke SQL Editor Supabase.
4. Klik tombol **Run** (Jalankan). Skrip ini akan membuat seluruh tabel, trigger, indeks, kebijakan RLS, publikasi Realtime, serta akun awal `admin` dan `track`.
5. Salin **Project URL** dan **Anon Public Key** dari menu *Project Settings -> API*.
6. Buka aplikasi web di browser -> Klik ikon **Pengaturan (Profil / Gir)** -> Masukkan URL & Key Supabase -> Klik **Tes & Simpan Koneksi**.

---

## ☁️ Panduan Setup Google Drive & Apps Script

1. Buat folder baru di Google Drive Anda (misal: `FOTO_OPERASIONAL_MINE`).
2. Buat Google Spreadsheet baru di dalam folder tersebut (misal: `Log Foto Operasional`).
3. Pada Google Spreadsheet, klik menu **Extensions (Ekstensi)** -> **Apps Script**.
4. Hapus semua kode default di Apps Script, lalu salin seluruh isi file [`Code.gs`](./Code.gs) ke editor tersebut.
5. Sesuaikan konstanta `SPREADSHEET_ID` dan `TARGET_FOLDER_ID` di bagian atas `Code.gs` sesuai ID Spreadsheet dan Folder Drive Anda.
6. Klik tombol **Deploy** di pojok kanan atas -> pilih **New deployment**.
7. Konfigurasikan:
   * **Select type**: Web app
   * **Execute as**: Me (email akun Google Anda)
   * **Who has access**: Anyone (Siapa saja)
8. Klik **Deploy** dan berikan izin akses (*Authorize access*).
9. Salin URL Web App yang berakhiran `/exec`.
10. Masukkan URL tersebut pada menu Pengaturan Web di bagian **Google Apps Script Endpoint**.

---

## 🚀 Panduan Deployment ke GitHub

Proyek ini merupakan Single Page Application (SPA) berbasis Vanilla HTML, CSS (Tailwind), dan JavaScript murni tanpa build step yang rumit, sehingga dapat langsung di-deploy melalui **GitHub Pages**:

```bash
# 1. Inisialisasi Git
git init

# 2. Tambahkan semua berkas (file backup otomatis diabaikan oleh .gitignore)
git add .

# 3. Commit
git commit -m "feat: initial release with air cleaner replace evidence and tim track role"

# 4. Hubungkan ke repository GitHub Anda
git remote add origin https://github.com/USERNAME/REPO_NAME.git
git branch -M main
git push -u origin main
```

Untuk mengaktifkan **GitHub Pages**:
* Buka repository di GitHub -> masuk ke menu **Settings** -> **Pages**.
* Pada bagian **Branch**, pilih `main` dan folder `/ (root)`.
* Klik **Save**. Aplikasi Anda akan aktif dalam beberapa menit!

---

## 📁 Struktur Berkas Proyek

```text
├── index.html          # Aplikasi utama (Frontend UI, Logic, State, & Offline Cache)
├── sw.js               # Service Worker untuk kapabilitas PWA & offline support
├── manifest.json       # Web App Manifest untuk instalasi di Android/iOS/Desktop
├── schema.sql          # Skema database PostgreSQL Supabase lengkap (12 tabel & Realtime)
├── Code.gs             # Google Apps Script untuk upload media ke Google Drive & Sheet
├── .gitignore          # Konfigurasi pengabaian berkas cadangan dan temporary
├── README.md           # Dokumentasi teknis proyek
├── xlsx.full.min.js    # Pustaka SheetJS untuk ekspor/impor Excel lokal
└── icons/              # Ikon aplikasi PWA
```

---

## 🛠️ Lisensi & Kontributor
Dikembangkan untuk kebutuhan operasional tambang efisiensi tinggi. Didukung oleh teknologi web modern, Supabase Realtime, dan Google Workspace API.
