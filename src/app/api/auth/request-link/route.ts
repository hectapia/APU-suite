import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';

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

    // 1. Query invitation table for this email
    const { data: invitations, error: invErr } = await supabaseAdmin
      .from('event_invitation')
      .select('*, event(*), provider(*)')
      .eq('invited_email', normalizedEmail)
      .order('created_at', { ascending: false });

    let activeInvitation = invitations && invitations.length > 0 ? invitations[0] : null;

    // 2. If no invitation found by invited_email, check provider table
    if (!activeInvitation) {
      const { data: providerMatch } = await supabaseAdmin
        .from('provider')
        .select('*')
        .ilike('contact_email', normalizedEmail)
        .limit(1)
        .maybeSingle();

      if (providerMatch) {
        // Look up if this provider has an event assigned
        const { data: eventMatch } = await supabaseAdmin
          .from('event')
          .select('*')
          .eq('id_provider', providerMatch.id_provider)
          .limit(1)
          .maybeSingle();

        if (eventMatch) {
          // Generate an invitation for them
          const token = crypto.randomBytes(32).toString('hex');
          const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

          const { data: createdInv } = await supabaseAdmin
            .from('event_invitation')
            .insert({
              id_event: eventMatch.id_event,
              id_provider: providerMatch.id_provider,
              invited_email: normalizedEmail,
              token,
              expires_at: expiresAt,
              is_accepted: false,
            })
            .select('*, event(*), provider(*)')
            .maybeSingle();

          activeInvitation = createdInv;
        }
      }
    }

    // 3. If still no invitation found, deny
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

    // 4. Ensure invitation token is valid/fresh
    let token = activeInvitation.token;
    if (activeInvitation.expires_at && new Date(activeInvitation.expires_at).getTime() < Date.now()) {
      token = crypto.randomBytes(32).toString('hex');
      const newExpiry = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
      await supabaseAdmin
        .from('event_invitation')
        .update({ token, expires_at: newExpiry })
        .eq('id_invitation', activeInvitation.id_invitation);
    }

    const origin = req.nextUrl.origin || 'http://localhost:3000';
    const magicLink = `${origin}/auth/verify?token=${token}`;

    // 5. Audit log
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
      eventTag: activeInvitation.event?.tag_event || 'Concurso',
      eventTitle: activeInvitation.event?.event_type || 'Licitación Asignada',
      providerName: activeInvitation.provider?.provider_name || 'Contratista',
      representative: activeInvitation.provider?.provider_representative || '',
    });
  } catch (err: any) {
    console.error('Error in /api/auth/request-link:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al procesar la solicitud de enlace.' },
      { status: 500 }
    );
  }
}
