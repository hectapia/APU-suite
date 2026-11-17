import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';
import { getInvitationByToken, recordInvitationInStore } from '@/lib/invitation-store';

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

    const cleanToken = token.trim();

    // 1. Resolve invitation through dual-layer store
    const invitation = await getInvitationByToken(cleanToken);

    if (!invitation || !invInvitationValid(invitation)) {
      await logAudit({
        userRole: 'ANONYMOUS',
        action: 'DENIED',
        entityType: 'AUTH_VERIFY',
        entityId: cleanToken.substring(0, 10),
        details: { reason: 'Token inválido, expirado o no encontrado.', token: cleanToken },
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      });

      return NextResponse.json(
        { error: 'El enlace de acceso es inválido o ha expirado.' },
        { status: 401 }
      );
    }

    // 2. Mark invitation accepted in DB and cache
    invitation.is_accepted = true;
    invitation.accepted_at = new Date().toISOString();
    recordInvitationInStore(invitation);

    try {
      await supabaseAdmin
        .from('event_invitation')
        .update({
          is_accepted: true,
          accepted_at: new Date().toISOString(),
        })
        .eq('token', cleanToken);
    } catch {
      // non-blocking
    }

    // 3. Find or create app_user
    const email = invitation.invited_email.toLowerCase();
    const providerName = invitation.provider?.provider_name || 'MHEBOSAP, S.A. DE C.V.';
    const fullName = invitation.provider?.provider_representative || `Estimador (${providerName})`;
    const providerId = invitation.id_provider || 1;

    let userId = 'prov-' + providerId;

    try {
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
            id_provider: providerId,
            is_active: true,
          })
          .select()
          .maybeSingle();

        if (newUser) {
          userId = newUser.id_user;
        }
      }
    } catch {
      // non-blocking fallback
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
        id_provider: providerId,
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
      id_provider: providerId,
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
