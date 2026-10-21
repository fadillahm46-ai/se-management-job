-- ==============================================================================
-- SKEMA LENGKAP DATABASE SUPABASE: SE MANAGEMENT JOB - MINE OPERATIONS
-- Versi       : v2.5.0 (Clean Architecture, Ultra-Low Egress, Zero-Zombie Data)
-- Tanggal     : 2026-10-21
-- Deskripsi   : Skrip DDL 100% mandiri dan bersih untuk inisialisasi akun / project baru Supabase.
--               Mencakup 11 tabel utama, RLS, Realtime WebSocket Pub/Sub, Replica Identity,
--               Trigger Audit Otomatis, dan Akun Pengguna Awal (Tanpa Data Dummy).
-- Cara Pakai  : Buka Supabase Dashboard > SQL Editor > New Query > Paste Seluruh Skrip > Run (Ctrl+Enter)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. EKSTENSI POSTGRESQL WAJIB
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 2. DDL TABEL DATABASE (11 TABEL UTAMA + 1 TABEL KOMPATIBILITAS)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 2.1 TABEL USERS (Manajemen Akun Pegawai & Hak Akses Multi-Role)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nrp VARCHAR(50) NOT NULL UNIQUE,
    nama VARCHAR(150) NOT NULL,
    password VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('admin', 'planner', 'user', 'mp_lt', 'mp_wt', 'basecontrol', 'oilman', 'washingman', 'track')),
    jabatan VARCHAR(100),
    no_wa VARCHAR(50),
    status_aktif BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.2 TABEL MASTER_ARMADA (Daftar Fisik Unit Armada Lubetruck & Water Truck)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.master_armada (
    id VARCHAR(50) PRIMARY KEY, -- 'ARM-01', 'ARM-02', dst.
    unit VARCHAR(50) NOT NULL UNIQUE, -- 'LT2535', 'WT101', dst.
    type_unit VARCHAR(50) NOT NULL CHECK (type_unit IN ('Lubetruck', 'Water Truck')),
    cluster VARCHAR(50) NOT NULL DEFAULT 'Selatan',
    status VARCHAR(50) NOT NULL DEFAULT 'Aktif' CHECK (status IN ('Aktif', 'Operasi', 'Standby', 'Breakdown', 'Maintenance', 'Non-Aktif')),
    keterangan TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.3 TABEL ARMADA_CLUSTERS (Alokasi & Penugasan Armada per Kluster Wilayah)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.armada_clusters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cluster_name VARCHAR(50) NOT NULL,
    armada_type VARCHAR(10) NOT NULL CHECK (armada_type IN ('LT', 'WT')),
    assigned_units TEXT, -- Contoh: 'LT2530, LT2535, LT2622'
    updated_by VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_cluster_armada UNIQUE (cluster_name, armada_type)
);

-- ------------------------------------------------------------------------------
-- 2.4 TABEL MASTER_UNITS (Populasi Unit Alat Berat Lapangan: Dozer, Exca, Shovel)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.master_units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    no_lambung VARCHAR(50) NOT NULL UNIQUE, -- 'CT2514', 'DZ8589', 'EX2168'
    type_model VARCHAR(100) NOT NULL, -- 'PC210-10M0', 'D85ESS-2', 'CAT395'
    kategori VARCHAR(50) NOT NULL DEFAULT 'coal' CHECK (kategori IN ('coal', 'non_coal', 'big_digger')),
    cluster VARCHAR(50) NOT NULL DEFAULT 'Selatan',
    lokasi VARCHAR(100) NOT NULL DEFAULT 'Pit Area',
    status VARCHAR(50) NOT NULL DEFAULT 'Operasi' CHECK (status IN ('Operasi', 'Breakdown', 'Standby')),
    status_aktif BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.5 TABEL MASTER_OPERATORS (Kontak Produksi & Operator Alat Berat)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.master_operators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nrp VARCHAR(50) NOT NULL UNIQUE,
    nama VARCHAR(150) NOT NULL,
    no_wa VARCHAR(100),
    jabatan VARCHAR(100) DEFAULT 'Operator',
    cluster VARCHAR(50) DEFAULT 'Selatan',
    status_aktif BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.6 TABEL MASTER_KONTAK_PRO (Kompatibilitas Ringkas Kontak Produksi)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.master_kontak_pro (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nrp VARCHAR(50) NOT NULL UNIQUE,
    nama VARCHAR(255) NOT NULL,
    no_wa VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.7 TABEL MASTER_ROSTER (Roster Kerja Bulanan Manpower & Operator)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.master_roster (
    id VARCHAR(100) PRIMARY KEY, -- 'RST-OPT-20261021-800101'
    jenis VARCHAR(20) NOT NULL CHECK (jenis IN ('OPT', 'OM', 'WM', 'FL')),
    nrp VARCHAR(50) NOT NULL,
    nama VARCHAR(150) NOT NULL,
    unit VARCHAR(50),
    unit_efektif VARCHAR(50),
    tanggal DATE NOT NULL,
    shift INT NOT NULL DEFAULT 1 CHECK (shift IN (1, 2)),
    kode_shift VARCHAR(20) NOT NULL DEFAULT 'DWS', -- 'DWS', 'NWS', 'OFF', 'R'
    periode VARCHAR(50),
    is_spare BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.8 TABEL JOBS (Jadwal & Riwayat Pekerjaan Aktif Transaksi Lapangan)
--     Mencakup Greasing Small, Big Digger, Air Cleaner, Washing, & Unscheduled
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.jobs (
    id VARCHAR(100) PRIMARY KEY, -- 'LT-SCH-20261021-EX2168-S1', 'UNS-20261021-001'
    job_type VARCHAR(30) NOT NULL DEFAULT 'lube', -- 'lube', 'water', 'sch_lt', 'sch_wt', 'unsch_lt', 'unsch_wt'
    cat VARCHAR(50) NOT NULL DEFAULT 'small', -- 'small', 'digger', 'aircleaner', 'topup', 'coal', 'rom', 'non_coal', 'unscheduled'
    tanggal DATE NOT NULL,
    shift INT NOT NULL DEFAULT 1 CHECK (shift IN (1, 2)),
    washing_round INT DEFAULT 1, -- Putaran washing (1 / 2)
    cluster VARCHAR(50) NOT NULL,
    waktu_rencana VARCHAR(50), -- '07:00 s/d 07:15'
    type_unit VARCHAR(100) NOT NULL,
    no_lambung VARCHAR(50) NOT NULL,
    lokasi VARCHAR(100) NOT NULL,
    armada_unit VARCHAR(50) NOT NULL, -- 'LT2535', 'WT101'
    opt_name VARCHAR(150),
    mp1 VARCHAR(150),
    mp2 VARCHAR(150),
    
    -- Realisasi Waktu & Hour Meter Aktual
    jam_start VARCHAR(10),
    jam_end VARCHAR(10),
    durasi NUMERIC(10, 1),
    hm_stop NUMERIC(10, 2),
    hm_ready NUMERIC(10, 2),
    
    -- Status Eksekusi
    status VARCHAR(30) NOT NULL DEFAULT 'scheduled', -- 'scheduled', 'plan', 'ach', 'done', 'non_ach', 'pending', 'cancelled'
    keterangan TEXT,
    is_pending BOOLEAN DEFAULT FALSE,
    ada_operator VARCHAR(10) DEFAULT 'Ya',
    
    -- Detail Servis Lapangan & Kendala Non-ACH
    unit_condition VARCHAR(50),
    service_type VARCHAR(50),
    pemesan VARCHAR(150),
    kondisi VARCHAR(100),
    service_notes TEXT,
    bd_notes TEXT,
    non_ach_category VARCHAR(100),
    non_ach_reason TEXT,
    carry_count INT DEFAULT 0,
    original_date DATE,
    
    created_by VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.9 TABEL ORDER_REQUESTS (Permintaan Servis Lapangan Unscheduled / Darurat)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.order_requests (
    id VARCHAR(100) PRIMARY KEY, -- 'ORD-20261021-001'
    kode_order VARCHAR(100),
    service_type VARCHAR(50) NOT NULL, -- 'greasing', 'oil_topup', 'air_cleaner', 'washing'
    type_unit VARCHAR(100) NOT NULL,
    tanggal DATE NOT NULL,
    shift INT NOT NULL DEFAULT 1 CHECK (shift IN (1, 2)),
    jam VARCHAR(10),
    nama_pemesan VARCHAR(150) NOT NULL,
    role_pemesan VARCHAR(50),
    nrp_pemesan VARCHAR(50),
    no_lambung VARCHAR(50) NOT NULL,
    cluster VARCHAR(50) NOT NULL,
    lokasi VARCHAR(100) NOT NULL,
    keadaan_unit VARCHAR(100),
    armada_unit VARCHAR(50),
    opt_name VARCHAR(150),
    mp1 VARCHAR(150),
    mp2 VARCHAR(150),
    hm_start NUMERIC(10, 2),
    hm_end NUMERIC(10, 2),
    jam_start VARCHAR(10),
    jam_end VARCHAR(10),
    durasi NUMERIC(10, 1),
    tanggal_eksekusi DATE,
    status VARCHAR(50) NOT NULL DEFAULT 'Open', -- 'Open', 'In Progress', 'Done', 'Cancelled'
    is_locked BOOLEAN DEFAULT FALSE,
    handled_by VARCHAR(100),
    keterangan TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.10 TABEL AIR_CLEANER_MONITORING (Monitoring Siklus Pembersihan Filter Udara)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.air_cleaner_monitoring (
    id VARCHAR(50) PRIMARY KEY, -- 'AC-EX2168'
    no_lambung VARCHAR(50) NOT NULL UNIQUE,
    type_model VARCHAR(100) NOT NULL,
    cleans JSONB NOT NULL DEFAULT '[]'::jsonb, -- Array string tanggal/waktu semprotan ['21/10/2026', ...]
    service_code VARCHAR(50),
    status VARCHAR(50) NOT NULL DEFAULT 'Baik',
    last_cleaned_date DATE,
    cluster VARCHAR(50),
    lokasi VARCHAR(100),
    evidence_url TEXT, -- URL Foto Evidence Pergantian Terakhir (Google Drive)
    last_replaced_at TIMESTAMPTZ, -- Waktu pergantian filter terakhir oleh Tim Track / Admin
    last_replaced_by VARCHAR(150), -- Nama PIC pergantian terakhir
    replace_notes TEXT, -- Catatan teknis pergantian filter
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.10.B TABEL AIR_CLEANER_REPLACEMENTS (Riwayat Pergantian Komponen Air Cleaner & Evidence)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.air_cleaner_replacements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    no_lambung VARCHAR(50) NOT NULL,
    type_model VARCHAR(100),
    tanggal DATE NOT NULL DEFAULT CURRENT_DATE,
    jam VARCHAR(20),
    pic VARCHAR(150) NOT NULL,
    pic_nrp VARCHAR(50),
    keterangan TEXT,
    evidence_url TEXT NOT NULL, -- Link Foto Google Drive
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.11 TABEL PICA_RECORDS (Problem Identification & Corrective Action)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pica_records (
    id VARCHAR(100) PRIMARY KEY, -- 'PICA-LT-01'
    job_id VARCHAR(100) NOT NULL,
    no_lambung VARCHAR(50) NOT NULL,
    tanggal DATE NOT NULL,
    shift INT NOT NULL DEFAULT 1 CHECK (shift IN (1, 2)),
    cluster VARCHAR(50) NOT NULL,
    kategori VARCHAR(100) NOT NULL,
    problem_description TEXT NOT NULL,
    root_cause TEXT,
    corrective_action TEXT,
    preventive_action TEXT,
    pic VARCHAR(150),
    status VARCHAR(50) DEFAULT 'Open',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.12 TABEL JOB_HISTORY (Snapshot Riwayat Pekerjaan Terkunci / Immutable Audit)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id VARCHAR(100) NOT NULL,
    no_lambung VARCHAR(50) NOT NULL,
    type_unit VARCHAR(100),
    cat VARCHAR(50) NOT NULL,
    job_type VARCHAR(30) NOT NULL DEFAULT 'lube',
    tanggal_rencana DATE NOT NULL,
    shift_rencana INT NOT NULL DEFAULT 1,
    waktu_rencana VARCHAR(50),
    cluster VARCHAR(50) NOT NULL,
    lokasi VARCHAR(100) NOT NULL,
    armada_unit VARCHAR(50),
    opt_name VARCHAR(150),
    mp1 VARCHAR(150),
    mp2 VARCHAR(150),
    tanggal_eksekusi DATE,
    jam_start VARCHAR(10),
    jam_end VARCHAR(10),
    durasi NUMERIC(10, 1),
    status_final VARCHAR(30) NOT NULL CHECK (status_final IN ('ACHIEVED', 'NON_ACH', 'ach', 'non_ach', 'service', 'bd', 'done')),
    keterangan TEXT,
    non_ach_category VARCHAR(100),
    non_ach_reason TEXT,
    snapshot_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_job_history_job_id UNIQUE (job_id)
);

-- ==============================================================================
-- 3. INDEX STRATEGIS (Kueri Cepat, Low-Egress, Anti-Lag)
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_users_nrp ON public.users(nrp);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);

CREATE INDEX IF NOT EXISTS idx_master_armada_unit ON public.master_armada(unit);
CREATE INDEX IF NOT EXISTS idx_master_units_lambung ON public.master_units(no_lambung);
CREATE INDEX IF NOT EXISTS idx_master_operators_nrp ON public.master_operators(nrp);

CREATE INDEX IF NOT EXISTS idx_roster_composite ON public.master_roster(tanggal, shift, nrp);
CREATE INDEX IF NOT EXISTS idx_roster_unit ON public.master_roster(unit);

CREATE INDEX IF NOT EXISTS idx_jobs_tanggal ON public.jobs(tanggal);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON public.jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_is_pending ON public.jobs(is_pending);
CREATE INDEX IF NOT EXISTS idx_jobs_armada ON public.jobs(armada_unit);
CREATE INDEX IF NOT EXISTS idx_jobs_no_lambung ON public.jobs(no_lambung);
CREATE INDEX IF NOT EXISTS idx_jobs_composite_hot ON public.jobs(tanggal, shift, status);

CREATE INDEX IF NOT EXISTS idx_orders_tanggal ON public.order_requests(tanggal);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.order_requests(status);
CREATE INDEX IF NOT EXISTS idx_orders_lambung ON public.order_requests(no_lambung);

CREATE INDEX IF NOT EXISTS idx_ac_lambung ON public.air_cleaner_monitoring(no_lambung);
CREATE INDEX IF NOT EXISTS idx_pica_job_id ON public.pica_records(job_id);
CREATE INDEX IF NOT EXISTS idx_pica_tanggal ON public.pica_records(tanggal);

CREATE INDEX IF NOT EXISTS idx_job_history_job_id ON public.job_history(job_id);
CREATE INDEX IF NOT EXISTS idx_job_history_no_lambung ON public.job_history(no_lambung);
CREATE INDEX IF NOT EXISTS idx_job_history_tanggal_eksekusi ON public.job_history(tanggal_eksekusi);
CREATE INDEX IF NOT EXISTS idx_job_history_status_final ON public.job_history(status_final);

-- ==============================================================================
-- 4. REPLICA IDENTITY FULL (Wajib Realtime Supabase untuk Payload Lengkap saat DELETE/UPDATE)
-- ==============================================================================
ALTER TABLE public.users REPLICA IDENTITY FULL;
ALTER TABLE public.master_armada REPLICA IDENTITY FULL;
ALTER TABLE public.armada_clusters REPLICA IDENTITY FULL;
ALTER TABLE public.master_units REPLICA IDENTITY FULL;
ALTER TABLE public.master_operators REPLICA IDENTITY FULL;
ALTER TABLE public.master_kontak_pro REPLICA IDENTITY FULL;
ALTER TABLE public.master_roster REPLICA IDENTITY FULL;
ALTER TABLE public.jobs REPLICA IDENTITY FULL;
ALTER TABLE public.order_requests REPLICA IDENTITY FULL;
ALTER TABLE public.air_cleaner_monitoring REPLICA IDENTITY FULL;
ALTER TABLE public.air_cleaner_replacements REPLICA IDENTITY FULL;
ALTER TABLE public.pica_records REPLICA IDENTITY FULL;
ALTER TABLE public.job_history REPLICA IDENTITY FULL;

-- ==============================================================================
-- 5. ROW LEVEL SECURITY (RLS) & POLICY AKSES TERBUKA UNTUK APLIKASI WEB
--    Memastikan aplikasi web dengan Anon Key dapat membaca dan menulis data
-- ==============================================================================
DO $$ 
DECLARE
    tbl TEXT;
    tables TEXT[] := ARRAY[
        'users', 'master_armada', 'armada_clusters', 'master_roster',
        'master_units', 'master_operators', 'master_kontak_pro', 'jobs', 
        'order_requests', 'air_cleaner_monitoring', 'air_cleaner_replacements', 'pica_records', 'job_history'
    ];
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', 'allow_all_anon_' || tbl, tbl);
        EXECUTE format(
            'CREATE POLICY %I ON public.%I FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);',
            'allow_all_anon_' || tbl, tbl
        );
    END LOOP;
END $$;

-- ==============================================================================
-- 6. SUPABASE REALTIME WEBSOCKET (Publikasi Dua Arah Tanpa Polling)
-- ==============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

DO $$ 
DECLARE
    tbl TEXT;
    tables TEXT[] := ARRAY[
        'users', 'master_armada', 'armada_clusters', 'master_roster',
        'master_units', 'master_operators', 'master_kontak_pro', 'jobs', 
        'order_requests', 'air_cleaner_monitoring', 'air_cleaner_replacements', 'pica_records', 'job_history'
    ];
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        BEGIN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl);
        EXCEPTION
            WHEN duplicate_object THEN
                NULL;
            WHEN OTHERS THEN
                NULL;
        END;
    END LOOP;
END $$;

-- ==============================================================================
-- 7. TRIGGER OTOMATIS UPDATED_AT TIMESTAMP
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.update_timestamp_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ 
DECLARE
    tbl TEXT;
    tables TEXT[] := ARRAY[
        'users', 'master_armada', 'armada_clusters', 'master_roster',
        'master_units', 'master_operators', 'master_kontak_pro', 'jobs', 
        'order_requests', 'air_cleaner_monitoring', 'pica_records'
    ];
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I;', 'trg_' || tbl || '_updated_at', tbl);
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.update_timestamp_column();',
            'trg_' || tbl || '_updated_at', tbl
        );
    END LOOP;
END $$;

-- ==============================================================================
-- 8. TRIGGER OTOMATIS: SNAPSHOT RIWAYAT PEKERJAAN (IMMUTABLE JOB_HISTORY)
--    Menyimpan snapshot otomatis saat job berubah status ke ACHIEVED / NON_ACH
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.trg_lock_job_history_snapshot_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_status_norm VARCHAR(30);
BEGIN
    v_status_norm := UPPER(COALESCE(NEW.status, ''));
    IF v_status_norm IN ('ACH', 'ACHIEVED', 'DONE', 'SERVICE', 'BD') THEN
        v_status_norm := 'ACHIEVED';
    ELSIF v_status_norm IN ('NON_ACH', 'NON-ACH', 'CANCELLED', 'CANCEL') THEN
        v_status_norm := 'NON_ACH';
    ELSE
        RETURN NEW;
    END IF;

    INSERT INTO public.job_history (
        job_id, no_lambung, type_unit, cat, job_type,
        tanggal_rencana, shift_rencana, waktu_rencana,
        cluster, lokasi, armada_unit, opt_name, mp1, mp2,
        tanggal_eksekusi, jam_start, jam_end, durasi,
        status_final, keterangan, non_ach_category, non_ach_reason,
        snapshot_data, created_at
    )
    VALUES (
        NEW.id, NEW.no_lambung, NEW.type_unit, NEW.cat, NEW.job_type,
        NEW.tanggal, NEW.shift, NEW.waktu_rencana,
        NEW.cluster, NEW.lokasi, NEW.armada_unit, NEW.opt_name, NEW.mp1, NEW.mp2,
        COALESCE(NEW.tanggal, CURRENT_DATE), NEW.jam_start, NEW.jam_end, NEW.durasi,
        v_status_norm, NEW.keterangan, NEW.non_ach_category, NEW.non_ach_reason,
        to_jsonb(NEW), NOW()
    )
    ON CONFLICT (job_id) DO UPDATE SET
        tanggal_eksekusi = EXCLUDED.tanggal_eksekusi,
        jam_start = EXCLUDED.jam_start,
        jam_end = EXCLUDED.jam_end,
        durasi = EXCLUDED.durasi,
        status_final = EXCLUDED.status_final,
        keterangan = EXCLUDED.keterangan,
        non_ach_category = EXCLUDED.non_ach_category,
        non_ach_reason = EXCLUDED.non_ach_reason,
        snapshot_data = EXCLUDED.snapshot_data;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_job_snapshot_lock ON public.jobs;
CREATE TRIGGER trg_job_snapshot_lock
    AFTER INSERT OR UPDATE OF status ON public.jobs
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_lock_job_history_snapshot_fn();

-- ==============================================================================
-- 9. SELESAI: SELURUH TABEL DIBUAT 100% KOSONG TANPA ISI DUMMY
-- Semua tabel (users, armada, clusters, units, operators, jobs, orders, dsb)
-- siap digunakan dalam keadaan bersih tanpa ada baris data awal.
-- ==============================================================================


-- ==============================================================================
-- 9. SEED AKUN UTAMA TIM TRACK (Kredensial Resmi Sesuai Permintaan)
-- ==============================================================================
INSERT INTO public.users (nrp, nama, password, role, jabatan, status_aktif)
VALUES
    ('admin', 'Admin Operasional', 'admin123', 'admin', 'Admin / Planner', TRUE),
    ('track', 'Tim Track Lapangan', 'track123', 'track', 'Tim Track', TRUE)
ON CONFLICT (nrp) DO UPDATE SET
    password = EXCLUDED.password,
    role = EXCLUDED.role,
    jabatan = EXCLUDED.jabatan;
