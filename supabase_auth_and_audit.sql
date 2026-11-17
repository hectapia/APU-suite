-- ==============================================================================
-- APU-SUITE: SUPABASE AUTH, ROW LEVEL SECURITY (RLS) & AUDIT LOG SCHEMA
-- ==============================================================================
-- Instrucciones: Ejecuta este script en el Supabase SQL Editor de tu proyecto.
-- https://supabase.com/dashboard/project/hxqmhgkjpgrlsregwspm/sql

-- 1. TABLA: audit_log (Bitácora inmutable de eventos de auditoría y seguridad)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log (
    id_log UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_user VARCHAR(100),
    user_role VARCHAR(50) NOT NULL DEFAULT 'ANONYMOUS',
    action VARCHAR(20) NOT NULL CHECK (action IN ('CREATE', 'READ', 'UPDATE', 'DELETE', 'DENIED')),
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(100),
    details JSONB DEFAULT '{}'::jsonb,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices de auditoría para filtrado de alta velocidad
CREATE INDEX IF NOT EXISTS idx_audit_log_user ON public.audit_log(id_user);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON public.audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON public.audit_log(entity_type);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.audit_log(created_at DESC);


-- 2. TABLA: event_invitation (Gestión de Magic Links sin contraseña)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_invitation (
    id_invitation UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_event INT REFERENCES public.event(id_event) ON DELETE CASCADE,
    id_provider INT REFERENCES public.provider(id_provider) ON DELETE CASCADE,
    invited_email VARCHAR(255) NOT NULL,
    token VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    is_accepted BOOLEAN DEFAULT FALSE,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_event_invitation_token ON public.event_invitation(token);
CREATE INDEX IF NOT EXISTS idx_event_invitation_email ON public.event_invitation(invited_email);


-- 2.1 VINCULACIÓN DIRECTA DE CONTRATISTA A CONCURSO (event.id_provider)
-- ------------------------------------------------------------------------------
ALTER TABLE public.event ADD COLUMN IF NOT EXISTS id_provider INT REFERENCES public.provider(id_provider) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_event_provider ON public.event(id_provider);


-- 3. TABLA: event_provider_assignment (Asignación granular de concurso a contratista)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_provider_assignment (
    id_assignment UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_event INT REFERENCES public.event(id_event) ON DELETE CASCADE,
    id_provider INT REFERENCES public.provider(id_provider) ON DELETE CASCADE,
    access_role VARCHAR(20) DEFAULT 'WRITE' CHECK (access_role IN ('READ', 'WRITE', 'SUBMITTED')),
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (id_event, id_provider)
);


-- 4. TABLA: app_user (Usuarios internos y personal de contratistas)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_user (
    id_user UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'PROVIDER_ESTIMATOR' CHECK (role IN ('ADMIN', 'PROVIDER_ESTIMATOR', 'AUDITOR', 'CLIENT_VIEWER')),
    password_hash TEXT,
    id_provider INT REFERENCES public.provider(id_provider) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Asegurar columna password_hash si la tabla ya existía
ALTER TABLE public.app_user ADD COLUMN IF NOT EXISTS password_hash TEXT;

-- Sembrar Administrador Principal por Defecto
INSERT INTO public.app_user (email, full_name, role, is_active)
VALUES ('hectapia@outlook.com', 'Ing. Héctor Tapia (Administrador)', 'ADMIN', true)
ON CONFLICT (email) DO UPDATE SET role = 'ADMIN', full_name = 'Ing. Héctor Tapia (Administrador)';


-- 5. FUNCIONES AUXILIARES PARA POLÍTICAS RLS (SECURITY DEFINER)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_auth_role()
RETURNS VARCHAR AS $$
BEGIN
    RETURN COALESCE(
        (SELECT role FROM public.app_user WHERE email = auth.jwt() ->> 'email' LIMIT 1),
        'ANONYMOUS'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_auth_provider_id()
RETURNS INT AS $$
BEGIN
    RETURN (SELECT id_provider FROM public.app_user WHERE email = auth.jwt() ->> 'email' LIMIT 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- 6. HABILITAR ROW LEVEL SECURITY (RLS) EN TODAS LAS TABLAS
-- ------------------------------------------------------------------------------
ALTER TABLE public.app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.concept ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.concept_apu_integration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_material ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_labor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_provider_assignment ENABLE ROW LEVEL SECURITY;


-- 7. POLÍTICAS RLS (Row Level Security)
-- ------------------------------------------------------------------------------

-- Regla A: El rol 'service_role' (usado por Next.js Backend API y Route Handlers) tiene acceso total
CREATE POLICY "service_role_all_app_user" ON public.app_user FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_event" ON public.event FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_concept" ON public.concept FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_apu" ON public.concept_apu_integration FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_cat_mat" ON public.catalog_material FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_cat_lab" ON public.catalog_labor FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_cat_eq" ON public.catalog_equipment FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_audit" ON public.audit_log FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_invitation" ON public.event_invitation FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_assignment" ON public.event_provider_assignment FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Regla B: Usuarios (app_user)
-- Admins pueden gestionar todos los usuarios.
-- Cada usuario autenticado solo puede leer su propio registro de perfil.
CREATE POLICY "admin_all_app_user" ON public.app_user
    FOR ALL TO authenticated
    USING (public.get_auth_role() = 'ADMIN')
    WITH CHECK (public.get_auth_role() = 'ADMIN');

CREATE POLICY "user_view_own_profile" ON public.app_user
    FOR SELECT TO authenticated
    USING (email = auth.jwt() ->> 'email');

-- Regla C: Concursos (event)
-- Admins pueden leer/escribir todos.
-- Contratistas solo pueden leer los concursos que tienen explícitamente asignados.
CREATE POLICY "admin_all_events" ON public.event
    FOR ALL TO authenticated
    USING (public.get_auth_role() = 'ADMIN');

CREATE POLICY "provider_view_assigned_events" ON public.event
    FOR SELECT TO authenticated
    USING (
        id_event IN (
            SELECT id_event FROM public.event_provider_assignment
            WHERE id_provider = public.get_auth_provider_id()
        )
    );

-- Regla D: Conceptos (concept)
-- Admins pueden leer/escribir todos.
-- Contratistas pueden leer los conceptos de sus eventos asignados.
CREATE POLICY "admin_all_concepts" ON public.concept
    FOR ALL TO authenticated
    USING (public.get_auth_role() = 'ADMIN');

CREATE POLICY "provider_view_assigned_concepts" ON public.concept
    FOR SELECT TO authenticated
    USING (
        id_event IN (
            SELECT id_event FROM public.event_provider_assignment
            WHERE id_provider = public.get_auth_provider_id()
        )
    );

-- Regla E: Integración APU (concept_apu_integration)
-- Admins pueden leer todas las propuestas.
-- Contratistas solo pueden leer y editar sus PROPIOS registros APU (id_provider coincidente).
CREATE POLICY "admin_all_apu" ON public.concept_apu_integration
    FOR ALL TO authenticated
    USING (public.get_auth_role() = 'ADMIN');

CREATE POLICY "provider_manage_own_apu" ON public.concept_apu_integration
    FOR ALL TO authenticated
    USING (id_provider = public.get_auth_provider_id())
    WITH CHECK (id_provider = public.get_auth_provider_id());

-- Regla F: Catálogos Maestros (Materiales, Mano de Obra, Equipos)
-- Todos los usuarios autenticados pueden consultar los catálogos.
-- Solo Administradores pueden insertar o modificar ítems en los catálogos maestros.
CREATE POLICY "read_catalogs_material" ON public.catalog_material FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_catalogs_labor" ON public.catalog_labor FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_catalogs_equipment" ON public.catalog_equipment FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_write_catalogs_material" ON public.catalog_material FOR INSERT TO authenticated WITH CHECK (public.get_auth_role() = 'ADMIN');
CREATE POLICY "admin_write_catalogs_labor" ON public.catalog_labor FOR INSERT TO authenticated WITH CHECK (public.get_auth_role() = 'ADMIN');
CREATE POLICY "admin_write_catalogs_equipment" ON public.catalog_equipment FOR INSERT TO authenticated WITH CHECK (public.get_auth_role() = 'ADMIN');

-- Regla G: Invitaciones (event_invitation) y Asignaciones (event_provider_assignment)
-- Solo Administradores pueden crear y ver invitaciones y asignaciones.
CREATE POLICY "admin_manage_invitations" ON public.event_invitation
    FOR ALL TO authenticated
    USING (public.get_auth_role() = 'ADMIN')
    WITH CHECK (public.get_auth_role() = 'ADMIN');

CREATE POLICY "admin_manage_assignments" ON public.event_provider_assignment
    FOR ALL TO authenticated
    USING (public.get_auth_role() = 'ADMIN')
    WITH CHECK (public.get_auth_role() = 'ADMIN');

-- Regla H: Bitácora de Auditoría (audit_log)
-- Admins y Auditores pueden leer todos los registros de auditoría.
-- Inserción permitida con registro de contexto.
CREATE POLICY "admin_read_audit_log" ON public.audit_log
    FOR SELECT TO authenticated
    USING (public.get_auth_role() IN ('ADMIN', 'AUDITOR'));

CREATE POLICY "auth_insert_audit_log" ON public.audit_log
    FOR INSERT TO authenticated
    WITH CHECK (true);
