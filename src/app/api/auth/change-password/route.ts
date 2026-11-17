import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { email, currentPassword, newPassword, userId } = body;

    if (!email || !newPassword) {
      return NextResponse.json(
        { error: 'Correo y nueva contraseña son obligatorios.' },
        { status: 400 }
      );
    }

    if (newPassword.length < 6) {
      return NextResponse.json(
        { error: 'La nueva contraseña debe tener al menos 6 caracteres.' },
        { status: 400 }
      );
    }

    const normalizedEmail = String(email).trim().toLowerCase();
    const newHash = crypto.createHash('sha256').update(newPassword).digest('hex');

    // Update in Supabase app_user if table and column exist
    const { error: userErr } = await supabaseAdmin
      .from('app_user')
      .upsert(
        {
          email: normalizedEmail,
          password_hash: newHash,
          full_name: 'Ing. Héctor Tapia (Administrador)',
          role: 'ADMIN',
          is_active: true,
        },
        { onConflict: 'email' }
      );

    if (userErr) {
      console.warn('Notice updating password in app_user:', userErr.message);
    }

    // Write audit record
    const meta = extractRequestMeta(req);
    await logAudit({
      userId: userId || 'admin-001',
      userRole: 'ADMIN',
      action: 'UPDATE',
      entityType: 'USER_PASSWORD',
      entityId: normalizedEmail,
      details: {
        email: normalizedEmail,
        action: 'PASSWORD_CHANGED',
        timestamp: new Date().toISOString(),
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    return NextResponse.json({
      success: true,
      message: 'Contraseña actualizada con éxito.',
    });
  } catch (err: any) {
    console.error('Error in POST /api/auth/change-password:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al actualizar la contraseña.' },
      { status: 500 }
    );
  }
}
