import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const token = searchParams.get('token');
    const meta = extractRequestMeta(req);

    if (!token) {
      await logAudit({
        userRole: 'ANONYMOUS',
        action: 'DENIED',
        entityType: 'AUTH_VERIFY',
        details: { reason: 'Token ausente en la petición.' },
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      });

      return NextResponse.json(
        { error: 'Token de acceso no proporcionado.' },
        { status: 400 }
      );
    }

    // 1. Query invitation
    const { data: invitation, error: invErr } = await supabaseAdmin
      .from('event_invitation')
      .select('*, event(*), provider(*)')
      .eq('token', token)
      .limit(1)
      .maybeSingle();

    if (invErr || !invInvitationValid(invitation)) {
      await logAudit({
        userRole: 'ANONYMOUS',
        action: 'DENIED',
        entityType: 'AUTH_VERIFY',
        entityId: token.substring(0, 10),
        details: { reason: 'Token inválido, expirado o no encontrado.' },
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      });

      return NextResponse.json(
        { error: 'El enlace de acceso es inválido o ha expirado.' },
        { status: 401 }
      );
    }

    // 2. Mark invitation accepted
    await supabaseAdmin
      .from('event_invitation')
      .update({
        is_accepted: true,
        accepted_at: new Date().toISOString(),
      })
      .eq('id_invitation', invitation.id_invitation);

    // 3. Find or create app_user
    const email = invitation.invited_email;
    const providerName = invitation.provider?.provider_name || 'Contratista';
    const fullName = invitation.provider?.provider_representative || `Estimador (${providerName})`;

    let userId = 'prov-' + (invitation.id_provider || '001');

    const { data: existingUser } = await supabaseAdmin
      .from('app_user')
      .select('*')
      .eq('email', email)
      .limit(1)
      .maybeSingle();

    if (existingUser) {
      userId = existingUser.id_user;
    } else {
      const { data: newUser } = await supabaseAdmin
        .from('app_user')
        .insert({
          email,
          full_name: fullName,
          role: 'PROVIDER_ESTIMATOR',
          is_active: true,
        })
        .select()
        .maybeSingle();

      if (newUser) {
        userId = newUser.id_user;
      }
    }

    // 4. Record Audit Log for successful magic link sign-in
    await logAudit({
      userId,
      userRole: 'PROVIDER_ESTIMATOR',
      action: 'READ',
      entityType: 'AUTH_VERIFY',
      entityId: String(invitation.id_event),
      details: {
        email,
        id_event: invitation.id_event,
        id_provider: invitation.id_provider,
        provider_name: providerName,
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    const userSession = {
      id_user: userId,
      email,
      full_name: fullName,
      role: 'PROVIDER_ESTIMATOR',
      id_provider: invitation.id_provider,
      provider_name: providerName,
    };

    return NextResponse.json({
      success: true,
      user: userSession,
      event: invitation.event,
    });
  } catch (err: any) {
    console.error('Error in /api/auth/verify:', err);
    return NextResponse.json(
      { error: err?.message || 'Error validando credencial.' },
      { status: 500 }
    );
  }
}

function invInvitationValid(invitation: any): boolean {
  if (!invitation) return false;
  if (invitation.expires_at) {
    const expiry = new Date(invitation.expires_at).getTime();
    if (Date.now() > expiry) return false;
  }
  return true;
}
