import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabase-admin';

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const limit = Math.min(Number(searchParams.get('limit')) || 50, 100);
    const action = searchParams.get('action');
    const entityType = searchParams.get('entity_type');

    let query = supabaseAdmin
      .from('audit_log')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(limit);

    if (action && action !== 'ALL') {
      query = query.eq('action', action);
    }
    if (entityType && entityType !== 'ALL') {
      query = query.eq('entity_type', entityType);
    }

    const { data, error } = await query;

    if (error) {
      // If table doesn't exist yet, return gracefully with empty array and hint
      return NextResponse.json({
        success: true,
        auditLogs: [],
        notice: error.message,
      });
    }

    return NextResponse.json({
      success: true,
      auditLogs: data || [],
    });
  } catch (err: any) {
    console.error('Error fetching audit log:', err);
    return NextResponse.json(
      { error: err?.message || 'Error al obtener bitácora de auditoría.' },
      { status: 500 }
    );
  }
}
