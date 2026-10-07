-- ==============================================================================
-- DATABASE SCHEMA: SE MANAGEMENT JOB - MINE OPERATIONS (SUPABASE COMPATIBLE)
-- ==============================================================================
-- Target Database : PostgreSQL / Supabase
-- Versi           : 2026.10 (Full Synchronization with index.html)
-- Keterangan      : Basis data terintegrasi penuh untuk manajemen jadwal Lubetruck &
--                   Water Truck, Data Master Armada, Populasi Unit Lapangan,
--                   Data Master Roster Bulanan, No OPT Produksi, Order Lapangan,
--                   Monitoring Saringan Udara (Air Cleaner), dan Log PICA Kendala.
-- CATATAN FOTO    : FOTO DOKUMENTASI TIDAK DISIMPAN DI DATABASE SUPABASE.
--                   Seluruh foto disimpan langsung ke Google Drive via Google Apps Script:
--                   Folder ID: 11EQ_NsZYeMmEKURpibXCRtyrQw5kKkh3
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. EKSTENSI & PEMBERSIHAN TABEL LAMA
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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
    role VARCHAR(30) NOT NULL CHECK (role IN ('admin', 'oilman', 'washingman', 'mp_lt', 'mp_wt', 'user', 'basecontrol', 'base_control')),
    jabatan VARCHAR(100) DEFAULT 'Staff Operasional',
    no_wa VARCHAR(30),
    status_aktif BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_nrp ON users(nrp);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

DO $$ 
BEGIN
    ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
    ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('admin', 'oilman', 'washingman', 'mp_lt', 'mp_wt', 'user', 'basecontrol', 'base_control'));
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- ------------------------------------------------------------------------------
-- 3. TABEL MASTER ARMADA (Unit Servis Lubetruck & Water Truck per Cluster)
--    Singkron dengan Data Master Armada di index.html
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_armada (
    id VARCHAR(100) PRIMARY KEY, -- Contoh: 'ARM-01', 'ARM-1741234567'
    unit VARCHAR(50) UNIQUE NOT NULL, -- Nomor Unit/Lambung: 'LT2535', 'WT101'
    type_unit VARCHAR(50) NOT NULL, -- 'Lubetruck' atau 'Water Truck'
    cluster VARCHAR(50) NOT NULL DEFAULT 'Selatan', -- 'Selatan', 'Tengah', 'Utara', 'ROM', dll.
    status VARCHAR(30) NOT NULL DEFAULT 'Aktif', -- 'Aktif', 'Standby', 'Breakdown'
    keterangan TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman jika tabel sudah ada
ALTER TABLE master_armada ADD COLUMN IF NOT EXISTS unit VARCHAR(50);
ALTER TABLE master_armada ADD COLUMN IF NOT EXISTS type_unit VARCHAR(50);
ALTER TABLE master_armada ADD COLUMN IF NOT EXISTS cluster VARCHAR(50) DEFAULT 'Selatan';
ALTER TABLE master_armada ADD COLUMN IF NOT EXISTS status VARCHAR(30) DEFAULT 'Aktif';

CREATE INDEX IF NOT EXISTS idx_master_armada_unit ON master_armada(unit);
CREATE INDEX IF NOT EXISTS idx_master_armada_type ON master_armada(type_unit);
CREATE INDEX IF NOT EXISTS idx_master_armada_cluster ON master_armada(cluster);

-- ------------------------------------------------------------------------------
-- 4. TABEL ARMADA CLUSTERS (Alokasi Gabungan Armada Bertugas per Cluster)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS armada_clusters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cluster_name VARCHAR(50) NOT NULL, -- 'Selatan', 'Tengah', 'Utara', 'ROM'
    armada_type VARCHAR(20) NOT NULL, -- 'LT' (Lube Truck) atau 'WT' (Water Truck)
    assigned_units TEXT NOT NULL, -- Contoh: 'LT2535, LT2622, LT2530'
    updated_by VARCHAR(50),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_cluster_armada UNIQUE(cluster_name, armada_type)
);

-- ------------------------------------------------------------------------------
-- 5. TABEL MASTER ROSTER (Jadwal Giliran Kerja Bulanan: OPT, OM, WM)
--    Singkron dengan Template & Parsing Roster di index.html
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_roster (
    id VARCHAR(100) PRIMARY KEY, -- Contoh: 'ROSTER-1741234567-1'
    jenis VARCHAR(20) NOT NULL DEFAULT 'OPT', -- 'OPT' (Operator), 'OM' (Oilman), 'WM' (Washingman)
    nrp VARCHAR(50) NOT NULL,
    nik VARCHAR(50),
    nama VARCHAR(150) NOT NULL,
    unit VARCHAR(50), -- Unit batangan bawaan: 'LT2510', 'LT2535'
    unit_efektif VARCHAR(50), -- Unit efektif (diperbarui jika personil spare)
    periode VARCHAR(10), -- Format 'YYYY-MM', misal '2026-10'
    tanggal DATE NOT NULL,
    shift INT NOT NULL DEFAULT 1, -- 1 = Day (Siang), 2 = Night (Malam)
    kode_shift VARCHAR(30) NOT NULL DEFAULT 'DWS', -- 'DWS', 'NWS', 'D514', 'N168', 'OOFF', 'CCUTI', 'INDR'
    is_spare BOOLEAN DEFAULT FALSE,
    keterangan TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migrasi aman kolom roster jika tabel sudah pernah dibuat sebelumnya
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS jenis VARCHAR(20) DEFAULT 'OPT';
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS nik VARCHAR(50);
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS unit VARCHAR(50);
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS unit_efektif VARCHAR(50);
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS shift INT DEFAULT 1;
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS kode_shift VARCHAR(30) DEFAULT 'DWS';
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS is_spare BOOLEAN DEFAULT FALSE;
ALTER TABLE master_roster ADD COLUMN IF NOT EXISTS keterangan TEXT;

DO $$ 
BEGIN
    ALTER TABLE master_roster DROP CONSTRAINT IF EXISTS uq_roster_entry;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_roster_tanggal ON master_roster(tanggal);
CREATE INDEX IF NOT EXISTS idx_roster_nrp ON master_roster(nrp);
CREATE INDEX IF NOT EXISTS idx_roster_jenis ON master_roster(jenis);
CREATE INDEX IF NOT EXISTS idx_roster_shift ON master_roster(shift);
CREATE INDEX IF NOT EXISTS idx_roster_unit ON master_roster(unit);

-- ------------------------------------------------------------------------------
-- 6. TABEL MASTER UNITS (Populasi Unit Lapangan: Excavator, Dozer, Grader, Digger)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_units (
    id VARCHAR(100) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    no_lambung VARCHAR(50) UNIQUE NOT NULL, -- 'EX001', 'DZ001', 'E2168'
    type_model VARCHAR(100) NOT NULL, -- 'PC210-10M0', 'D85ESS-2', 'PC850-8R1'
    kategori VARCHAR(50) NOT NULL DEFAULT 'coal', -- 'coal', 'non_coal', 'ob', 'support'
    cluster VARCHAR(50) NOT NULL DEFAULT 'Selatan', -- 'Selatan', 'Tengah', 'Utara', 'ROM'
    lokasi VARCHAR(100) NOT NULL DEFAULT 'Pit Area',
    status VARCHAR(30) NOT NULL DEFAULT 'Operasi', -- 'Operasi', 'Breakdown', 'Standby'
    status_aktif BOOLEAN DEFAULT TRUE,
    keterangan TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE master_units ADD COLUMN IF NOT EXISTS no_lambung VARCHAR(50);
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS type_model VARCHAR(100);
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS kategori VARCHAR(50) DEFAULT 'coal';
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS cluster VARCHAR(50) DEFAULT 'Selatan';
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS lokasi VARCHAR(100) DEFAULT 'Pit Area';
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS status VARCHAR(30) DEFAULT 'Operasi';
ALTER TABLE master_units ADD COLUMN IF NOT EXISTS status_aktif BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_units_no_lambung ON master_units(no_lambung);
CREATE INDEX IF NOT EXISTS idx_units_cluster ON master_units(cluster);
CREATE INDEX IF NOT EXISTS idx_units_status ON master_units(status);

-- ------------------------------------------------------------------------------
-- 7. TABEL MASTER OPERATORS (No OPT Produksi)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_operators (
    id VARCHAR(100) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    nrp VARCHAR(50) UNIQUE NOT NULL,
    nama VARCHAR(150) NOT NULL,
    no_wa VARCHAR(30),
    jabatan VARCHAR(80) DEFAULT 'Operator',
    cluster VARCHAR(50) DEFAULT 'Selatan',
    armada_unit VARCHAR(50),
    status_aktif BOOLEAN DEFAULT TRUE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE master_operators ADD COLUMN IF NOT EXISTS no_wa VARCHAR(30);
ALTER TABLE master_operators ADD COLUMN IF NOT EXISTS status_aktif BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_operators_nrp ON master_operators(nrp);
CREATE INDEX IF NOT EXISTS idx_operators_jabatan ON master_operators(jabatan);

-- ------------------------------------------------------------------------------
-- 8. TABEL JOBS (Jadwal Terencana, Realisasi, & Unscheduled LT/WT)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS jobs (
    id VARCHAR(100) PRIMARY KEY, -- 'LT-01', 'WT-01', 'UNS-01'
    job_type VARCHAR(30) NOT NULL DEFAULT 'lube', -- 'lube', 'water', 'unsch_lt', 'unsch_wt'
    cat VARCHAR(50) NOT NULL DEFAULT 'small', -- 'small', 'digger', 'aircleaner', 'topup', 'coal', 'rom', 'non_coal', 'unscheduled'
    tanggal DATE NOT NULL,
    shift INT NOT NULL DEFAULT 1, -- 1 = Siang, 2 = Malam
    washing_round INT DEFAULT 1, -- Putaran washing (1 / 2)
    cluster VARCHAR(50) NOT NULL, -- 'Selatan', 'Tengah', 'Utara', 'ROM'
    waktu_rencana VARCHAR(50), -- '07:00 s/d 07:15'
    type_unit VARCHAR(100) NOT NULL,
    no_lambung VARCHAR(50) NOT NULL,
    lokasi VARCHAR(100) NOT NULL,
    armada_unit VARCHAR(50) NOT NULL, -- Unit pelaksana: 'LT2535', 'WT101'
    opt_name VARCHAR(150),
    mp1 VARCHAR(150),
    mp2 VARCHAR(150),
    
    -- Realisasi Pelaksanaan Waktu Aktual
    jam_start VARCHAR(10),
    jam_end VARCHAR(10),
    durasi NUMERIC(10, 1),
    hm_stop NUMERIC(10, 2),
    hm_ready NUMERIC(10, 2),
    
    -- Status Eksekusi (scheduled, plan, ach, done, non_ach, pending, cancelled)
    status VARCHAR(30) NOT NULL DEFAULT 'scheduled',
    keterangan TEXT,
    is_pending BOOLEAN DEFAULT FALSE,
    ada_operator VARCHAR(10) DEFAULT 'Ya',
    
    -- Detail Tambahan & Kendala Non-Ach
    unit_condition VARCHAR(50),
    service_type VARCHAR(50),
    pemesan VARCHAR(150),
    kondisi VARCHAR(100),
    service_notes TEXT,
    bd_notes TEXT,
    non_ach_category VARCHAR(100),
    non_ach_reason TEXT,
    
    created_by VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS cat VARCHAR(50) DEFAULT 'small';
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS durasi NUMERIC(10, 1);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS service_type VARCHAR(50);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS pemesan VARCHAR(150);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS kondisi VARCHAR(100);
ALTER TABLE jobs DROP COLUMN IF EXISTS fotos;

CREATE INDEX IF NOT EXISTS idx_jobs_tanggal ON jobs(tanggal);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_armada ON jobs(armada_unit);
CREATE INDEX IF NOT EXISTS idx_jobs_no_lambung ON jobs(no_lambung);
CREATE INDEX IF NOT EXISTS idx_jobs_cluster ON jobs(cluster);

-- ------------------------------------------------------------------------------
-- 9. TABEL ORDER REQUESTS (Permintaan Layanan Servis Lapangan)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_requests (
    id VARCHAR(100) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    kode_order VARCHAR(50) UNIQUE,
    tanggal DATE NOT NULL,
    jam VARCHAR(10) NOT NULL,
    nama_pemesan VARCHAR(150) NOT NULL,
    role_pemesan VARCHAR(30) NOT NULL DEFAULT 'user',
    nrp_pemesan VARCHAR(50),
    no_lambung VARCHAR(50) NOT NULL,
    cluster VARCHAR(50) NOT NULL,
    lokasi VARCHAR(100) NOT NULL,
    keadaan_unit VARCHAR(100) NOT NULL,
    deskripsi TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'Pending',
    catatan_admin TEXT,
    handled_by VARCHAR(150),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_tanggal ON order_requests(tanggal);
CREATE INDEX IF NOT EXISTS idx_orders_status ON order_requests(status);
CREATE INDEX IF NOT EXISTS idx_orders_no_lambung ON order_requests(no_lambung);

-- ------------------------------------------------------------------------------
-- 10. TABEL AIR CLEANER MONITORING (Pemantauan Saringan Udara Unit Lapangan)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS air_cleaner_monitoring (
    id VARCHAR(100) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    no_lambung VARCHAR(50) UNIQUE NOT NULL,
    type_model VARCHAR(100) NOT NULL,
    cleans JSONB DEFAULT '[]'::jsonb,
    service_code VARCHAR(50) DEFAULT '',
    status VARCHAR(30) NOT NULL DEFAULT 'Baik',
    last_cleaned_date DATE,
    keterangan TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_air_cleaner_no_lambung ON air_cleaner_monitoring(no_lambung);
CREATE INDEX IF NOT EXISTS idx_air_cleaner_status ON air_cleaner_monitoring(status);

-- ------------------------------------------------------------------------------
-- 11. TABEL PICA RECORDS (Problem Identification & Corrective Action)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pica_records (
    id VARCHAR(100) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    job_id VARCHAR(100),
    no_lambung VARCHAR(50) NOT NULL,
    tanggal DATE NOT NULL,
    shift INT DEFAULT 1,
    cluster VARCHAR(50),
    kategori VARCHAR(80) NOT NULL,
    problem_description TEXT NOT NULL,
    root_cause TEXT,
    corrective_action TEXT,
    preventive_action TEXT,
    pic VARCHAR(150),
    status VARCHAR(30) DEFAULT 'Open',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pica_tanggal ON pica_records(tanggal);
CREATE INDEX IF NOT EXISTS idx_pica_status ON pica_records(status);

-- ------------------------------------------------------------------------------
-- 12. ROW LEVEL SECURITY (RLS) POLICIES - IZINKAN KONEKSI DARI INDEX.HTML
--     Mengatasi error 401 / 403 saat web app melakukan sinkronisasi dengan Supabase
-- ------------------------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_armada ENABLE ROW LEVEL SECURITY;
ALTER TABLE armada_clusters ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_roster ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_operators ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE air_cleaner_monitoring ENABLE ROW LEVEL SECURITY;
ALTER TABLE pica_records ENABLE ROW LEVEL SECURITY;

DO $$ 
DECLARE
    tbl TEXT;
    tables TEXT[] := ARRAY[
        'users', 'master_armada', 'armada_clusters', 'master_roster',
        'master_units', 'master_operators', 'jobs', 'order_requests',
        'air_cleaner_monitoring', 'pica_records'
    ];
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', 'allow_all_anon_' || tbl, tbl);
        EXECUTE format(
            'CREATE POLICY %I ON %I FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);',
            'allow_all_anon_' || tbl, tbl
        );
    END LOOP;
END $$;

-- ------------------------------------------------------------------------------
-- 13. TRIGGER OTOMATIS UPDATED_AT TIMESTAMP
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
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_armada_updated_at') THEN
        CREATE TRIGGER trg_armada_updated_at BEFORE UPDATE ON master_armada FOR EACH ROW EXECUTE FUNCTION update_timestamp_column();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_roster_updated_at') THEN
        CREATE TRIGGER trg_roster_updated_at BEFORE UPDATE ON master_roster FOR EACH ROW EXECUTE FUNCTION update_timestamp_column();
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
-- 14. INITIAL SEED DATA (Singkron Penuh dengan Data Default di index.html)
-- ------------------------------------------------------------------------------

-- A. Data Pengguna Default (5 Role)
INSERT INTO users (nrp, nama, password, role, jabatan, status_aktif)
VALUES
    ('admin',   'Admin Operasional',       'admin123', 'admin',       'Admin / Planner',    TRUE),
    ('user',    'User Lapangan',           'user123',  'user',        'User Pemohon / Driver', TRUE),
    ('om',      'Oilman (Lubetruck)',      'om123',    'mp_lt',       'Crew Lube Truck', TRUE),
    ('wm',      'Washingman (Water Truck)','wm123',    'mp_wt',       'Crew Water Truck', TRUE),
    ('bsc',     'Operator Base Control',   'bsc123',   'basecontrol', 'Radio Room / Dispatcher', TRUE),
    ('ADMIN01', 'Admin Operasional',       'admin123', 'admin',       'Admin / Planner',    TRUE),
    ('OM1001',  'Budi Santoso (Oilman)',   'om123',    'oilman',      'Crew Lube Truck', TRUE),
    ('WM2001',  'Dedi Prasetyo (Washingman)','wm123',  'washingman',  'Crew Water Truck', TRUE),
    ('USR3001', 'Agus Supriyadi (User)',   'user123',  'user',        'Foreman / Staff Lapangan', TRUE),
    ('BC4001',  'Rian Setiawan (Base Control)', 'bsc123', 'basecontrol', 'Radio Dispatcher / Base Control', TRUE)
ON CONFLICT (nrp) DO NOTHING;

-- B. Data Master Armada (Seluruh Armada Lubetruck & Water Truck)
INSERT INTO master_armada (id, unit, type_unit, cluster, status)
VALUES
    -- Lubetruck
    ('ARM-01', 'LT2535', 'Lubetruck', 'Selatan', 'Aktif'),
    ('ARM-02', 'LT2622', 'Lubetruck', 'Selatan', 'Aktif'),
    ('ARM-03', 'LT2530', 'Lubetruck', 'Selatan', 'Aktif'),
    ('ARM-04', 'LT2514', 'Lubetruck', 'Tengah',  'Aktif'),
    ('ARM-05', 'LT2518', 'Lubetruck', 'Tengah',  'Aktif'),
    ('ARM-06', 'LT2510', 'Lubetruck', 'Utara',   'Aktif'),
    ('ARM-07', 'LT2525', 'Lubetruck', 'Utara',   'Aktif'),
    ('ARM-08', 'LT2515', 'Lubetruck', 'Selatan', 'Aktif'),
    ('ARM-09', 'LT2536', 'Lubetruck', 'Selatan', 'Aktif'),
    -- Water Truck
    ('ARM-10', 'WT101',  'Water Truck', 'Selatan', 'Aktif'),
    ('ARM-11', 'WT102',  'Water Truck', 'Tengah',  'Aktif'),
    ('ARM-12', 'WT103',  'Water Truck', 'Utara',   'Aktif'),
    ('ARM-13', 'WT104',  'Water Truck', 'Selatan', 'Aktif'),
    ('ARM-14', 'WT105',  'Water Truck', 'Tengah',  'Aktif'),
    ('ARM-15', 'WT2520', 'Water Truck', 'Selatan', 'Aktif'),
    ('ARM-16', 'WT2644', 'Water Truck', 'Utara',   'Aktif'),
    ('ARM-17', 'WT2645', 'Water Truck', 'ROM',     'Aktif')
ON CONFLICT (unit) DO UPDATE SET
    type_unit = EXCLUDED.type_unit,
    cluster = EXCLUDED.cluster,
    status = EXCLUDED.status;

-- C. Alokasi Armada Bertugas per Cluster
INSERT INTO armada_clusters (cluster_name, armada_type, assigned_units)
VALUES
    ('Selatan', 'LT', 'LT2535, LT2622, LT2530'),
    ('Tengah',  'LT', 'LT2514, LT2518'),
    ('Utara',   'LT', 'LT2510, LT2525'),
    ('Selatan', 'WT', 'WT101, WT104, WT2520'),
    ('Tengah',  'WT', 'WT102, WT105'),
    ('Utara',   'WT', 'WT103, WT2644'),
    ('ROM',     'WT', 'WT2645')
ON CONFLICT (cluster_name, armada_type) DO UPDATE SET
    assigned_units = EXCLUDED.assigned_units;

-- D. Contoh Master Populasi Unit Lapangan
INSERT INTO master_units (no_lambung, type_model, kategori, cluster, lokasi, status)
VALUES
    ('EX2168', 'PC210-10M0', 'coal',     'Selatan', 'BALANAI',        'Operasi'),
    ('EX2169', 'PC210-10M0', 'coal',     'Selatan', 'SIM E',          'Operasi'),
    ('DZ8589', 'D85ESS-2',   'non_coal', 'Tengah',  'FRONT RAJAWALI', 'Operasi'),
    ('EX8501', 'PC850-8R1',  'coal',     'Utara',   'PIT UTARA',      'Operasi'),
    ('CT3951', 'CAT395',     'non_coal', 'ROM',     'ROM STOCKPILE',  'Operasi')
ON CONFLICT (no_lambung) DO NOTHING;

-- E. Contoh Master Operator Produksi
INSERT INTO master_operators (nrp, nama, no_wa, jabatan, cluster)
VALUES
    ('OPT3001', 'Budi Santoso',  '081234567801', 'Operator Excavator', 'Selatan'),
    ('OPT3002', 'Joko Widodo',   '081234567802', 'Operator Dozer',     'Tengah'),
    ('OPT3003', 'Slamet Riyadi', '081234567803', 'Operator Shovel',    'Utara')
ON CONFLICT (nrp) DO NOTHING;

-- F. Contoh Roster Aktif
INSERT INTO master_roster (id, jenis, nrp, nama, unit, unit_efektif, tanggal, shift, kode_shift, is_spare)
VALUES
    ('RST-01', 'OPT', '800101', 'Budi Santoso',  'LT2510', 'LT2510', CURRENT_DATE, 1, 'DWS',  FALSE),
    ('RST-02', 'OPT', '800102', 'Joko Widodo',   'LT2510', 'LT2510', CURRENT_DATE, 2, 'NWS',  FALSE),
    ('RST-03', 'OM',  '800201', 'Hendra Gunawan', 'LT2535', 'LT2535', CURRENT_DATE, 1, 'DWS',  FALSE),
    ('RST-04', 'OM',  '800202', 'Doni Pratama',   'LT2535', 'LT2535', CURRENT_DATE, 1, 'DWS',  FALSE),
    ('RST-05', 'WM',  '800301', 'Agus Setiawan',  'WT101',  'WT101',  CURRENT_DATE, 1, 'DWS',  FALSE)
ON CONFLICT (id) DO NOTHING;

-- ==============================================================================
-- AKHIR SKEMA DATABASE SE MANAGEMENT JOB
-- ==============================================================================
