import { supabaseAdmin } from './supabase-admin';
import { AuditAction, AuditLog } from '@/types/database';
import { NextRequest } from 'next/server';

export interface LogAuditParams {
  userId?: string | null;
  userRole?: string;
  action: AuditAction;
  entityType: string;
  entityId?: string | number | null;
  details?: Record<string, any>;
  ipAddress?: string | null;
  userAgent?: string | null;
}

export function extractRequestMeta(req: NextRequest): { ipAddress: string | null; userAgent: string | null } {
  const forwarded = req.headers.get('x-forwarded-for');
  const ip = forwarded ? forwarded.split(',')[0].trim() : req.headers.get('x-real-ip') || null;
  const userAgent = req.headers.get('user-agent') || null;
  return { ipAddress: ip, userAgent };
}

export async function logAudit(params: LogAuditParams): Promise<{ success: boolean }> {
  try {
    const payload = {
      id_user: params.userId ? String(params.userId) : null,
      user_role: params.userRole || 'ANONYMOUS',
      action: params.action,
      entity_type: params.entityType,
      entity_id: params.entityId ? String(params.entityId) : null,
      details: params.details || {},
      ip_address: params.ipAddress || null,
      user_agent: params.userAgent || null,
    };

    const { error } = await supabaseAdmin.from('audit_log').insert(payload);
    if (error) {
      console.warn('AuditLog insert warning:', error.message);
    }
    return { success: !error };
  } catch (err: any) {
    console.warn('AuditLog exception:', err?.message);
    return { success: false };
  }
}
