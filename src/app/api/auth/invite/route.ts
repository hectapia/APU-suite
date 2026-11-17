import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';
import { recordInvitationInStore } from '@/lib/invitation-store';

// GET: Fetch existing invitations, providers, and event assignments
export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const eventId = searchParams.get('id_event');

    let invQuery = supabaseAdmin
      .from('event_invitation')
      .select('*, event(*), provider(*)')
      .order('created_at', { ascending: false });

    if (eventId) {
      invQuery = invQuery.eq('id_event', Number(eventId));
    }

    const [invRes, provRes] = await Promise.all([
      invQuery,
      supabaseAdmin.from('provider').select('*').order('provider_name', { ascending: true }),
    ]);

    return NextResponse.json({
      success: true,
      invitations: invRes.data || [],
      providers: provRes.data || [],
    });
  } catch (err: any) {
    console.error('Error fetching invitations:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al obtener invitaciones.' },
      { status: 500 }
    );
  }
}

// POST: Create new invitation and link contractor to event
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      email,
      fullName,
      providerId: incomingProviderId,
      providerName,
      id_event,
      accessRole = 'WRITE',
      userId,
      userRole,
    } = body;

    if (!email || !id_event) {
      return NextResponse.json(
        { error: 'Correo electrónico y Concurso (id_event) son obligatorios.' },
        { status: 400 }
      );
    }

    const normalizedEmail = String(email).trim().toLowerCase();
    const eventId = Number(id_event);

    // 1. Resolve or create provider
    let providerId: number | null = incomingProviderId ? Number(incomingProviderId) : null;

    if (!providerId && providerName) {
      const { data: existingProvider } = await supabaseAdmin
        .from('provider')
        .select('id_provider')
        .ilike('provider_name', providerName.trim())
        .limit(1)
        .maybeSingle();

      if (existingProvider) {
        providerId = existingProvider.id_provider;
      } else {
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

    // Update provider representative / email if available
    if (providerId && (fullName || normalizedEmail)) {
      await supabaseAdmin
        .from('provider')
        .update({
          ...(fullName ? { provider_representative: fullName } : {}),
          ...(normalizedEmail ? { contact_email: normalizedEmail } : {}),
        })
        .eq('id_provider', providerId);
    }

    // 2. Link Contractor to Event:
    // A) Directly on event table if column id_provider exists
    if (providerId) {
      const { error: eventUpdateErr } = await supabaseAdmin
        .from('event')
        .update({ id_provider: providerId })
        .eq('id_event', eventId);

      if (eventUpdateErr) {
        console.warn('Notice updating event.id_provider:', eventUpdateErr.message);
      }

      // B) On event_provider_assignment table
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

    // 3. Generate secure signed token
    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(); // 7 days

    // 4. Store invitation
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
      .select('*, event(*), provider(*)')
      .single();

    if (invErr) {
      console.warn('Notice inserting event_invitation:', invErr.message);
    }

    // 5. Register in dual-layer store
    recordInvitationInStore({
      id_invitation: invitation?.id_invitation || `inv-${Date.now()}`,
      id_event: eventId,
      id_provider: providerId,
      invited_email: normalizedEmail,
      token,
      expires_at: expiresAt,
      is_accepted: false,
      created_at: new Date().toISOString(),
      event: invitation?.event || {
        id_event: eventId,
        tag_event: `PEP-DG-SAP-${String(eventId).padStart(3, '0')}-2026`,
        event_type: 'Concurso / Licitación Asignada',
      },
      provider: invitation?.provider || {
        id_provider: providerId,
        provider_name: providerName || 'Contratista Asignado',
        provider_representative: fullName,
      },
    });

    // 6. Build Magic Link
    const origin = req.nextUrl.origin || 'http://localhost:3000';
    const magicLink = `${origin}/auth/verify?token=${token}`;

    // 7. Write Audit Record
    const meta = extractRequestMeta(req);
    await logAudit({
      userId: userId || 'admin-001',
      userRole: userRole || 'ADMIN',
      action: 'CREATE',
      entityType: 'INVITATION',
      entityId: String(eventId),
      details: {
        id_invitation: invitation?.id_invitation,
        invited_email: normalizedEmail,
        provider_name: providerName || 'Asignado',
        id_provider: providerId,
        id_event: eventId,
        access_role: accessRole,
        magicLink,
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    return NextResponse.json({
      success: true,
      message: 'Invitación y vinculación de contratista creadas con éxito.',
      token,
      magicLink,
      invitation: invitation || invitationPayload,
    });
  } catch (err: any) {
    console.error('Error in POST /api/auth/invite:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al procesar la invitación.' },
      { status: 500 }
    );
  }
}

// PUT: Edit existing invitation, update contractor data, or re-link event
export async function PUT(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      id_invitation,
      id_event,
      providerId: incomingProviderId,
      providerName,
      fullName,
      email,
      accessRole = 'WRITE',
      regenerateToken = false,
      userId,
      userRole,
    } = body;

    if (!id_invitation) {
      return NextResponse.json(
        { error: 'id_invitation es obligatorio para editar.' },
        { status: 400 }
      );
    }

    const normalizedEmail = email ? String(email).trim().toLowerCase() : undefined;
    const eventId = id_event ? Number(id_event) : undefined;
    let providerId: number | null = incomingProviderId ? Number(incomingProviderId) : null;

    // 1. Resolve or update provider
    if (!providerId && providerName) {
      const { data: existingProvider } = await supabaseAdmin
        .from('provider')
        .select('id_provider')
        .ilike('provider_name', providerName.trim())
        .limit(1)
        .maybeSingle();

      if (existingProvider) {
        providerId = existingProvider.id_provider;
      }
    }

    if (providerId) {
      const provUpdate: any = {};
      if (providerName) provUpdate.provider_name = providerName.trim();
      if (fullName) provUpdate.provider_representative = fullName.trim();
      if (normalizedEmail) provUpdate.contact_email = normalizedEmail;

      if (Object.keys(provUpdate).length > 0) {
        await supabaseAdmin.from('provider').update(provUpdate).eq('id_provider', providerId);
      }
    }

    // 2. Link Contractor to Event if both provided
    if (eventId && providerId) {
      // Update event.id_provider
      await supabaseAdmin.from('event').update({ id_provider: providerId }).eq('id_event', eventId);

      // Update event_provider_assignment
      await supabaseAdmin
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
    }

    // 3. Prepare invitation updates
    const invUpdate: any = {};
    if (eventId) invUpdate.id_event = eventId;
    if (providerId) invUpdate.id_provider = providerId;
    if (normalizedEmail) invUpdate.invited_email = normalizedEmail;

    let newToken: string | undefined;
    if (regenerateToken) {
      newToken = crypto.randomBytes(32).toString('hex');
      invUpdate.token = newToken;
      invUpdate.expires_at = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
      invUpdate.is_accepted = false;
    }

    const { data: updatedInvitation, error: updateErr } = await supabaseAdmin
      .from('event_invitation')
      .update(invUpdate)
      .eq('id_invitation', id_invitation)
      .select('*, event(*), provider(*)')
      .single();

    if (updateErr) throw updateErr;

    const origin = req.nextUrl.origin || 'http://localhost:3000';
    const magicLink = updatedInvitation?.token
      ? `${origin}/auth/verify?token=${updatedInvitation.token}`
      : undefined;

    // 4. Log Audit
    const meta = extractRequestMeta(req);
    await logAudit({
      userId: userId || 'admin-001',
      userRole: userRole || 'ADMIN',
      action: 'UPDATE',
      entityType: 'INVITATION',
      entityId: String(id_invitation),
      details: {
        id_invitation,
        id_event: eventId,
        id_provider: providerId,
        invited_email: normalizedEmail,
        regenerated: regenerateToken,
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    return NextResponse.json({
      success: true,
      message: 'Invitación y asignación de contratista actualizadas con éxito.',
      invitation: updatedInvitation,
      magicLink,
    });
  } catch (err: any) {
    console.error('Error in PUT /api/auth/invite:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al actualizar la invitación.' },
      { status: 500 }
    );
  }
}

// DELETE: Cancel / remove an invitation
export async function DELETE(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const id_invitation = searchParams.get('id_invitation');

    if (!id_invitation) {
      return NextResponse.json(
        { error: 'id_invitation es requerido para eliminar.' },
        { status: 400 }
      );
    }

    const { error: delErr } = await supabaseAdmin
      .from('event_invitation')
      .delete()
      .eq('id_invitation', id_invitation);

    if (delErr) throw delErr;

    const meta = extractRequestMeta(req);
    await logAudit({
      userRole: 'ADMIN',
      action: 'DELETE',
      entityType: 'INVITATION',
      entityId: String(id_invitation),
      details: { id_invitation },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    return NextResponse.json({
      success: true,
      message: 'Invitación eliminada con éxito.',
    });
  } catch (err: any) {
    console.error('Error in DELETE /api/auth/invite:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al eliminar la invitación.' },
      { status: 500 }
    );
  }
}
