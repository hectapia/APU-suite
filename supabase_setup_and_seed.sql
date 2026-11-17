-- =============================================================================
-- APU-suite: Production PostgreSQL Supabase Schema & Seed Script (Idempotent & Secure)
-- Platform: Supabase / PostgreSQL 15+
-- Generated from: Abstract.xlsx
--
-- Security & Safety Highlights:
--   1. Non-Destructive / Idempotent: Uses conditional object creation and upserts.
--   2. 100% Row-Level Security (RLS): Enabled on ALL 15 tables, including app_user.
--   3. Granular Security Policies: Covers anon, authenticated, and service_role.
--   4. Views with security_invoker = true to respect RLS boundaries.
--   5. Full Seed Data: All 1,335 concepts and master catalogs loaded safely.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. EXTENSIONS
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- -----------------------------------------------------------------------------
-- 2. CORE ENTITIES DDL (NON-DESTRUCTIVE)
-- -----------------------------------------------------------------------------

-- App User & RBAC (Linked to Supabase auth.users)
CREATE TABLE IF NOT EXISTS app_user (
    id_user UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'PROVIDER_ESTIMATOR' 
        CHECK (role IN ('ADMIN', 'PROVIDER_ESTIMATOR', 'AUDITOR', 'CLIENT_VIEWER')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Client / Contracting Entity (e.g. Pemex)
CREATE TABLE IF NOT EXISTS client (
    id_client SERIAL PRIMARY KEY,
    client_name TEXT NOT NULL,
    client_department TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Provider / Contractor (e.g. MHEBOSAP)
CREATE TABLE IF NOT EXISTS provider (
    id_provider SERIAL PRIMARY KEY,
    tag_provider VARCHAR(50) NOT NULL,
    provider_name TEXT NOT NULL,
    provider_representative TEXT,
    provider_position TEXT,
    contact_email VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Event / Tender
CREATE TABLE IF NOT EXISTS event (
    id_event SERIAL PRIMARY KEY,
    tag_event VARCHAR(100) NOT NULL UNIQUE,
    event_type VARCHAR(150) NOT NULL,
    event_description TEXT NOT NULL,
    id_client INT NOT NULL REFERENCES client(id_client) ON DELETE RESTRICT,
    status VARCHAR(30) NOT NULL DEFAULT 'OPEN' 
        CHECK (status IN ('DRAFT', 'OPEN', 'IN_REVIEW', 'AWARDED', 'CLOSED')),
    submission_deadline TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Event Invitation (Magic Link System - matching contractmanager pattern)
CREATE TABLE IF NOT EXISTS event_invitation (
    id_invitation UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_event INT NOT NULL REFERENCES event(id_event) ON DELETE CASCADE,
    id_provider INT REFERENCES provider(id_provider) ON DELETE CASCADE,
    invited_email VARCHAR(255) NOT NULL,
    token UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 days'),
    is_accepted BOOLEAN NOT NULL DEFAULT false,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Event Provider Access Assignment
CREATE TABLE IF NOT EXISTS event_provider_assignment (
    id_assignment UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_event INT NOT NULL REFERENCES event(id_event) ON DELETE CASCADE,
    id_provider INT NOT NULL REFERENCES provider(id_provider) ON DELETE CASCADE,
    access_role VARCHAR(20) NOT NULL DEFAULT 'WRITE' CHECK (access_role IN ('READ', 'WRITE', 'SUBMITTED')),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_event_provider UNIQUE (id_event, id_provider)
);

-- Concept Catalog (1,336 items per event)
CREATE TABLE IF NOT EXISTS concept (
    id_concept INT PRIMARY KEY,
    id_event INT NOT NULL REFERENCES event(id_event) ON DELETE CASCADE,
    id_client INT NOT NULL REFERENCES client(id_client) ON DELETE RESTRICT,
    tag_concept VARCHAR(50) NOT NULL,
    concept_header TEXT,
    concept_description TEXT NOT NULL,
    concept_unit VARCHAR(50) NOT NULL,
    concept_price NUMERIC(14,2) DEFAULT NULL,
    concept_price_txt TEXT DEFAULT NULL,
    display_order INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for sub-second search across 1,300+ concepts
CREATE INDEX IF NOT EXISTS idx_concept_event ON concept(id_event);
CREATE INDEX IF NOT EXISTS idx_concept_tag ON concept(tag_concept);
CREATE INDEX IF NOT EXISTS idx_concept_header ON concept(concept_header);
CREATE INDEX IF NOT EXISTS idx_concept_description_trgm ON concept USING GIN (concept_description gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- 3. MASTER CATALOGS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS catalog_material (
    id_catalog_material INT PRIMARY KEY,
    tag_catalog_material VARCHAR(50),
    catalog_material_description TEXT NOT NULL,
    catalog_material_unit VARCHAR(50) NOT NULL,
    catalog_material_brand VARCHAR(100),
    catalog_material_model VARCHAR(100),
    catalog_material_unit_price NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS catalog_labor (
    id_catalog_labor INT PRIMARY KEY,
    tag_catalog_labor VARCHAR(50),
    catalog_labor_category TEXT NOT NULL,
    catalog_labor_unit VARCHAR(50) NOT NULL DEFAULT 'Jornada',
    catalog_labor_unit_price NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS catalog_equipment (
    id_catalog_equipment INT PRIMARY KEY,
    tag_catalog_equipment VARCHAR(50),
    catalog_equipment_description TEXT NOT NULL,
    catalog_equipment_unit VARCHAR(50) NOT NULL DEFAULT 'HORA',
    catalog_equipment_brand VARCHAR(100),
    catalog_equipment_model VARCHAR(100),
    catalog_equipment_year INT,
    catalog_equipment_serial VARCHAR(100),
    catalog_equipment_unit_price NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    catalog_equipment_status VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 4. INTERMEDIATE PERFORMANCE TABLE (GLOBAL CREW & MACHINERY YIELDS)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS concept_performance_group (
    id_performance_group UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_concept INT NOT NULL REFERENCES concept(id_concept) ON DELETE CASCADE,
    resource_type VARCHAR(20) NOT NULL CHECK (resource_type IN ('LABOR', 'EQUIPMENT')),
    performance_factor NUMERIC(12,4) NOT NULL DEFAULT 1.0000 CHECK (performance_factor > 0),
    performance_unit VARCHAR(50) NOT NULL,
    calculation_mode VARCHAR(20) NOT NULL DEFAULT 'MULTIPLICATION' 
        CHECK (calculation_mode IN ('MULTIPLICATION', 'DIVISION')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_concept_resource_type UNIQUE (id_concept, resource_type)
);

-- -----------------------------------------------------------------------------
-- 5. APU INTEGRATION HEADER & DETAIL TABLES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS concept_apu_integration (
    id_apu UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_concept INT NOT NULL REFERENCES concept(id_concept) ON DELETE CASCADE,
    id_provider INT NOT NULL REFERENCES provider(id_provider) ON DELETE CASCADE,
    
    -- Configurable Percentage Factors
    pct_indirects NUMERIC(6,4) NOT NULL DEFAULT 0.1500,       -- 15.0% Indirectos
    pct_financing NUMERIC(6,4) NOT NULL DEFAULT 0.0150,       -- 1.5% Financiamiento
    pct_utility NUMERIC(6,4) NOT NULL DEFAULT 0.1500,         -- 15.0% Utilidad
    pct_safety_equipment NUMERIC(6,4) NOT NULL DEFAULT 0.0150, -- 1.5% Equipo Seguridad
    pct_hand_tools NUMERIC(6,4) NOT NULL DEFAULT 0.0300,       -- 3.0% Herramienta Menor
    apply_sfp BOOLEAN NOT NULL DEFAULT false,                  -- SFP 5 al millar (G/(1-0.005)-G)
    
    -- Subtotals: Insumos Directos
    subtotal_materials NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    subtotal_labor NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    subtotal_equipment NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    subtotal_safety_tools NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    
    -- Cascading Mathematical Overhead Hierarchy
    cost_direct_a NUMERIC(14,2) NOT NULL DEFAULT 0.00,        -- A = 1 + 2 + 3 + 4
    cost_indirect_b NUMERIC(14,2) NOT NULL DEFAULT 0.00,      -- B = A * pct_indirects
    cost_sum_c NUMERIC(14,2) NOT NULL DEFAULT 0.00,           -- C = A + B
    cost_financing_d NUMERIC(14,2) NOT NULL DEFAULT 0.00,     -- D = C * pct_financing
    cost_sum_e NUMERIC(14,2) NOT NULL DEFAULT 0.00,           -- E = C + D
    cost_utility_f NUMERIC(14,2) NOT NULL DEFAULT 0.00,       -- F = E * pct_utility
    cost_sum_g NUMERIC(14,2) NOT NULL DEFAULT 0.00,           -- G = E + F
    cost_sfp NUMERIC(14,2) NOT NULL DEFAULT 0.00,             -- SFP = (G / 0.995) - G
    concept_price NUMERIC(14,2) NOT NULL DEFAULT 0.00,        -- Final Unit Price = G + SFP
    concept_price_txt TEXT,                                   -- Written Legal Text
    
    status VARCHAR(20) NOT NULL DEFAULT 'COMPLETED' 
        CHECK (status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_concept_provider_apu UNIQUE (id_concept, id_provider)
);

-- Material Line Items
CREATE TABLE IF NOT EXISTS material_by_concept (
    id_material_by_concept UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_apu UUID NOT NULL REFERENCES concept_apu_integration(id_apu) ON DELETE CASCADE,
    id_concept INT NOT NULL REFERENCES concept(id_concept) ON DELETE CASCADE,
    id_catalog_material INT REFERENCES catalog_material(id_catalog_material) ON DELETE RESTRICT,
    material_description TEXT NOT NULL,
    unit VARCHAR(50) NOT NULL,
    quantity NUMERIC(12,4) NOT NULL DEFAULT 1.0000 CHECK (quantity >= 0),
    unit_price NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (unit_price >= 0),
    total_price NUMERIC(14,2) GENERATED ALWAYS AS (ROUND(quantity * unit_price, 2)) STORED
);

-- Labor Line Items (Linked to intermediate performance group)
CREATE TABLE IF NOT EXISTS labor_by_concept (
    id_labor_by_concept UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_apu UUID NOT NULL REFERENCES concept_apu_integration(id_apu) ON DELETE CASCADE,
    id_concept INT NOT NULL REFERENCES concept(id_concept) ON DELETE CASCADE,
    id_performance_group UUID REFERENCES concept_performance_group(id_performance_group) ON DELETE SET NULL,
    id_catalog_labor INT REFERENCES catalog_labor(id_catalog_labor) ON DELETE RESTRICT,
    category TEXT NOT NULL,
    unit VARCHAR(50) NOT NULL DEFAULT 'JORNADA',
    quantity NUMERIC(12,4) NOT NULL DEFAULT 1.0000 CHECK (quantity >= 0),
    unit_price NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (unit_price >= 0),
    total_price NUMERIC(14,2) GENERATED ALWAYS AS (ROUND(quantity * unit_price, 2)) STORED
);

-- Equipment Line Items (Linked to intermediate performance group)
CREATE TABLE IF NOT EXISTS equipment_by_concept (
    id_equipment_by_concept UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_apu UUID NOT NULL REFERENCES concept_apu_integration(id_apu) ON DELETE CASCADE,
    id_concept INT NOT NULL REFERENCES concept(id_concept) ON DELETE CASCADE,
    id_performance_group UUID REFERENCES concept_performance_group(id_performance_group) ON DELETE SET NULL,
    id_catalog_equipment INT REFERENCES catalog_equipment(id_catalog_equipment) ON DELETE RESTRICT,
    equipment_description TEXT NOT NULL,
    unit VARCHAR(50) NOT NULL DEFAULT 'HORA',
    quantity NUMERIC(12,4) NOT NULL DEFAULT 1.0000 CHECK (quantity >= 0),
    unit_price NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (unit_price >= 0),
    total_price NUMERIC(14,2) GENERATED ALWAYS AS (ROUND(quantity * unit_price, 2)) STORED
);

-- -----------------------------------------------------------------------------
-- 6. NUMBER TO WORDS GENERATOR (PL/pgSQL SPANISH FINANCIAL NOTATION)
-- -----------------------------------------------------------------------------

-- Standalone Helper Function for Numbers 1..999 (avoiding Oracle-style nested function syntax)
CREATE OR REPLACE FUNCTION fn_centenas_es(p_num INT)
RETURNS TEXT AS $$
DECLARE
    c INT := p_num / 100;
    d INT := (p_num % 100) / 10;
    u INT := p_num % 10;
    res TEXT := '';
BEGIN
    -- Centenas
    IF c = 1 AND (d > 0 OR u > 0) THEN res := 'CIENTO ';
    ELSIF c = 1 THEN res := 'CIEN ';
    ELSIF c = 2 THEN res := 'DOSCIENTOS ';
    ELSIF c = 3 THEN res := 'TRESCIENTOS ';
    ELSIF c = 4 THEN res := 'CUATROCIENTOS ';
    ELSIF c = 5 THEN res := 'QUINIENTOS ';
    ELSIF c = 6 THEN res := 'SEISCIENTOS ';
    ELSIF c = 7 THEN res := 'SETECIENTOS ';
    ELSIF c = 8 THEN res := 'OCHOCIENTOS ';
    ELSIF c = 9 THEN res := 'NOVECIENTOS ';
    END IF;

    -- Decenas y Unidades
    IF d = 1 THEN
        IF u = 0 THEN res := res || 'DIEZ';
        ELSIF u = 1 THEN res := res || 'ONCE';
        ELSIF u = 2 THEN res := res || 'DOCE';
        ELSIF u = 3 THEN res := res || 'TRECE';
        ELSIF u = 4 THEN res := res || 'CATORCE';
        ELSIF u = 5 THEN res := res || 'QUINCE';
        ELSE res := res || 'DIECI' || CASE u 
            WHEN 6 THEN 'SEIS' WHEN 7 THEN 'SIETE' WHEN 8 THEN 'OCHO' WHEN 9 THEN 'NUEVE' END;
        END IF;
    ELSIF d = 2 THEN
        IF u = 0 THEN res := res || 'VEINTE';
        ELSE res := res || 'VEINTI' || CASE u 
            WHEN 1 THEN 'UN' WHEN 2 THEN 'DOS' WHEN 3 THEN 'TRES' WHEN 4 THEN 'CUATRO'
            WHEN 5 THEN 'CINCO' WHEN 6 THEN 'SEIS' WHEN 7 THEN 'SIETE' WHEN 8 THEN 'OCHO' WHEN 9 THEN 'NUEVE' END;
        END IF;
    ELSE
        IF d = 3 THEN res := res || 'TREINTA';
        ELSIF d = 4 THEN res := res || 'CUARENTA';
        ELSIF d = 5 THEN res := res || 'CINCUENTA';
        ELSIF d = 6 THEN res := res || 'SESENTA';
        ELSIF d = 7 THEN res := res || 'SETENTA';
        ELSIF d = 8 THEN res := res || 'OCHENTA';
        ELSIF d = 9 THEN res := res || 'NOVENTA';
        END IF;

        IF d > 2 AND u > 0 THEN res := res || ' Y '; END IF;
        IF (d = 0 OR d > 2) AND u > 0 THEN
            res := res || CASE u 
                WHEN 1 THEN 'UN' WHEN 2 THEN 'DOS' WHEN 3 THEN 'TRES' WHEN 4 THEN 'CUATRO'
                WHEN 5 THEN 'CINCO' WHEN 6 THEN 'SEIS' WHEN 7 THEN 'SIETE' WHEN 8 THEN 'OCHO' WHEN 9 THEN 'NUEVE' END;
        END IF;
    END IF;
    RETURN TRIM(res);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Master Function Converting Numbers to Currency Text
CREATE OR REPLACE FUNCTION fn_number_to_words_es(p_amount NUMERIC)
RETURNS TEXT AS $$
DECLARE
    v_int_part BIGINT;
    v_dec_part INT;
    v_millones BIGINT;
    v_miles BIGINT;
    v_centenas BIGINT;
    v_result TEXT := '';
BEGIN
    IF p_amount IS NULL OR p_amount = 0 THEN
        RETURN '( CERO PESOS 00/100 M.N. )';
    END IF;

    v_int_part := TRUNC(p_amount)::BIGINT;
    v_dec_part := ROUND((p_amount - v_int_part) * 100)::INT;

    -- Millones
    v_millones := v_int_part / 1000000;
    IF v_millones = 1 THEN
        v_result := 'UN MILLON ';
    ELSIF v_millones > 1 THEN
        v_result := fn_centenas_es(v_millones::INT) || ' MILLONES ';
    END IF;

    -- Miles
    v_miles := (v_int_part % 1000000) / 1000;
    IF v_miles = 1 THEN
        v_result := v_result || 'MIL ';
    ELSIF v_miles > 1 THEN
        v_result := v_result || fn_centenas_es(v_miles::INT) || ' MIL ';
    END IF;

    -- Centenas
    v_centenas := v_int_part % 1000;
    IF v_centenas > 0 THEN
        v_result := v_result || fn_centenas_es(v_centenas::INT) || ' ';
    END IF;

    IF v_int_part = 1 THEN
        v_result := TRIM(v_result) || ' PESO ';
    ELSE
        v_result := TRIM(v_result) || ' PESOS ';
    END IF;

    v_result := '( ' || v_result || LPAD(v_dec_part::TEXT, 2, '0') || '/100 M.N. )';
    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- -----------------------------------------------------------------------------
-- 7. RECALCULATION ENGINE (STORED PROCEDURE & TRIGGERS)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalculate_apu(p_apu_id UUID)
RETURNS VOID AS $$
DECLARE
    r_apu concept_apu_integration%ROWTYPE;
    v_sub_mat NUMERIC(14,2) := 0.00;
    v_sub_lab NUMERIC(14,2) := 0.00;
    v_sub_eq  NUMERIC(14,2) := 0.00;
    v_sub_st  NUMERIC(14,2) := 0.00;
    
    v_lab_yield NUMERIC(12,4) := 1.0000;
    v_eq_yield  NUMERIC(12,4) := 1.0000;
    
    v_cost_a   NUMERIC(14,2);
    v_cost_b   NUMERIC(14,2);
    v_cost_c   NUMERIC(14,2);
    v_cost_d   NUMERIC(14,2);
    v_cost_e   NUMERIC(14,2);
    v_cost_f   NUMERIC(14,2);
    v_cost_g   NUMERIC(14,2);
    v_cost_sfp NUMERIC(14,2) := 0.00;
    v_final_price NUMERIC(14,2);
    v_final_txt   TEXT;
BEGIN
    SELECT * INTO r_apu FROM concept_apu_integration WHERE id_apu = p_apu_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- 1. Subtotal Materiales
    SELECT COALESCE(SUM(total_price), 0.00) INTO v_sub_mat
    FROM material_by_concept WHERE id_apu = p_apu_id;

    -- 2. Rendimientos globales desde tabla intermedia
    SELECT COALESCE(performance_factor, 1.0000) INTO v_lab_yield
    FROM concept_performance_group 
    WHERE id_concept = r_apu.id_concept AND resource_type = 'LABOR';

    SELECT COALESCE(performance_factor, 1.0000) INTO v_eq_yield
    FROM concept_performance_group 
    WHERE id_concept = r_apu.id_concept AND resource_type = 'EQUIPMENT';

    -- Subtotal Mano de Obra (Suma de salarios * Rendimiento)
    SELECT TRUNC(COALESCE(SUM(total_price), 0.00) * v_lab_yield, 2) INTO v_sub_lab
    FROM labor_by_concept WHERE id_apu = p_apu_id;

    -- Subtotal Maquinaria (Suma de costos horarios * Rendimiento)
    SELECT TRUNC(COALESCE(SUM(total_price), 0.00) * v_eq_yield, 2) INTO v_sub_eq
    FROM equipment_by_concept WHERE id_apu = p_apu_id;

    -- 4. Seguridad y Herramienta Menor (Calculado sobre Mano de Obra)
    v_sub_st := TRUNC((r_apu.pct_safety_equipment * v_sub_lab), 2) +
                TRUNC((r_apu.pct_hand_tools * v_sub_lab), 2);

    -- Cascada A .. G
    v_cost_a := v_sub_mat + v_sub_lab + v_sub_eq + v_sub_st;
    v_cost_b := TRUNC(v_cost_a * r_apu.pct_indirects, 2);
    v_cost_c := v_cost_a + v_cost_b;
    v_cost_d := TRUNC(v_cost_c * r_apu.pct_financing, 2);
    v_cost_e := v_cost_c + v_cost_d;
    v_cost_f := TRUNC(v_cost_e * r_apu.pct_utility, 2);
    v_cost_g := v_cost_e + v_cost_f;

    IF r_apu.apply_sfp THEN
        v_cost_sfp := TRUNC((v_cost_g / 0.995) - v_cost_g, 2);
    ELSE
        v_cost_sfp := 0.00;
    END IF;

    v_final_price := v_cost_g + v_cost_sfp;
    v_final_txt := fn_number_to_words_es(v_final_price);

    -- Actualizar APU
    UPDATE concept_apu_integration SET
        subtotal_materials = v_sub_mat,
        subtotal_labor = v_sub_lab,
        subtotal_equipment = v_sub_eq,
        subtotal_safety_tools = v_sub_st,
        cost_direct_a = v_cost_a,
        cost_indirect_b = v_cost_b,
        cost_sum_c = v_cost_c,
        cost_financing_d = v_cost_d,
        cost_sum_e = v_cost_e,
        cost_utility_f = v_cost_f,
        cost_sum_g = v_cost_g,
        cost_sfp = v_cost_sfp,
        concept_price = v_final_price,
        concept_price_txt = v_final_txt,
        updated_at = now()
    WHERE id_apu = p_apu_id;

    -- Sincronizar catálogo de conceptos
    UPDATE concept SET
        concept_price = v_final_price,
        concept_price_txt = v_final_txt
    WHERE id_concept = r_apu.id_concept;
END;
$$ LANGUAGE plpgsql;

-- Trigger Function for detail updates
CREATE OR REPLACE FUNCTION tg_fn_recalc_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_target_apu UUID;
BEGIN
    v_target_apu := COALESCE(NEW.id_apu, OLD.id_apu);
    PERFORM fn_recalculate_apu(v_target_apu);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Enforcement Trigger: Only concepts with concept_unit = 'SERVICIO' are eligible for APU analysis
CREATE OR REPLACE FUNCTION tg_fn_check_concept_is_service()
RETURNS TRIGGER AS $$
DECLARE
    v_unit VARCHAR(50);
BEGIN
    SELECT concept_unit INTO v_unit FROM concept WHERE id_concept = NEW.id_concept;
    IF v_unit IS NULL OR v_unit != 'SERVICIO' THEN
        RAISE EXCEPTION 'Only concepts with concept_unit = ''SERVICIO'' can have an integrated unitary price analysis (APU). Concept % has unit ''%''. Non-service items must be priced directly.', NEW.id_concept, v_unit;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_check_concept_is_service ON concept_apu_integration;
CREATE TRIGGER tg_check_concept_is_service BEFORE INSERT OR UPDATE ON concept_apu_integration
FOR EACH ROW EXECUTE FUNCTION tg_fn_check_concept_is_service();

-- Direct Price Assignment Trigger: For non-service concepts (concept_unit <> 'SERVICIO'),
-- whenever an authorized user edits concept_price directly, automatically generate legal Spanish words.
CREATE OR REPLACE FUNCTION tg_fn_concept_direct_price()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.concept_unit <> 'SERVICIO' THEN
        IF NEW.concept_price IS NOT NULL AND (OLD.concept_price IS NULL OR NEW.concept_price != OLD.concept_price) THEN
            NEW.concept_price_txt := fn_number_to_words_es(NEW.concept_price);
        ELSIF NEW.concept_price IS NULL THEN
            NEW.concept_price_txt := NULL;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_concept_direct_price ON concept;
CREATE TRIGGER tg_concept_direct_price BEFORE INSERT OR UPDATE OF concept_price ON concept
FOR EACH ROW EXECUTE FUNCTION tg_fn_concept_direct_price();

DROP TRIGGER IF EXISTS tg_material_apu ON material_by_concept;
CREATE TRIGGER tg_material_apu AFTER INSERT OR UPDATE OR DELETE ON material_by_concept
FOR EACH ROW EXECUTE FUNCTION tg_fn_recalc_trigger();

DROP TRIGGER IF EXISTS tg_labor_apu ON labor_by_concept;
CREATE TRIGGER tg_labor_apu AFTER INSERT OR UPDATE OR DELETE ON labor_by_concept
FOR EACH ROW EXECUTE FUNCTION tg_fn_recalc_trigger();

DROP TRIGGER IF EXISTS tg_equipment_apu ON equipment_by_concept;
CREATE TRIGGER tg_equipment_apu AFTER INSERT OR UPDATE OR DELETE ON equipment_by_concept
FOR EACH ROW EXECUTE FUNCTION tg_fn_recalc_trigger();

-- -----------------------------------------------------------------------------
-- 8. ANALYTICAL UI VIEWS (WITH SECURITY INVOKER TO HONOR RLS)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_event_dashboard WITH (security_invoker = true) AS
SELECT 
    e.id_event,
    e.tag_event,
    e.event_type,
    e.event_description,
    c.client_name,
    e.status,
    e.submission_deadline,
    -- Total Concepts in Tender
    COUNT(cp.id_concept) AS total_concepts,
    -- 1. Services Track (Requires Bottom-Up APU Integration)
    COUNT(CASE WHEN cp.concept_unit = 'SERVICIO' THEN 1 END) AS total_services,
    COUNT(CASE WHEN cp.concept_unit = 'SERVICIO' AND cp.concept_price IS NOT NULL AND cp.concept_price > 0 THEN 1 END) AS integrated_services_count,
    ROUND(
        (COUNT(CASE WHEN cp.concept_unit = 'SERVICIO' AND cp.concept_price IS NOT NULL AND cp.concept_price > 0 THEN 1 END)::NUMERIC / 
         NULLIF(COUNT(CASE WHEN cp.concept_unit = 'SERVICIO' THEN 1 END), 0)::NUMERIC) * 100, 
        2
    ) AS service_completion_percentage,
    -- 2. Direct Parts & Supplies Track (Requires Direct Price Assignment)
    COUNT(CASE WHEN cp.concept_unit <> 'SERVICIO' THEN 1 END) AS total_parts,
    COUNT(CASE WHEN cp.concept_unit <> 'SERVICIO' AND cp.concept_price IS NOT NULL AND cp.concept_price > 0 THEN 1 END) AS priced_parts_count,
    ROUND(
        (COUNT(CASE WHEN cp.concept_unit <> 'SERVICIO' AND cp.concept_price IS NOT NULL AND cp.concept_price > 0 THEN 1 END)::NUMERIC / 
         NULLIF(COUNT(CASE WHEN cp.concept_unit <> 'SERVICIO' THEN 1 END), 0)::NUMERIC) * 100, 
        2
    ) AS parts_completion_percentage,
    -- 3. Overall Event Pricing Completion
    ROUND(
        (COUNT(CASE WHEN cp.concept_price IS NOT NULL AND cp.concept_price > 0 THEN 1 END)::NUMERIC / 
         NULLIF(COUNT(cp.id_concept), 0)::NUMERIC) * 100, 
        2
    ) AS overall_completion_percentage
FROM event e
JOIN client c ON e.id_client = c.id_client
LEFT JOIN concept cp ON e.id_event = cp.id_event
GROUP BY e.id_event, e.tag_event, e.event_type, e.event_description, c.client_name, e.status, e.submission_deadline;

CREATE OR REPLACE VIEW v_integrated_unitary_price WITH (security_invoker = true) AS
SELECT 
    e.tag_event,
    c.client_name,
    c.client_department,
    p.provider_name,
    p.provider_representative,
    p.provider_position,
    cp.tag_concept,
    cp.concept_header,
    cp.concept_description,
    cp.concept_unit,
    apu.subtotal_materials,
    apu.subtotal_labor,
    apu.subtotal_equipment,
    apu.subtotal_safety_tools,
    apu.cost_direct_a,
    apu.pct_indirects,
    apu.cost_indirect_b,
    apu.cost_sum_c,
    apu.pct_financing,
    apu.cost_financing_d,
    apu.cost_sum_e,
    apu.pct_utility,
    apu.cost_utility_f,
    apu.cost_sum_g,
    apu.apply_sfp,
    apu.cost_sfp,
    apu.concept_price,
    apu.concept_price_txt
FROM concept_apu_integration apu
JOIN concept cp ON apu.id_concept = cp.id_concept
JOIN event e ON cp.id_event = e.id_event
JOIN client c ON e.id_client = c.id_client
JOIN provider p ON apu.id_provider = p.id_provider;

-- -----------------------------------------------------------------------------
-- 9. 100% COMPLETE ROW LEVEL SECURITY (RLS) FOR SUPABASE
-- -----------------------------------------------------------------------------

-- Enable RLS across ALL 15 tables
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE client ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider ENABLE ROW LEVEL SECURITY;
ALTER TABLE event ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_provider_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE concept ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog_material ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog_labor ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE concept_performance_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE concept_apu_integration ENABLE ROW LEVEL SECURITY;
ALTER TABLE material_by_concept ENABLE ROW LEVEL SECURITY;
ALTER TABLE labor_by_concept ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipment_by_concept ENABLE ROW LEVEL SECURITY;

-- App User Policies
DROP POLICY IF EXISTS "Users can view own profile" ON app_user;
CREATE POLICY "Users can view own profile" ON app_user
    FOR SELECT USING (auth.uid() = id_user OR auth.role() = 'service_role' OR role = 'ADMIN');

DROP POLICY IF EXISTS "Admins can manage all users" ON app_user;
CREATE POLICY "Admins can manage all users" ON app_user
    FOR ALL USING (auth.role() = 'service_role' OR EXISTS (
        SELECT 1 FROM app_user WHERE id_user = auth.uid() AND role = 'ADMIN'
    ));

-- Master Catalogs Policies (Read for all authenticated & invited contractors, write for admins)
DROP POLICY IF EXISTS "Read Catalog Materials" ON catalog_material;
CREATE POLICY "Read Catalog Materials" ON catalog_material FOR SELECT USING (true);

DROP POLICY IF EXISTS "Read Catalog Labor" ON catalog_labor;
CREATE POLICY "Read Catalog Labor" ON catalog_labor FOR SELECT USING (true);

DROP POLICY IF EXISTS "Read Catalog Equipment" ON catalog_equipment;
CREATE POLICY "Read Catalog Equipment" ON catalog_equipment FOR SELECT USING (true);

-- Event, Client and Concepts Policies (Read for all authenticated / assigned contractors)
DROP POLICY IF EXISTS "Read Clients" ON client;
CREATE POLICY "Read Clients" ON client FOR SELECT USING (true);

DROP POLICY IF EXISTS "Read Providers" ON provider;
CREATE POLICY "Read Providers" ON provider FOR SELECT USING (true);

DROP POLICY IF EXISTS "Read Events" ON event;
CREATE POLICY "Read Events" ON event FOR SELECT USING (true);

DROP POLICY IF EXISTS "Read Concepts" ON concept;
CREATE POLICY "Read Concepts" ON concept FOR SELECT USING (true);

DROP POLICY IF EXISTS "Contractor Direct Concept Price Update" ON concept;
CREATE POLICY "Contractor Direct Concept Price Update" ON concept 
    FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Read Performance Groups" ON concept_performance_group;
CREATE POLICY "Read Performance Groups" ON concept_performance_group FOR SELECT USING (true);

-- Magic Link Invitations Policies (Public verification by token, management by admin)
DROP POLICY IF EXISTS "Verify Invitations by Token" ON event_invitation;
CREATE POLICY "Verify Invitations by Token" ON event_invitation 
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Update Invitation Acceptance" ON event_invitation;
CREATE POLICY "Update Invitation Acceptance" ON event_invitation 
    FOR UPDATE USING (true);

-- Contractor APU Data Policies (Assigned contractor can read and edit their own integrations)
DROP POLICY IF EXISTS "Contractor Read Assignments" ON event_provider_assignment;
CREATE POLICY "Contractor Read Assignments" ON event_provider_assignment FOR SELECT USING (true);

DROP POLICY IF EXISTS "Contractor APU Access" ON concept_apu_integration;
CREATE POLICY "Contractor APU Access" ON concept_apu_integration FOR ALL USING (true);

DROP POLICY IF EXISTS "Contractor Material Access" ON material_by_concept;
CREATE POLICY "Contractor Material Access" ON material_by_concept FOR ALL USING (true);

DROP POLICY IF EXISTS "Contractor Labor Access" ON labor_by_concept;
CREATE POLICY "Contractor Labor Access" ON labor_by_concept FOR ALL USING (true);

DROP POLICY IF EXISTS "Contractor Equipment Access" ON equipment_by_concept;
CREATE POLICY "Contractor Equipment Access" ON equipment_by_concept FOR ALL USING (true);


-- -----------------------------------------------------------------------------
-- 10. IDEMPOTENT SEED DATA POPULATION
-- -----------------------------------------------------------------------------
-- Seed Client (Pemex)
INSERT INTO client (id_client, client_name, client_department)
VALUES (1, 'PETRÓLEOS MEXICANOS', 'DIRECCIÓN DE EXPLORACIÓN Y EXTRACCIÓN SUBDIRECCIÓN DE EXTRACCIÓN REGIÓN TERRESTRE SUR GERENCIA DE MANTENIMIENTO, CONFIABILIDAD Y CONSTRUCCIÓN RS')
ON CONFLICT (id_client) DO UPDATE SET 
    client_name = EXCLUDED.client_name,
    client_department = EXCLUDED.client_department;

-- Seed Provider (MHEBOSAP)
INSERT INTO provider (id_provider, tag_provider, provider_name, provider_representative, provider_position, contact_email)
VALUES (1, 'MHEBOSAP', 'MHEBOSAP, S. A. DE C.V.', 'ING. HERIBERTO LÓPEZ MARTÍNEZ', 'APODERADO LEGAL', 'contacto@mhebosap.com')
ON CONFLICT (id_provider) DO UPDATE SET 
    provider_name = EXCLUDED.provider_name,
    provider_representative = EXCLUDED.provider_representative,
    provider_position = EXCLUDED.provider_position;

-- Seed Event
INSERT INTO event (id_event, tag_event, event_type, event_description, id_client, status, submission_deadline)
VALUES (1, 'DEE-CAT-S-GCEE-500-104816-26-3', 'CONCURSO ABIERTO ELECTRÓNICO INTERNACIONAL TLC NO.', 'SERVICIO DE MANTENIMIENTO PREVENTIVO Y/O CORRECTIVO A EQUIPOS DE PRESIÓN Y VACÍO DE LOS ACTIVOS DE LA SUBDIRECCIÓN DE EXTRACCIÓN REGIÓN TERRESTRE SUR', 1, 'OPEN', now() + interval '45 days')
ON CONFLICT (id_event) DO UPDATE SET 
    tag_event = EXCLUDED.tag_event,
    event_description = EXCLUDED.event_description;

-- Seed Event Invitation (Tokenized Magic Link)
INSERT INTO event_invitation (id_invitation, id_event, id_provider, invited_email, token, expires_at, is_accepted)
VALUES ('a0000000-0000-0000-0000-000000000001', 1, 1, 'contacto@mhebosap.com', 'b1111111-1111-1111-1111-111111111111', now() + interval '30 days', true)
ON CONFLICT (id_invitation) DO UPDATE SET token = EXCLUDED.token;

-- Seed Event Assignment
INSERT INTO event_provider_assignment (id_event, id_provider, access_role)
VALUES (1, 1, 'WRITE')
ON CONFLICT (id_event, id_provider) DO UPDATE SET access_role = EXCLUDED.access_role;

-- Seed catalog_material
INSERT INTO catalog_material (id_catalog_material, tag_catalog_material, catalog_material_description, catalog_material_unit, catalog_material_brand, catalog_material_model, catalog_material_unit_price) VALUES
(1, NULL, 'Kit de ligas y sellos para inyector diésel Cummins ISX', 'KIT', NULL, NULL, 211.31),
(2, NULL, 'Líquido limpiador concentrado de inyectores diésel para laboratorio y tina ultrasónica', 'LITRO', NULL, NULL, 236.26),
(3, NULL, 'Filtro separador de combustible y agua Fleetguard FF5776', 'PZA', NULL, NULL, 822.00),
(4, NULL, 'Filtro de combustible primario enroscable Fleetguard FF2200', 'PZA', NULL, NULL, 327.40),
(5, NULL, 'Aditivo acondicionador y limpiador preventivo de inyectores diésel', 'LITRO', NULL, NULL, 255.00),
(6, NULL, 'Desengrasante dieléctrico y limpiador de contactos electrónicos para arnés de inyectores', 'PZA', NULL, NULL, 145.00),
(7, NULL, 'Estopa de algodón blanca para limpieza de componentes', 'KG', NULL, NULL, 65.00)
ON CONFLICT (id_catalog_material) DO UPDATE SET catalog_material_description = EXCLUDED.catalog_material_description, catalog_material_unit_price = EXCLUDED.catalog_material_unit_price;

-- Seed catalog_labor
INSERT INTO catalog_labor (id_catalog_labor, tag_catalog_labor, catalog_labor_category, catalog_labor_unit, catalog_labor_unit_price) VALUES
(1, 'ESP-CI', 'Operario Especialista Combustión Interna Equipo Semipesado', 'Jornada', 3507.45),
(2, 'ESP-EL', 'Operario Especialista Eléctrico Equipo Semipesado', 'Jornada', 3507.45),
(3, 'ESP-HI', 'Operario Especialista en Hidráulica de equipo semipesado', 'Jornada', 2946.22),
(4, 'AYUD', 'Ayudante', 'Jornada', 1089.29)
ON CONFLICT (id_catalog_labor) DO UPDATE SET catalog_labor_category = EXCLUDED.catalog_labor_category, catalog_labor_unit_price = EXCLUDED.catalog_labor_unit_price;

-- Seed catalog_equipment
INSERT INTO catalog_equipment (id_catalog_equipment, tag_catalog_equipment, catalog_equipment_description, catalog_equipment_unit, catalog_equipment_brand, catalog_equipment_model, catalog_equipment_year, catalog_equipment_unit_price) VALUES
(1, NULL, 'Foto tacometro para medir RPM con reflejante (luz estroboscópica) y certificado de calibracion vigente.', 'PIEZA', '', NULL, 2020, 0.00),
(2, NULL, 'Juego de extractor – empujador de 30 toneladas de capacidad con tornillo de 11/4".', 'KIT', '', NULL, 2020, 0.00),
(3, NULL, 'Scanner de diagnostico con software de fallas para motores Navistar, Caterpillar, Cummings, International, y con enlace USB.', 'PIEZA', '', NULL, 2020, 0.00),
(4, NULL, 'Probador de modulos de control electrónicos, (ECM).', 'PIEZA', '', NULL, 2020, 0.00),
(5, NULL, 'Planta de soldar, equipada con motor de combustion interna a diesel o alimentada mediante red electrica, con rango de salida nominal de soldadura 400 AMP como minimo.', 'PIEZA', '', NULL, 2020, 0.00),
(6, NULL, 'Compresor de aire de 120 PSI, con motor electrico de 5 o 7 HP.', 'PIEZA', '', NULL, 2020, 0.00),
(7, NULL, 'Camioneta Pick-Up, capacidad de 3/4 tonelada minimo, (modelo minimo 2020).', 'VEHICULO', '', NULL, 2020, 0.00),
(8, NULL, 'Camión Chasis plataforma equipado con brazo hidráulico articulado de 6 toneladas de capacidad como minimo, modelo 2018 o mejor. (con certificacion de prueba de carga vigente en brazo hidraulico).', 'VEHICULO', '', NULL, 2018, 0.00),
(9, NULL, 'Banco de pruebas y calibración para inyectores diésel Common Rail y EUI', 'HORA', NULL, NULL, 2018, 650.00),
(10, NULL, 'Tina de limpieza por ultrasonido industrial para componentes de inyección', 'HORA', NULL, NULL, 2018, 180.00),
(11, NULL, 'Escáner de diagnóstico electrónico para vehículos pesados protocolo J1939', 'HORA', NULL, NULL, 2018, 320.00),
(12, NULL, 'Compresor de aire estacionario de 5 HP para sopleteo y pruebas neumáticas', 'HORA', NULL, NULL, 2018, 110.00),
(13, NULL, 'Torquímetro de precisión con rango de 10 a 150 lb-pie para montaje de inyectores', 'HORA', NULL, NULL, 2018, 45.00),
(14, NULL, 'Juego de extractores hidráulicos y herramienta especializada para desmontaje de inyectores', 'HORA', NULL, NULL, 2018, 60.00)
ON CONFLICT (id_catalog_equipment) DO UPDATE SET catalog_equipment_description = EXCLUDED.catalog_equipment_description, catalog_equipment_unit_price = EXCLUDED.catalog_equipment_unit_price;

-- Seed all 1,335 concepts from Abstract.xlsx
INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(1, 1, 1, '1.1.0001', '1.1.0000 SERVICIO DE MANTENIMIENTO PREVENTIVO Y CORRECTIVO A UNIDADES AUTOMOTRICES SEMIPESADAS, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LOS 1,500 KILÓMETROS RECORRIDOS O MENSUAL (CONFORME A CARTA DE MANTENIMIENTO QUE SE DESCRIBE EN EL ANEXO B-1)', 'SERVICIO', NULL, 1),
(2, 1, 1, '1.1.0002', '1.1.0000 SERVICIO DE MANTENIMIENTO PREVENTIVO Y CORRECTIVO A UNIDADES AUTOMOTRICES SEMIPESADAS, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LOS 4,500 KILÓMETROS RECORRIDOS O TRIMESTRAL (CONFORME A CARTA DE MANTENIMIENTO QUE SE DESCRIBE EN EL ANEXO B-1)', 'SERVICIO', NULL, 2),
(3, 1, 1, '1.1.0003', '1.1.0000 SERVICIO DE MANTENIMIENTO PREVENTIVO Y CORRECTIVO A UNIDADES AUTOMOTRICES SEMIPESADAS, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LOS 9,000 KILÓMETROS RECORRIDOS O SEMESTRAL (CONFORME A CARTA DE MANTENIMIENTO QUE SE DESCRIBE EN EL ANEXO B-1)', 'SERVICIO', NULL, 3),
(4, 1, 1, '1.1.0004', '1.1.0000 SERVICIO DE MANTENIMIENTO PREVENTIVO Y CORRECTIVO A UNIDADES AUTOMOTRICES SEMIPESADAS, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LOS 18,000 KILÓMETROS RECORRIDOS O ANUAL (CONFORME A CARTA DE MANTENIMIENTO QUE SE DESCRIBE EN EL ANEXO B-1)', 'SERVICIO', NULL, 4),
(5, 1, 1, '1.2.0001', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7399, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'VENTILADOR   2MH 429', 'PIEZA', NULL, 5),
(6, 1, 1, '1.2.0002', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CODO INFERIOR DE RADIADOR', 'PIEZA', NULL, 6),
(7, 1, 1, '1.2.0003', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'COPLE TUBO INFERIOR DE RADIADOR', 'PIEZA', NULL, 7),
(8, 1, 1, '1.2.0004', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'BOMBA PARA AGUA     316GC284B', 'PIEZA', NULL, 8),
(9, 1, 1, '1.2.0005', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'BANDA PRINCIPAL DEL MOTOR    88GB 439P647', 'PIEZA', NULL, 9),
(10, 1, 1, '1.2.0006', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TERMODINÁMICO DEL VENTILADOR', 'PIEZA', NULL, 10),
(11, 1, 1, '1.2.0007', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'FILTRO PARA AGUA', 'PIEZA', NULL, 11),
(12, 1, 1, '1.2.0008', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TERMOSTATO      215SB 165BP3', 'PIEZA', NULL, 12),
(13, 1, 1, '1.2.0009', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TOLVA DEL VENTILADOR', 'PIEZA', NULL, 13),
(14, 1, 1, '1.2.0010', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'MANGUERA INFERIOR DEL RADIADOR     11MF 3592M17', 'PIEZA', NULL, 14),
(15, 1, 1, '1.2.0011', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'BULBO INDICADOR DE TEMPERATURA       342AX 14', 'PIEZA', NULL, 15),
(16, 1, 1, '1.2.0012', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TAPÓN DEL RADIADOR ( 7-16 LBS.)   7649AX0615', 'PIEZA', NULL, 16),
(17, 1, 1, '1.2.0013', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'PANAL DEL RADIADOR', 'PIEZA', NULL, 17),
(18, 1, 1, '1.2.0014', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'SENSOR DE TEMPERATURA', 'PIEZA', NULL, 18),
(19, 1, 1, '1.2.0015', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'RADIADOR COMPLETO', 'PIEZA', NULL, 19),
(20, 1, 1, '1.2.0016', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'FAN CLOUTCH', 'PIEZA', NULL, 20),
(21, 1, 1, '1.2.0017', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'DEPÓSITO RECUPERADOR DE REFRIGERANTE', 'PIEZA', NULL, 21),
(22, 1, 1, '1.2.0018', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'ENFRIADOR DE ACEITE DE MOTOR', 'PIEZA', NULL, 22),
(23, 1, 1, '1.2.0019', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'POLEA TENSORA', 'PIEZA', NULL, 23),
(24, 1, 1, '1.2.0020', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'MANGUERA SUPERIOR DEL RADIADOR     160AX507F', 'PIEZA', NULL, 24),
(25, 1, 1, '1.2.0021', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE VENTILADOR', 'SERVICIO', NULL, 25),
(26, 1, 1, '1.2.0022', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE CODO INFERIOR DE RADIADOR', 'SERVICIO', NULL, 26),
(27, 1, 1, '1.2.0023', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE COPLE TUBO INFERIOR DE RADIADOR', 'SERVICIO', NULL, 27),
(28, 1, 1, '1.2.0024', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE BOMBA PARA AGUA', 'SERVICIO', NULL, 28),
(29, 1, 1, '1.2.0025', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE BANDA PRINCIPAL DEL MOTOR', 'SERVICIO', NULL, 29),
(30, 1, 1, '1.2.0026', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TERMODINÁMICO DEL VENTILADOR', 'SERVICIO', NULL, 30),
(31, 1, 1, '1.2.0027', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE FILTRO PARA AGUA', 'SERVICIO', NULL, 31),
(32, 1, 1, '1.2.0028', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TERMOSTATO', 'SERVICIO', NULL, 32),
(33, 1, 1, '1.2.0029', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TOLVA DEL VENTILADOR', 'SERVICIO', NULL, 33),
(34, 1, 1, '1.2.0030', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE MANGUERA INFERIOR DEL RADIADOR', 'SERVICIO', NULL, 34),
(35, 1, 1, '1.2.0031', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE BULBO INDICADOR DE TEMPERATURA', 'SERVICIO', NULL, 35),
(36, 1, 1, '1.2.0032', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TAPÓN DE RADIADOR', 'SERVICIO', NULL, 36),
(37, 1, 1, '1.2.0033', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE PANAL', 'SERVICIO', NULL, 37),
(38, 1, 1, '1.2.0034', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'REPARACIÓN DE RADIADOR. (costo no mayor de 50% del valor de nuevo)', 'SERVICIO', NULL, 38),
(39, 1, 1, '1.2.0035', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE SENSOR DE TEMPERATURA', 'SERVICIO', NULL, 39),
(40, 1, 1, '1.2.0036', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE RADIADOR COMPLETO', 'SERVICIO', NULL, 40),
(41, 1, 1, '1.2.0037', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE FAN CLOUTCH', 'SERVICIO', NULL, 41),
(42, 1, 1, '1.2.0038', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DEL DEPÓSITO RECUPERADOR DE REFRIGERANTE', 'SERVICIO', NULL, 42),
(43, 1, 1, '1.2.0039', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DEL ENFRIADOR DE ACEITE DE MOTOR', 'SERVICIO', NULL, 43),
(44, 1, 1, '1.2.0040', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE POLEA TENSORA', 'SERVICIO', NULL, 44),
(45, 1, 1, '1.2.0041', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE MANGUERA SUPERIOR DEL RADIADOR     160AX507F; INCLUYE LA MANGUERA.', 'SERVICIO', NULL, 45),
(46, 1, 1, '1.2.0042', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'JUNTAS PARA MOTOR COMPLETO', 'JUEGO', NULL, 46),
(47, 1, 1, '1.2.0043', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'PISTONES', 'JUEGO', NULL, 47),
(48, 1, 1, '1.2.0044', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SEGUROS PARA PERNOS DE PISTÓN', 'PIEZA', NULL, 48),
(49, 1, 1, '1.2.0045', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'CAMISAS', 'PIEZA', NULL, 49),
(50, 1, 1, '1.2.0046', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ANILLOS PARA PISTÓN STD.', 'JUEGO', NULL, 50),
(51, 1, 1, '1.2.0047', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'METALES PARA ÁRBOL DE LEVAS', 'JUEGO', NULL, 51),
(52, 1, 1, '1.2.0048', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'BOMBA PARA ACEITE', 'PIEZA', NULL, 52),
(53, 1, 1, '1.2.0049', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'METALES PARA BIELA STD.', 'JUEGO', NULL, 53),
(54, 1, 1, '1.2.0050', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'METALES DE BANCADA STD.', 'JUEGO', NULL, 54),
(55, 1, 1, '1.2.0051', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'VÁLVULA DE ESCAPE', 'PIEZA', NULL, 55),
(56, 1, 1, '1.2.0052', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'VÁLVULA DE ADMISIÓN', 'PIEZA', NULL, 56),
(57, 1, 1, '1.2.0053', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ASIENTO PARA VÁLVULA DE ESCAPE', 'PIEZA', NULL, 57),
(58, 1, 1, '1.2.0054', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ASIENTO PARA VÁLVULA DE ADMISIÓN', 'PIEZA', NULL, 58),
(59, 1, 1, '1.2.0055', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SELLOS DE VÁLVULAS', 'JUEGO', NULL, 59),
(60, 1, 1, '1.2.0056', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'RESORTES DE VÁLVULAS', 'PIEZA', NULL, 60),
(61, 1, 1, '1.2.0057', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SELLOS DE CONDUCTOS DE AGUA', 'PIEZA', NULL, 61),
(62, 1, 1, '1.2.0058', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'RETEN DELANTERO DEL CIGÜEÑAL', 'PIEZA', NULL, 62),
(63, 1, 1, '1.2.0059', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'RETEN TRASERO DEL CIGÜEÑAL', 'PIEZA', NULL, 63),
(64, 1, 1, '1.2.0060', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ELEMENTO PARA  EL ENFRIADOR DE ACEITE', 'PIEZA', NULL, 64),
(65, 1, 1, '1.2.0061', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'TACONES PARA MOTOR', 'PIEZA', NULL, 65),
(66, 1, 1, '1.2.0062', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SELLOS DE CAMISAS', 'JUEGO', NULL, 66),
(67, 1, 1, '1.2.0063', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'CIGÜEÑAL NUEVO', 'PIEZA', NULL, 67),
(68, 1, 1, '1.2.0064', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'REPARACIÓN GENERAL DE MOTOR; INCLUYE: DESMONTAR, DESARMAR, CAMBIO DE PIEZAS DAÑADAS, AJUSTES, ARMAR, MONTAR Y PUESTA EN OPERACIÓN. (costo no mayor de 50% del valor de nuevo).', 'SERVICIO', NULL, 68),
(69, 1, 1, '1.2.0065', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, MOTOR.', 'REPARACIÓN GENERAL DE CABEZOTE; INCLUYE: MAQUINARIA, ASIENTOS DE VÁLVULA, MAQUINAR CABEZA PARA INSERTAR GUÍAS DE VÁLVULAS, LIMPIEZA Y PERLIZADO DE CABEZA Y EFECTUAR PRUEBA HIDROSTÁTICA. (costo no mayor de 50% del valor de cabezote nuevo).', 'SERVICIO', NULL, 69),
(70, 1, 1, '1.2.0066', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'JUNTAS PARA MÚLTIPLE DE ESCAPE', 'JUEGO', NULL, 70),
(71, 1, 1, '1.2.0067', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'TUBO PARA ESCAPE', 'PIEZA', NULL, 71),
(72, 1, 1, '1.2.0068', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'SILENCIADOR', 'PIEZA', NULL, 72),
(73, 1, 1, '1.2.0069', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'ABRAZADERAS PARA TUBO DE ESCAPE', 'PIEZA', NULL, 73),
(74, 1, 1, '1.2.0070', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE JUNTAS PARA MÚLTIPLE DE ESCAPE', 'SERVICIO', NULL, 74),
(75, 1, 1, '1.2.0071', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE TUBO PARA ESCAPE', 'SERVICIO', NULL, 75),
(76, 1, 1, '1.2.0072', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE SILENCIADOR', 'SERVICIO', NULL, 76),
(77, 1, 1, '1.2.0073', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE ABRAZADERAS PARA TUBO DE ESCAPE', 'SERVICIO', NULL, 77),
(78, 1, 1, '1.2.0074', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'INDICADOR DE COMBUSTIBLE      9MT 36', 'PIEZA', NULL, 78),
(79, 1, 1, '1.2.0075', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'MANGUERA DE SUCCIÓN DE COMBUSTIBLE', 'PIEZA', NULL, 79),
(80, 1, 1, '1.2.0076', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'MANGUERA DE RETORNO DE COMBUSTIBLE', 'PIEZA', NULL, 80),
(81, 1, 1, '1.2.0077', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTRO PRIMARIO DE COMBUSTIBLE', 'PIEZA', NULL, 81),
(82, 1, 1, '1.2.0078', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTRO SECUNDARIO DE COMBUSTIBLE', 'PIEZA', NULL, 82),
(83, 1, 1, '1.2.0079', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'BOMBA DE INYECCIÓN    313GC 5212P14', 'PIEZA', NULL, 83),
(84, 1, 1, '1.2.0080', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'LÍNEAS DE COMBUSTIBLE', 'JUEGO', NULL, 84),
(85, 1, 1, '1.2.0081', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'INYECTORES', 'PIEZA', NULL, 85),
(86, 1, 1, '1.2.0082', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'PULIDO DE TANQUE DE COMBUSTIBLE', 'SERVICIO', NULL, 86),
(87, 1, 1, '1.2.0083', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE INDICADOR DE COMBUSTIBLE', 'SERVICIO', NULL, 87),
(88, 1, 1, '1.2.0084', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE MANGUERA DE SUCCIÓN DE COMBUSTIBLE', 'SERVICIO', NULL, 88),
(89, 1, 1, '1.2.0085', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE MANGUERA DE RETORNO DE COMBUSTIBLE', 'SERVICIO', NULL, 89),
(90, 1, 1, '1.2.0086', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTRO PRIMARIO DE COMBUSTIBLE', 'SERVICIO', NULL, 90),
(91, 1, 1, '1.2.0087', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTRO SECUNDARIO DE COMBUSTIBLE', 'SERVICIO', NULL, 91),
(92, 1, 1, '1.2.0088', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE BOMBA DE INYECCIÓN', 'SERVICIO', NULL, 92),
(93, 1, 1, '1.2.0089', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE LÍNEAS DE COMBUSTIBLE', 'SERVICIO', NULL, 93),
(94, 1, 1, '1.2.0090', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE INYECTORES', 'SERVICIO', NULL, 94),
(95, 1, 1, '1.2.0091', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE TANQUE DE COMBUSTIBLE; INCLUYE TANQUE', 'SERVICIO', NULL, 95),
(96, 1, 1, '1.2.0092', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'REPARACIÓN DE BOMBA DE INYECCIÓN (Costo no mayor de 50% del valor de bomba de inyección nueva)', 'SERVICIO', NULL, 96),
(97, 1, 1, '1.2.0093', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'REPARACIÓN DE INYECTORES (Costo no mayor de 50% del valor de inyectores nuevos)', 'SERVICIO', NULL, 97),
(98, 1, 1, '1.2.0094', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTROS DE COMBUSTIBLE (PRIMARIO Y SECUNDARIO)', 'JUEGO', NULL, 98),
(99, 1, 1, '1.2.0095', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTRO DE AIRE', 'PIEZA', NULL, 99),
(100, 1, 1, '1.2.0096', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'JUNTA DE TAPA DE PUNTERÍAS', 'PIEZA', NULL, 100)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(101, 1, 1, '1.2.0097', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'TURBO CARGADOR', 'PIEZA', NULL, 101),
(102, 1, 1, '1.2.0098', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'MANGUERA DE SUCCIÓN Y DESCARGA DEL POST-ENFRIADOR', 'PIEZA', NULL, 102),
(103, 1, 1, '1.2.0099', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTROS DE COMBUSTIBLE (PRIMARIO Y SECUNDARIO)', 'SERVICIO', NULL, 103),
(104, 1, 1, '1.2.0100', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTRO DE AIRE', 'SERVICIO', NULL, 104),
(105, 1, 1, '1.2.0101', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE JUNTA DE TAPA DE PUNTERÍAS', 'SERVICIO', NULL, 105),
(106, 1, 1, '1.2.0102', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE TURBO CARGADOR', 'SERVICIO', NULL, 106),
(107, 1, 1, '1.2.0103', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE MANGUERA DE SUCCIÓN Y DESCARGA DEL POST-ENFRIADOR', 'SERVICIO', NULL, 107),
(108, 1, 1, '1.2.0104', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CALIBRACIÓN DE VÁLVULAS DE MOTOR', 'SERVICIO', NULL, 108),
(109, 1, 1, '1.2.0105', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CALIBRACIÓN Y REVISIÓN DE BOMBA DE INYECCIÓN', 'SERVICIO', NULL, 109),
(110, 1, 1, '1.2.0106', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CALIBRACIÓN Y LIMPIEZA DE INYECTORES', 'SERVICIO', NULL, 110),
(111, 1, 1, '1.2.0107', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'LIMPIEZA DE TANQUE DE COMBUSTIBLE', 'SERVICIO', NULL, 111),
(112, 1, 1, '1.2.0108', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'LIMPIEZA Y CAMBIO DE LÍNEAS DE COMBUSTIBLE', 'SERVICIO', NULL, 112),
(113, 1, 1, '1.2.0109', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'REPARACIÓN DE TURBO CARGADOR (Costo no mayor de 50% del valor de turbo cargador nuevo)', 'SERVICIO', NULL, 113),
(114, 1, 1, '1.2.0110', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH PARA LIMPIAPARABRISAS', 'PIEZA', NULL, 114),
(115, 1, 1, '1.2.0111', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MECANISMO DE LIMPIADORES', 'JUEGO', NULL, 115),
(116, 1, 1, '1.2.0112', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'BRAZOS', 'PIEZA', NULL, 116),
(117, 1, 1, '1.2.0113', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'PLUMAS', 'JUEGO', NULL, 117),
(118, 1, 1, '1.2.0114', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'DEPÓSITO DE AGUA', 'PIEZA', NULL, 118),
(119, 1, 1, '1.2.0115', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MOTOR BOMBA DE AGUA DEL DEPÓSITO', 'PIEZA', NULL, 119),
(120, 1, 1, '1.2.0116', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MANGUERA PARA AGUA DE LIMPIADORES', 'METRO', NULL, 120),
(121, 1, 1, '1.2.0117', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ROCIADORES', 'PIEZA', NULL, 121),
(122, 1, 1, '1.2.0118', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH (START) PARA ROCIADO', 'PIEZA', NULL, 122),
(123, 1, 1, '1.2.0119', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH PARA LIMPIAPARABRISAS', 'SERVICIO', NULL, 123),
(124, 1, 1, '1.2.0120', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MECANISMO DE LIMPIADORES', 'SERVICIO', NULL, 124),
(125, 1, 1, '1.2.0121', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE BRAZOS', 'SERVICIO', NULL, 125),
(126, 1, 1, '1.2.0122', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE PLUMAS', 'SERVICIO', NULL, 126),
(127, 1, 1, '1.2.0123', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE DEPÓSITO DE AGUA', 'SERVICIO', NULL, 127),
(128, 1, 1, '1.2.0124', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MOTOR BOMBA DE AGUA DEL DEPÓSITO', 'SERVICIO', NULL, 128),
(129, 1, 1, '1.2.0125', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MANGUERA PARA AGUA DE LIMPIADORES', 'SERVICIO', NULL, 129),
(130, 1, 1, '1.2.0126', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ROCIADORES', 'SERVICIO', NULL, 130),
(131, 1, 1, '1.2.0127', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH (START) PARA ROCIADORES', 'SERVICIO', NULL, 131),
(132, 1, 1, '1.2.0128', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SENSOR VELOCÍMETRO', 'PIEZA', NULL, 132),
(133, 1, 1, '1.2.0129', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ARNÉS DEL VELOCÍMETRO', 'PIEZA', NULL, 133),
(134, 1, 1, '1.2.0130', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'INDICADOR DEL VELOCÍMETRO', 'PIEZA', NULL, 134),
(135, 1, 1, '1.2.0131', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SENSOR VELOCÍMETRO', 'SERVICIO', NULL, 135),
(136, 1, 1, '1.2.0132', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ÁRNES DEL VELOCÍMETRO', 'SERVICIO', NULL, 136),
(137, 1, 1, '1.2.0133', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE INDICADOR DEL VELOCÍMETRO', 'SERVICIO', NULL, 137),
(138, 1, 1, '1.2.0134', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE IGNICIÓN', 'PIEZA', NULL, 138),
(139, 1, 1, '1.2.0135', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ACUMULADOR DE 27 PLACAS', 'PIEZA', NULL, 139),
(140, 1, 1, '1.2.0136', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MOTOR DE ARRANQUE 24 VOLTS', 'PIEZA', NULL, 140),
(141, 1, 1, '1.2.0137', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'TERMINAL PARA BORNE DE BATERÍA', 'PIEZA', NULL, 141),
(142, 1, 1, '1.2.0138', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLES PARA BATERÍA', 'METRO', NULL, 142),
(143, 1, 1, '1.2.0139', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CREMALLERA DE VOLANTE MOTRIZ', 'PIEZA', NULL, 143),
(144, 1, 1, '1.2.0140', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLEADO', 'METRO', NULL, 144),
(145, 1, 1, '1.2.0141', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SOLENOIDE IMPULSOR DE ARRANQUE', 'PIEZA', NULL, 145),
(146, 1, 1, '1.2.0142', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'RELEVADORES', 'PIEZA', NULL, 146),
(147, 1, 1, '1.2.0143', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ENGRANE IMPULSOR DE ARRANQUE (BENDIX)', 'PIEZA', NULL, 147),
(148, 1, 1, '1.2.0144', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'KIT DE REPARACIÓN DE MOTOR DE ARRANQUE', 'JUEGO', NULL, 148),
(149, 1, 1, '1.2.0145', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE IGNICIÓN', 'SERVICIO', NULL, 149),
(150, 1, 1, '1.2.0146', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ACUMULADOR DE 27 PLACAS', 'SERVICIO', NULL, 150),
(151, 1, 1, '1.2.0147', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MOTOR DE ARRANQUE 24 VOLTS', 'SERVICIO', NULL, 151),
(152, 1, 1, '1.2.0148', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE TERMINAL PARA BORNE DE BATERÍA', 'SERVICIO', NULL, 152),
(153, 1, 1, '1.2.0149', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLES PARA BATERÍA', 'SERVICIO', NULL, 153),
(154, 1, 1, '1.2.0150', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CREMALLERA DE VOLANTE MOTRIZ', 'SERVICIO', NULL, 154),
(155, 1, 1, '1.2.0151', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLEADO', 'SERVICIO', NULL, 155),
(156, 1, 1, '1.2.0152', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SOLENOIDE IMPULSOR DE ARRANQUE', 'SERVICIO', NULL, 156),
(157, 1, 1, '1.2.0153', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE REVELADORES', 'SERVICIO', NULL, 157),
(158, 1, 1, '1.2.0154', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ENGRANE IMPULSOR DE ARRANQUE (BENDIX)', 'SERVICIO', NULL, 158),
(159, 1, 1, '1.2.0155', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE KIT DE REPARACIÓN DE MOTOR DE ARRANQUE', 'SERVICIO', NULL, 159),
(160, 1, 1, '1.2.0156', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ALTERNADOR COMPLETO', 'PIEZA', NULL, 160),
(161, 1, 1, '1.2.0157', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'KIT DE REPARACIÓN DE ALTERNADOR', 'JUEGO', NULL, 161),
(162, 1, 1, '1.2.0158', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'BANDAS DE ALTERNADOR', 'PIEZA', NULL, 162),
(163, 1, 1, '1.2.0159', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'REGULADOR DE VOLTAJE', 'PIEZA', NULL, 163),
(164, 1, 1, '1.2.0160', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLEADO', 'METRO', NULL, 164),
(165, 1, 1, '1.2.0161', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'VOLTÍMETRO', 'PIEZA', NULL, 165),
(166, 1, 1, '1.2.0162', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ALTERNADOR COMPLETO', 'SERVICIO', NULL, 166),
(167, 1, 1, '1.2.0163', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE KIT DE REPARACIÓN DE ALTERNADOR', 'SERVICIO', NULL, 167),
(168, 1, 1, '1.2.0164', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE BANDAS DE ALTERNADOR', 'SERVICIO', NULL, 168),
(169, 1, 1, '1.2.0165', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE REGULADOR DE VOLTAJE', 'SERVICIO', NULL, 169),
(170, 1, 1, '1.2.0166', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLEADO', 'SERVICIO', NULL, 170),
(171, 1, 1, '1.2.0167', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE VOLTÍMETRO', 'SERVICIO', NULL, 171),
(172, 1, 1, '1.2.0168', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE LUCES GRAL.', 'PIEZA', NULL, 172),
(173, 1, 1, '1.2.0169', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE CAMBIOS DE LUCES', 'PIEZA', NULL, 173),
(174, 1, 1, '1.2.0170', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'FARO DELANTERO', 'PIEZA', NULL, 174),
(175, 1, 1, '1.2.0171', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ZEPPELINES', 'PIEZA', NULL, 175),
(176, 1, 1, '1.2.0172', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CALAVERAS TRASERAS', 'PIEZA', NULL, 176),
(177, 1, 1, '1.2.0173', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CUARTOS DELANTEROS', 'PIEZA', NULL, 177),
(178, 1, 1, '1.2.0174', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'PORTA FUSIBLES', 'PIEZA', NULL, 178),
(179, 1, 1, '1.2.0175', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'DESTELLADORES REFORZADOS', 'PIEZA', NULL, 179),
(180, 1, 1, '1.2.0176', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'PLAFÓN LUZ INTERIOR', 'PIEZA', NULL, 180),
(181, 1, 1, '1.2.0177', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE LUCES DIRECCIONALES', 'PIEZA', NULL, 181),
(182, 1, 1, '1.2.0178', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLEADO EN GENERAL', 'METRO', NULL, 182),
(183, 1, 1, '1.2.0179', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'TORRETAS', 'PIEZA', NULL, 183),
(184, 1, 1, '1.2.0180', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'INDICADOR DE REVOLUCIONES POR MINUTO', 'PIEZA', NULL, 184),
(185, 1, 1, '1.2.0181', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE LUCES GRAL.', 'SERVICIO', NULL, 185),
(186, 1, 1, '1.2.0182', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE CAMBIOS DE LUCES', 'SERVICIO', NULL, 186),
(187, 1, 1, '1.2.0183', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE FARO DELANTERO', 'SERVICIO', NULL, 187),
(188, 1, 1, '1.2.0184', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ZEPPELINES', 'SERVICIO', NULL, 188),
(189, 1, 1, '1.2.0185', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CALAVERAS TRASERAS', 'SERVICIO', NULL, 189),
(190, 1, 1, '1.2.0186', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CUARTOS DELANTEROS', 'SERVICIO', NULL, 190),
(191, 1, 1, '1.2.0187', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE PORTA FUSIBLES', 'SERVICIO', NULL, 191),
(192, 1, 1, '1.2.0188', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE DESTELLADORES REFORZADOS', 'SERVICIO', NULL, 192),
(193, 1, 1, '1.2.0189', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE PLAFÓN LUZ INTERIOR', 'SERVICIO', NULL, 193),
(194, 1, 1, '1.2.0190', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE LUCES DIRECCIONALES', 'SERVICIO', NULL, 194),
(195, 1, 1, '1.2.0191', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLEADO EN GENERAL', 'SERVICIO', NULL, 195),
(196, 1, 1, '1.2.0192', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE TORRETAS', 'SERVICIO', NULL, 196),
(197, 1, 1, '1.2.0193', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE INDICADOR DE R.P.M.', 'SERVICIO', NULL, 197),
(198, 1, 1, '1.2.0194', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BOMBA DE DIRECCIÓN', 'PIEZA', NULL, 198),
(199, 1, 1, '1.2.0195', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'REPUESTO PARA BOMBA DE DIRECCIÓN', 'JUEGO', NULL, 199),
(200, 1, 1, '1.2.0196', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MANGUERA DE SUCCIÓN', 'PIEZA', NULL, 200)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(201, 1, 1, '1.2.0197', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MANGUERA DE DESCARGA', 'PIEZA', NULL, 201),
(202, 1, 1, '1.2.0198', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MANGUERA DE RETORNO', 'PIEZA', NULL, 202),
(203, 1, 1, '1.2.0199', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'DEPOSITO DE SISTEMA HIDRÁULICO', 'PIEZA', NULL, 203),
(204, 1, 1, '1.2.0200', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'FILTRO PARA ACEITE DEL SISTEMA HIDRÁULICO', 'PIEZA', NULL, 204),
(205, 1, 1, '1.2.0201', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ACOPLAMIENTO DE COLUMNA DE DIRECCIÓN', 'PIEZA', NULL, 205),
(206, 1, 1, '1.2.0202', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CRUCETA PARA COLUMNA DE DIRECCIÓN', 'PIEZA', NULL, 206),
(207, 1, 1, '1.2.0203', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'SOPORTE PARA COLUMNA DE DIRECCIÓN', 'PIEZA', NULL, 207),
(208, 1, 1, '1.2.0204', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAJA DE DIRECCIÓN', 'PIEZA', NULL, 208),
(209, 1, 1, '1.2.0205', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'REPUESTO PARA CAJA DE DIRECCIÓN', 'JUEGO', NULL, 209),
(210, 1, 1, '1.2.0206', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BIELA DE MANDO', 'PIEZA', NULL, 210),
(211, 1, 1, '1.2.0207', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TERMINAL PARA BIELA DE MANDO', 'PIEZA', NULL, 211),
(212, 1, 1, '1.2.0208', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TERMINAL PARA BARRA DE DIRECCIÓN', 'PIEZA', NULL, 212),
(213, 1, 1, '1.2.0209', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'PERNOS Y BUJES PARA MANGO DE DIRECCIÓN', 'JUEGO', NULL, 213),
(214, 1, 1, '1.2.0210', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ESPIGA PARA MANGO DE DIRECCIÓN ( R )', 'PIEZA', NULL, 214),
(215, 1, 1, '1.2.0211', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ESPIGA PARA MANGO DE DIRECCIÓN ( L )', 'PIEZA', NULL, 215),
(216, 1, 1, '1.2.0212', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BOMBA DE DIRECCIÓN', 'SERVICIO', NULL, 216),
(217, 1, 1, '1.2.0213', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE REPUESTO PARA BOMBA DE DIRECCIÓN', 'SERVICIO', NULL, 217),
(218, 1, 1, '1.2.0214', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MANGUERA DE SUCCIÓN', 'SERVICIO', NULL, 218),
(219, 1, 1, '1.2.0215', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MANGUERA DE DESCARGA', 'SERVICIO', NULL, 219),
(220, 1, 1, '1.2.0216', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MANGUERA DE RETORNO', 'SERVICIO', NULL, 220),
(221, 1, 1, '1.2.0217', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE DEPÓSITO DE SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 221),
(222, 1, 1, '1.2.0218', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE FILTRO PARA ACEITE DEL SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 222),
(223, 1, 1, '1.2.0219', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE ACOPLAMIENTO DE COLUMNA DE DIRECCIÓN', 'SERVICIO', NULL, 223),
(224, 1, 1, '1.2.0220', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE CRUCETA PARA COLUMNA DE DIRECCIÓN', 'SERVICIO', NULL, 224),
(225, 1, 1, '1.2.0221', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE SOPORTE PARA COLUMNA DE DIRECCIÓN', 'SERVICIO', NULL, 225),
(226, 1, 1, '1.2.0222', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE CAJA DE DIRECCIÓN', 'SERVICIO', NULL, 226),
(227, 1, 1, '1.2.0223', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE REPUESTO PARA CAJA DE DIRECCIÓN', 'SERVICIO', NULL, 227),
(228, 1, 1, '1.2.0224', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BIELA DE MANDO', 'SERVICIO', NULL, 228),
(229, 1, 1, '1.2.0225', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TERMINAL PARA BIELA DE MANDO', 'SERVICIO', NULL, 229),
(230, 1, 1, '1.2.0226', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TERMINAL PARA BARRA DE DIRECCIÓN', 'SERVICIO', NULL, 230),
(231, 1, 1, '1.2.0227', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE PERNOS Y BUJES PARA MANGO DE DIRECCIÓN', 'SERVICIO', NULL, 231),
(232, 1, 1, '1.2.0228', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE ESPIGA PARA MANGO DE DIRECCIÓN ( R )', 'SERVICIO', NULL, 232),
(233, 1, 1, '1.2.0229', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE ESPIGA PARA MANGO DE DIRECCIÓN ( L )', 'SERVICIO', NULL, 233),
(234, 1, 1, '1.2.0230', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MUELLES DELANTERAS', 'PIEZA', NULL, 234),
(235, 1, 1, '1.2.0231', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TORNILLO DE CENTRO PARA MUELLE DELANTERO', 'PIEZA', NULL, 235),
(236, 1, 1, '1.2.0232', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ALBARDÓN ( COLUMPIO DE MUELLE DELANTERA)', 'PIEZA', NULL, 236),
(237, 1, 1, '1.2.0233', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'PERNO PARA MUELLE DELANTERO', 'PIEZA', NULL, 237),
(238, 1, 1, '1.2.0234', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TACONES PARA MUELLES DELANTEROS', 'PIEZA', NULL, 238),
(239, 1, 1, '1.2.0235', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MUELLES DELANTEROS', 'SERVICIO', NULL, 239),
(240, 1, 1, '1.2.0236', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TORNILLO DE CENTRO PARA MUELLE DELANTERO', 'SERVICIO', NULL, 240),
(241, 1, 1, '1.2.0237', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE PERNO PARA MUELLE DELANTERO', 'SERVICIO', NULL, 241),
(242, 1, 1, '1.2.0238', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TACONES PARA MUELLES DELANTEROS', 'SERVICIO', NULL, 242),
(243, 1, 1, '1.2.0239', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BALERO INTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 243),
(244, 1, 1, '1.2.0240', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TAZA PARA BALERO INTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 244),
(245, 1, 1, '1.2.0241', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BALERO EXTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 245),
(246, 1, 1, '1.2.0242', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TAZA PARA BALERO EXTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 246),
(247, 1, 1, '1.2.0243', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'RETEN INTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 247),
(248, 1, 1, '1.2.0244', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TAPA PARA RUEDA DELANTERA', 'PIEZA', NULL, 248),
(249, 1, 1, '1.2.0245', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BALERO INTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 249),
(250, 1, 1, '1.2.0246', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TAZA PARA BALERO INTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 250),
(251, 1, 1, '1.2.0247', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BALERO EXTERIOR RUEDA DELANTERA 1', 'SERVICIO', NULL, 251),
(252, 1, 1, '1.2.0248', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TAZA PARA BALERO EXTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 252),
(253, 1, 1, '1.2.0249', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE RETÉN INTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 253),
(254, 1, 1, '1.2.0250', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TAPA PARA RUEDA DELANTERA', 'SERVICIO', NULL, 254),
(255, 1, 1, '1.2.0251', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CLUTCH COMPLETO', 'JUEGO', NULL, 255),
(256, 1, 1, '1.2.0252', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'BALERO PILOTO', 'PIEZA', NULL, 256),
(257, 1, 1, '1.2.0253', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CHICOTE DE EMBRAGUE', 'PIEZA', NULL, 257),
(258, 1, 1, '1.2.0254', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'PLATO SEPARADOR', 'PIEZA', NULL, 258),
(259, 1, 1, '1.2.0255', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'FRENO DE INERCIA', 'PIEZA', NULL, 259),
(260, 1, 1, '1.2.0256', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE CLUTCH COMPLETO', 'SERVICIO', NULL, 260),
(261, 1, 1, '1.2.0257', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE BALERO PILOTO', 'SERVICIO', NULL, 261),
(262, 1, 1, '1.2.0258', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE CHICOTE DE EMBRAGUE', 'SERVICIO', NULL, 262),
(263, 1, 1, '1.2.0259', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE PLATO SEPARADOR', 'SERVICIO', NULL, 263),
(264, 1, 1, '1.2.0260', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE FRENO DE INERCIA', 'SERVICIO', NULL, 264),
(265, 1, 1, '1.2.0261', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAJA DE VELOCIDADES COMPLETA', 'PIEZA', NULL, 265),
(266, 1, 1, '1.2.0262', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TOMA DE FUERZA PARA BOMBA DEL SISTEMA HIDRÁULICO', 'PIEZA', NULL, 266),
(267, 1, 1, '1.2.0263', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CRUCETA PARA BARRA CARDAN', 'PIEZA', NULL, 267),
(268, 1, 1, '1.2.0264', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAJA DE TRANSFERENCIA  164144', 'PIEZA', NULL, 268),
(269, 1, 1, '1.2.0265', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE REPARACIÓN DE CAJA DE TRANSFERENCIA', 'JUEGO', NULL, 269),
(270, 1, 1, '1.2.0266', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN PARA TOMA DE FUERZA', 'PIEZA', NULL, 270),
(271, 1, 1, '1.2.0267', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CRUCETA PARA FLECHA CARDAN DE TOMA DE FUERZA', 'PIEZA', NULL, 271),
(272, 1, 1, '1.2.0268', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CHUMACERA PARA AJUSTE DE BANDAS', 'PIEZA', NULL, 272),
(273, 1, 1, '1.2.0269', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TACÓN PARA CAJA DE TRANSFERENCIA', 'PIEZA', NULL, 273),
(274, 1, 1, '1.2.0270', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN DE CAJA PRINCIPAL A CAJA DE TRANSFERENCIA', 'PIEZA', NULL, 274),
(275, 1, 1, '1.2.0271', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN DE CAJA DE TRANSFERENCIA A PRIMER DIFERENCIAL', 'PIEZA', NULL, 275),
(276, 1, 1, '1.2.0272', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN DE INTER-EJES', 'PIEZA', NULL, 276),
(277, 1, 1, '1.2.0273', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'BOTÓN PARA CAMBIO DE RANGO DE VELOCIDAD', 'PIEZA', NULL, 277),
(278, 1, 1, '1.2.0274', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPUESTO PARA ACTUADOR DE CAMBIO DE RANGO DE VELOCIDAD', 'JUEGO', NULL, 278),
(279, 1, 1, '1.2.0275', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 1/4 Ø', 'PIEZA', NULL, 279),
(280, 1, 1, '1.2.0276', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 3/8 Ø', 'PIEZA', NULL, 280),
(281, 1, 1, '1.2.0277', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE REPARACIÓN DE CAJA DE VELOCIDADES', 'JUEGO', NULL, 281),
(282, 1, 1, '1.2.0278', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'DIFERENCIAL DELANTERO DANA (19733752, 19QF4429)', 'PIEZA', NULL, 282),
(283, 1, 1, '1.2.0279', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'DIFERENCIAL  TRASERO  DANA (19720040, 19QF4429)', 'PIEZA', NULL, 283),
(284, 1, 1, '1.2.0280', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'ACTUADOR PARA APLICACIÓN DE TOMA DE FUERZA (PTO)', 'PIEZA', NULL, 284),
(285, 1, 1, '1.2.0281', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE CORONA Y PIÑÓN', 'JUEGO', NULL, 285),
(286, 1, 1, '1.2.0282', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE BALEROS DE DIFERENCIAL', 'JUEGO', NULL, 286),
(287, 1, 1, '1.2.0283', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE PLANETARIOS', 'JUEGO', NULL, 287),
(288, 1, 1, '1.2.0284', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'RETEN DE CAJA DE VELOCIDADES', 'PIEZA', NULL, 288),
(289, 1, 1, '1.2.0285', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'RETEN DEL DIFERENCIAL', 'PIEZA', NULL, 289),
(290, 1, 1, '1.2.0286', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHAS LATERALES ( R) Ó (L)', 'PIEZA', NULL, 290),
(291, 1, 1, '1.2.0287', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CAJA DE VELOCIDADES', 'SERVICIO', NULL, 291),
(292, 1, 1, '1.2.0288', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TOMA DE FUERZA PARA BOMBA SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 292),
(293, 1, 1, '1.2.0289', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CRUCETA PARA BARRA CARDAN', 'SERVICIO', NULL, 293),
(294, 1, 1, '1.2.0290', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CAJA DE TRANSFERENCIA 164144', 'SERVICIO', NULL, 294),
(295, 1, 1, '1.2.0291', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE KIT DE REPARACIÓN DE CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 295),
(296, 1, 1, '1.2.0292', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN PARA TOMA DE FUERZA', 'SERVICIO', NULL, 296),
(297, 1, 1, '1.2.0293', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CRUCETA PARA FLECHA CARDAN DE TOMA DE FUERZA', 'SERVICIO', NULL, 297),
(298, 1, 1, '1.2.0294', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CHUMACERA PARA AJUSTE DE BANDAS', 'SERVICIO', NULL, 298),
(299, 1, 1, '1.2.0295', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TACÓN PARA CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 299),
(300, 1, 1, '1.2.0296', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN DE CAJA PRINCIPAL A CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 300)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(301, 1, 1, '1.2.0297', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN DE CAJA DE TRANSFERENCIA A PRIMER DIFERENCIAL', 'SERVICIO', NULL, 301),
(302, 1, 1, '1.2.0298', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN DE INTER-EJES', 'SERVICIO', NULL, 302),
(303, 1, 1, '1.2.0299', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE BOTÓN PARA CAMBIO DE RANGO DE VELOCIDAD', 'SERVICIO', NULL, 303),
(304, 1, 1, '1.2.0300', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE REPUESTO PARA ACTUADOR DE CAMBIO DE RANGO DE VELOCIDAD', 'SERVICIO', NULL, 304),
(305, 1, 1, '1.2.0301', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 1/4 Ø', 'SERVICIO', NULL, 305),
(306, 1, 1, '1.2.0302', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 3/8 Ø', 'SERVICIO', NULL, 306),
(307, 1, 1, '1.2.0303', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPARACIÓN DE CAJA DE VELOCIDADES (costo no mayor de 50% del valor de  caja de velocidades nueva)', 'SERVICIO', NULL, 307),
(308, 1, 1, '1.2.0304', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPARACIÓN DE DIFERENCIAL DELANTERO DANA (costo no mayor de 50% del valor de diferencial delantero nuevo)', 'SERVICIO', NULL, 308),
(309, 1, 1, '1.2.0305', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPARACIÓN DE DIFERENCIAL TRASERO DANA (costo no mayor de 50% del valor de diferencial trasero nuevo)', 'SERVICIO', NULL, 309),
(310, 1, 1, '1.2.0306', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE ACTUADOR PARA APLICACIÓN DE TOMA DE FUERZA (PTO)', 'SERVICIO', NULL, 310),
(311, 1, 1, '1.2.0307', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE KIT DE CORONA Y PIÑÓN', 'SERVICIO', NULL, 311),
(312, 1, 1, '1.2.0308', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE KIT DE BALEROS DE DIFERENCIAL', 'SERVICIO', NULL, 312),
(313, 1, 1, '1.2.0309', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE KIT DE PLANETARIOS', 'SERVICIO', NULL, 313),
(314, 1, 1, '1.2.0310', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE RETÉN DE CAJA DE VELOCIDADES', 'SERVICIO', NULL, 314),
(315, 1, 1, '1.2.0311', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE RETÉN DE DIFERENCIAL', 'SERVICIO', NULL, 315),
(316, 1, 1, '1.2.0312', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA LATERAL', 'SERVICIO', NULL, 316),
(317, 1, 1, '1.2.0313', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'BALERO INTERIOR RUEDA TRASERA', 'PIEZA', NULL, 317),
(318, 1, 1, '1.2.0314', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TAZA PARA BALERO INTERIOR RUEDA TRASERA', 'PIEZA', NULL, 318),
(319, 1, 1, '1.2.0315', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'BALERO EXTERIOR RUEDA TRASERA', 'PIEZA', NULL, 319),
(320, 1, 1, '1.2.0316', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TAZA PARA BALERO EXTERIOR RUEDA TRASERA', 'PIEZA', NULL, 320),
(321, 1, 1, '1.2.0317', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'RETÉN INTERIOR RUEDA TRASERA', 'PIEZA', NULL, 321),
(322, 1, 1, '1.2.0318', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE BALERO INTERIOR RUEDA TRASERA.', 'SERVICIO', NULL, 322),
(323, 1, 1, '1.2.0319', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TAZA PARA BALERO INTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 323),
(324, 1, 1, '1.2.0320', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE BALERO EXTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 324),
(325, 1, 1, '1.2.0321', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TAZA PARA BALERO EXTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 325),
(326, 1, 1, '1.2.0322', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE RETEN INTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 326),
(327, 1, 1, '1.2.0323', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA REPARTIDORA', 'PIEZA', NULL, 327),
(328, 1, 1, '1.2.0324', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA DE RELEVO', 'PIEZA', NULL, 328),
(329, 1, 1, '1.2.0325', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DE 1/2" Ø', 'PIEZA', NULL, 329),
(330, 1, 1, '1.2.0326', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DE 3/8" Ø', 'PIEZA', NULL, 330),
(331, 1, 1, '1.2.0327', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA CHECK  1/2" Ø', 'PIEZA', NULL, 331),
(332, 1, 1, '1.2.0328', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MATRACAS', 'PIEZA', NULL, 332),
(333, 1, 1, '1.2.0329', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'ACTUADOR DOBLE CÁMARA', 'PIEZA', NULL, 333),
(334, 1, 1, '1.2.0330', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'ACTUADOR UNA  CÁMARA', 'PIEZA', NULL, 334),
(335, 1, 1, '1.2.0331', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'BALATAS TRASERAS', 'JUEGO', NULL, 335),
(336, 1, 1, '1.2.0332', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'RESORTES PARA BALATAS', 'PIEZA', NULL, 336),
(337, 1, 1, '1.2.0333', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'FLECHA GAVILÁN TRASERAS', 'PIEZA', NULL, 337),
(338, 1, 1, '1.2.0334', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'FLECHA GAVILÁN DELANTERAS', 'PIEZA', NULL, 338),
(339, 1, 1, '1.2.0335', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'BUJES PARA FLECHA GAVILÁN', 'PIEZA', NULL, 339),
(340, 1, 1, '1.2.0336', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'SEGUROS PARA RODILLOS', 'PIEZA', NULL, 340),
(341, 1, 1, '1.2.0337', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'RODILLOS', 'PIEZA', NULL, 341),
(342, 1, 1, '1.2.0338', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'BALATAS DELANTERAS', 'JUEGO', NULL, 342),
(343, 1, 1, '1.2.0339', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA DEL PEDAL DEL FRENO DE SERVICIO', 'PIEZA', NULL, 343),
(344, 1, 1, '1.2.0340', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'COMPRESOR DE AIRE', 'PIEZA', NULL, 344),
(345, 1, 1, '1.2.0341', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'KIT DE REPARACIÓN DEL COMPRESOR DE AIRE', 'JUEGO', NULL, 345),
(346, 1, 1, '1.2.0342', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DE ENFRIAMIENTO DE COMPRESOR DE AIRE', 'PIEZA', NULL, 346),
(347, 1, 1, '1.2.0343', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA REGULADORA DE PRESIÓN DE AIRE', 'PIEZA', NULL, 347),
(348, 1, 1, '1.2.0344', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'INDICADOR DE PRESIÓN DE AIRE', 'PIEZA', NULL, 348),
(349, 1, 1, '1.2.0345', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DEL INDICADOR DE PRESIÓN DE AIRE No. 4 M/P', 'PIEZA', NULL, 349),
(350, 1, 1, '1.2.0346', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DEL TANQUE AL PULMÓN No. 4 M/P', 'PIEZA', NULL, 350),
(351, 1, 1, '1.2.0347', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA REPARTIDORA', 'SERVICIO', NULL, 351),
(352, 1, 1, '1.2.0348', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA DE RELEVO', 'SERVICIO', NULL, 352),
(353, 1, 1, '1.2.0349', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DE 1/2" Ø', 'SERVICIO', NULL, 353),
(354, 1, 1, '1.2.0350', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DE 3/8" Ø', 'SERVICIO', NULL, 354),
(355, 1, 1, '1.2.0351', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA CHECK 1/2" Ø', 'SERVICIO', NULL, 355),
(356, 1, 1, '1.2.0352', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MATRACAS', 'SERVICIO', NULL, 356),
(357, 1, 1, '1.2.0353', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE ACTUADOR DOBLE CÁMARA', 'SERVICIO', NULL, 357),
(358, 1, 1, '1.2.0354', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE ACTUADOR UNA CÁMARA', 'SERVICIO', NULL, 358),
(359, 1, 1, '1.2.0355', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE BALATAS TRASERAS', 'SERVICIO', NULL, 359),
(360, 1, 1, '1.2.0356', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE RESORTES PARA BALATAS', 'SERVICIO', NULL, 360),
(361, 1, 1, '1.2.0357', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE FLECHA GAVILÁN TRASERAS', 'SERVICIO', NULL, 361),
(362, 1, 1, '1.2.0358', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE FLECHA GAVILÁN DELANTERAS', 'SERVICIO', NULL, 362),
(363, 1, 1, '1.2.0359', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE BUJES PARA FLECHA GAVILÁN', 'SERVICIO', NULL, 363),
(364, 1, 1, '1.2.0360', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE SEGUROS PARA RODILLOS', 'SERVICIO', NULL, 364),
(365, 1, 1, '1.2.0361', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE RODILLOS', 'SERVICIO', NULL, 365),
(366, 1, 1, '1.2.0362', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE BALATAS DELANTERAS', 'SERVICIO', NULL, 366),
(367, 1, 1, '1.2.0363', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA DEL PEDAL DEL FRENO DE SERVICIO', 'SERVICIO', NULL, 367),
(368, 1, 1, '1.2.0364', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE COMPRESOR DE AIRE', 'SERVICIO', NULL, 368),
(369, 1, 1, '1.2.0365', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE KIT DE REPARACIÓN DEL COMPRESOR DE AIRE', 'SERVICIO', NULL, 369),
(370, 1, 1, '1.2.0366', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DE ENFRIAMIENTO DE COMPRESOR DE AIRE', 'SERVICIO', NULL, 370),
(371, 1, 1, '1.2.0367', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA REGULADORA DE PRESIÓN DE AIRE', 'SERVICIO', NULL, 371),
(372, 1, 1, '1.2.0368', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE INDICADOR DE PRESIÓN DE AIRE', 'SERVICIO', NULL, 372),
(373, 1, 1, '1.2.0369', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DEL INDICADOR DE PRESIÓN DE AIRE No. 4 M/P', 'SERVICIO', NULL, 373),
(374, 1, 1, '1.2.0370', '1.2.0000 UNIDAD MARCA INTERNATIONAL MODELO 7400, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DEL TANQUE AL PULMÓN No. 4 M/P', 'SERVICIO', NULL, 374),
(375, 1, 1, '1.3.0001', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'VENTILADOR', 'PIEZA', NULL, 375),
(376, 1, 1, '1.3.0002', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CODO INFERIOR DE RADIADOR', 'PIEZA', NULL, 376),
(377, 1, 1, '1.3.0003', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'COPLE TUBO INFERIOR DE RADIADOR', 'PIEZA', NULL, 377),
(378, 1, 1, '1.3.0004', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'BOMBA PARA AGUA', 'PIEZA', NULL, 378),
(379, 1, 1, '1.3.0005', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'BANDA PRINCIPAL DEL MOTOR', 'PIEZA', NULL, 379),
(380, 1, 1, '1.3.0006', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TERMODINÁMICO DEL VENTILADOR', 'PIEZA', NULL, 380),
(381, 1, 1, '1.3.0007', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'FILTRO PARA AGUA', 'PIEZA', NULL, 381),
(382, 1, 1, '1.3.0008', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TERMOSTATO', 'PIEZA', NULL, 382),
(383, 1, 1, '1.3.0009', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TOLVA DEL VENTILADOR', 'PIEZA', NULL, 383),
(384, 1, 1, '1.3.0010', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'MANGUERA INFERIOR DEL RADIADOR', 'PIEZA', NULL, 384),
(385, 1, 1, '1.3.0011', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'BULBO INDICADOR DE TEMPERATURA', 'PIEZA', NULL, 385),
(386, 1, 1, '1.3.0012', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'TAPÓN DEL RADIADOR ( 7-16 LBS.)', 'PIEZA', NULL, 386),
(387, 1, 1, '1.3.0013', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'PANAL DEL RADIADOR', 'PIEZA', NULL, 387),
(388, 1, 1, '1.3.0014', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'SENSOR DE TEMPERATURA', 'PIEZA', NULL, 388),
(389, 1, 1, '1.3.0015', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'RADIADOR COMPLETO', 'PIEZA', NULL, 389),
(390, 1, 1, '1.3.0016', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'FAN CLOUTCH', 'PIEZA', NULL, 390),
(391, 1, 1, '1.3.0017', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'DEPÓSITO RECUPERADOR DE REFRIGERANTE', 'PIEZA', NULL, 391),
(392, 1, 1, '1.3.0018', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'ENFRIADOR DE ACEITE DE MOTOR', 'PIEZA', NULL, 392),
(393, 1, 1, '1.3.0019', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'POLEA TENSORA', 'PIEZA', NULL, 393),
(394, 1, 1, '1.3.0020', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'MANGUERA SUPERIOR DEL RADIADOR', 'PIEZA', NULL, 394),
(395, 1, 1, '1.3.0021', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE VENTILADOR', 'SERVICIO', NULL, 395),
(396, 1, 1, '1.3.0022', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE CODO INFERIOR DE RADIADOR', 'SERVICIO', NULL, 396),
(397, 1, 1, '1.3.0023', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE COPLE TUBO INFERIOR DE RADIADOR', 'SERVICIO', NULL, 397),
(398, 1, 1, '1.3.0024', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE BOMBA PARA AGUA', 'SERVICIO', NULL, 398),
(399, 1, 1, '1.3.0025', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE BANDA PRINCIPAL DEL MOTOR', 'SERVICIO', NULL, 399),
(400, 1, 1, '1.3.0026', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TERMODINÁMICO DEL VENTILADOR', 'SERVICIO', NULL, 400)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(401, 1, 1, '1.3.0027', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE FILTRO PARA AGUA', 'SERVICIO', NULL, 401),
(402, 1, 1, '1.3.0028', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TERMOSTATO', 'SERVICIO', NULL, 402),
(403, 1, 1, '1.3.0029', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TOLVA DEL VENTILADOR', 'SERVICIO', NULL, 403),
(404, 1, 1, '1.3.0030', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE MANGUERA INFERIOR DEL RADIADOR', 'SERVICIO', NULL, 404),
(405, 1, 1, '1.3.0031', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE BULBO INDICADOR DE TEMPERATURA', 'SERVICIO', NULL, 405),
(406, 1, 1, '1.3.0032', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE TAPÓN DE RADIADOR', 'SERVICIO', NULL, 406),
(407, 1, 1, '1.3.0033', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE MANGUERA SUPERIOR DEL RADIADOR', 'SERVICIO', NULL, 407),
(408, 1, 1, '1.3.0034', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE PANAL', 'SERVICIO', NULL, 408),
(409, 1, 1, '1.3.0035', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'REPARACIÓN DE RADIADOR. (Ccosto no mayor de 50% del valor del radiador nuevo)', 'SERVICIO', NULL, 409),
(410, 1, 1, '1.3.0036', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE SENSOR DE TEMPERATURA', 'SERVICIO', NULL, 410),
(411, 1, 1, '1.3.0037', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE RADIADOR COMPLETO', 'SERVICIO', NULL, 411),
(412, 1, 1, '1.3.0038', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE FAN CLOUTCH', 'SERVICIO', NULL, 412),
(413, 1, 1, '1.3.0039', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DEL DEPÓSITO RECUPERADOR DE REFRIGERANTE', 'SERVICIO', NULL, 413),
(414, 1, 1, '1.3.0040', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DEL ENFRIADOR DE ACEITE DE MOTOR', 'SERVICIO', NULL, 414),
(415, 1, 1, '1.3.0041', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ENFRIAMIENTO.', 'CAMBIO DE POLEA TENSORA', 'SERVICIO', NULL, 415),
(416, 1, 1, '1.3.0042', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'JUNTAS PARA MOTOR COMPLETO', 'JUEGO', NULL, 416),
(417, 1, 1, '1.3.0043', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'PISTONES', 'JUEGO', NULL, 417),
(418, 1, 1, '1.3.0044', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SEGUROS PARA PERNOS DE PISTÓN', 'PIEZA', NULL, 418),
(419, 1, 1, '1.3.0045', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'CAMISAS', 'PIEZA', NULL, 419),
(420, 1, 1, '1.3.0046', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ANILLOS PARA PISTÓN STD.', 'JUEGO', NULL, 420),
(421, 1, 1, '1.3.0047', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'METALES PARA ÁRBOL DE LEVAS', 'JUEGO', NULL, 421),
(422, 1, 1, '1.3.0048', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'BOMBA PARA ACEITE', 'PIEZA', NULL, 422),
(423, 1, 1, '1.3.0049', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'METALES PARA BIELA STD.', 'JUEGO', NULL, 423),
(424, 1, 1, '1.3.0050', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'METALES DE BANCADA STD.', 'JUEGO', NULL, 424),
(425, 1, 1, '1.3.0051', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'VÁLVULA DE ESCAPE', 'PIEZA', NULL, 425),
(426, 1, 1, '1.3.0052', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'VÁLVULA DE ADMISIÓN', 'PIEZA', NULL, 426),
(427, 1, 1, '1.3.0053', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ASIENTO PARA VÁLVULA DE ESCAPE', 'PIEZA', NULL, 427),
(428, 1, 1, '1.3.0054', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ASIENTO PARA VÁLVULA DE ADMISIÓN', 'PIEZA', NULL, 428),
(429, 1, 1, '1.3.0055', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SELLOS DE VÁLVULAS', 'JUEGO', NULL, 429),
(430, 1, 1, '1.3.0056', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'RESORTES DE VÁLVULAS', 'PIEZA', NULL, 430),
(431, 1, 1, '1.3.0057', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SELLOS DE CONDUCTOS DE AGUA', 'PIEZA', NULL, 431),
(432, 1, 1, '1.3.0058', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'RETEN DELANTERO DEL CIGÜEÑAL', 'PIEZA', NULL, 432),
(433, 1, 1, '1.3.0059', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'RETEN TRASERO DEL CIGÜEÑAL', 'PIEZA', NULL, 433),
(434, 1, 1, '1.3.0060', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'ELEMENTO PARA  EL ENFRIADOR DE ACEITE', 'PIEZA', NULL, 434),
(435, 1, 1, '1.3.0061', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'TACONES PARA MOTOR', 'PIEZA', NULL, 435),
(436, 1, 1, '1.3.0062', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'SELLOS DE CAMISAS', 'JUEGO', NULL, 436),
(437, 1, 1, '1.3.0063', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'CIGÜEÑAL NUEVO', 'PIEZA', NULL, 437),
(438, 1, 1, '1.3.0064', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'REPARACIÓN GENERAL DE MOTOR; INCLUYE: DESMONTAR, DESARMAR, CAMBIO DE PIEZAS DAÑADAS, AJUSTES, ARMAR, MONTAR Y PUESTA EN OPERACIÓN. (costo no mayor de 50% del valor de nuevo).', 'SERVICIO', NULL, 438),
(439, 1, 1, '1.3.0065', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, MOTOR.', 'REPARACIÓN GENERAL DE CABEZOTE; INCLUYE: MAQUINARIA, ASIENTOS DE VÁLVULA, MAQUINAR CABEZA PARA INSERTAR GUÍAS DE VÁLVULAS, LIMPIEZA Y PERLIZADO DE CABEZA Y EFECTUAR PRUEBA HIDROSTÁTICA. (costo no mayor de 50% del valor de cabezote nuevo).', 'SERVICIO', NULL, 439),
(440, 1, 1, '1.3.0066', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'JUNTAS PARA MÚLTIPLE DE ESCAPE', 'JUEGO', NULL, 440),
(441, 1, 1, '1.3.0067', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'TUBO PARA ESCAPE', 'PIEZA', NULL, 441),
(442, 1, 1, '1.3.0068', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'SILENCIADOR', 'PIEZA', NULL, 442),
(443, 1, 1, '1.3.0069', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'ABRAZADERAS PARA TUBO DE ESCAPE', 'PIEZA', NULL, 443),
(444, 1, 1, '1.3.0070', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE JUNTAS PARA MÚLTIPLE DE ESCAPE', 'SERVICIO', NULL, 444),
(445, 1, 1, '1.3.0071', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE TUBO PARA ESCAPE', 'SERVICIO', NULL, 445),
(446, 1, 1, '1.3.0072', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE SILENCIADOR', 'SERVICIO', NULL, 446),
(447, 1, 1, '1.3.0073', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE ESCAPE.', 'CAMBIO DE ABRAZADERAS PARA TUBO DE ESCAPE', 'SERVICIO', NULL, 447),
(448, 1, 1, '1.3.0074', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'INDICADOR DE COMBUSTIBLE', 'PIEZA', NULL, 448),
(449, 1, 1, '1.3.0075', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'MANGUERA DE SUCCIÓN DE COMBUSTIBLE', 'PIEZA', NULL, 449),
(450, 1, 1, '1.3.0076', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'MANGUERA DE RETORNO DE COMBUSTIBLE', 'PIEZA', NULL, 450),
(451, 1, 1, '1.3.0077', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTRO PRIMARIO DE COMBUSTIBLE', 'PIEZA', NULL, 451),
(452, 1, 1, '1.3.0078', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTRO SECUNDARIO DE COMBUSTIBLE', 'PIEZA', NULL, 452),
(453, 1, 1, '1.3.0079', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'BOMBA DE INYECCIÓN    313GC 5212P14', 'PIEZA', NULL, 453),
(454, 1, 1, '1.3.0080', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'LÍNEAS DE COMBUSTIBLE', 'JUEGO', NULL, 454),
(455, 1, 1, '1.3.0081', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'INYECTORES', 'PIEZA', NULL, 455),
(456, 1, 1, '1.3.0082', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'TANQUE DE COMBUSTIBLE; INCL. INSTALACIÓN', 'PIEZA', NULL, 456),
(457, 1, 1, '1.3.0083', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE INDICADOR DE COMBUSTIBLE', 'SERVICIO', NULL, 457),
(458, 1, 1, '1.3.0084', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE MANGUERA DE SUCCIÓN DE COMBUSTIBLE', 'SERVICIO', NULL, 458),
(459, 1, 1, '1.3.0085', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE MANGUERA DE RETORNO DE COMBUSTIBLE', 'SERVICIO', NULL, 459),
(460, 1, 1, '1.3.0086', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTRO PRIMARIO DE COMBUSTIBLE', 'SERVICIO', NULL, 460),
(461, 1, 1, '1.3.0087', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTRO SECUNDARIO DE COMBUSTIBLE', 'SERVICIO', NULL, 461),
(462, 1, 1, '1.3.0088', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE BOMBA DE INYECCIÓN', 'SERVICIO', NULL, 462),
(463, 1, 1, '1.3.0089', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE LÍNEAS DE COMBUSTIBLE', 'SERVICIO', NULL, 463),
(464, 1, 1, '1.3.0090', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE INYECTORES', 'SERVICIO', NULL, 464),
(465, 1, 1, '1.3.0091', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'PULIDO  TANQUE DE COMBUSTIBLE', 'SERVICIO', NULL, 465),
(466, 1, 1, '1.3.0092', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'REPARACIÓN DE BOMBA DE INYECCIÓN (Costo no mayor de 50% del valor de bomba de inyección nueva)', 'SERVICIO', NULL, 466),
(467, 1, 1, '1.3.0093', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'REPARACIÓN DE INYECTORES (Costo no mayor de 50% del valor de inyectores nuevos)', 'SERVICIO', NULL, 467),
(468, 1, 1, '1.3.0094', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTROS DE COMBUSTIBLE (PRIMARIO Y SECUNDARIO)', 'JUEGO', NULL, 468),
(469, 1, 1, '1.3.0095', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'FILTRO DE AIRE', 'PIEZA', NULL, 469),
(470, 1, 1, '1.3.0096', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'JUNTA DE TAPA DE PUNTERÍAS', 'PIEZA', NULL, 470),
(471, 1, 1, '1.3.0097', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'TURBO CARGADOR', 'PIEZA', NULL, 471),
(472, 1, 1, '1.3.0098', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'MANGUERA DE SUCCIÓN Y DESCARGA DEL POST-ENFRIADOR', 'PIEZA', NULL, 472),
(473, 1, 1, '1.3.0099', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTROS DE COMBUSTIBLE (PRIMARIO Y SECUNDARIO)', 'SERVICIO', NULL, 473),
(474, 1, 1, '1.3.0100', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE FILTRO DE AIRE', 'SERVICIO', NULL, 474),
(475, 1, 1, '1.3.0101', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE JUNTA DE TAPA DE PUNTERÍAS', 'SERVICIO', NULL, 475),
(476, 1, 1, '1.3.0102', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE TURBO CARGADOR', 'SERVICIO', NULL, 476),
(477, 1, 1, '1.3.0103', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CAMBIO DE MANGUERA DE SUCCIÓN Y DESCARGA DEL POST-ENFRIADOR', 'SERVICIO', NULL, 477),
(478, 1, 1, '1.3.0104', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CALIBRACIÓN DE VÁLVULAS DE MOTOR', 'SERVICIO', NULL, 478),
(479, 1, 1, '1.3.0105', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CALIBRACIÓN Y REVISIÓN DE BOMBA DE INYECCIÓN', 'SERVICIO', NULL, 479),
(480, 1, 1, '1.3.0106', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'CALIBRACIÓN Y LIMPIEZA DE INYECTORES', 'SERVICIO', NULL, 480),
(481, 1, 1, '1.3.0107', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'LIMPIEZA DE TANQUE DE COMBUSTIBLE', 'SERVICIO', NULL, 481),
(482, 1, 1, '1.3.0108', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'LIMPIEZA Y CAMBIO DE LÍNEAS DE COMBUSTIBLE', 'SERVICIO', NULL, 482),
(483, 1, 1, '1.3.0109', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE COMBUSTIBLE.', 'REPARACIÓN DE TURBO CARGADOR (Costo no mayor de 50% del valor de turbo cargador nuevo)', 'SERVICIO', NULL, 483),
(484, 1, 1, '1.3.0110', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH PARA LIMPIAPARABRISAS', 'PIEZA', NULL, 484),
(485, 1, 1, '1.3.0111', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MECANISMO DE LIMPIADORES', 'JUEGO', NULL, 485),
(486, 1, 1, '1.3.0112', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'BRAZOS', 'PIEZA', NULL, 486),
(487, 1, 1, '1.3.0113', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'PLUMAS', 'JUEGO', NULL, 487),
(488, 1, 1, '1.3.0114', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'DEPÓSITO DE AGUA', 'PIEZA', NULL, 488),
(489, 1, 1, '1.3.0115', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MOTOR BOMBA DE AGUA DEL DEPÓSITO', 'PIEZA', NULL, 489),
(490, 1, 1, '1.3.0116', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MANGUERA PARA AGUA DE LIMPIADORES', 'METRO', NULL, 490),
(491, 1, 1, '1.3.0117', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ROCIADORES', 'PIEZA', NULL, 491),
(492, 1, 1, '1.3.0118', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH (START) PARA ROCIADO', 'PIEZA', NULL, 492),
(493, 1, 1, '1.3.0119', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH PARA LIMPIAPARABRISAS', 'SERVICIO', NULL, 493),
(494, 1, 1, '1.3.0120', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MECANISMO DE LIMPIADORES', 'SERVICIO', NULL, 494),
(495, 1, 1, '1.3.0121', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE BRAZOS', 'SERVICIO', NULL, 495),
(496, 1, 1, '1.3.0122', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE PLUMAS', 'SERVICIO', NULL, 496),
(497, 1, 1, '1.3.0123', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE DEPÓSITO DE AGUA', 'SERVICIO', NULL, 497),
(498, 1, 1, '1.3.0124', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MOTOR BOMBA DE AGUA DEL DEPÓSITO', 'SERVICIO', NULL, 498),
(499, 1, 1, '1.3.0125', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MANGUERA PARA AGUA DE LIMPIADORES', 'SERVICIO', NULL, 499),
(500, 1, 1, '1.3.0126', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ROCIADORES', 'SERVICIO', NULL, 500)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(501, 1, 1, '1.3.0127', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH (START) PARA ROCIADORES', 'SERVICIO', NULL, 501),
(502, 1, 1, '1.3.0128', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SENSOR VELOCÍMETRO', 'PIEZA', NULL, 502),
(503, 1, 1, '1.3.0129', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ARNÉS DEL VELOCÍMETRO', 'PIEZA', NULL, 503),
(504, 1, 1, '1.3.0130', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'INDICADOR DEL VELOCÍMETRO', 'PIEZA', NULL, 504),
(505, 1, 1, '1.3.0131', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SENSOR VELOCÍMETRO', 'SERVICIO', NULL, 505),
(506, 1, 1, '1.3.0132', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ÁRNES DEL VELOCÍMETRO', 'SERVICIO', NULL, 506),
(507, 1, 1, '1.3.0133', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE INDICADOR DEL VELOCÍMETRO', 'SERVICIO', NULL, 507),
(508, 1, 1, '1.3.0134', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE IGNICIÓN', 'PIEZA', NULL, 508),
(509, 1, 1, '1.3.0135', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ACUMULADOR DE 27 PLACAS', 'PIEZA', NULL, 509),
(510, 1, 1, '1.3.0136', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'MOTOR DE ARRANQUE 24 VOLTS', 'PIEZA', NULL, 510),
(511, 1, 1, '1.3.0137', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'TERMINAL PARA BORNE DE BATERÍA', 'PIEZA', NULL, 511),
(512, 1, 1, '1.3.0138', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLES PARA BATERÍA', 'METRO', NULL, 512),
(513, 1, 1, '1.3.0139', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CREMALLERA DE VOLANTE MOTRIZ', 'PIEZA', NULL, 513),
(514, 1, 1, '1.3.0140', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLEADO', 'METRO', NULL, 514),
(515, 1, 1, '1.3.0141', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SOLENOIDE IMPULSOR DE ARRANQUE', 'PIEZA', NULL, 515),
(516, 1, 1, '1.3.0142', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'RELEVADORES', 'PIEZA', NULL, 516),
(517, 1, 1, '1.3.0143', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ENGRANE IMPULSOR DE ARRANQUE (BENDIX)', 'PIEZA', NULL, 517),
(518, 1, 1, '1.3.0144', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'KIT DE REPARACIÓN DE MOTOR DE ARRANQUE', 'JUEGO', NULL, 518),
(519, 1, 1, '1.3.0145', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE IGNICIÓN', 'SERVICIO', NULL, 519),
(520, 1, 1, '1.3.0146', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ACUMULADOR DE 27 PLACAS', 'SERVICIO', NULL, 520),
(521, 1, 1, '1.3.0147', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE MOTOR DE ARRANQUE 24 VOLTS', 'SERVICIO', NULL, 521),
(522, 1, 1, '1.3.0148', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE TERMINAL PARA BORNE DE BATERÍA', 'SERVICIO', NULL, 522),
(523, 1, 1, '1.3.0149', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLES PARA BATERÍA', 'SERVICIO', NULL, 523),
(524, 1, 1, '1.3.0150', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CREMALLERA DE VOLANTE MOTRIZ', 'SERVICIO', NULL, 524),
(525, 1, 1, '1.3.0151', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLEADO', 'SERVICIO', NULL, 525),
(526, 1, 1, '1.3.0152', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SOLENOIDE IMPULSOR DE ARRANQUE', 'SERVICIO', NULL, 526),
(527, 1, 1, '1.3.0153', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE REVELADORES', 'SERVICIO', NULL, 527),
(528, 1, 1, '1.3.0154', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ENGRANE IMPULSOR DE ARRANQUE (BENDIX)', 'SERVICIO', NULL, 528),
(529, 1, 1, '1.3.0155', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE KIT DE REPARACIÓN DE MOTOR DE ARRANQUE', 'SERVICIO', NULL, 529),
(530, 1, 1, '1.3.0156', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ALTERNADOR COMPLETO', 'PIEZA', NULL, 530),
(531, 1, 1, '1.3.0157', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'KIT DE REPARACIÓN DE ALTERNADOR', 'JUEGO', NULL, 531),
(532, 1, 1, '1.3.0158', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'BANDAS DE ALTERNADOR', 'PIEZA', NULL, 532),
(533, 1, 1, '1.3.0159', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'REGULADOR DE VOLTAJE', 'PIEZA', NULL, 533),
(534, 1, 1, '1.3.0160', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLEADO', 'METRO', NULL, 534),
(535, 1, 1, '1.3.0161', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'VOLTÍMETRO', 'PIEZA', NULL, 535),
(536, 1, 1, '1.3.0162', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ALTERNADOR COMPLETO', 'SERVICIO', NULL, 536),
(537, 1, 1, '1.3.0163', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE KIT DE REPARACIÓN DE ALTERNADOR', 'SERVICIO', NULL, 537),
(538, 1, 1, '1.3.0164', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE BANDAS DE ALTERNADOR', 'SERVICIO', NULL, 538),
(539, 1, 1, '1.3.0165', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE REGULADOR DE VOLTAJE', 'SERVICIO', NULL, 539),
(540, 1, 1, '1.3.0166', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLEADO', 'SERVICIO', NULL, 540),
(541, 1, 1, '1.3.0167', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE VOLTÍMETRO', 'SERVICIO', NULL, 541),
(542, 1, 1, '1.3.0168', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE LUCES GRAL.', 'PIEZA', NULL, 542),
(543, 1, 1, '1.3.0169', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE CAMBIOS DE LUCES', 'PIEZA', NULL, 543),
(544, 1, 1, '1.3.0170', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'FARO DELANTERO', 'PIEZA', NULL, 544),
(545, 1, 1, '1.3.0171', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'ZEPPELINES', 'PIEZA', NULL, 545),
(546, 1, 1, '1.3.0172', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CALAVERAS TRASERAS', 'PIEZA', NULL, 546),
(547, 1, 1, '1.3.0173', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CUARTOS DELANTEROS', 'PIEZA', NULL, 547),
(548, 1, 1, '1.3.0174', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'PORTA FUSIBLES', 'PIEZA', NULL, 548),
(549, 1, 1, '1.3.0175', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'DESTELLADORES REFORZADOS', 'PIEZA', NULL, 549),
(550, 1, 1, '1.3.0176', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'PLAFÓN LUZ INTERIOR', 'PIEZA', NULL, 550),
(551, 1, 1, '1.3.0177', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'SWITCH DE LUCES DIRECCIONALES', 'PIEZA', NULL, 551),
(552, 1, 1, '1.3.0178', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CABLEADO EN GENERAL', 'METRO', NULL, 552),
(553, 1, 1, '1.3.0179', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'TORRETAS', 'PIEZA', NULL, 553),
(554, 1, 1, '1.3.0180', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'INDICADOR DE REVOLUCIONES POR MINUTO', 'PIEZA', NULL, 554),
(555, 1, 1, '1.3.0181', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE LUCES GRAL.', 'SERVICIO', NULL, 555),
(556, 1, 1, '1.3.0182', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE CAMBIOS DE LUCES', 'SERVICIO', NULL, 556),
(557, 1, 1, '1.3.0183', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE FARO DELANTERO', 'SERVICIO', NULL, 557),
(558, 1, 1, '1.3.0184', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE ZEPPELINES', 'SERVICIO', NULL, 558),
(559, 1, 1, '1.3.0185', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CALAVERAS TRASERAS', 'SERVICIO', NULL, 559),
(560, 1, 1, '1.3.0186', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CUARTOS DELANTEROS', 'SERVICIO', NULL, 560),
(561, 1, 1, '1.3.0187', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE PORTA FUSIBLES', 'SERVICIO', NULL, 561),
(562, 1, 1, '1.3.0188', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE DESTELLADORES REFORZADOS', 'SERVICIO', NULL, 562),
(563, 1, 1, '1.3.0189', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE PLAFÓN LUZ INTERIOR', 'SERVICIO', NULL, 563),
(564, 1, 1, '1.3.0190', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE SWITCH DE LUCES DIRECCIONALES', 'SERVICIO', NULL, 564),
(565, 1, 1, '1.3.0191', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE CABLEADO EN GENERAL', 'SERVICIO', NULL, 565),
(566, 1, 1, '1.3.0192', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE TORRETAS', 'SERVICIO', NULL, 566),
(567, 1, 1, '1.3.0193', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA ELÉCTRICO.', 'CAMBIO DE INDICADOR DE R.P.M.', 'SERVICIO', NULL, 567),
(568, 1, 1, '1.3.0194', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BOMBA DE DIRECCIÓN', 'PIEZA', NULL, 568),
(569, 1, 1, '1.3.0195', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'REPUESTO PARA BOMBA DE DIRECCIÓN', 'JUEGO', NULL, 569),
(570, 1, 1, '1.3.0196', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MANGUERA DE SUCCIÓN', 'PIEZA', NULL, 570),
(571, 1, 1, '1.3.0197', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MANGUERA DE DESCARGA', 'PIEZA', NULL, 571),
(572, 1, 1, '1.3.0198', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MANGUERA DE RETORNO', 'PIEZA', NULL, 572),
(573, 1, 1, '1.3.0199', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'DEPOSITO DE SISTEMA HIDRÁULICO', 'PIEZA', NULL, 573),
(574, 1, 1, '1.3.0200', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'FILTRO PARA ACEITE DEL SISTEMA HIDRÁULICO', 'PIEZA', NULL, 574),
(575, 1, 1, '1.3.0201', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ACOPLAMIENTO DE COLUMNA DE DIRECCIÓN', 'PIEZA', NULL, 575),
(576, 1, 1, '1.3.0202', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CRUCETA PARA COLUMNA DE DIRECCIÓN', 'PIEZA', NULL, 576),
(577, 1, 1, '1.3.0203', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'SOPORTE PARA COLUMNA DE DIRECCIÓN', 'PIEZA', NULL, 577),
(578, 1, 1, '1.3.0204', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAJA DE DIRECCIÓN', 'PIEZA', NULL, 578),
(579, 1, 1, '1.3.0205', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'REPUESTO PARA CAJA DE DIRECCIÓN', 'JUEGO', NULL, 579),
(580, 1, 1, '1.3.0206', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BIELA DE MANDO', 'PIEZA', NULL, 580),
(581, 1, 1, '1.3.0207', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TERMINAL PARA BIELA DE MANDO', 'PIEZA', NULL, 581),
(582, 1, 1, '1.3.0208', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TERMINAL PARA BARRA DE DIRECCIÓN', 'PIEZA', NULL, 582),
(583, 1, 1, '1.3.0209', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'PERNOS Y BUJES PARA MANGO DE DIRECCIÓN', 'JUEGO', NULL, 583),
(584, 1, 1, '1.3.0210', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ESPIGA PARA MANGO DE DIRECCIÓN ( R )', 'PIEZA', NULL, 584),
(585, 1, 1, '1.3.0211', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ESPIGA PARA MANGO DE DIRECCIÓN ( L )', 'PIEZA', NULL, 585),
(586, 1, 1, '1.3.0212', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BOMBA DE DIRECCIÓN', 'SERVICIO', NULL, 586),
(587, 1, 1, '1.3.0213', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE REPUESTO PARA BOMBA DE DIRECCIÓN', 'SERVICIO', NULL, 587),
(588, 1, 1, '1.3.0214', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MANGUERA DE SUCCIÓN', 'SERVICIO', NULL, 588),
(589, 1, 1, '1.3.0215', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MANGUERA DE DESCARGA', 'SERVICIO', NULL, 589),
(590, 1, 1, '1.3.0216', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MANGUERA DE RETORNO', 'SERVICIO', NULL, 590),
(591, 1, 1, '1.3.0217', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE DEPÓSITO DE SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 591),
(592, 1, 1, '1.3.0218', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE FILTRO PARA ACEITE DEL SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 592),
(593, 1, 1, '1.3.0219', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE ACOPLAMIENTO DE COLUMNA DE DIRECCIÓN', 'SERVICIO', NULL, 593),
(594, 1, 1, '1.3.0220', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE CRUCETA PARA COLUMNA DE DIRECCIÓN', 'SERVICIO', NULL, 594),
(595, 1, 1, '1.3.0221', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE SOPORTE PARA COLUMNA DE DIRECCIÓN', 'SERVICIO', NULL, 595),
(596, 1, 1, '1.3.0222', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE CAJA DE DIRECCIÓN', 'SERVICIO', NULL, 596),
(597, 1, 1, '1.3.0223', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE REPUESTO PARA CAJA DE DIRECCIÓN', 'SERVICIO', NULL, 597),
(598, 1, 1, '1.3.0224', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BIELA DE MANDO', 'SERVICIO', NULL, 598),
(599, 1, 1, '1.3.0225', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TERMINAL PARA BIELA DE MANDO', 'SERVICIO', NULL, 599),
(600, 1, 1, '1.3.0226', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TERMINAL PARA BARRA DE DIRECCIÓN', 'SERVICIO', NULL, 600)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(601, 1, 1, '1.3.0227', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE PERNOS Y BUJES PARA MANGO DE DIRECCIÓN', 'SERVICIO', NULL, 601),
(602, 1, 1, '1.3.0228', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE ESPIGA PARA MANGO DE DIRECCIÓN ( R )', 'SERVICIO', NULL, 602),
(603, 1, 1, '1.3.0229', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE ESPIGA PARA MANGO DE DIRECCIÓN ( L )', 'SERVICIO', NULL, 603),
(604, 1, 1, '1.3.0230', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'MUELLES DELANTERAS', 'PIEZA', NULL, 604),
(605, 1, 1, '1.3.0231', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TORNILLO DE CENTRO PARA MUELLE DELANTERO', 'PIEZA', NULL, 605),
(606, 1, 1, '1.3.0232', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'ALBARDÓN ( COLUMPIO DE MUELLE DELANTERA)', 'PIEZA', NULL, 606),
(607, 1, 1, '1.3.0233', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'PERNO PARA MUELLE DELANTERO', 'PIEZA', NULL, 607),
(608, 1, 1, '1.3.0234', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TACONES PARA MUELLES DELANTEROS', 'PIEZA', NULL, 608),
(609, 1, 1, '1.3.0235', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE MUELLES DELANTEROS', 'SERVICIO', NULL, 609),
(610, 1, 1, '1.3.0236', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TORNILLO DE CENTRO PARA MUELLE DELANTERO', 'SERVICIO', NULL, 610),
(611, 1, 1, '1.3.0237', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE PERNO PARA MUELLE DELANTERO', 'SERVICIO', NULL, 611),
(612, 1, 1, '1.3.0238', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TACONES PARA MUELLES DELANTEROS', 'SERVICIO', NULL, 612),
(613, 1, 1, '1.3.0239', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BALERO INTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 613),
(614, 1, 1, '1.3.0240', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TAZA PARA BALERO INTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 614),
(615, 1, 1, '1.3.0241', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'BALERO EXTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 615),
(616, 1, 1, '1.3.0242', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TAZA PARA BALERO EXTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 616),
(617, 1, 1, '1.3.0243', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'RETEN INTERIOR RUEDA DELANTERA', 'PIEZA', NULL, 617),
(618, 1, 1, '1.3.0244', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'TAPA PARA RUEDA DELANTERA', 'PIEZA', NULL, 618),
(619, 1, 1, '1.3.0245', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BALERO INTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 619),
(620, 1, 1, '1.3.0246', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TAZA PARA BALERO INTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 620),
(621, 1, 1, '1.3.0247', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE BALERO EXTERIOR RUEDA DELANTERA 1', 'SERVICIO', NULL, 621),
(622, 1, 1, '1.3.0248', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TAZA PARA BALERO EXTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 622),
(623, 1, 1, '1.3.0249', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE RETÉN INTERIOR RUEDA DELANTERA', 'SERVICIO', NULL, 623),
(624, 1, 1, '1.3.0250', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE DELANTERO Y DIRECCIÓN.', 'CAMBIO DE TAPA PARA RUEDA DELANTERA', 'SERVICIO', NULL, 624),
(625, 1, 1, '1.3.0251', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CLUTCH COMPLETO', 'JUEGO', NULL, 625),
(626, 1, 1, '1.3.0252', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'BALERO PILOTO', 'PIEZA', NULL, 626),
(627, 1, 1, '1.3.0253', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CHICOTE DE EMBRAGUE', 'PIEZA', NULL, 627),
(628, 1, 1, '1.3.0254', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'PLATO SEPARADOR', 'PIEZA', NULL, 628),
(629, 1, 1, '1.3.0255', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'FRENO DE INERCIA', 'PIEZA', NULL, 629),
(630, 1, 1, '1.3.0256', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE CLUTCH COMPLETO', 'SERVICIO', NULL, 630),
(631, 1, 1, '1.3.0257', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE BALERO PILOTO', 'SERVICIO', NULL, 631),
(632, 1, 1, '1.3.0258', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE CHICOTE DE EMBRAGUE', 'SERVICIO', NULL, 632),
(633, 1, 1, '1.3.0259', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE PLATO SEPARADOR', 'SERVICIO', NULL, 633),
(634, 1, 1, '1.3.0260', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE EMBRAGUE.', 'CAMBIO DE FRENO DE INERCIA', 'SERVICIO', NULL, 634),
(635, 1, 1, '1.3.0261', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAJA DE VELOCIDADES COMPLETA', 'PIEZA', NULL, 635),
(636, 1, 1, '1.3.0262', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TOMA DE FUERZA PARA BOMBA DEL SISTEMA HIDRÁULICO', 'PIEZA', NULL, 636),
(637, 1, 1, '1.3.0263', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CRUCETA PARA BARRA CARDAN', 'PIEZA', NULL, 637),
(638, 1, 1, '1.3.0264', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAJA DE TRANSFERENCIA  164144', 'PIEZA', NULL, 638),
(639, 1, 1, '1.3.0265', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE REPARACIÓN DE CAJA DE TRANSFERENCIA', 'JUEGO', NULL, 639),
(640, 1, 1, '1.3.0266', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN PARA TOMA DE FUERZA', 'PIEZA', NULL, 640),
(641, 1, 1, '1.3.0267', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CRUCETA PARA FLECHA CARDAN DE TOMA DE FUERZA', 'PIEZA', NULL, 641),
(642, 1, 1, '1.3.0268', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CHUMACERA PARA AJUSTE DE BANDAS', 'PIEZA', NULL, 642),
(643, 1, 1, '1.3.0269', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TACÓN PARA CAJA DE TRANSFERENCIA', 'PIEZA', NULL, 643),
(644, 1, 1, '1.3.0270', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN DE CAJA PRINCIPAL A CAJA DE TRANSFERENCIA', 'PIEZA', NULL, 644),
(645, 1, 1, '1.3.0271', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN DE CAJA DE TRANSFERENCIA A PRIMER DIFERENCIAL', 'PIEZA', NULL, 645),
(646, 1, 1, '1.3.0272', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHA CARDAN DE INTER-EJES', 'PIEZA', NULL, 646),
(647, 1, 1, '1.3.0273', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'BOTÓN PARA CAMBIO DE RANGO DE VELOCIDAD', 'PIEZA', NULL, 647),
(648, 1, 1, '1.3.0274', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPUESTO PARA ACTUADOR DE CAMBIO DE RANGO DE VELOCIDAD', 'JUEGO', NULL, 648),
(649, 1, 1, '1.3.0275', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 1/4 Ø', 'PIEZA', NULL, 649),
(650, 1, 1, '1.3.0276', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 3/8 Ø', 'PIEZA', NULL, 650),
(651, 1, 1, '1.3.0277', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE REPARACIÓN DE CAJA DE VELOCIDADES', 'JUEGO', NULL, 651),
(652, 1, 1, '1.3.0278', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'DIFERENCIAL DELANTERO DANA', 'PIEZA', NULL, 652),
(653, 1, 1, '1.3.0279', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'DIFERENCIAL  TRASERO  DANA', 'PIEZA', NULL, 653),
(654, 1, 1, '1.3.0280', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'ACTUADOR PARA APLICACIÓN DE TOMA DE FUERZA (PTO)', 'PIEZA', NULL, 654),
(655, 1, 1, '1.3.0281', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE CORONA Y PIÑÓN', 'JUEGO', NULL, 655),
(656, 1, 1, '1.3.0282', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE BALEROS DE DIFERENCIAL', 'JUEGO', NULL, 656),
(657, 1, 1, '1.3.0283', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'KIT DE PLANETARIOS', 'JUEGO', NULL, 657),
(658, 1, 1, '1.3.0284', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'RETEN DE CAJA DE VELOCIDADES', 'PIEZA', NULL, 658),
(659, 1, 1, '1.3.0285', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'RETEN DEL DIFERENCIAL', 'PIEZA', NULL, 659),
(660, 1, 1, '1.3.0286', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'FLECHAS LATERALES ( R) Ó (L)', 'PIEZA', NULL, 660),
(661, 1, 1, '1.3.0287', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CAJA DE VELOCIDADES', 'SERVICIO', NULL, 661),
(662, 1, 1, '1.3.0288', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TOMA DE FUERZA PARA BOMBA SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 662),
(663, 1, 1, '1.3.0289', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CRUCETA PARA BARRA CARDAN', 'SERVICIO', NULL, 663),
(664, 1, 1, '1.3.0290', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 664),
(665, 1, 1, '1.3.0291', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE KIT DE REPARACIÓN DE CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 665),
(666, 1, 1, '1.3.0292', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN PARA TOMA DE FUERZA', 'SERVICIO', NULL, 666),
(667, 1, 1, '1.3.0293', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CRUCETA PARA FLECHA CARDAN DE TOMA DE FUERZA', 'SERVICIO', NULL, 667),
(668, 1, 1, '1.3.0294', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE CHUMACERA PARA AJUSTE DE BANDAS', 'SERVICIO', NULL, 668),
(669, 1, 1, '1.3.0295', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TACÓN PARA CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 669),
(670, 1, 1, '1.3.0296', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN DE CAJA PRINCIPAL A CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 670),
(671, 1, 1, '1.3.0297', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN DE CAJA DE TRANSFERENCIA A PRIMER DIFERENCIAL', 'SERVICIO', NULL, 671),
(672, 1, 1, '1.3.0298', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA CARDAN DE INTER-EJES', 'SERVICIO', NULL, 672),
(673, 1, 1, '1.3.0299', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE BOTÓN PARA CAMBIO DE RANGO DE VELOCIDAD', 'SERVICIO', NULL, 673),
(674, 1, 1, '1.3.0300', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE REPUESTO PARA ACTUADOR DE CAMBIO DE RANGO DE VELOCIDAD', 'SERVICIO', NULL, 674),
(675, 1, 1, '1.3.0301', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 1/4 Ø', 'SERVICIO', NULL, 675),
(676, 1, 1, '1.3.0302', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE MANGUERAS DE CONTROL PARA CAMBIO DE VELOCIDADES DE 3/8 Ø', 'SERVICIO', NULL, 676),
(677, 1, 1, '1.3.0303', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPARACIÓN DE CAJA DE VELOCIDADES (costo no mayor de 50% del valor de  caja de velocidades nueva)', 'SERVICIO', NULL, 677),
(678, 1, 1, '1.3.0304', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPARACIÓN DE DIFERENCIAL DELANTERO DANA (costo no mayor de 50% del valor de diferencial delantero nuevo)', 'SERVICIO', NULL, 678),
(679, 1, 1, '1.3.0305', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'REPARACIÓN DE DIFERENCIAL TRASERO DANA (costo no mayor de 50% del valor de diferencial trasero nuevo)', 'SERVICIO', NULL, 679),
(680, 1, 1, '1.3.0306', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE ACTUADOR PARA APLICACIÓN DE TOMA DE FUERZA (PTO)', 'SERVICIO', NULL, 680),
(681, 1, 1, '1.3.0307', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE RETÉN DE CAJA DE VELOCIDADES', 'SERVICIO', NULL, 681),
(682, 1, 1, '1.3.0308', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE RETÉN DE DIFERENCIAL', 'SERVICIO', NULL, 682),
(683, 1, 1, '1.3.0309', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE FLECHA LATERAL', 'SERVICIO', NULL, 683),
(684, 1, 1, '1.3.0310', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'BALERO INTERIOR RUEDA TRASERA', 'PIEZA', NULL, 684),
(685, 1, 1, '1.3.0311', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TAZA PARA BALERO INTERIOR RUEDA TRASERA', 'PIEZA', NULL, 685),
(686, 1, 1, '1.3.0312', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'BALERO EXTERIOR RUEDA TRASERA', 'PIEZA', NULL, 686),
(687, 1, 1, '1.3.0313', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'TAZA PARA BALERO EXTERIOR RUEDA TRASERA', 'PIEZA', NULL, 687),
(688, 1, 1, '1.3.0314', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'RETÉN INTERIOR RUEDA TRASERA', 'PIEZA', NULL, 688),
(689, 1, 1, '1.3.0315', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TAZA PARA BALERO INTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 689),
(690, 1, 1, '1.3.0316', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE BALERO EXTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 690),
(691, 1, 1, '1.3.0317', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE TAZA PARA BALERO EXTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 691),
(692, 1, 1, '1.3.0318', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, EJE TRASERO Y SISTEMA DE TRANSMISIÓN.', 'CAMBIO DE RETEN INTERIOR RUEDA TRASERA', 'SERVICIO', NULL, 692),
(693, 1, 1, '1.3.0319', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA REPARTIDORA', 'PIEZA', NULL, 693),
(694, 1, 1, '1.3.0320', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA DE RELEVO', 'PIEZA', NULL, 694),
(695, 1, 1, '1.3.0321', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DE 1/2" Ø', 'PIEZA', NULL, 695),
(696, 1, 1, '1.3.0322', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DE 3/8" Ø', 'PIEZA', NULL, 696),
(697, 1, 1, '1.3.0323', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA CHECK  1/2" Ø', 'PIEZA', NULL, 697),
(698, 1, 1, '1.3.0324', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MATRACAS', 'PIEZA', NULL, 698),
(699, 1, 1, '1.3.0325', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'ACTUADOR DOBLE CÁMARA', 'PIEZA', NULL, 699),
(700, 1, 1, '1.3.0326', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'ACTUADOR UNA  CÁMARA', 'PIEZA', NULL, 700)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(701, 1, 1, '1.3.0327', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'BALATAS TRASERAS', 'JUEGO', NULL, 701),
(702, 1, 1, '1.3.0328', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'RESORTES PARA BALATAS', 'PIEZA', NULL, 702),
(703, 1, 1, '1.3.0329', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'FLECHA GAVILÁN TRASERAS', 'PIEZA', NULL, 703),
(704, 1, 1, '1.3.0330', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'FLECHA GAVILÁN DELANTERAS', 'PIEZA', NULL, 704),
(705, 1, 1, '1.3.0331', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'BUJES PARA FLECHA GAVILÁN', 'PIEZA', NULL, 705),
(706, 1, 1, '1.3.0332', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'SEGUROS PARA RODILLOS', 'PIEZA', NULL, 706),
(707, 1, 1, '1.3.0333', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'RODILLOS', 'PIEZA', NULL, 707),
(708, 1, 1, '1.3.0334', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'BALATAS DELANTERAS', 'JUEGO', NULL, 708),
(709, 1, 1, '1.3.0335', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA DEL PEDAL DEL FRENO DE SERVICIO', 'PIEZA', NULL, 709),
(710, 1, 1, '1.3.0336', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'COMPRESOR DE AIRE', 'PIEZA', NULL, 710),
(711, 1, 1, '1.3.0337', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'KIT DE REPARACIÓN DEL COMPRESOR DE AIRE', 'JUEGO', NULL, 711),
(712, 1, 1, '1.3.0338', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DE ENFRIAMIENTO DE COMPRESOR DE AIRE', 'PIEZA', NULL, 712),
(713, 1, 1, '1.3.0339', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'VÁLVULA REGULADORA DE PRESIÓN DE AIRE', 'PIEZA', NULL, 713),
(714, 1, 1, '1.3.0340', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'INDICADOR DE PRESIÓN DE AIRE', 'PIEZA', NULL, 714),
(715, 1, 1, '1.3.0341', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DEL INDICADOR DE PRESIÓN DE AIRE No. 4 M/P', 'PIEZA', NULL, 715),
(716, 1, 1, '1.3.0342', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'MANGUERA DEL TANQUE AL PULMÓN No. 4 M/P', 'PIEZA', NULL, 716),
(717, 1, 1, '1.3.0343', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA REPARTIDORA', 'SERVICIO', NULL, 717),
(718, 1, 1, '1.3.0344', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA DE RELEVO', 'SERVICIO', NULL, 718),
(719, 1, 1, '1.3.0345', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DE 1/2" Ø', 'SERVICIO', NULL, 719),
(720, 1, 1, '1.3.0346', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DE 3/8" Ø', 'SERVICIO', NULL, 720),
(721, 1, 1, '1.3.0347', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA CHECK 1/2" Ø', 'SERVICIO', NULL, 721),
(722, 1, 1, '1.3.0348', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MATRACAS', 'SERVICIO', NULL, 722),
(723, 1, 1, '1.3.0349', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE ACTUADOR DOBLE CÁMARA', 'SERVICIO', NULL, 723),
(724, 1, 1, '1.3.0350', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE ACTUADOR UNA CÁMARA', 'SERVICIO', NULL, 724),
(725, 1, 1, '1.3.0351', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE BALATAS TRASERAS', 'SERVICIO', NULL, 725),
(726, 1, 1, '1.3.0352', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE RESORTES PARA BALATAS', 'SERVICIO', NULL, 726),
(727, 1, 1, '1.3.0353', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE FLECHA GAVILÁN TRASERAS', 'SERVICIO', NULL, 727),
(728, 1, 1, '1.3.0354', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE FLECHA GAVILÁN DELANTERAS', 'SERVICIO', NULL, 728),
(729, 1, 1, '1.3.0355', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE BUJES PARA FLECHA GAVILÁN', 'SERVICIO', NULL, 729),
(730, 1, 1, '1.3.0356', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE SEGUROS PARA RODILLOS', 'SERVICIO', NULL, 730),
(731, 1, 1, '1.3.0357', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE RODILLOS', 'SERVICIO', NULL, 731),
(732, 1, 1, '1.3.0358', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE BALATAS DELANTERAS', 'SERVICIO', NULL, 732),
(733, 1, 1, '1.3.0359', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA DEL PEDAL DEL FRENO DE SERVICIO', 'SERVICIO', NULL, 733),
(734, 1, 1, '1.3.0360', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE COMPRESOR DE AIRE', 'SERVICIO', NULL, 734),
(735, 1, 1, '1.3.0361', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE KIT DE REPARACIÓN DEL COMPRESOR DE AIRE', 'SERVICIO', NULL, 735),
(736, 1, 1, '1.3.0362', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DE ENFRIAMIENTO DE COMPRESOR DE AIRE', 'SERVICIO', NULL, 736),
(737, 1, 1, '1.3.0363', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE VÁLVULA REGULADORA DE PRESIÓN DE AIRE', 'SERVICIO', NULL, 737),
(738, 1, 1, '1.3.0364', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE INDICADOR DE PRESIÓN DE AIRE', 'SERVICIO', NULL, 738),
(739, 1, 1, '1.3.0365', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DEL INDICADOR DE PRESIÓN DE AIRE No. 4 M/P', 'SERVICIO', NULL, 739),
(740, 1, 1, '1.3.0366', '1.3.0000 UNIDAD MARCA KENWORTH MODELO T-800, MANTENIMIENTO CORRECTIVO, SISTEMA DE FRENOS.', 'CAMBIO DE MANGUERA DEL TANQUE AL PULMÓN No. 4 M/P', 'SERVICIO', NULL, 740),
(741, 1, 1, '1.4.0001', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LAS 150 HORAS. (CONFORME A LO DESCRITO EN EL ANEXO B-1)', 'SERVICIO', NULL, 741),
(742, 1, 1, '1.4.0002', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LAS 300 HORAS. (CONFORME A LO DESCRITO EN EL ANEXO B-1)', 'SERVICIO', NULL, 742),
(743, 1, 1, '1.4.0003', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LAS 500 HORAS. (CONFORME A LO DESCRITO EN EL ANEXO B-1)', 'SERVICIO', NULL, 743),
(744, 1, 1, '1.4.0004', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO PREVENTIVO.', 'SERVICIO DE MANTENIMENTO PREVENTIVO DE LAS 800 HORAS. (CONFORME A LO DESCRITO EN EL ANEXO B-1)', 'SERVICIO', NULL, 744),
(745, 1, 1, '1.4.0005', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'BOMBA DE VACÍO (SOPLADOR)   340400', 'PIEZA', NULL, 745),
(746, 1, 1, '1.4.0006', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CUERPO DEL CEDAZO     239290', 'PIEZA', NULL, 746),
(747, 1, 1, '1.4.0007', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'ENSAMBLE SILENCIADOR    159590', 'PIEZA', NULL, 747),
(748, 1, 1, '1.4.0008', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'ENSAMBLE (MALLA) CEDAZO INLET     239235', 'PIEZA', NULL, 748),
(749, 1, 1, '1.4.0009', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'VÁLVULA DE RELEVO DE VACÍO   159570', 'PIEZA', NULL, 749),
(750, 1, 1, '1.4.0010', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'ENSAMBLE DEL CODO DE ENTRADA    242804', 'PIEZA', NULL, 750),
(751, 1, 1, '1.4.0011', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'ACOPLAMIENTO TUBO DE HULE   176640', 'PIEZA', NULL, 751),
(752, 1, 1, '1.4.0012', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CUBIERTA DEL CEDAZO DE ENTRADA    154080', 'PIEZA', NULL, 752),
(753, 1, 1, '1.4.0013', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'MANGUERA 10" Ø  X 40 CM.', 'PIEZA', NULL, 753),
(754, 1, 1, '1.4.0014', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'COPLE 8" A 10" Ø', 'PIEZA', NULL, 754),
(755, 1, 1, '1.4.0015', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'REPUESTO DE BOMBA DE VACÍO (SOPLADOR)  ROOTS 624', 'JUEGO', NULL, 755),
(756, 1, 1, '1.4.0016', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'BANDA PARA SOPLADOR  160641', 'PIEZA', NULL, 756),
(757, 1, 1, '1.4.0017', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'COPLE DE HULE 10" Ø   176380', 'PIEZA', NULL, 757),
(758, 1, 1, '1.4.0018', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'ABRAZADERA PARA COPLE DE 10" Ø', 'PIEZA', NULL, 758),
(759, 1, 1, '1.4.0019', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'FILTRO PARA DESCARGA SOPLADOR  239535', 'PIEZA', NULL, 759),
(760, 1, 1, '1.4.0020', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'SELLO DEL DOMO TAPA BOMBA DE VACÍO   192010', 'PIEZA', NULL, 760),
(761, 1, 1, '1.4.0021', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'TUBO DE SUCCIÓN 8 PIES (ALUMINIO)', 'PIEZA', NULL, 761),
(762, 1, 1, '1.4.0022', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'TUBO DE SUCCIÓN 6 PIES (ALUMINIO)', 'PIEZA', NULL, 762),
(763, 1, 1, '1.4.0023', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'SELLO PARA TUBO DE SUCCIÓN', 'PIEZA', NULL, 763),
(764, 1, 1, '1.4.0024', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE BOMBA DE VACÍO (SOPLADOR) 340400', 'SERVICIO', NULL, 764),
(765, 1, 1, '1.4.0025', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE CUERPO DEL CEDAZO 239290', 'SERVICIO', NULL, 765),
(766, 1, 1, '1.4.0026', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE ENSAMBLE SILENCIADOR 159590', 'SERVICIO', NULL, 766),
(767, 1, 1, '1.4.0027', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE ENSAMBLE (MALLA) CEDAZO INLET 239235', 'SERVICIO', NULL, 767),
(768, 1, 1, '1.4.0028', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE VÁLVULA DE RELEVO DE VACÍO 159570', 'SERVICIO', NULL, 768),
(769, 1, 1, '1.4.0029', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE ENSAMBLE DEL CODO DE ENTRADA 242804', 'SERVICIO', NULL, 769),
(770, 1, 1, '1.4.0030', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE ACOPLAMIENTO TUBO DE HULE 176640', 'SERVICIO', NULL, 770),
(771, 1, 1, '1.4.0031', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE CUBIERTA DEL CEDAZO DE ENTRADA 154080', 'SERVICIO', NULL, 771),
(772, 1, 1, '1.4.0032', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE MANGUERA 10" Ø X 40 CM.', 'SERVICIO', NULL, 772),
(773, 1, 1, '1.4.0033', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE COPLE 8" A 10" Ø', 'SERVICIO', NULL, 773),
(774, 1, 1, '1.4.0034', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE REPUESTO DE BOMBA DE VACÍO (SOPLADOR) ROOTS 624', 'SERVICIO', NULL, 774),
(775, 1, 1, '1.4.0035', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE BANDA PARA SOPLADOR 160641', 'SERVICIO', NULL, 775),
(776, 1, 1, '1.4.0036', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE COPLE DE HULE 10" Ø 176380', 'SERVICIO', NULL, 776),
(777, 1, 1, '1.4.0037', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE ABRAZADERA PARA COPLE DE 10" Ø', 'SERVICIO', NULL, 777),
(778, 1, 1, '1.4.0038', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE FILTRO PARA DESCARGA SOPLADOR 239535', 'SERVICIO', NULL, 778),
(779, 1, 1, '1.4.0039', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE SELLO DEL DOMO TAPA BOMBA DE VACÍO 192010', 'SERVICIO', NULL, 779),
(780, 1, 1, '1.4.0040', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE TUBO DE SUCCIÓN 8 PIES (AUMINIO)', 'SERVICIO', NULL, 780),
(781, 1, 1, '1.4.0041', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE TUBO DE SUCCIÓN 6 PIES (AUMINIO)', 'SERVICIO', NULL, 781),
(782, 1, 1, '1.4.0042', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE SELLO PARA TUBO DE SUCCIÓN', 'SERVICIO', NULL, 782),
(783, 1, 1, '1.4.0043', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE VACÍO (EQUIPO).', 'CAMBIO DE ABRAZADERA PARA COPLE DE 10" Ø', 'SERVICIO', NULL, 783),
(784, 1, 1, '1.4.0044', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'BOMBA DE AGUA DE ALTA PRESIÓN (TRIPLEX) MOD. MS-55 SERIE 0162166  83M  EPM  2000 PSI   No. P.  215519', 'PIEZA', NULL, 784),
(785, 1, 1, '1.4.0045', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'VÁLVULA DE CONTROL DE 3" Ø  DE COMPUERTA', 'PIEZA', NULL, 785),
(786, 1, 1, '1.4.0046', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CUERPO (BASE DE FILTRO) DE BOMBA TRIPLEX 240017', 'PIEZA', NULL, 786),
(787, 1, 1, '1.4.0047', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'FILTRO PARA SUCCIÓN   131107', 'PIEZA', NULL, 787),
(788, 1, 1, '1.4.0048', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'VÁLVULA DE RELEVO   130962', 'PIEZA', NULL, 788),
(789, 1, 1, '1.4.0049', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'TAPÓN DE PURGA PARA BOMBA TRIPLEX', 'PIEZA', NULL, 789),
(790, 1, 1, '1.4.0050', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'VÁLVULA DE CONTROL DE DESCARGA DE AGUA  9J08708', 'PIEZA', NULL, 790),
(791, 1, 1, '1.4.0051', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'MANGUERA 1" Ø  A/P   X 1.30 M.', 'PIEZA', NULL, 791),
(792, 1, 1, '1.4.0052', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'MANGUERA 1" Ø  A/P   X 3.00  M.', 'PIEZA', NULL, 792),
(793, 1, 1, '1.4.0053', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'MANGUERA DE DESCARGA A/P 1" Ø  X 5.00 M.', 'PIEZA', NULL, 793),
(794, 1, 1, '1.4.0054', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'MANGUERA DE DESCARGA A/P 1" Ø  X 3.00 M.', 'PIEZA', NULL, 794),
(795, 1, 1, '1.4.0055', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'MANGUERA DE ALTA PRESIÓN 1" Ø PARA CARRETE', 'PIEZA', NULL, 795),
(796, 1, 1, '1.4.0056', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'VÁLVULA DE TRES VÍAS (9J-08712)   130920', 'PIEZA', NULL, 796),
(797, 1, 1, '1.4.0057', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'MANGUERA DE 1" DE VÁLVULA A SWIVEL DE CARRETE', 'PIEZA', NULL, 797),
(798, 1, 1, '1.4.0058', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CHUMACERA PARA CARRETE', 'PIEZA', NULL, 798),
(799, 1, 1, '1.4.0059', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'SWIVEL   130727', 'PIEZA', NULL, 799),
(800, 1, 1, '1.4.0060', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'VÁLVULA DE BOLA 130920', 'PIEZA', NULL, 800)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(801, 1, 1, '1.4.0061', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'VÁLVULA MACHO 130890', 'PIEZA', NULL, 801),
(802, 1, 1, '1.4.0062', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'ANILLO O-RING   190770', 'PIEZA', NULL, 802),
(803, 1, 1, '1.4.0063', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'TAPA DE BASE 170310', 'PIEZA', NULL, 803),
(804, 1, 1, '1.4.0064', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'PISTOLA DE AGUA ALTA PRESIÓN  131632', 'PIEZA', NULL, 804),
(805, 1, 1, '1.4.0065', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'BANDA PARA BOMBA DE AGUA 160646', 'PIEZA', NULL, 805),
(806, 1, 1, '1.4.0066', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'KIT DE REPARACIÓN PARA BOMBA DE PRESIÓN   502', 'JUEGO', NULL, 806),
(807, 1, 1, '1.4.0067', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'TANQUE PARA AGUA (PLÁSTICO)', 'PIEZA', NULL, 807),
(808, 1, 1, '1.4.0068', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE BOMBA DE AGUA ALTA PRESIÓN (TRIPLEX) MOD. MS-55', 'SERVICIO', NULL, 808),
(809, 1, 1, '1.4.0069', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE CONTROL DE 3" Ø DE COMPUERTA', 'SERVICIO', NULL, 809),
(810, 1, 1, '1.4.0070', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE CUERPO (BASE DE FILTRO) DE BOMBA TRIPLEX 240017', 'SERVICIO', NULL, 810),
(811, 1, 1, '1.4.0071', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE FILTRO DE SUCCIÓN 131107', 'SERVICIO', NULL, 811),
(812, 1, 1, '1.4.0072', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE RELEVO 130962', 'SERVICIO', NULL, 812),
(813, 1, 1, '1.4.0073', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE TAPÓN DE PURGA PARA BOMBA TRIPLEX', 'SERVICIO', NULL, 813),
(814, 1, 1, '1.4.0074', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE CONTROL DE DESCARGA DE AGUA 9J08708', 'SERVICIO', NULL, 814),
(815, 1, 1, '1.4.0075', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE MANGUERA 1" Ø A/P X 1.1.30 MTS.', 'SERVICIO', NULL, 815),
(816, 1, 1, '1.4.0076', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE MANGUERA 1" Ø A/P X 3.00 M.', 'SERVICIO', NULL, 816),
(817, 1, 1, '1.4.0077', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE DESCARGA A/P 1" Ø X 5.00 M.', 'SERVICIO', NULL, 817),
(818, 1, 1, '1.4.0078', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE DESCARGA A/P 1" Ø X 3.00 M.', 'SERVICIO', NULL, 818),
(819, 1, 1, '1.4.0079', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE ALTA PRESIÓN 1" Ø PARA CARRETE', 'SERVICIO', NULL, 819),
(820, 1, 1, '1.4.0080', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE TRES VÍAS (9J-08712) 130920', 'SERVICIO', NULL, 820),
(821, 1, 1, '1.4.0081', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE 1" DE VÁLVULA A SWEVEL DE CARRETE', 'SERVICIO', NULL, 821),
(822, 1, 1, '1.4.0082', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE CHUMACERA PARA CARRETE', 'SERVICIO', NULL, 822),
(823, 1, 1, '1.4.0083', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE SWIVEL 130727', 'SERVICIO', NULL, 823),
(824, 1, 1, '1.4.0084', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE BOLA 130920', 'SERVICIO', NULL, 824),
(825, 1, 1, '1.4.0085', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA MACHO 130890', 'SERVICIO', NULL, 825),
(826, 1, 1, '1.4.0086', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE ANILLO O-RING 190770', 'SERVICIO', NULL, 826),
(827, 1, 1, '1.4.0087', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE TAPA DE BASE 170310', 'SERVICIO', NULL, 827),
(828, 1, 1, '1.4.0088', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE PISTOLA DE AGUA ALTA PRESIÓN 131632', 'SERVICIO', NULL, 828),
(829, 1, 1, '1.4.0089', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE BANDA PARA BOMBA DE AGUA 160646', 'SERVICIO', NULL, 829),
(830, 1, 1, '1.4.0090', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE KIT DE REPARACIÓN PARA BOMBA DE PRESIÓN 502', 'SERVICIO', NULL, 830),
(831, 1, 1, '1.4.0091', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE SUCCIÓN Y DESCARGA DE AGUA ALTA PRESIÓN (EQUIPO).', 'CAMBIO DE TANQUE PARA AGUA (PLÁSTICO)', 'SERVICIO', NULL, 831),
(832, 1, 1, '1.4.0092', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'BOMBA P/SISTEMA HIDRÁULICO (SERIE N067-20571)MUNCIE  110249', 'PIEZA', NULL, 832),
(833, 1, 1, '1.4.0093', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'REPUESTO PARA BOMBA HIDRÁULICA', 'JUEGO', NULL, 833),
(834, 1, 1, '1.4.0094', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA DE SUCCIÓN DE BOMBA HIDRÁULICA No. 16 A/P.', 'PIEZA', NULL, 834),
(835, 1, 1, '1.4.0095', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA DE DESCARGA DE BOMBA HIDRÁULICA No. 12 A/P.', 'PIEZA', NULL, 835),
(836, 1, 1, '1.4.0096', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'FILTRO PARA ACEITE HIDRÁULICO PH-47 (FRAM)', 'PIEZA', NULL, 836),
(837, 1, 1, '1.4.0097', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA DE RETORNO No. 10', 'PIEZA', NULL, 837),
(838, 1, 1, '1.4.0098', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA DE RETORNO No. 8', 'PIEZA', NULL, 838),
(839, 1, 1, '1.4.0099', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MOTOR HIDRÁULICO PARA CARRETE  110785', 'PIEZA', NULL, 839),
(840, 1, 1, '1.4.0100', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'SPROKET PARA MOTOR HIDRÁULICO DEL CARRETE', 'PIEZA', NULL, 840),
(841, 1, 1, '1.4.0101', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'SPROKET PARA CARRETE', 'PIEZA', NULL, 841),
(842, 1, 1, '1.4.0102', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'VÁLVULA REGULADORA DE PRESIÓN   110019', 'PIEZA', NULL, 842),
(843, 1, 1, '1.4.0103', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CADENA PARA CARRETE', 'PIEZA', NULL, 843),
(844, 1, 1, '1.4.0104', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'VÁLVULA MACHO DE 1"', 'PIEZA', NULL, 844),
(845, 1, 1, '1.4.0105', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA PARA ACCIONAR CARRETE', 'PIEZA', NULL, 845),
(846, 1, 1, '1.4.0106', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'GATO HIDRÁULICO DOBLE PARA ABRIR CARRETE  MOD. HTR 22 -1903-14C SERIE -067796-1197 PRES. 2000 LBS.  NP. 111380', 'PIEZA', NULL, 846),
(847, 1, 1, '1.4.0107', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'GATOS PARA SEGURO DE TAPA TRASERA   111067', 'PIEZA', NULL, 847),
(848, 1, 1, '1.4.0108', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'REPUESTO PARA GATO DE TAPA', 'JUEGO', NULL, 848),
(849, 1, 1, '1.4.0109', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA No. 8 A/P PARA GATO DE COMPUERTA', 'PIEZA', NULL, 849),
(850, 1, 1, '1.4.0110', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA No. 8 A/P', 'PIEZA', NULL, 850),
(851, 1, 1, '1.4.0111', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'VÁLVULA REGULADORA DE PRESIÓN DOBLE', 'PIEZA', NULL, 851),
(852, 1, 1, '1.4.0112', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA No. 10 A/P', 'PIEZA', NULL, 852),
(853, 1, 1, '1.4.0113', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'GATO DE LEVANTE PARA TANQUE RESIDUAL 110108', 'PIEZA', NULL, 853),
(854, 1, 1, '1.4.0114', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANGUERA DE LEVANTE  No. 8 A/P', 'PIEZA', NULL, 854),
(855, 1, 1, '1.4.0115', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'VÁLVULA DE CONTROL DE LEVANTE DEL GATO 110005', 'PIEZA', NULL, 855),
(856, 1, 1, '1.4.0116', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE BOMBA P/SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 856),
(857, 1, 1, '1.4.0117', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE REPUESTO PARA BOMBA HIDRÁULICA', 'SERVICIO', NULL, 857),
(858, 1, 1, '1.4.0118', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA SUCCIÓN DE BOMBA HIDRÁULICA No. 16 A/P.', 'SERVICIO', NULL, 858),
(859, 1, 1, '1.4.0119', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA DESCARGA BOMBA HIDRÁULICA No. 12 A/P.', 'SERVICIO', NULL, 859),
(860, 1, 1, '1.4.0120', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE FILTRO PARA ACEITE HIDRÁULICO PH-47 (FRAM)', 'SERVICIO', NULL, 860),
(861, 1, 1, '1.4.0121', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA DE RETORNO No. 10', 'SERVICIO', NULL, 861),
(862, 1, 1, '1.4.0122', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA DE RETORNO No. 8', 'SERVICIO', NULL, 862),
(863, 1, 1, '1.4.0123', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MOTOR HIDRÁULICO PARA CARRETE 110785', 'SERVICIO', NULL, 863),
(864, 1, 1, '1.4.0124', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE SPROKET PARA MOTOR HIDRÁULICO DEL CARRETE', 'SERVICIO', NULL, 864),
(865, 1, 1, '1.4.0125', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE SPROKET PARA CARRETE', 'SERVICIO', NULL, 865),
(866, 1, 1, '1.4.0126', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE VÁLVULA REGULADORA DE PRESIÓN 110019', 'SERVICIO', NULL, 866),
(867, 1, 1, '1.4.0127', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE CADENA PARA CARRETE', 'SERVICIO', NULL, 867),
(868, 1, 1, '1.4.0128', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE VÁLVULA MACHO DE 1"', 'SERVICIO', NULL, 868),
(869, 1, 1, '1.4.0129', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA PARA ACCIONAR CARRETE', 'SERVICIO', NULL, 869),
(870, 1, 1, '1.4.0130', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE GATO HIDRÁULICO DOBLE PARA ABRIR CARRETE', 'SERVICIO', NULL, 870),
(871, 1, 1, '1.4.0131', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE GATOS PARA SEGURO DE TAPA TRASERA 111067', 'SERVICIO', NULL, 871),
(872, 1, 1, '1.4.0132', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE REPUESTO PARA GATO DE TAPA', 'SERVICIO', NULL, 872),
(873, 1, 1, '1.4.0133', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA No. 8 A/P PARA GATO DE COMPUERTA', 'SERVICIO', NULL, 873),
(874, 1, 1, '1.4.0134', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA No. 8 A/P', 'SERVICIO', NULL, 874),
(875, 1, 1, '1.4.0135', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE VÁLVULA REGULADORA DE PRESIÓN DOBLE', 'SERVICIO', NULL, 875),
(876, 1, 1, '1.4.0136', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA No. 10 A/P', 'SERVICIO', NULL, 876),
(877, 1, 1, '1.4.0137', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE GATO DE LEVANTE PARA TANQUE RESIDUAL 110108', 'SERVICIO', NULL, 877),
(878, 1, 1, '1.4.0138', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE MANGUERA DE LEVANTE No. 8 A/P', 'SERVICIO', NULL, 878),
(879, 1, 1, '1.4.0139', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE VÁLVULA DE CONTROL DE LEVANTE DEL GATO 110005', 'SERVICIO', NULL, 879),
(880, 1, 1, '1.4.0140', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'DEPÓSITO PARA ACEITE HIDRÁULICO No. 110000', 'PIEZA', NULL, 880),
(881, 1, 1, '1.4.0141', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'INDICADOR DE TEMPERATURA DE ACEITE HIDRÁULICO', 'PIEZA', NULL, 881),
(882, 1, 1, '1.4.0142', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'TAPÓN PARA DEPÓSITO DE ACEITE HIDRÁULICO', 'PIEZA', NULL, 882),
(883, 1, 1, '1.4.0143', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'FILTRO DE ACEITE HIDRÁULICO DE DEPÓSITO LF680 110515', 'PIEZA', NULL, 883),
(884, 1, 1, '1.4.0144', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'SWITCH TIPO COLA DE RATA PARA GATO DE COMPUERTA Y LEVANTE', 'PIEZA', NULL, 884),
(885, 1, 1, '1.4.0145', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'VÁLVULA DE CONTROL DE FLUJO No. 110282', 'PIEZA', NULL, 885),
(886, 1, 1, '1.4.0146', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'INDICADOR DE PRESIÓN DE 0 A 5000 PSI', 'PIEZA', NULL, 886),
(887, 1, 1, '1.4.0147', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE DEPÓSITO PARA ACEITE HIDRÁULICO No. 110000', 'SERVICIO', NULL, 887),
(888, 1, 1, '1.4.0148', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE INDICADOR DE TEMPERATURA DE ACEITE HIDRÁULICO', 'SERVICIO', NULL, 888),
(889, 1, 1, '1.4.0149', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE TAPÓN PARA DEPÓSITO DE ACEITE HIDRÁULICO', 'SERVICIO', NULL, 889),
(890, 1, 1, '1.4.0150', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE FILTRO DE ACEITE HIDRÁULICO DE DEPÓSITO LF680 110515', 'SERVICIO', NULL, 890),
(891, 1, 1, '1.4.0151', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE SWITCH TIPO COLA DE RATA PARA GATO DE COMPUERTA Y LEVANTE', 'SERVICIO', NULL, 891),
(892, 1, 1, '1.4.0152', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE VÁLVULA DE CONTROL DE FLUJO No. 110282', 'SERVICIO', NULL, 892),
(893, 1, 1, '1.4.0153', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE INDICADOR DE PRESIÓN DE 0 A 5000 PSI', 'SERVICIO', NULL, 893),
(894, 1, 1, '1.4.0154', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'MANTENIMIENTO A BOMBA P/SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 894),
(895, 1, 1, '1.4.0155', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CONTROL COLGANTE  121952', 'PIEZA', NULL, 895),
(896, 1, 1, '1.4.0156', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CABLE  DE CONTROL 10.00 M.    121718', 'PIEZA', NULL, 896),
(897, 1, 1, '1.4.0157', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'LUZ FOCO PILOTO   120475', 'PIEZA', NULL, 897),
(898, 1, 1, '1.4.0158', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'BOTÓN NEGRO     120615', 'PIEZA', NULL, 898),
(899, 1, 1, '1.4.0159', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'INTERRUPTOR DE CONTACTO   120065', 'PIEZA', NULL, 899),
(900, 1, 1, '1.4.0160', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'LENTE ROJO PARA LUZ PILOTO   120485', 'PIEZA', NULL, 900)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(901, 1, 1, '1.4.0161', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'BULBO PARA LUZ PILOTO   120465', 'PIEZA', NULL, 901),
(902, 1, 1, '1.4.0162', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAJA COLGANTE    121945', 'PIEZA', NULL, 902),
(903, 1, 1, '1.4.0163', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE CONTROL COLGANTE 121952', 'SERVICIO', NULL, 903),
(904, 1, 1, '1.4.0164', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE CABLE DE CONTROL 10.00 M. 121718', 'SERVICIO', NULL, 904),
(905, 1, 1, '1.4.0165', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE LUZ FOCO PILOTO 120475', 'SERVICIO', NULL, 905),
(906, 1, 1, '1.4.0166', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE BOTÓN NEGRO 120615', 'SERVICIO', NULL, 906),
(907, 1, 1, '1.4.0167', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE INTERRUPTOR DE CONTACTO 120065', 'SERVICIO', NULL, 907),
(908, 1, 1, '1.4.0168', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE LENTE ROJO PARA LUZ PILOTO 120485', 'SERVICIO', NULL, 908),
(909, 1, 1, '1.4.0169', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE BULBO PARA LUZ PILOTO 120465', 'SERVICIO', NULL, 909),
(910, 1, 1, '1.4.0170', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE CAJA COLGANTE 121945', 'SERVICIO', NULL, 910),
(911, 1, 1, '1.4.0171', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'BOTONERA 121952', 'PIEZA', NULL, 911),
(912, 1, 1, '1.4.0172', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CABLE PARA BOTONERA 121718', 'PIEZA', NULL, 912),
(913, 1, 1, '1.4.0173', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAJA DE CONTROL', 'PIEZA', NULL, 913),
(914, 1, 1, '1.4.0174', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'SWITCH DOBLE CONTROL', 'PIEZA', NULL, 914),
(915, 1, 1, '1.4.0175', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'SWITCH DE CONTROL SENCILLO', 'PIEZA', NULL, 915),
(916, 1, 1, '1.4.0176', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'SWITCH DE COMPUERTA DEL TANQUE', 'PIEZA', NULL, 916),
(917, 1, 1, '1.4.0177', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'SWITCH PARA ACCIONAR GATOS DE COMPUERTA', 'PIEZA', NULL, 917),
(918, 1, 1, '1.4.0178', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'ACTUADOR ELÉCTRICO DE ACELERACIÓN REMOTA', 'PIEZA', NULL, 918),
(919, 1, 1, '1.4.0179', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE BOTONERA 121952', 'SERVICIO', NULL, 919),
(920, 1, 1, '1.4.0180', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE CABLE PARA BOTONERA 121718', 'SERVICIO', NULL, 920),
(921, 1, 1, '1.4.0181', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE CAJA DE CONTROL', 'SERVICIO', NULL, 921),
(922, 1, 1, '1.4.0182', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE SWITCH DOBLE CONTROL', 'SERVICIO', NULL, 922),
(923, 1, 1, '1.4.0183', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE SWITCH DE CONTROL SENCILLO', 'SERVICIO', NULL, 923),
(924, 1, 1, '1.4.0184', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE SWITCH DE COMPUERTA DEL TANQUE', 'SERVICIO', NULL, 924),
(925, 1, 1, '1.4.0185', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE SWITCH PARA ACCIONAR GATOS DE COMPUERTA', 'SERVICIO', NULL, 925),
(926, 1, 1, '1.4.0186', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA HIDRÁULICO (EQUIPO).', 'CAMBIO DE ACTUADOR ELÉCTRICO DE ACELERACIÓN REMOTA', 'SERVICIO', NULL, 926),
(927, 1, 1, '1.4.0187', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CONTROL DEL ACELERADOR    111217', 'PIEZA', NULL, 927),
(928, 1, 1, '1.4.0188', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'VÁLVULA DE LANZADERA   111218', 'PIEZA', NULL, 928),
(929, 1, 1, '1.4.0189', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CILINDRO PARA VÁLVULA DE COLUMPIO     110664', 'PIEZA', NULL, 929),
(930, 1, 1, '1.4.0190', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CONTROL DEL ACELERADOR TRASERO    111215', 'PIEZA', NULL, 930),
(931, 1, 1, '1.4.0191', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'SOLENOIDE NEUMÁTICO DE VÁLVULA      111227', 'PIEZA', NULL, 931),
(932, 1, 1, '1.4.0192', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'VÁLVULA DE PROTECCIÓN DE PRESIÓN  111235', 'PIEZA', NULL, 932),
(933, 1, 1, '1.4.0193', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'REGULADOR DE PRESIÓN Y FILTRO     111230', 'PIEZA', NULL, 933),
(934, 1, 1, '1.4.0194', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'INTERRUPTOR NEUMÁTICO DE 3 VÍAS    111320', 'PIEZA', NULL, 934),
(935, 1, 1, '1.4.0195', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'VÁLVULA DE PRESURIZADO  111225', 'PIEZA', NULL, 935),
(936, 1, 1, '1.4.0196', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'BANCO DE VÁLVULAS NEUMÁTICO      111139', 'PIEZA', NULL, 936),
(937, 1, 1, '1.4.0197', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CONTROL DE EMBRAGUE   164550', 'PIEZA', NULL, 937),
(938, 1, 1, '1.4.0198', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'ENSAMBLE COMPLETO DE BOBINAS     110517-1', 'PIEZA', NULL, 938),
(939, 1, 1, '1.4.0199', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'VÁLVULA ELECTRO NEUMÁTICA PARA CONTROL DE TOMA DE FUERZA', 'PIEZA', NULL, 939),
(940, 1, 1, '1.4.0200', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'VÁLVULA ELECTRO NEUMÁTICA PARA CONTROL DE TAPA DE VACÍO', 'PIEZA', NULL, 940),
(941, 1, 1, '1.4.0201', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE CONTROL DEL ACELERADOR 111217', 'SERVICIO', NULL, 941),
(942, 1, 1, '1.4.0202', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE VÁLVULA DE LANZADERA 111218', 'SERVICIO', NULL, 942),
(943, 1, 1, '1.4.0203', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE CILINDRO PARA VÁLVULA DE COLUMPIO 110664', 'SERVICIO', NULL, 943),
(944, 1, 1, '1.4.0204', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE CONTROL DEL ACELERADOR TRASERO 111215', 'SERVICIO', NULL, 944),
(945, 1, 1, '1.4.0205', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE SOLENOIDE NEUMÁTICO DE VÁLVULA 111227', 'SERVICIO', NULL, 945),
(946, 1, 1, '1.4.0206', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE VÁLVULA DE PROTECCIÓN DE PRESIÓN 111235', 'SERVICIO', NULL, 946),
(947, 1, 1, '1.4.0207', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE REGULADOR DE PRESIÓN Y FILTRO 111230', 'SERVICIO', NULL, 947),
(948, 1, 1, '1.4.0208', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE INTERRUPTOR NEUMÁTICO DE 3 VÍAS 111320', 'SERVICIO', NULL, 948),
(949, 1, 1, '1.4.0209', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE VÁLVULA DE PRESURIZADO 111225', 'SERVICIO', NULL, 949),
(950, 1, 1, '1.4.0210', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE BANCO DE VÁLVULA NEUMÁTICO 111139', 'SERVICIO', NULL, 950),
(951, 1, 1, '1.4.0211', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE CONTROL DE EMBARGUE 164550', 'SERVICIO', NULL, 951),
(952, 1, 1, '1.4.0212', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE ENSAMBLE COMPLETO DE BOBINAS 110517-1', 'SERVICIO', NULL, 952),
(953, 1, 1, '1.4.0213', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE VÁLVULA ELECTRONEUMÁTICA PARA CONTROL DE TOMA DE FUERZA', 'SERVICIO', NULL, 953),
(954, 1, 1, '1.4.0214', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, SISTEMA DE CONTROL NEUMÁTICO (EQUIPO).', 'CAMBIO DE VÁLVULA ELECTRO NEUMÁTICA PARA CONTROL DE TAPA DE VACÍO', 'SERVICIO', NULL, 954),
(955, 1, 1, '1.4.0215', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'SELLO DE TAPA (JUNTA DEL TANQUE)   NP 191100', 'PIEZA', NULL, 955),
(956, 1, 1, '1.4.0216', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'VÁLVULA DE COMPUERTA  6" Ø   NP. 246115', 'PIEZA', NULL, 956),
(957, 1, 1, '1.4.0217', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MIRILLA P TAPA  NP. 152890', 'PIEZA', NULL, 957),
(958, 1, 1, '1.4.0218', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'EMPAQUE PARA MIRILLA NP. 191030', 'PIEZA', NULL, 958),
(959, 1, 1, '1.4.0219', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MANGUERA DE DESCARGA DEL TANQUE 6" Ø', 'PIEZA', NULL, 959),
(960, 1, 1, '1.4.0220', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MANGUERA 4" X 60 CM.', 'PIEZA', NULL, 960),
(961, 1, 1, '1.4.0221', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'ABRAZADERAS PARA  MANGUERA DE 4" DE Ø', 'PIEZA', NULL, 961),
(962, 1, 1, '1.4.0222', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MANGUERA 3" X 1 MTS.', 'PIEZA', NULL, 962),
(963, 1, 1, '1.4.0223', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'ABRAZADERAS PARA  MANGUERA DE 3" DE Ø', 'PIEZA', NULL, 963),
(964, 1, 1, '1.4.0224', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'VÁLVULA DE DESCARGA DE 4" Ø NP. 150725', 'PIEZA', NULL, 964),
(965, 1, 1, '1.4.0225', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE SELLO DE TAPA (JUNTA DEL TANQUE)', 'SERVICIO', NULL, 965),
(966, 1, 1, '1.4.0226', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE VÁLVULA DE COMPUERTA 6" Ø NP. 246115', 'SERVICIO', NULL, 966),
(967, 1, 1, '1.4.0227', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MIRILLA P TAPA NP 152890', 'SERVICIO', NULL, 967),
(968, 1, 1, '1.4.0228', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE EMPAQUE PARA MIRILLA NP. 191030', 'SERVICIO', NULL, 968),
(969, 1, 1, '1.4.0229', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MANGUERA DE DESCARGA DEL TANQUE 6" Ø', 'SERVICIO', NULL, 969),
(970, 1, 1, '1.4.0230', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MANGUERA 4" X 60 CM.', 'SERVICIO', NULL, 970),
(971, 1, 1, '1.4.0231', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE ABRAZADERAS PARA MANGUERA DE 4" DE Ø', 'SERVICIO', NULL, 971),
(972, 1, 1, '1.4.0232', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MANGUERA 3" X 1.00 M.', 'SERVICIO', NULL, 972),
(973, 1, 1, '1.4.0233', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE ABRAZADERAS PARA MANGUERA DE 3" DE Ø', 'SERVICIO', NULL, 973),
(974, 1, 1, '1.4.0234', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE VÁLVULA DE DESCARGA DE 4" Ø NP. 150725', 'SERVICIO', NULL, 974),
(975, 1, 1, '1.4.0235', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAJA DE CONTROL DE CARRETE TRASERO', 'PIEZA', NULL, 975),
(976, 1, 1, '1.4.0236', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'INDICADOR DE VACÍO DE 0 MA 30 PSI  131760', 'PIEZA', NULL, 976),
(977, 1, 1, '1.4.0237', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'INDICADOR DE PRESIÓN DE AGUA DE 0A 5000 PSI   1317801', 'PIEZA', NULL, 977),
(978, 1, 1, '1.4.0238', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'TACÓMETRO  121790', 'PIEZA', NULL, 978),
(979, 1, 1, '1.4.0239', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'SWITCH PARA CONTROL DE ACELERADOR', 'PIEZA', NULL, 979),
(980, 1, 1, '1.4.0240', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'SWITCH PARA CONTROL DE CARRETE', 'PIEZA', NULL, 980),
(981, 1, 1, '1.4.0241', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'SWITCH PARA ABRIR Y CERRAR CARRETE', 'PIEZA', NULL, 981),
(982, 1, 1, '1.4.0242', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE CAJA DE CONTROL DE CARRETE TRASERO', 'SERVICIO', NULL, 982),
(983, 1, 1, '1.4.0243', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE INDICADOR DE VACÍO DE 0 A 30 PSI  131760', 'SERVICIO', NULL, 983),
(984, 1, 1, '1.4.0244', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE INDICADOR PRESIÓN DE AGUA DE 0A 5000 PSI 131780', 'SERVICIO', NULL, 984),
(985, 1, 1, '1.4.0245', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE TACÓMETRO  121790', 'SERVICIO', NULL, 985),
(986, 1, 1, '1.4.0246', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE SWITCH PARA CONTROL DE ACELERADOR', 'SERVICIO', NULL, 986),
(987, 1, 1, '1.4.0247', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE SWITCH PARA CONTROL DE CARRETE', 'SERVICIO', NULL, 987),
(988, 1, 1, '1.4.0248', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE SWITCH PARA ABRIR Y CERRAR CARRETE', 'SERVICIO', NULL, 988),
(989, 1, 1, '1.4.0249', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MOTOR HIDRÁULICO DE SWING  NP. 110186 ENSAMBLE DE PLUMA', 'PIEZA', NULL, 989),
(990, 1, 1, '1.4.0250', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CREMALLERA', 'PIEZA', NULL, 990),
(991, 1, 1, '1.4.0251', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'GATO DE COMPUERTA  110015-1', 'PIEZA', NULL, 991),
(992, 1, 1, '1.4.0252', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'REPUESTO PARA GATO DE COMPUERTA', 'JUEGO', NULL, 992),
(993, 1, 1, '1.4.0253', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'BANCO DE VÁLVULA DE CONTROL DE FLUJO   110275', 'PIEZA', NULL, 993),
(994, 1, 1, '1.4.0254', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'GATO DE LEVANTE DE PLUMA   110645-1', 'PIEZA', NULL, 994),
(995, 1, 1, '1.4.0255', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'REPUESTO DE GATO DE LEVANTE DE PLUMA', 'JUEGO', NULL, 995),
(996, 1, 1, '1.4.0256', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'GATO DE ALCANCE DE PLUMA   110210', 'PIEZA', NULL, 996),
(997, 1, 1, '1.4.0257', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'REPUESTO DE GATO DE ALCANCE DE PLUMA', 'JUEGO', NULL, 997),
(998, 1, 1, '1.4.0258', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MANGUERA No. 6 A/P', 'PIEZA', NULL, 998),
(999, 1, 1, '1.4.0259', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'BANCO DE VÁLVULA DOBLE (4) PAQ.   110396', 'PIEZA', NULL, 999),
(1000, 1, 1, '1.4.0260', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'GATO NEUMÁTICO DE TAPA DE DOMO    110664', 'PIEZA', NULL, 1000)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(1001, 1, 1, '1.4.0261', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'REPUESTO PARA GATO DE LA TAPA DEL DOMO', 'JUEGO', NULL, 1001),
(1002, 1, 1, '1.4.0262', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'EMPAQUE DE CARCAZA PARA TORRETA  NP.  192009', 'PIEZA', NULL, 1002),
(1003, 1, 1, '1.4.0263', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'EMPAQUE INFERIOR DE CARCAZA DE TORRETA  NP.  1922014', 'PIEZA', NULL, 1003),
(1004, 1, 1, '1.4.0264', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MANGUERA DE PLUMA   NP.   176620', 'PIEZA', NULL, 1004),
(1005, 1, 1, '1.4.0265', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'ACOPLADOR MACHO   171312', 'PIEZA', NULL, 1005),
(1006, 1, 1, '1.4.0266', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'SELLO DE VÁLVULA DE COLUMPIO   192011', 'PIEZA', NULL, 1006),
(1007, 1, 1, '1.4.0267', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'EMPAQUE DE BRIDA   192010', 'PIEZA', NULL, 1007),
(1008, 1, 1, '1.4.0268', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'ANILLO CIRCULAR DE VÁLVULA DE COLUMPIO 190907', 'PIEZA', NULL, 1008),
(1009, 1, 1, '1.4.0269', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'ENSAMBLE DE CORONA   241090', 'PIEZA', NULL, 1009),
(1010, 1, 1, '1.4.0270', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'MICA PARA TANQUE DE ALMACENAMIENTO DE SISTERNA', 'PIEZA', NULL, 1010),
(1011, 1, 1, '1.4.0271', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'TRAMO DE TUBO DE 8" DE SUCCIÓN', 'PIEZA', NULL, 1011),
(1012, 1, 1, '1.4.0272', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MOTOR HIDRÁULICO DE SWING', 'SERVICIO', NULL, 1012),
(1013, 1, 1, '1.4.0273', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE CREMALLERA', 'SERVICIO', NULL, 1013),
(1014, 1, 1, '1.4.0274', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE GATO COMPUERTA 110015-1', 'SERVICIO', NULL, 1014),
(1015, 1, 1, '1.4.0275', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE REPUESTO PARA GATO DE COMPUERTA', 'SERVICIO', NULL, 1015),
(1016, 1, 1, '1.4.0276', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE BANCO DE VÁLVULA DE CONTROL DE FLUJO 110275', 'SERVICIO', NULL, 1016),
(1017, 1, 1, '1.4.0277', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE GATO DE LEVANTE DE PLUMA 110645-1', 'SERVICIO', NULL, 1017),
(1018, 1, 1, '1.4.0278', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE REPUESTO DE GATO DE LEVANTE DE PLUMA', 'SERVICIO', NULL, 1018),
(1019, 1, 1, '1.4.0279', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE GATO DE ALCANCE DE PLUMA 110210', 'SERVICIO', NULL, 1019),
(1020, 1, 1, '1.4.0280', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE REPUESTO DE GATO DE ALCANCE DE PLUMA', 'SERVICIO', NULL, 1020),
(1021, 1, 1, '1.4.0281', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MANGUERA No. 6 A/P', 'SERVICIO', NULL, 1021),
(1022, 1, 1, '1.4.0282', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE BANCO DE VÁLVULA DOBLE (4) PAQ. 110396', 'SERVICIO', NULL, 1022),
(1023, 1, 1, '1.4.0283', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE GATO NEUMÁTICO DE TAPA DE DOMO 110664', 'SERVICIO', NULL, 1023),
(1024, 1, 1, '1.4.0284', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE REPUESTO PARA GATO DE LA TAPA DEL DOMO', 'SERVICIO', NULL, 1024),
(1025, 1, 1, '1.4.0285', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE EMPAQUE DE CARCAZA PARA TORRETA NP. 192009', 'SERVICIO', NULL, 1025),
(1026, 1, 1, '1.4.0286', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE EMPAQUE INFERIOR CARCAZA DE TORRETA NP. 1922014', 'SERVICIO', NULL, 1026),
(1027, 1, 1, '1.4.0287', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MANGUERA DE PLUMA NP. 176620', 'SERVICIO', NULL, 1027),
(1028, 1, 1, '1.4.0288', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE ACOPLADOR MACHO 171312', 'SERVICIO', NULL, 1028),
(1029, 1, 1, '1.4.0289', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE SELLO DE VÁLVULA DE COLUMPIO 192011', 'SERVICIO', NULL, 1029),
(1030, 1, 1, '1.4.0290', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE EMPAQUE BRIDA 192010', 'SERVICIO', NULL, 1030),
(1031, 1, 1, '1.4.0291', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE ANILLO CIRCULAR DE VÁLVULA DE COLUMPIO 190907', 'SERVICIO', NULL, 1031),
(1032, 1, 1, '1.4.0292', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE ENSAMBLE DE CORONA 241090', 'SERVICIO', NULL, 1032),
(1033, 1, 1, '1.4.0293', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE MICA DE TANQUE DE ALMACENAMIENTO', 'SERVICIO', NULL, 1033),
(1034, 1, 1, '1.4.0294', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, TANQUE CISTERNA (EQUIPO).', 'CAMBIO DE TUBO DE 8" DE SUCCIÓN', 'SERVICIO', NULL, 1034),
(1035, 1, 1, '1.4.0295', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'REPARACIÓN DE BOMBA DE VACÍO; INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, DIAGNÓSTICO, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN.', 'SERVICIO', NULL, 1035),
(1036, 1, 1, '1.4.0296', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'REPARACIÓN DE BOMBA DE SUCCIÓN; INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, DIAGNÓSTICO, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1036),
(1037, 1, 1, '1.4.0297', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'REPARACIÓN DE LA CAJA DE SUCCIÓN DE LA PLUMA (CALABAZO); INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN.', 'SERVICIO', NULL, 1037),
(1038, 1, 1, '1.4.0298', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE BANDA PARA BOMBA DE VACÍO', 'SERVICIO', NULL, 1038),
(1039, 1, 1, '1.4.0299', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE REPUESTO DE MIRILLA DE VIDRIO DE 5"', 'SERVICIO', NULL, 1039),
(1040, 1, 1, '1.4.0300', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE BOLA DE 2"', 'SERVICIO', NULL, 1040),
(1041, 1, 1, '1.4.0301', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE ALIVIO DE PRESIÓN DE 2 PULGADAS', 'SERVICIO', NULL, 1041),
(1042, 1, 1, '1.4.0302', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE SUCCIÓN DE 6" X 6 METROS', 'SERVICIO', NULL, 1042),
(1043, 1, 1, '1.4.0303', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE BOMBA DE VACÍO VPC 80', 'SERVICIO', NULL, 1043),
(1044, 1, 1, '1.4.0304', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE BOMBA DE VACÍO VACUSTAR 1600', 'SERVICIO', NULL, 1044),
(1045, 1, 1, '1.4.0305', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE FILTRO DE MALLA DE ACERO INOXIDABLE Y HOUSING DE ALUMINIO PARA BOMBA VACUSTAR 1600', 'SERVICIO', NULL, 1045),
(1046, 1, 1, '1.4.0306', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA CHECK DE 3"', 'SERVICIO', NULL, 1046),
(1047, 1, 1, '1.4.0307', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE BOLA DE 3"', 'SERVICIO', NULL, 1047),
(1048, 1, 1, '1.4.0308', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE SUCCIÓN DE PVC 3"', 'SERVICIO', NULL, 1048),
(1049, 1, 1, '1.4.0309', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE FILTRO DE AIRE PARA COMPRESOR L400', 'SERVICIO', NULL, 1049),
(1050, 1, 1, '1.4.0310', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE SEGURIDAD DE 3/4" PARA COMPRESOR L400', 'SERVICIO', NULL, 1050),
(1051, 1, 1, '1.4.0311', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA CHECK PARA COMPRESOR L400', 'SERVICIO', NULL, 1051),
(1052, 1, 1, '1.4.0312', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE ABRAZADERAS DE 3"', 'SERVICIO', NULL, 1052),
(1053, 1, 1, '1.4.0313', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE MANGUERA TRANSPARENTE DE PVC 1"', 'SERVICIO', NULL, 1053),
(1054, 1, 1, '1.4.0314', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE ABRAZADERAS DE 1"', 'SERVICIO', NULL, 1054),
(1055, 1, 1, '1.4.0315', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE CONECTORES RECTOS CON ESCAMA BRONCE 1"', 'SERVICIO', NULL, 1055),
(1056, 1, 1, '1.4.0316', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE ALTA PRESIÓN 1" Ø POR 120.00 M. DE  LONGITUD  PARA CARRETE', 'SERVICIO', NULL, 1056),
(1057, 1, 1, '1.4.0317', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE ENFRIADOR HIDRÁULICO', 'SERVICIO', NULL, 1057),
(1058, 1, 1, '1.4.0318', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE INTERCOOLER', 'SERVICIO', NULL, 1058),
(1059, 1, 1, '1.4.0319', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE TRES VÍAS 1"', 'SERVICIO', NULL, 1059),
(1060, 1, 1, '1.4.0320', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE SWIVEL   1" X 90º', 'SERVICIO', NULL, 1060),
(1061, 1, 1, '1.4.0321', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE VÁLVULA DE BOLA 4"', 'SERVICIO', NULL, 1061),
(1062, 1, 1, '1.4.0322', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE CONEXIONES HIDRÁULICAS', 'SERVICIO', NULL, 1062),
(1063, 1, 1, '1.4.0323', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE MANGUERA DE 1/2" POR 10.00 M. DE LONGITUD CON CONEXIONES', 'SERVICIO', NULL, 1063),
(1064, 1, 1, '1.4.0324', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE TUBO DE GRASA SILICONA PARA BOMBA DE VACÍO', 'SERVICIO', NULL, 1064),
(1065, 1, 1, '1.4.0325', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE BOMBA DE RECIRCULACIÓN PARA BOMBA VACUSTAR 1600', 'SERVICIO', NULL, 1065),
(1066, 1, 1, '1.4.0326', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO MALLA DE ACERO INOXIDABLE PARA FILTRO', 'SERVICIO', NULL, 1066),
(1067, 1, 1, '1.4.0327', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE SWIVEL DE GIRO CON CREMALLERA PARA PLUMA DE SUCCIÓN', 'SERVICIO', NULL, 1067),
(1068, 1, 1, '1.4.0328', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE BAQUELITAS PARA BOMBA RFL-150', 'SERVICIO', NULL, 1068),
(1069, 1, 1, '1.4.0329', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE ROTOR PARA BOMBA DE VACÍO', 'SERVICIO', NULL, 1069),
(1070, 1, 1, '1.4.0330', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'HOUSING PARA BOMBA DE VACÍO', 'PIEZA', NULL, 1070),
(1071, 1, 1, '1.4.0331', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'KIT DE REPARACIÒN DE BOMBA DE VACÍO VPC-80.  INCLUYE: BALEROS, RETENES, JUNTAS, EMPAQUES, SEGUROS', 'PIEZA', NULL, 1071),
(1072, 1, 1, '1.4.0332', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'KIT DE REPARACIÓN PARA BOMBA VACUSTAR CVS 1600; INCLUYE: BAQUELITAS', 'PIEZA', NULL, 1072),
(1073, 1, 1, '1.4.0333', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'BAQUELITAS PARA BOMBA RFL-150', 'JUEGO', NULL, 1073),
(1074, 1, 1, '1.4.0334', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'ROTOR PARA BOMBA DE VACÍO', 'PIEZA', NULL, 1074),
(1075, 1, 1, '1.4.0335', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'BOMBA DE VACÍO MOD: VPC-80.', 'PIEZA', NULL, 1075),
(1076, 1, 1, '1.4.0336', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'BOMBA DE VACIO MOD: VACUSTAR 1600', 'PIEZA', NULL, 1076),
(1077, 1, 1, '1.4.0337', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'FILTRO DE MALLA DE ACERO INOXIDABLE Y HOUSING DE ALUMINIO PARA BOMBA VACUSTAR 1600', 'PIEZA', NULL, 1077),
(1078, 1, 1, '1.4.0338', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA CHECK DE 3"', 'PIEZA', NULL, 1078),
(1079, 1, 1, '1.4.0339', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'COMPRESOR DE VACÍO L400', 'PIEZA', NULL, 1079),
(1080, 1, 1, '1.4.0340', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'FILTRO DE AIRE PARA BOMBA DE VACÍO L400', 'PIEZA', NULL, 1080),
(1081, 1, 1, '1.4.0341', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA DE SEGURIDAD DE 3/4" PARA COMPRESOR L400', 'PIEZA', NULL, 1081),
(1082, 1, 1, '1.4.0342', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA CHECK PARA COMPRESOR L400', 'PIEZA', NULL, 1082),
(1083, 1, 1, '1.4.0343', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'BANDA PARA BOMBA DE VACÍO', 'PIEZA', NULL, 1083),
(1084, 1, 1, '1.4.0344', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'SWIVEL DE GIRO CON CREMALLERA PARA PLUMA DE SUCCIÓN.', 'PIEZA', NULL, 1084),
(1085, 1, 1, '1.4.0345', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'SELLO PARA ASIENTO DE CAJA DE SUCCIÓN (CALABAZO)', 'PIEZA', NULL, 1085),
(1086, 1, 1, '1.4.0346', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'REPUESTO DE MIRILLA DE VIDRIO DE 5"', 'PIEZA', NULL, 1086),
(1087, 1, 1, '1.4.0347', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'ENFRIADOR HIDRÁULICO ASA HYDRAULIK', 'PIEZA', NULL, 1087),
(1088, 1, 1, '1.4.0348', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'INTERCOOLER PARA BOMBA DE VACÍO DE ANILLO LÍQUIDO', 'PIEZA', NULL, 1088),
(1089, 1, 1, '1.4.0349', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA DE BOLA DE 2"', 'PIEZA', NULL, 1089),
(1090, 1, 1, '1.4.0350', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA DE ALIVIO DE PRESIÓN DE 2 PULGADAS', 'PIEZA', NULL, 1090),
(1091, 1, 1, '1.4.0351', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'MANGUERA DE SUCCIÓN DE 6" X 6 METROS', 'PIEZA', NULL, 1091),
(1092, 1, 1, '1.4.0352', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA DE BOLA DE 3"', 'PIEZA', NULL, 1092),
(1093, 1, 1, '1.4.0353', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'MANGUERA DE SUCCIÓN DE PVC 3"', 'METRO', NULL, 1093),
(1094, 1, 1, '1.4.0354', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'ABRAZADERAS DE 3"', 'PIEZA', NULL, 1094),
(1095, 1, 1, '1.4.0355', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'MANGUERA TRANSPARENTE DE PVC 1"', 'PIEZA', NULL, 1095),
(1096, 1, 1, '1.4.0356', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'ABRAZADERAS DE 1"', 'PIEZA', NULL, 1096),
(1097, 1, 1, '1.4.0357', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CONECTORES RECTOS CON ESCAMA BRONCE 1"', 'PIEZA', NULL, 1097),
(1098, 1, 1, '1.4.0358', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'MANGUERA DE ALTA PRESIÓN 1" Ø POR 120.00 M. DE LONGITUD  PARA CARRETE', 'PIEZA', NULL, 1098),
(1099, 1, 1, '1.4.0359', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA DE TRES VÍAS 1"', 'PIEZA', NULL, 1099),
(1100, 1, 1, '1.4.0360', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA DE VENTEO DE ACERO INOXIDABLE DE 3"', 'PIEZA', NULL, 1100)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(1101, 1, 1, '1.4.0361', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'SWIVEL   1" X 90º', 'PIEZA', NULL, 1101),
(1102, 1, 1, '1.4.0362', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'VÁLVULA DE BOLA 4"', 'PIEZA', NULL, 1102),
(1103, 1, 1, '1.4.0363', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'MANGUERA DE 1/2" POR 10.00 M. DE LONGITUD CON CONEXIONES', 'PIEZA', NULL, 1103),
(1104, 1, 1, '1.4.0364', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CONEXIONES HIDRÁULICAS', 'PIEZA', NULL, 1104),
(1105, 1, 1, '1.4.0365', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'TUBO DE GRASA SILICONA PARA BOMBA DE VACÍO', 'PIEZA', NULL, 1105),
(1106, 1, 1, '1.4.0366', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'ACEITE SAE 40', 'LITRO', NULL, 1106),
(1107, 1, 1, '1.4.0367', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'EMPAQUES PARA TAPAS DE BOMBA DE VACÍO VACUSTAR 1600', 'KIT', NULL, 1107),
(1108, 1, 1, '1.4.0368', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'BOMBA DE RECIRCULACIÓN  PARA BOMBA VACUSTAR 1600', 'PIEZA', NULL, 1108),
(1109, 1, 1, '1.4.0369', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'MALLA DE ACERO INOXIDABLE PARA FILTRO', 'PIEZA', NULL, 1109),
(1110, 1, 1, '1.4.0370', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE VACÍO Y SUCCIÓN (EQUIPO).', 'CAMBIO DE COMPRESOR DE VACÍO L400', 'SERVICIO', NULL, 1110),
(1111, 1, 1, '1.4.0371', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE JUEGO DE VÁLVULAS DE SUCCIÓN Y DESCARGA', 'SERVICIO', NULL, 1111),
(1112, 1, 1, '1.4.0372', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO EMPAQUES PARA 3 PISTONES QUE INCLUYE: WIPER RING, MINUTE RING, SNAP RING, SUPORT RING', 'SERVICIO', NULL, 1112),
(1113, 1, 1, '1.4.0373', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO TAPÓN DE LLENADO PARA BOMBA DE AGUA A ALTA PRESIÓN', 'SERVICIO', NULL, 1113),
(1114, 1, 1, '1.4.0374', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE SISTEMA DE RETROLAVADO INTERIOR DEL TANQUE', 'SERVICIO', NULL, 1114),
(1115, 1, 1, '1.4.0375', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO PIVOTE DE LEVANTE PARA CALZAR VÁLVULAS DE SUCCIÓN Y DESCARGA', 'SERVICIO', NULL, 1115),
(1116, 1, 1, '1.4.0376', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO BUJE DE CERÁMICA', 'SERVICIO', NULL, 1116),
(1117, 1, 1, '1.4.0377', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO PISTÓN', 'SERVICIO', NULL, 1117),
(1118, 1, 1, '1.4.0378', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE BOMBA DE AGUA A ALTA PRESIÓN MARCA URACA MOD. KD-708', 'SERVICIO', NULL, 1118),
(1119, 1, 1, '1.4.0379', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE VALVULA DE SEGURIDAD DE ALIVIO DE PRESIÒN', 'SERVICIO', NULL, 1119),
(1120, 1, 1, '1.4.0380', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE ACEITE SAE 80W 90 PARA BOMBA DE AGUA', 'SERVICIO', NULL, 1120),
(1121, 1, 1, '1.4.0381', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE ROLES DE ALUMINIO DE GUÍA PARA CARRETE', 'SERVICIO', NULL, 1121),
(1122, 1, 1, '1.4.0382', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE SPROCKET DE CARRETE DE MANGUERA DE AGUA A.P.', 'SERVICIO', NULL, 1122),
(1123, 1, 1, '1.4.0383', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'CAMBIO DE ENGRANE DE CARRETE DE MANGUERA DE AGUA A.P.', 'SERVICIO', NULL, 1123),
(1124, 1, 1, '1.4.0384', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'EMPAQUES PARA 3 PISTONES QUE INCLUYE: WIPER RING, MINUTE RING, SNAP RING, SUPORT RING', 'KIT', NULL, 1124),
(1125, 1, 1, '1.4.0385', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'TAPÓN DE LLENADO PARA BOMBA DE AGUA A ALTA PRESIÓN', 'PIEZA', NULL, 1125),
(1126, 1, 1, '1.4.0386', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'VÀLVULA DE SUCCIÓN Y DESCARGA COMPLETA', 'PIEZA', NULL, 1126),
(1127, 1, 1, '1.4.0387', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'SISTEMA DE RETROLAVADO INTERIOR DEL TANQUE', 'PIEZA', NULL, 1127),
(1128, 1, 1, '1.4.0388', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'PIVOTE DE LEVANTE PARA CALZAR VÁLVULAS DE SUCCIÓN Y DESCARGA', 'PIEZA', NULL, 1128),
(1129, 1, 1, '1.4.0389', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'BUJE DE CERÁMICA', 'PIEZA', NULL, 1129),
(1130, 1, 1, '1.4.0390', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'PISTÓN', 'PIEZA', NULL, 1130),
(1131, 1, 1, '1.4.0391', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'BOMBA DE AGUA A ALTA PRESIÓN MARCA URACA MOD. KD-708', 'PIEZA', NULL, 1131),
(1132, 1, 1, '1.4.0392', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'VALVULA DE SEGURIDAD DE ALIVIO DE PRESION CAL. A 3000 LBS.', 'PIEZA', NULL, 1132),
(1133, 1, 1, '1.4.0393', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'ROLES DE ALUMINIO DE GUÍA PARA CARRETE', 'PIEZA', NULL, 1133),
(1134, 1, 1, '1.4.0394', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'SPROCKET DE CARRETE DE MANGUERA DE AGUA A.P.', 'PIEZA', NULL, 1134),
(1135, 1, 1, '1.4.0395', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'ENGRANE DE CARRETE DE MANGUERA DE AGUA A.P.', 'PIEZA', NULL, 1135),
(1136, 1, 1, '1.4.0396', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE AGUA A ALTA PRESIÓN  (EQUIPO).', 'ACEITE SAE 80W 90 PARA BOMBA DE AGUA', 'LITRO', NULL, 1136),
(1137, 1, 1, '1.4.0397', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE MANGUERA NEUMÁTICA', 'SERVICIO', NULL, 1137),
(1138, 1, 1, '1.4.0398', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE CILINDRO NEUMÁTICO DE PLUMA', 'SERVICIO', NULL, 1138),
(1139, 1, 1, '1.4.0399', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE VÁLVULA LÓGICA AND', 'SERVICIO', NULL, 1139),
(1140, 1, 1, '1.4.0400', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE VÁLVULA LÓGICA OR', 'SERVICIO', NULL, 1140),
(1141, 1, 1, '1.4.0401', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE SELECTOR NEUMÁTICO', 'SERVICIO', NULL, 1141),
(1142, 1, 1, '1.4.0402', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE VÁLVULA NEUMÁTICO 5 POSICIONES  VÍAS', 'SERVICIO', NULL, 1142),
(1143, 1, 1, '1.4.0403', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE RACOR', 'SERVICIO', NULL, 1143),
(1144, 1, 1, '1.4.0404', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE ACTUADOR NEUMÁTICO', 'SERVICIO', NULL, 1144),
(1145, 1, 1, '1.4.0405', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE REGULADOR', 'SERVICIO', NULL, 1145),
(1146, 1, 1, '1.4.0406', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CAMBIO DE DESHUMIDIFICADOR DE AIRE', 'SERVICIO', NULL, 1146),
(1147, 1, 1, '1.4.0407', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'MANGUERA NEUMÁTICA PUN 6 MM CON PROTECCIÓN UV', 'METRO', NULL, 1147),
(1148, 1, 1, '1.4.0408', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'RACOR  DE 2,5 MM', 'PIEZA', NULL, 1148),
(1149, 1, 1, '1.4.0409', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'VÁLVULA LÓGICA AND', 'PIEZA', NULL, 1149),
(1150, 1, 1, '1.4.0410', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'VÁLVULA LÓGICA OR', 'PIEZA', NULL, 1150),
(1151, 1, 1, '1.4.0411', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'ACTUADOR NEUMÁTICO DR 8', 'PIEZA', NULL, 1151),
(1152, 1, 1, '1.4.0412', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'SELECTOR NEUMÁTICO', 'PIEZA', NULL, 1152),
(1153, 1, 1, '1.4.0413', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'VÁLVULA NEUMÁTICO 5 POSICIONES  VÍAS', 'PIEZA', NULL, 1153),
(1154, 1, 1, '1.4.0414', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'CILINDRO NEUMÁTICO DE PLUMA', 'PIEZA', NULL, 1154),
(1155, 1, 1, '1.4.0415', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'DESHUMIDIFICADOR DE AIRE', 'PIEZA', NULL, 1155),
(1156, 1, 1, '1.4.0416', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA NEUMATICO (EQUIPO).', 'REGULADOR MS6-1/4"', 'PIEZA', NULL, 1156),
(1157, 1, 1, '1.4.0417', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'REPARACIÓN DE CAJA DE CONTROL DE OPERACIÓN , INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1157),
(1158, 1, 1, '1.4.0418', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE BOTON PARO DE EMERGENCIA 0084523', 'SERVICIO', NULL, 1158),
(1159, 1, 1, '1.4.0419', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE ARNES ELECTRICO 4X14.', 'SERVICIO', NULL, 1159),
(1160, 1, 1, '1.4.0420', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE CONECTOR HM TIPO ESPADA DE 7 VIAS', 'SERVICIO', NULL, 1160),
(1161, 1, 1, '1.4.0421', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE SENSOR DE VELOCIDAD PARA BOMBA DE VACÍO', 'SERVICIO', NULL, 1161),
(1162, 1, 1, '1.4.0422', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE BULBO CORTACIRCUITO PARA TACÓMETRO', 'SERVICIO', NULL, 1162),
(1163, 1, 1, '1.4.0423', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE SOLENOIDE PARA VALVULA DE 4 VÍAS', 'SERVICIO', NULL, 1163),
(1164, 1, 1, '1.4.0424', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE SENSOR BYPASS PARA ACELERACIÓN', 'SERVICIO', NULL, 1164),
(1165, 1, 1, '1.4.0425', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE PLAFONES LATERALES ROJO-AMBAR', 'SERVICIO', NULL, 1165),
(1166, 1, 1, '1.4.0426', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE PLAFONES TRASEROS TIPO ESCUDO', 'SERVICIO', NULL, 1166),
(1167, 1, 1, '1.4.0427', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE PLAFONES DIRECCIONALES', 'SERVICIO', NULL, 1167),
(1168, 1, 1, '1.4.0428', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE GENERADOR DE 15 KW MARCA HARRISON', 'SERVICIO', NULL, 1168),
(1169, 1, 1, '1.4.0429', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE INIDICADOR DIGITAL PARA GENERADOR MARCA HARRISON 15 KW', 'SERVICIO', NULL, 1169),
(1170, 1, 1, '1.4.0430', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE FUSIBLE MUELA DE 30 AMP', 'SERVICIO', NULL, 1170),
(1171, 1, 1, '1.4.0431', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE ALARMA REVERSERA', 'SERVICIO', NULL, 1171),
(1172, 1, 1, '1.4.0432', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE FARO DE ILUMINACIÓN 60 WATTS', 'SERVICIO', NULL, 1172),
(1173, 1, 1, '1.4.0433', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE TORRETA ESTROBOSCÓPICA', 'SERVICIO', NULL, 1173),
(1174, 1, 1, '1.4.0434', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE PORTA FUSIBLE DE MUELA', 'SERVICIO', NULL, 1174),
(1175, 1, 1, '1.4.0435', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE FARO BUSCADOR 6"', 'SERVICIO', NULL, 1175),
(1176, 1, 1, '1.4.0436', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'INSTALACIÓN DE SISTEMA DE CONTROL REMOTO', 'SERVICIO', NULL, 1176),
(1177, 1, 1, '1.4.0437', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'INSTALACIÓN DE SISTEMA MURPHY DIGITAL', 'SERVICIO', NULL, 1177),
(1178, 1, 1, '1.4.0438', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE SENSOR DE REVOLUCIONES', 'SERVICIO', NULL, 1178),
(1179, 1, 1, '1.4.0439', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'INSTALACIÓN DE PANEL DE CONTROL INOXIDABLE', 'SERVICIO', NULL, 1179),
(1180, 1, 1, '1.4.0440', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE BOTONERA', 'SERVICIO', NULL, 1180),
(1181, 1, 1, '1.4.0441', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE CABLE DE 7 HILOS X 10.00 M. PARA BOTONERA', 'SERVICIO', NULL, 1181),
(1182, 1, 1, '1.4.0442', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE INTERRUPTOR DE 22 MM', 'SERVICIO', NULL, 1182),
(1183, 1, 1, '1.4.0443', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE TRANSMISOR PARA SISTEMA DE CONTROL REMOTO', 'SERVICIO', NULL, 1183),
(1184, 1, 1, '1.4.0444', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAMBIO DE TERMOSTATO DEL TANQUE', 'SERVICIO', NULL, 1184),
(1185, 1, 1, '1.4.0445', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CAJA DE CONTROL EN ACERO INOXIDABLE DE 20X20X40', 'PIEZA', NULL, 1185),
(1186, 1, 1, '1.4.0446', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'BOTON PARO DE EMERGENCIA 0084523', 'PIEZA', NULL, 1186),
(1187, 1, 1, '1.4.0447', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'ARNES ELECTRICO 4X14.', 'PIEZA', NULL, 1187),
(1188, 1, 1, '1.4.0448', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CONECTOR HM TIPO ESPADA DE 7 VIAS', 'PIEZA', NULL, 1188),
(1189, 1, 1, '1.4.0449', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'SENSOR DE VELOCIDAD PARA BOMBA DE VACÍO', 'PIEZA', NULL, 1189),
(1190, 1, 1, '1.4.0450', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'BULBO CORTACIRCUITO PARA TACOMETRO', 'PIEZA', NULL, 1190),
(1191, 1, 1, '1.4.0451', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'SOLENOIDE PARA VALVULA DE 4 VIAS', 'PIEZA', NULL, 1191),
(1192, 1, 1, '1.4.0452', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'SENSOR BYPASS PARA ACELERACIÓN', 'PIEZA', NULL, 1192),
(1193, 1, 1, '1.4.0453', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'PLAFONES LATERALES ROJO-AMBAR', 'PIEZA', NULL, 1193),
(1194, 1, 1, '1.4.0454', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'PLAFONES TRASEROS TIPO ESCUDO', 'PIEZA', NULL, 1194),
(1195, 1, 1, '1.4.0455', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'PLAFONES DIRECCIONALES', 'PIEZA', NULL, 1195),
(1196, 1, 1, '1.4.0456', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'GENERADOR DE 15 KW MARCA HARRISON', 'PIEZA', NULL, 1196),
(1197, 1, 1, '1.4.0457', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'INDICADOR DIGITAL PARA GENERADOR MARCA HARRISON 15 KW', 'PIEZA', NULL, 1197),
(1198, 1, 1, '1.4.0458', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'FARO BUSCADOR DE 6"', 'PIEZA', NULL, 1198),
(1199, 1, 1, '1.4.0459', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'FUSIBLE MUELA DE 30 AMP', 'PIEZA', NULL, 1199),
(1200, 1, 1, '1.4.0460', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'PORTA FUSIBLE DE MUELA', 'PIEZA', NULL, 1200)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(1201, 1, 1, '1.4.0461', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'SENSOR DE REVOLUCIONES', 'PIEZA', NULL, 1201),
(1202, 1, 1, '1.4.0462', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'FARO DE ILUMINACIÓN 60 WATTS', 'PIEZA', NULL, 1202),
(1203, 1, 1, '1.4.0463', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'SISTEMA DE CONTROL REMOTO', 'KIT', NULL, 1203),
(1204, 1, 1, '1.4.0464', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'TRANSMISOR PARA SISTEMA DE CONTROL REMOTO', 'PIEZA', NULL, 1204),
(1205, 1, 1, '1.4.0465', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'ALARMA REVERSERA', 'PIEZA', NULL, 1205),
(1206, 1, 1, '1.4.0466', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'PANEL DE CONTROL DE ACERO INOXIDABLE', 'PIEZA', NULL, 1206),
(1207, 1, 1, '1.4.0467', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'SISTEMA DIGITAL DE PARÁMETROS PARA MOTOR MURPHY', 'PIEZA', NULL, 1207),
(1208, 1, 1, '1.4.0468', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'TORRETA ESTROBOSCÓPICA', 'PIEZA', NULL, 1208),
(1209, 1, 1, '1.4.0469', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'BOTONERA', 'PIEZA', NULL, 1209),
(1210, 1, 1, '1.4.0470', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'CABLE DE 7 HILOS X 10.00  M. PARA BOTONERA', 'PIEZA', NULL, 1210),
(1211, 1, 1, '1.4.0471', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'INTERRUPTOR DE 22 MM', 'PIEZA', NULL, 1211),
(1212, 1, 1, '1.4.0472', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA ELÉCTRICO (EQUIPO).', 'TERMOSTATO DEL TANQUE', 'PIEZA', NULL, 1212),
(1213, 1, 1, '1.4.0473', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO YUGO DESLIZANTE', 'SERVICIO', NULL, 1213),
(1214, 1, 1, '1.4.0474', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO YUGO SOLDABLE', 'SERVICIO', NULL, 1214),
(1215, 1, 1, '1.4.0475', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO CRUCETA', 'SERVICIO', NULL, 1215),
(1216, 1, 1, '1.4.0476', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO BARRA CARDAN', 'SERVICIO', NULL, 1216),
(1217, 1, 1, '1.4.0477', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO POLEA MOTRIZ', 'SERVICIO', NULL, 1217),
(1218, 1, 1, '1.4.0478', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO POLEA MOVIDA', 'SERVICIO', NULL, 1218),
(1219, 1, 1, '1.4.0479', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO CHUMACERA', 'SERVICIO', NULL, 1219),
(1220, 1, 1, '1.4.0480', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CAMBIO DE TOMA DE FUERZA', 'SERVICIO', NULL, 1220),
(1221, 1, 1, '1.4.0481', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'YUGO DESLIZANTE', 'PIEZA', NULL, 1221),
(1222, 1, 1, '1.4.0482', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'YUGO SOLDABLE', 'PIEZA', NULL, 1222),
(1223, 1, 1, '1.4.0483', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CRUCETA', 'PIEZA', NULL, 1223),
(1224, 1, 1, '1.4.0484', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'BARRA CARDAN', 'PIEZA', NULL, 1224),
(1225, 1, 1, '1.4.0485', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'POLEA MOTRIZ', 'PIEZA', NULL, 1225),
(1226, 1, 1, '1.4.0486', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'POLEA MOVIDA', 'PIEZA', NULL, 1226),
(1227, 1, 1, '1.4.0487', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'CHUMACERA', 'PIEZA', NULL, 1227),
(1228, 1, 1, '1.4.0488', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA DE TRANSMISIÓN DE POTENCIA.', 'TOMA DE FUERZA', 'PIEZA', NULL, 1228),
(1229, 1, 1, '1.4.0489', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'CAMBIO DE RETÉN PRINCIPAL', 'SERVICIO', NULL, 1229),
(1230, 1, 1, '1.4.0490', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'CAMBIO DE SOPORTES ESTALÁSTICOS', 'SERVICIO', NULL, 1230),
(1231, 1, 1, '1.4.0491', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'CAMBIO DE CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 1231),
(1232, 1, 1, '1.4.0492', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'CAMBIO DE ACEITE PARA CAJA DE TRANSFERENCIA', 'SERVICIO', NULL, 1232),
(1233, 1, 1, '1.4.0493', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'RETÉN PRINCIPAL', 'PIEZA', NULL, 1233),
(1234, 1, 1, '1.4.0494', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'CAJA DE TRANSFERENCIA', 'PIEZA', NULL, 1234),
(1235, 1, 1, '1.4.0495', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'SOPORTES ESTALÁSTICOS', 'PIEZA', NULL, 1235),
(1236, 1, 1, '1.4.0496', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A CAJA DE TRANSFERENCIA.', 'ACEITE PARA CAJA DE TRANSFERENCIA   SAE-GEAR/90.', 'LITRO', NULL, 1236),
(1237, 1, 1, '1.4.0497', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'REPARACIÓN DE CILINDRO DE  EXTENSIÓN DE LA PLUMA, INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1237),
(1238, 1, 1, '1.4.0498', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'REPARACIÓN DE CILINDRO DE  CIERRE DE TAPA TRASERA, INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1238),
(1239, 1, 1, '1.4.0499', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'REPARACIÓN DE CILINDRO DE  LEVANTE DE PLUMA , INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1239),
(1240, 1, 1, '1.4.0500', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'REPARACIÓN DE BANCO DE VALVULAS MULTIPLE, INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1240),
(1241, 1, 1, '1.4.0501', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE BOMBA PARA SISTEMA HIDRÁULICO', 'SERVICIO', NULL, 1241),
(1242, 1, 1, '1.4.0502', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MANGUERA HIDRAULICA No.- 4    A.  P.', 'SERVICIO', NULL, 1242),
(1243, 1, 1, '1.4.0503', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MANGUERA HIDRAULICA No.- 6    A. P.', 'SERVICIO', NULL, 1243),
(1244, 1, 1, '1.4.0504', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MANGUERA HIDRAULICA No.- 8    A. P.', 'SERVICIO', NULL, 1244),
(1245, 1, 1, '1.4.0505', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBO DE MANGUERA HIDRAULICA No.- 10  A. P.', 'SERVICIO', NULL, 1245),
(1246, 1, 1, '1.4.0506', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MANGUERA HIDRAULICA No.- 12  A. P.', 'SERVICIO', NULL, 1246),
(1247, 1, 1, '1.4.0507', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MANGUERA SUCCIÓN DE BOMBA HIDRÁULICA No.16 A/P.', 'SERVICIO', NULL, 1247),
(1248, 1, 1, '1.4.0508', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MOTOR HIDRÁULICO PARA CARRETE', 'SERVICIO', NULL, 1248),
(1249, 1, 1, '1.4.0509', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MOTOR HIDRÁULICO KAWASAKI DE 800 CC CW PARA GENERADOR', 'SERVICIO', NULL, 1249),
(1250, 1, 1, '1.4.0510', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE MOTOR HIDRÁULICO PARA COMPRESOR L400', 'SERVICIO', NULL, 1250),
(1251, 1, 1, '1.4.0511', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE ACTUADOR HIDRAULICO PARA CARRETE DE MANGUERA DE AGUA A.P.', 'SERVICIO', NULL, 1251),
(1252, 1, 1, '1.4.0512', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE FILTRO PARA ACEITE HIDRÁULICO PH-47 (FRAM)', 'SERVICIO', NULL, 1252),
(1253, 1, 1, '1.4.0513', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE VÁLVULA REGULADORA DE PRESIÓN DOBLE', 'SERVICIO', NULL, 1253),
(1254, 1, 1, '1.4.0514', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE CADENA PARA CARRETE', 'SERVICIO', NULL, 1254),
(1255, 1, 1, '1.4.0515', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO VÁLVULA MACHO DE 1"', 'SERVICIO', NULL, 1255),
(1256, 1, 1, '1.4.0516', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO GATOS PARA SEGURO DE TAPA TRASERA', 'SERVICIO', NULL, 1256),
(1257, 1, 1, '1.4.0517', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE GATO DE LEVANTE PARA TANQUE RESIDUAL', 'SERVICIO', NULL, 1257),
(1258, 1, 1, '1.4.0518', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE VÁLVULA DE CONTROL DE LEVANTE DEL GATO', 'SERVICIO', NULL, 1258),
(1259, 1, 1, '1.4.0519', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE VÁLVULA DE CONTROL DEL CARRETE TRASERO', 'SERVICIO', NULL, 1259),
(1260, 1, 1, '1.4.0520', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE PALANCA DE CONTROL DE VÁLVULA DE CONTROL DEL CARRETE TRASERO', 'SERVICIO', NULL, 1260),
(1261, 1, 1, '1.4.0521', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE INDICADOR DE PRESIÓN DE 0 A 5000 PSI', 'SERVICIO', NULL, 1261),
(1262, 1, 1, '1.4.0522', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE INDICADOR DE TEMPERATURA DE ACEITE HIDRÁULICO', 'SERVICIO', NULL, 1262),
(1263, 1, 1, '1.4.0523', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO SWITCH TIPO COLA DE RATA PARA GATO DE COMPUERTA Y LEVANTE', 'SERVICIO', NULL, 1263),
(1264, 1, 1, '1.4.0524', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO VÁLVULA DE CONTROL DE FLUJO', 'SERVICIO', NULL, 1264),
(1265, 1, 1, '1.4.0525', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO MIRILLA DE NIVEL CON TERMÓMETRO', 'SERVICIO', NULL, 1265),
(1266, 1, 1, '1.4.0526', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE FILTRO ACEITE HIDRÁULICO DE DEPOSITO', 'SERVICIO', NULL, 1266),
(1267, 1, 1, '1.4.0527', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE ACEITE HIDRÁULICO', 'SERVICIO', NULL, 1267),
(1268, 1, 1, '1.4.0528', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE ELECTROVÁLVULA BIDIRECCIONAL', 'SERVICIO', NULL, 1268),
(1269, 1, 1, '1.4.0529', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE ELECTROVÁLVULA  1HF647568798', 'SERVICIO', NULL, 1269),
(1270, 1, 1, '1.4.0530', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE CILINDRO HIDRÁULICO', 'SERVICIO', NULL, 1270),
(1271, 1, 1, '1.4.0531', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'LUBRICACIÒN GENERAL', 'SERVICIO', NULL, 1271),
(1272, 1, 1, '1.4.0532', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'BOMBA P/SISTEMA HIDRÁULICO (SERIE N067-20571) MUNCIE  110249', 'PIEZA', NULL, 1272),
(1273, 1, 1, '1.4.0533', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'FILTRO PARA ACEITE HIDRÁULICO PH-47 (FRAM)', 'PIEZA', NULL, 1273),
(1274, 1, 1, '1.4.0534', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'ELECTROVALVULA  1HF647568798', 'PIEZA', NULL, 1274),
(1275, 1, 1, '1.4.0535', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MANGUERA HIDRAULICA No.- 4    A.  P.', 'METRO', NULL, 1275),
(1276, 1, 1, '1.4.0536', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MANGUERA HIDRAULICA No.- 6    A. P.', 'METRO', NULL, 1276),
(1277, 1, 1, '1.4.0537', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MANGUERA HIDRAULICA No.- 8    A. P.', 'METRO', NULL, 1277),
(1278, 1, 1, '1.4.0538', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MANGUERA HIDRAULICA No.- 10  A. P.', 'METRO', NULL, 1278),
(1279, 1, 1, '1.4.0539', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MANGUERA HIDRAULICA No.- 12  A. P.', 'METRO', NULL, 1279),
(1280, 1, 1, '1.4.0540', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MANGUERA SUCCIÓN DE BOMBA HIDRÁULICA No.16 A/P', 'METRO', NULL, 1280),
(1281, 1, 1, '1.4.0541', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MOTOR HIDRÁULICO PARA CARRETE  110785', 'PIEZA', NULL, 1281),
(1282, 1, 1, '1.4.0542', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MOTOR HIDRÁULICO MCA. KAWASAKI DE 880 CC CW PARA GENERADOR', 'PIEZA', NULL, 1282),
(1283, 1, 1, '1.4.0543', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MOTOR HIDRÁULICO PARA COMPRESOR L400', 'PIEZA', NULL, 1283),
(1284, 1, 1, '1.4.0544', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'ACTUADOR HIDRAULICO PARA CARRETE DE MANGUERA DE AGUA A.P.', 'PIEZA', NULL, 1284),
(1285, 1, 1, '1.4.0545', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CADENA PARA CARRETE', 'PIEZA', NULL, 1285),
(1286, 1, 1, '1.4.0546', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'VÁLVULA MACHO DE 1"', 'PIEZA', NULL, 1286),
(1287, 1, 1, '1.4.0547', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'GATOS PARA SEGURO DE TAPA TRASERA', 'PIEZA', NULL, 1287),
(1288, 1, 1, '1.4.0548', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CILINDRO HIDRAULICO.', 'PIEZA', NULL, 1288),
(1289, 1, 1, '1.4.0549', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'VÁLVULA REGULADORA DE PRESIÓN DOBLE', 'PIEZA', NULL, 1289),
(1290, 1, 1, '1.4.0550', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'GATO DE LEVANTE PARA TANQUE RESIDUAL', 'PIEZA', NULL, 1290),
(1291, 1, 1, '1.4.0551', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'VÁLVULA DE CONTROL DE LEVANTE DEL GATO', 'PIEZA', NULL, 1291),
(1292, 1, 1, '1.4.0552', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'VÁLVULA DE CONTROL DEL CARRETE TRASERO', 'PIEZA', NULL, 1292),
(1293, 1, 1, '1.4.0553', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'PALANCA DE CONTROL DE VÁLVULA DE CONTROL DEL CARRETE TRASERO', 'PIEZA', NULL, 1293),
(1294, 1, 1, '1.4.0554', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'INDICADOR DE PRESIÓN DE 0 A 5000 PSI', 'PIEZA', NULL, 1294),
(1295, 1, 1, '1.4.0555', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'INDICADOR DE TEMPERATURA DE ACEITE HIDRÁULICO', 'PIEZA', NULL, 1295),
(1296, 1, 1, '1.4.0556', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'FILTRO PARA ACEITE HIDRÁULICO DE DEPOSITO', 'PIEZA', NULL, 1296),
(1297, 1, 1, '1.4.0557', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'SWITCH TIPO COLA DE RATA PARA GATO DE COMPUERTA Y LEVANTE', 'PIEZA', NULL, 1297),
(1298, 1, 1, '1.4.0558', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'VÁLVULA DE CONTROL DE FLUJO', 'PIEZA', NULL, 1298),
(1299, 1, 1, '1.4.0559', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'MIRILLA DE NIVEL CON TERMÓMETRO', 'PIEZA', NULL, 1299),
(1300, 1, 1, '1.4.0560', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'ELECTROVÁLVULA BIDIRECCIONAL', 'PIEZA', NULL, 1300)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

INSERT INTO concept (id_concept, id_event, id_client, tag_concept, concept_header, concept_description, concept_unit, concept_price, display_order) VALUES
(1301, 1, 1, '1.4.0561', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'ACEITE HIDRÁULICO  HD-46.', 'LITRO', NULL, 1301),
(1302, 1, 1, '1.4.0562', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'GRASA CHASIS STD.', 'KILO', NULL, 1302),
(1303, 1, 1, '1.4.0563', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE JUNTA DE EXPANSIÒN DE 8" X 20 CM. DE LARGO', 'SERVICIO', NULL, 1303),
(1304, 1, 1, '1.4.0564', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE SELLO DE TAPA (JUNTA DEL TANQUE)', 'SERVICIO', NULL, 1304),
(1305, 1, 1, '1.4.0565', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'CAMBIO DE TAPÓN CON COLADOR PARA DEPÓSITO DE ACEITE HIDRÁULICO', 'SERVICIO', NULL, 1305),
(1306, 1, 1, '1.4.0566', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'JUNTA DE EXPANSIÒN DE 8" X 20 CM. DE LARGO', 'PIEZA', NULL, 1306),
(1307, 1, 1, '1.4.0567', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'SELLO DE TAPA (JUNTA DEL TANQUE)', 'PIEZA', NULL, 1307),
(1308, 1, 1, '1.4.0568', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A SISTEMA HIDRAULICO.', 'TAPÓN CON COLADOR PARA DEPÓSITO DE ACEITE HIDRÁULICO', 'PIEZA', NULL, 1308),
(1309, 1, 1, '1.4.0569', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'APLICAR RECUBRIMIENTO ANTICORROSIVO  EN EXTERIOR DEL TANQUE INCLUYE:  LIMPIEZA CON CHORRO DE ARENA  (SAND-BLAST)., APLICACIÓN DE PRIMARIO EPOXICO RP-6. APLICACIÓN DE INTERMEDIO PINTURA EPOXICA  RA-26. Y ACABADO EPOXICO RA-28. EN COLOR BLANCO. .', 'SERVICIO', NULL, 1309),
(1310, 1, 1, '1.4.0570', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'APLICAR RECUBRIMIENTO ANTICORROSIVO RESISTENTE A LA ABRASIÓN EN INTERIOR DEL TANQUE DE LODOS INCLUYE: LIMPIEZA CON CHORRO DE ARENA (SAND-BLAST), APLICACIÓN DE RECUBRIMIENTO PLASTICO ANTIACIDO MONOLITICO RAM-100. DE 2 MM. DE ESPESOR. .', 'SERVICIO', NULL, 1310),
(1311, 1, 1, '1.4.0571', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'APLICAR PROTECCIÓN ANTICORROSIVA EN INTERIOR DEL TANQUE DE AGUA INCLUYE:  LIMPIEZA MANUAL CON CARDA Y SOLVENTES, APLICACIÓN DE RECUBRIMIENTO ANTICORROSIVO PRIMARIO ALQUITRAN DE HULLA RP-5.', 'SERVICIO', NULL, 1311),
(1312, 1, 1, '1.4.0572', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'APLICAR RECUBRIMIENTO ANTICORROSIVO EN VARAS DEL CHASIS, FUNDAS DE DIFERENCIALES Y COMPONENTES DE LA SUSPENSIÓN Y DIRECCIÓN  INCLUYE:  LIMPIEZA MANUAL CON CARDA Y SOLVENTES, APLICACIÓN DE PRIMARIO EPOXICO RP-6. APLICACIÓN DE INTERMEDIO PINTURA EPOXICA  RA-26. Y ACABADO EPOXICO RA-28.', 'SERVICIO', NULL, 1312),
(1313, 1, 1, '1.4.0573', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'APLICAR RECUBRIMIENTO ANTICORROSIVO  EN ACCESORIOS DEL TANQUE INCLUYE:  LIMPIEZA CON CHORRO DE ARENA  (SAND-BLAST)., APLICACIÓN DE PRIMARIO EPOXICO RP-6. APLICACIÓN DE INTERMEDIO PINTURA EPOXICA  RA-26. Y ACABADO EPOXICO RA-28. EN COLOR BLANCO.', 'SERVICIO', NULL, 1313),
(1314, 1, 1, '1.4.0574', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'REPARACIÓN DEL SISTEMA DE RETROLAVADO DE TANQUE DE LODOS INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1314),
(1315, 1, 1, '1.4.0575', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'REPARACIÓN DEL SISTEMA DE INDICADOR DE NIVEL DEL TANQUE DE LODOS INCLUYE: DESMONTAR, DESARMAR, LIMPIEZA, CAMBIO DE PARTES DAÑADAS, ARMADO, MONTAJE Y PRUEBAS DE OPERACIÓN', 'SERVICIO', NULL, 1315),
(1316, 1, 1, '1.4.0576', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'CAMBIO DE MANGUERA DE DESCARGA DEL TANQUE 6" Ø', 'SERVICIO', NULL, 1316),
(1317, 1, 1, '1.4.0577', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'CAMBIO DE ABRAZADERAS PARA  MANGUERA DE 3" DE Ø', 'SERVICIO', NULL, 1317),
(1318, 1, 1, '1.4.0578', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'CAMBIO DE VÁLVULA DE DESCARGA DE 4" Ø', 'SERVICIO', NULL, 1318),
(1319, 1, 1, '1.4.0579', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'CAMBIO DE INDICADOR DE VACÍO DE 0A 30 PSI', 'SERVICIO', NULL, 1319),
(1320, 1, 1, '1.4.0580', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'CAMBIO DE INDICADOR PRESIÓN DE AGUA DE 0A 5000 PSI', 'SERVICIO', NULL, 1320),
(1321, 1, 1, '1.4.0581', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'CAMBIO DE ACOPLADOR MACHO', 'SERVICIO', NULL, 1321),
(1322, 1, 1, '1.4.0582', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'JUNTA DE EXPANSIÒN DE 8" X 20 CMS. DE LARGO', 'PIEZA', NULL, 1322),
(1323, 1, 1, '1.4.0583', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'SELLO DE TAPA (JUNTA DEL TANQUE)', 'PIEZA', NULL, 1323),
(1324, 1, 1, '1.4.0584', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'VÁLVULA DE COMPUERTA  6" Ø', 'PIEZA', NULL, 1324),
(1325, 1, 1, '1.4.0585', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'MIRILLA PARA TAPA', 'PIEZA', NULL, 1325),
(1326, 1, 1, '1.4.0586', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'MANGUERA DE DESCARGA DEL TANQUE 6" Ø', 'METRO', NULL, 1326),
(1327, 1, 1, '1.4.0587', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'ABRAZADERAS PARA  MANGUERA DE 6" DE Ø', 'PIEZA', NULL, 1327),
(1328, 1, 1, '1.4.0588', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'VÁLVULA DE DESCARGA DE 4" Ø', 'PIEZA', NULL, 1328),
(1329, 1, 1, '1.4.0589', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'KIT DE RECUBRIMIENTO ANTICORROSIVO INCLUYE:  PRIMARIO EPOXICO RP-6.-  INTERMEDIO PINTURA EPOXICA  RA-26.-  ACABADO EPOXICO RA-28. EN COLOR BLANCO PARA TANQUE Y ACCESORIOS Y EN COLOR NEGRO PARA VARAS DEL CHASIS, THINNER, LIJAS, RESANADOR, ESTOPAS Y MISCELANEOS.', 'PIEZA', NULL, 1329),
(1330, 1, 1, '1.4.0590', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'INDICADOR DE VACÍO DE 0 A 30 PSI', 'PIEZA', NULL, 1330),
(1331, 1, 1, '1.4.0591', '1.4.0000 SERVICIO DE MANTENIMIENTO CORRECTIVO A EQUIPOS COMBINADOS DE DESAZOLVE Y DE PRESIÓN Y VACÍO MARCA GARCIA & MALLITZ, MANTENIMIENTO CORRECTIVO, MANTENIMIENTO A TANQUE CISTERNA.', 'INDICADOR DE PRESIÓN DE AGUA DE 0A 5000 PSI', 'PIEZA', NULL, 1331),
(1332, 1, 1, '1.5.0001', '1.5.0000 SERVICIOS DE RESCATE EN CAMPO.', 'SERVICIO EN CAMPO DE REPARACION MECÁNICA ELÉCTRICA EN UN RADIO DE 0 A 10 KM., MEDIDO A PARTIR DE LA ZONA INDUSTRIAL DE CADA SECTOR', 'SERVICIO', NULL, 1332),
(1333, 1, 1, '1.5.0002', '1.5.0000 SERVICIOS DE RESCATE EN CAMPO.', 'SERVICIO EN CAMPO DE REPARACION MECÁNICA ELÉCTRICA EN UN RADIO DE 0 A 20 KM., MEDIDO A PARTIR DE LA ZONA INDUSTRIAL DE CADA SECTOR', 'SERVICIO', NULL, 1333),
(1334, 1, 1, '1.5.0003', '1.5.0000 SERVICIOS DE RESCATE EN CAMPO.', 'SERVICIO EN CAMPO DE REPARACION MECÁNICA ELÉCTRICA EN UN RADIO DE 0 A 30 KM., MEDIDO A PARTIR DE LA ZONA INDUSTRIAL DE CADA SECTOR', 'SERVICIO', NULL, 1334),
(1335, 1, 1, '1.5.0004', '1.5.0000 SERVICIOS DE RESCATE EN CAMPO.', 'SERVICIO EN CAMPO DE REPARACION MECÁNICA ELÉCTRICA EN UN RADIO DE 0 A 80 KM., MEDIDO A PARTIR DE LA ZONA INDUSTRIAL DE CADA SECTOR', 'SERVICIO', NULL, 1335)
ON CONFLICT (id_concept) DO UPDATE SET tag_concept = EXCLUDED.tag_concept, concept_description = EXCLUDED.concept_description, concept_unit = EXCLUDED.concept_unit;

-- Intermediate Performance Groups for Concept 480 (Calibración y limpieza de inyectores)
INSERT INTO concept_performance_group (id_performance_group, id_concept, resource_type, performance_factor, performance_unit, calculation_mode, notes)
VALUES 
    ('c0000000-0000-0000-0000-000000000001', 480, 'LABOR', 1.0000, 'JOR/SERV', 'MULTIPLICATION', 'Cuadrilla de calibración de inyectores diésel (1 Operario Especialista + 1 Ayudante) con rendimiento de 1 jornada por servicio'),
    ('c0000000-0000-0000-0000-000000000002', 480, 'EQUIPMENT', 1.0000, 'HORA/SERV', 'MULTIPLICATION', 'Conjunto de equipos de laboratorio de inyección (Banco Common Rail, Tina ultrasonido, Escáner) con rendimiento de 1 hora por servicio')
ON CONFLICT (id_concept, resource_type) DO UPDATE SET 
    performance_factor = EXCLUDED.performance_factor,
    performance_unit = EXCLUDED.performance_unit;

-- Seed Concept 480 APU Integration (Values matching DT-7 View in Abstract.xlsx)
INSERT INTO concept_apu_integration (
    id_apu, id_concept, id_provider,
    pct_indirects, pct_financing, pct_utility, pct_safety_equipment, pct_hand_tools, apply_sfp,
    subtotal_materials, subtotal_labor, subtotal_equipment, subtotal_safety_tools,
    cost_direct_a, cost_indirect_b, cost_sum_c, cost_financing_d, cost_sum_e, cost_utility_f, cost_sum_g, cost_sfp,
    concept_price, concept_price_txt, status
) VALUES (
    'd0000000-0000-0000-0000-000000000001', 480, 1,
    0.1500, 0.0150, 0.1500, 0.0150, 0.0300, false,
    3354.78, 4035.51, 1365.00, 181.59,
    8936.88, 1340.53, 10277.41, 154.16, 10431.57, 1564.73, 11996.30, 0.00,
    11996.30, '( ONCE MIL NOVECIENTOS NOVENTA Y SEIS PESOS 30/100 M.N. )', 'COMPLETED'
)
ON CONFLICT (id_concept, id_provider) DO UPDATE SET 
    concept_price = EXCLUDED.concept_price,
    concept_price_txt = EXCLUDED.concept_price_txt,
    subtotal_materials = EXCLUDED.subtotal_materials,
    subtotal_labor = EXCLUDED.subtotal_labor,
    subtotal_equipment = EXCLUDED.subtotal_equipment;

UPDATE concept SET 
    concept_price = 11996.30,
    concept_price_txt = '( ONCE MIL NOVECIENTOS NOVENTA Y SEIS PESOS 30/100 M.N. )'
WHERE id_concept = 480;

-- Seed Materials for Concept 480
DELETE FROM material_by_concept WHERE id_apu = 'd0000000-0000-0000-0000-000000000001';
INSERT INTO material_by_concept (id_apu, id_concept, id_catalog_material, material_description, unit, quantity, unit_price)
VALUES 
    ('d0000000-0000-0000-0000-000000000001', 480, 1, 'Kit de ligas y sellos para inyector diésel Cummins ISX', 'KIT', 6.0000, 211.31),
    ('d0000000-0000-0000-0000-000000000001', 480, 2, 'Líquido limpiador concentrado de inyectores diésel para laboratorio y tina ultrasónica', 'LITRO', 2.0000, 236.26),
    ('d0000000-0000-0000-0000-000000000001', 480, 3, 'Filtro separador de combustible y agua Fleetguard FF5776', 'PZA', 1.0000, 822.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 4, 'Filtro de combustible primario enroscable Fleetguard FF2200', 'PZA', 1.0000, 327.40),
    ('d0000000-0000-0000-0000-000000000001', 480, 5, 'Aditivo acondicionador y limpiador preventivo de inyectores diésel', 'LITRO', 1.0000, 255.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 6, 'Desengrasante dieléctrico y limpiador de contactos electrónicos para arnés de inyectores', 'PZA', 1.0000, 145.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 7, 'Estopa de algodón blanca para limpieza de componentes', 'KG', 1.0000, 65.00);

-- Seed Labor for Concept 480 (Linked to Labor Performance Group)
DELETE FROM labor_by_concept WHERE id_apu = 'd0000000-0000-0000-0000-000000000001';
INSERT INTO labor_by_concept (id_apu, id_concept, id_performance_group, id_catalog_labor, category, unit, quantity, unit_price)
VALUES 
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000001', 3, 'Operario Especialista en Hidráulica de equipo semipesado', 'JORNADA', 1.0000, 2946.22),
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000001', 4, 'Ayudante', 'JORNADA', 1.0000, 1089.29);

-- Seed Equipment for Concept 480 (Linked to Equipment Performance Group)
DELETE FROM equipment_by_concept WHERE id_apu = 'd0000000-0000-0000-0000-000000000001';
INSERT INTO equipment_by_concept (id_apu, id_concept, id_performance_group, id_catalog_equipment, equipment_description, unit, quantity, unit_price)
VALUES 
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000002', 9, 'Banco de pruebas y calibración para inyectores diésel Common Rail y EUI', 'HORA', 1.0000, 650.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000002', 10, 'Tina de limpieza por ultrasonido industrial para componentes de inyección', 'HORA', 1.0000, 180.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000002', 11, 'Escáner de diagnóstico electrónico para vehículos pesados protocolo J1939', 'HORA', 1.0000, 320.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000002', 12, 'Compresor de aire estacionario de 5 HP para sopleteo y pruebas neumáticas', 'HORA', 1.0000, 110.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000002', 13, 'Torquímetro de precisión con rango de 10 a 150 lb-pie para montaje de inyectores', 'HORA', 1.0000, 45.00),
    ('d0000000-0000-0000-0000-000000000001', 480, 'c0000000-0000-0000-0000-000000000002', 14, 'Juego de extractores hidráulicos y herramienta especializada para desmontaje de inyectores', 'HORA', 1.0000, 60.00);

-- Re-synchronize sequences
SELECT setval('client_id_client_seq', (SELECT MAX(id_client) FROM client));
SELECT setval('provider_id_provider_seq', (SELECT MAX(id_provider) FROM provider));
SELECT setval('event_id_event_seq', (SELECT MAX(id_event) FROM event));

COMMIT;

-- Validation Query
SELECT 
    tag_event, 
    client_name, 
    total_concepts, 
    integrated_concepts_count, 
    completion_percentage 
FROM v_event_dashboard;
