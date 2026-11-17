import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';
import {
  getInvitationsByEmail,
  recordInvitationInStore,
  StoredInvitation,
} from '@/lib/invitation-store';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { email } = body;
    const meta = extractRequestMeta(req);

    if (!email || typeof email !== 'string') {
      return NextResponse.json(
        { error: 'Por favor ingresa un correo electrónico válido.' },
        { status: 400 }
      );
    }

    const normalizedEmail = email.trim().toLowerCase();

    // 1. Check dual-layer invitation store
    const existingInvs = await getInvitationsByEmail(normalizedEmail);
    let activeInvitation: StoredInvitation | null =
      existingInvs.length > 0 ? existingInvs[0] : null;

    // 2. If no invitation in store, check provider table in DB
    if (!activeInvitation) {
      try {
        const { data: providerMatch } = await supabaseAdmin
          .from('provider')
          .select('*')
          .ilike('contact_email', normalizedEmail)
          .limit(1)
          .maybeSingle();

        if (providerMatch) {
          // Look up if this provider has an event assigned or fallback to event 1
          const { data: eventMatch } = await supabaseAdmin
            .from('event')
            .select('*')
            .eq('id_provider', providerMatch.id_provider)
            .limit(1)
            .maybeSingle();

          const targetEventId = eventMatch?.id_event || 1;

          // Fetch event details
          const { data: evDetail } = await supabaseAdmin
            .from('event')
            .select('*')
            .eq('id_event', targetEventId)
            .maybeSingle();

          const token = crypto.randomBytes(32).toString('hex');
          const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString();

          activeInvitation = {
            id_invitation: `inv-${Date.now()}`,
            id_event: targetEventId,
            id_provider: providerMatch.id_provider,
            invited_email: normalizedEmail,
            token,
            expires_at: expiresAt,
            is_accepted: false,
            created_at: new Date().toISOString(),
            event: evDetail || {
              id_event: targetEventId,
              tag_event: 'PEP-DG-SAP-001-2026',
              event_type: 'Servicios de Mantenimiento y Reacondicionamiento Integral',
            },
            provider: providerMatch,
          };

          // Save to DB
          try {
            await supabaseAdmin.from('event_invitation').insert({
              id_event: targetEventId,
              id_provider: providerMatch.id_provider,
              invited_email: normalizedEmail,
              token,
              expires_at: expiresAt,
              is_accepted: false,
            });
          } catch {
            // non-blocking
          }

          recordInvitationInStore(activeInvitation);
        }
      } catch (err) {
        console.warn('Provider check warning:', err);
      }
    }

    // 3. If no invitation found, deny
    if (!activeInvitation) {
      await logAudit({
        userRole: 'ANONYMOUS',
        action: 'DENIED',
        entityType: 'AUTH_REQUEST_LINK',
        entityId: normalizedEmail,
        details: {
          email: normalizedEmail,
          reason: 'No se encontró invitación activa registrada para este correo.',
        },
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      });

      return NextResponse.json(
        {
          error:
            'No se encontró ninguna invitación activa asociada a este correo. Solicita tu acceso al Administrador convocante (hectapia@outlook.com).',
        },
        { status: 404 }
      );
    }

    // 5. Ensure invitation token is valid/fresh (refresh if expired)
    let token = activeInvitation.token;
    if (activeInvitation.expires_at && new Date(activeInvitation.expires_at).getTime() < Date.now()) {
      token = crypto.randomBytes(32).toString('hex');
      const newExpiry = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString();
      activeInvitation.token = token;
      activeInvitation.expires_at = newExpiry;
      recordInvitationInStore(activeInvitation);

      try {
        await supabaseAdmin
          .from('event_invitation')
          .update({ token, expires_at: newExpiry })
          .eq('id_invitation', activeInvitation.id_invitation);
      } catch {
        // non-blocking
      }
    }

    const origin = req.nextUrl.origin || 'http://localhost:3000';
    const magicLink = `${origin}/auth/verify?token=${token}`;

    // 6. Audit log
    await logAudit({
      userId: `prov-${activeInvitation.id_provider || '001'}`,
      userRole: 'PROVIDER_ESTIMATOR',
      action: 'READ',
      entityType: 'AUTH_REQUEST_LINK',
      entityId: String(activeInvitation.id_event),
      details: {
        email: normalizedEmail,
        id_event: activeInvitation.id_event,
        provider_name: activeInvitation.provider?.provider_name,
        magicLink,
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    return NextResponse.json({
      success: true,
      message: 'Invitación activa localizada con éxito.',
      token,
      magicLink,
      eventTag: activeInvitation.event?.tag_event || 'PEP-DG-SAP-001-2026',
      eventTitle: activeInvitation.event?.event_type || 'Licitación Asignada',
      providerName: activeInvitation.provider?.provider_name || 'MHEBOSAP, S.A. DE C.V.',
      representative: activeInvitation.provider?.provider_representative || 'Ing. Fernando Tapia',
    });
  } catch (err: any) {
    console.error('Error in /api/auth/request-link:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al procesar la solicitud de enlace.' },
      { status: 500 }
    );
  }
}
