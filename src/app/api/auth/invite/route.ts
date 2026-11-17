import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { email, fullName, providerName, id_event, accessRole = 'WRITE', userId, userRole } = body;

    if (!email || !id_event) {
      return NextResponse.json(
        { error: 'Correo electrónico y Concurso (id_event) son obligatorios.' },
        { status: 400 }
      );
    }

    const normalizedEmail = String(email).trim().toLowerCase();
    const eventId = Number(id_event);

    // 1. Find or create provider
    let providerId: number | null = null;
    if (providerName) {
      const { data: existingProvider } = await supabaseAdmin
        .from('provider')
        .select('id_provider')
        .ilike('provider_name', providerName.trim())
        .limit(1)
        .maybeSingle();

      if (existingProvider) {
        providerId = existingProvider.id_provider;
      } else {
        // Find max provider ID
        const { data: maxRow } = await supabaseAdmin
          .from('provider')
          .select('id_provider')
          .order('id_provider', { ascending: false })
          .limit(1)
          .maybeSingle();

        const nextProviderId = (maxRow?.id_provider || 0) + 1;
        const tag = `PROV-${String(nextProviderId).padStart(3, '0')}`;

        const { data: newProvider, error: provErr } = await supabaseAdmin
          .from('provider')
          .insert({
            id_provider: nextProviderId,
            tag_provider: tag,
            provider_name: providerName.trim(),
            provider_representative: fullName || null,
            contact_email: normalizedEmail,
          })
          .select()
          .single();

        if (!provErr && newProvider) {
          providerId = newProvider.id_provider;
        }
      }
    }

    // 2. Generate secure signed token
    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(); // 7 days

    // 3. Store invitation
    const invitationPayload = {
      id_event: eventId,
      id_provider: providerId,
      invited_email: normalizedEmail,
      token,
      expires_at: expiresAt,
      is_accepted: false,
    };

    const { data: invitation, error: invErr } = await supabaseAdmin
      .from('event_invitation')
      .insert(invitationPayload)
      .select()
      .single();

    if (invErr) {
      console.warn('Notice inserting event_invitation:', invErr.message);
    }

    // 4. Assign provider to event if providerId exists
    if (providerId) {
      const { error: assignErr } = await supabaseAdmin
        .from('event_provider_assignment')
        .upsert(
          {
            id_event: eventId,
            id_provider: providerId,
            access_role: accessRole,
            assigned_at: new Date().toISOString(),
          },
          { onConflict: 'id_event,id_provider' }
        );

      if (assignErr) {
        console.warn('Notice updating event_provider_assignment:', assignErr.message);
      }
    }

    // 5. Build full Magic Link URL
    const origin = req.nextUrl.origin || 'http://localhost:3000';
    const magicLink = `${origin}/auth/verify?token=${token}`;

    // 6. Write Audit Record
    const meta = extractRequestMeta(req);
    await logAudit({
      userId: userId || 'admin-001',
      userRole: userRole || 'ADMIN',
      action: 'CREATE',
      entityType: 'INVITATION',
      entityId: String(eventId),
      details: {
        invited_email: normalizedEmail,
        provider_name: providerName || 'Sin asignar',
        id_provider: providerId,
        id_event: eventId,
        token_prefix: token.substring(0, 8) + '...',
        magicLink,
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    return NextResponse.json({
      success: true,
      message: 'Invitación generada con éxito.',
      token,
      magicLink,
      invitation: invitation || invitationPayload,
    });
  } catch (err: any) {
    console.error('Error in /api/auth/invite:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al procesar la invitación.' },
      { status: 500 }
    );
  }
}
