-- ==============================================================================
-- DATABASE SCHEMA: SE MANAGEMENT JOB - MINE OPERATIONS (SUPABASE COMPATIBLE)
-- ==============================================================================
-- Target Database : PostgreSQL / Supabase
-- Keterangan      : Skema basis data operasional tambang, jadwal Lube Truck & Water Truck,
--                   permintaan order lapangan, PICA kendala, dan monitoring saringan udara.
-- CATATAN FOTO    : FOTO DOKUMENTASI TIDAK DISIMPAN DI DATABASE SUPABASE.
--                   Seluruh foto disimpan langsung ke Google Drive via Google Apps Script:
--                   Folder ID: 11EQ_NsZYeMmEKURpibXCRtyrQw5kKkh3
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. EKSTENSI & PEMBERSIHAN TABEL FOTO LAMA (JIKA ADA)
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Pastikan tidak ada tabel foto terpisah di Supabase
DROP TABLE IF EXISTS fotos CASCADE;
DROP TABLE IF EXISTS photos CASCADE;
DROP TABLE IF EXISTS job_photos CASCADE;

-- ------------------------------------------------------------------------------
-- 2. TABEL USERS (Master Pengguna & Hak Akses Peran)
--    Mendukung role: admin, oilman, washingman, mp_lt, mp_wt, user, basecontrol
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nrp VARCHAR(50) UNIQUE NOT NULL,
    nama VARCHAR(150) NOT NULL,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL CHECK (role IN ('admin', 'oilman', 'washingman', 'mp_lt', 'mp_wt', 'user', 'basecontrol')),
    jabatan VARCHAR(100) DEFAULT 'Staff Operasional',
    no_wa VARCHAR(30),
    status_aktif BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indeks untuk pencarian cepat login berdasarkan NRP dan Role
CREATE INDEX IF NOT EXISTS idx_users_nrp ON users(nrp);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- ------------------------------------------------------------------------------
-- 3. TABEL MASTER UNITS (Daftar Armada & Alat Berat Tambang)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_units (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    no_lambung VARCHAR(50) UNIQUE NOT NULL,
    type_model VARCHAR(100) NOT NULL,
    kategori VARCHAR(50) NOT NULL DEFAULT 'ob', -- 'coal', 'ob', 'hauler', 'support', 'armada'
    cluster VARCHAR(50) NOT NULL DEFAULT 'Tengah', -- 'Selatan', 'Tengah', 'Utara'
    lokasi VARCHAR(100) NOT NULL DEFAULT 'Pit Area',
    status VARCHAR(30) NOT NULL DEFAULT 'Operasi', -- 'Operasi', 'Breakdown', 'Standby'
    keterangan TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman: Pastikan kolom no_lambung ada jika tabel sudah pernah dibuat sebelumnya
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS no_lambung VARCHAR(50);
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS type_model VARCHAR(100);
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS kategori VARCHAR(50) DEFAULT 'ob';
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS cluster VARCHAR(50) DEFAULT 'Tengah';
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS lokasi VARCHAR(100) DEFAULT 'Pit Area';
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS status VARCHAR(30) DEFAULT 'Operasi';

CREATE INDEX IF NOT EXISTS idx_units_no_lambung ON master_units(no_lambung);
CREATE INDEX IF NOT EXISTS idx_units_cluster ON master_units(cluster);
CREATE INDEX IF NOT EXISTS idx_units_status ON master_units(status);

-- ------------------------------------------------------------------------------
-- 4. TABEL MASTER OPERATORS & MANPOWER
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_operators (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nrp VARCHAR(50) UNIQUE NOT NULL,
    nama VARCHAR(150) NOT NULL,
    jabatan VARCHAR(80) DEFAULT 'Operator', -- 'Operator', 'Oilman', 'Washingman', 'Driver'
    no_wa VARCHAR(30),
    cluster VARCHAR(50) DEFAULT 'Tengah',
    armada_unit VARCHAR(50), -- misal 'LT2535', 'WT101'
    status_aktif BOOLEAN DEFAULT TRUE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_operators_nrp ON master_operators(nrp);
CREATE INDEX IF NOT EXISTS idx_operators_jabatan ON master_operators(jabatan);

-- ------------------------------------------------------------------------------
-- 5. TABEL ARMADA CLUSTERS (Penugasan Wilayah LT & WT)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS armada_clusters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cluster_name VARCHAR(50) NOT NULL, -- 'Selatan', 'Tengah', 'Utara'
    armada_type VARCHAR(20) NOT NULL, -- 'LT' (Lube Truck) atau 'WT' (Water Truck)
    assigned_units TEXT NOT NULL, -- Contoh: 'LT2535, LT2622, LT2530'
    updated_by VARCHAR(50),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_cluster_armada UNIQUE(cluster_name, armada_type)
);

-- ------------------------------------------------------------------------------
-- 6. TABEL MASTER ROSTER (Jadwal Giliran Kerja & Shift)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_roster (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nrp VARCHAR(50) NOT NULL,
    nama VARCHAR(150) NOT NULL,
    periode VARCHAR(10) NOT NULL, -- Format 'YYYY-MM', misal '2026-09'
    tanggal DATE NOT NULL,
    shift_code VARCHAR(10) NOT NULL, -- 'D' (Day), 'N' (Night), 'OFF', 'CT' (Cuti)
    tipe_karyawan VARCHAR(20) NOT NULL DEFAULT 'OPT', -- 'OPT' (Operator) atau 'MP' (Manpower)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_roster_entry UNIQUE(nrp, tanggal)
);

CREATE INDEX IF NOT EXISTS idx_roster_tanggal ON master_roster(tanggal);
CREATE INDEX IF NOT EXISTS idx_roster_periode ON master_roster(periode);

-- ------------------------------------------------------------------------------
-- 7. TABEL JOBS (Jadwal Kerja & Realisasi Lube Truck & Water Truck)
--    Foto dokumentasi disimpan langsung ke Google Drive via Google Apps Script
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(100) PRIMARY KEY, -- Misal: 'LTJ-01', 'WTJ-S1-01', 'UNSCH-LT-01'
    job_type VARCHAR(30) NOT NULL, -- 'lube', 'water', 'unsch_lt', 'unsch_wt', 'opportunity_washing'
    tanggal DATE NOT NULL,
    shift INT NOT NULL DEFAULT 1, -- 1 = Shift Siang, 2 = Shift Malam
    washing_round INT DEFAULT 1, -- Putaran washing (khusus water truck)
    cluster VARCHAR(50) NOT NULL, -- 'Selatan', 'Tengah', 'Utara'
    waktu_rencana VARCHAR(50), -- '06:00 s/d 06:30'
    type_unit VARCHAR(100) NOT NULL,
    no_lambung VARCHAR(50) NOT NULL,
    lokasi VARCHAR(100) NOT NULL,
    armada_unit VARCHAR(50) NOT NULL, -- Unit pelaksana: 'LT2535', 'WT101'
    opt_name VARCHAR(150),
    mp1 VARCHAR(150),
    mp2 VARCHAR(150),
    
    -- Realisasi Waktu & Jam Kerja
    jam_start VARCHAR(10),
    jam_end VARCHAR(10),
    hm_stop NUMERIC(10, 2),
    hm_ready NUMERIC(10, 2),
    
    -- Status Pencapaian (ACH / Done / NON ACH / Pending)
    status VARCHAR(30) NOT NULL DEFAULT 'plan', -- 'plan', 'ach', 'non_ach', 'pending', 'cancelled'
    keterangan TEXT,
    is_pending BOOLEAN DEFAULT FALSE,
    ada_operator VARCHAR(10) DEFAULT 'Ya', -- 'Ya' atau 'Tidak'
    cat VARCHAR(50) DEFAULT 'ob', -- 'coal', 'ob', 'support'
    
    -- Detail Kondisi Khusus & Service
    unit_condition VARCHAR(50), -- 'normal', 'service_ps', 'breakdown'
    service_notes TEXT,
    bd_notes TEXT,
    
    -- Alasan Kendala jika NON-ACH
    non_ach_category VARCHAR(100),
    non_ach_reason TEXT,
    
    -- Catatan: Foto dokumentasi disimpan langsung ke Google Drive melalui Google Apps Script
    
    created_by VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman: Pastikan kolom no_lambung ada jika tabel jobs sudah pernah dibuat sebelumnya
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS no_lambung VARCHAR(50);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS type_unit VARCHAR(100);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS armada_unit VARCHAR(50);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS job_type VARCHAR(30);

-- Hapus kolom fotos jika sempat dibuat sebelumnya di tabel jobs
ALTER TABLE jobs DROP COLUMN IF EXISTS fotos;

CREATE INDEX IF NOT EXISTS idx_jobs_tanggal ON jobs(tanggal);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_armada ON jobs(armada_unit);
CREATE INDEX IF NOT EXISTS idx_jobs_no_lambung ON jobs(no_lambung);
CREATE INDEX IF NOT EXISTS idx_jobs_type ON jobs(job_type);

-- ------------------------------------------------------------------------------
-- 8. TABEL ORDER REQUESTS (Permintaan Layanan dari Pengawas / User / Base Control)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    kode_order VARCHAR(50) UNIQUE,
    tanggal DATE NOT NULL,
    jam VARCHAR(10) NOT NULL,
    nama_pemesan VARCHAR(150) NOT NULL,
    role_pemesan VARCHAR(30) NOT NULL DEFAULT 'user', -- 'user', 'basecontrol', 'admin'
    nrp_pemesan VARCHAR(50),
    no_lambung VARCHAR(50) NOT NULL,
    cluster VARCHAR(50) NOT NULL,
    lokasi VARCHAR(100) NOT NULL,
    keadaan_unit VARCHAR(100) NOT NULL, -- 'Normal', 'Breakdown', 'Peringatan', 'Urgent'
    deskripsi TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'Pending', -- 'Pending', 'Diproses', 'Selesai', 'Dibatalkan'
    catatan_admin TEXT,
    handled_by VARCHAR(150),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman: Pastikan kolom no_lambung ada jika tabel order_requests sudah pernah dibuat
ALTER TABLE order_requests ADD COLUMN IF NOT EXISTS no_lambung VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_orders_tanggal ON order_requests(tanggal);
CREATE INDEX IF NOT EXISTS idx_orders_status ON order_requests(status);
CREATE INDEX IF NOT EXISTS idx_orders_role_pemesan ON order_requests(role_pemesan);
CREATE INDEX IF NOT EXISTS idx_orders_no_lambung ON order_requests(no_lambung);

-- ------------------------------------------------------------------------------
-- 9. TABEL AIR CLEANER MONITORING (Pemantauan Saringan Udara Unit)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS air_cleaner_monitoring (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    no_lambung VARCHAR(50) UNIQUE NOT NULL,
    type_model VARCHAR(100) NOT NULL,
    cleans JSONB DEFAULT '[]'::jsonb, -- Riwayat tanggal pembersihan: ["27/09/2026", "29/09/2026"]
    service_code VARCHAR(50) DEFAULT '', -- 'PS250', 'PS500', 'PS1000'
    status VARCHAR(30) NOT NULL DEFAULT 'Baik', -- 'Baik', 'Peringatan', 'Di Ganti', 'Baru'
    last_cleaned_date DATE,
    keterangan TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman: Pastikan kolom no_lambung ada jika tabel air_cleaner_monitoring sudah pernah dibuat
ALTER TABLE air_cleaner_monitoring ADD COLUMN IF NOT EXISTS no_lambung VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_air_cleaner_no_lambung ON air_cleaner_monitoring(no_lambung);
CREATE INDEX IF NOT EXISTS idx_air_cleaner_status ON air_cleaner_monitoring(status);

-- ------------------------------------------------------------------------------
-- 10. TABEL PICA RECORDS (Problem Identification & Corrective Action)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pica_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id VARCHAR(100),
    no_lambung VARCHAR(50) NOT NULL,
    tanggal DATE NOT NULL,
    shift INT DEFAULT 1,
    cluster VARCHAR(50),
    kategori VARCHAR(80) NOT NULL, -- 'Manpower', 'Machine', 'Material', 'Method', 'Environment'
    problem_description TEXT NOT NULL,
    root_cause TEXT,
    corrective_action TEXT,
    preventive_action TEXT,
    pic VARCHAR(150),
    status VARCHAR(30) DEFAULT 'Open', -- 'Open', 'In Progress', 'Closed'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman: Pastikan kolom no_lambung ada jika tabel pica_records sudah pernah dibuat
ALTER TABLE pica_records ADD COLUMN IF NOT EXISTS no_lambung VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_pica_tanggal ON pica_records(tanggal);
CREATE INDEX IF NOT EXISTS idx_pica_kategori ON pica_records(kategori);
CREATE INDEX IF NOT EXISTS idx_pica_status ON pica_records(status);

-- ------------------------------------------------------------------------------
-- 11. TRIGGER OTOMATIS: UPDATED_AT TIMESTAMP
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_timestamp_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_updated_at') THEN
        CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_timestamp_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_units_updated_at') THEN
        CREATE TRIGGER trg_units_updated_at BEFORE UPDATE ON master_units FOR EACH ROW EXECUTE FUNCTION update_timestamp_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_jobs_updated_at') THEN
        CREATE TRIGGER trg_jobs_updated_at BEFORE UPDATE ON jobs FOR EACH ROW EXECUTE FUNCTION update_timestamp_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_orders_updated_at') THEN
        CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON order_requests FOR EACH ROW EXECUTE FUNCTION update_timestamp_column();
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 12. INITIAL SEED DATA (Default Pengguna 5 Akses Peran & Cluster Awal)
-- ------------------------------------------------------------------------------
INSERT INTO users (nrp, nama, password, role, jabatan, status_aktif)
VALUES
    ('ADMIN01', 'Super Admin Operasional', 'ADMIN01', 'admin', 'Pengawas / Planner', TRUE),
    ('OM1001', 'Budi Santoso (Oilman)', 'OM1001', 'oilman', 'Crew Lube Truck', TRUE),
    ('WM2001', 'Dedi Prasetyo (Washingman)', 'WM2001', 'washingman', 'Crew Water Truck', TRUE),
    ('USR3001', 'Agus Supriyadi (User)', 'USR3001', 'user', 'Foreman / Staff Lapangan', TRUE),
    ('BC4001', 'Rian Setiawan (Base Control)', 'BC4001', 'basecontrol', 'Radio Dispatcher / Base Control', TRUE)
ON CONFLICT (nrp) DO NOTHING;

INSERT INTO armada_clusters (cluster_name, armada_type, assigned_units)
VALUES
    ('Selatan', 'LT', 'LT2535, LT2622, LT2530'),
    ('Tengah',  'LT', 'LT2514, LT2518'),
    ('Utara',   'LT', 'LT2510, LT2525'),
    ('Selatan', 'WT', 'WT101'),
    ('Tengah',  'WT', 'WT102'),
    ('Utara',   'WT', 'WT101')
ON CONFLICT (cluster_name, armada_type) DO NOTHING;

-- Selesai
