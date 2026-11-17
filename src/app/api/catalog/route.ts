import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { type, data, userId, userRole } = body;
    const meta = extractRequestMeta(req);

    if (!type || !data) {
      return NextResponse.json({ error: 'Faltan parámetros requeridos (type, data).' }, { status: 400 });
    }

    if (type === 'MATERIAL') {
      const { data: maxRow } = await supabaseAdmin
        .from('catalog_material')
        .select('id_catalog_material')
        .order('id_catalog_material', { ascending: false })
        .limit(1)
        .maybeSingle();

      const nextId = (maxRow?.id_catalog_material || 0) + 1;
      const tag = data.tag_catalog_material || `MAT-${String(nextId).padStart(4, '0')}`;

      const { data: inserted, error: insertErr } = await supabaseAdmin
        .from('catalog_material')
        .insert({
          id_catalog_material: nextId,
          tag_catalog_material: tag,
          catalog_material_description: data.catalog_material_description,
          catalog_material_unit: data.catalog_material_unit || 'PZA',
          catalog_material_unit_price: parseFloat(data.catalog_material_unit_price) || 0,
          catalog_material_brand: data.catalog_material_brand || null,
          catalog_material_model: data.catalog_material_model || null,
        })
        .select()
        .single();

      if (insertErr) throw insertErr;

      await logAudit({
        userId: userId || null,
        userRole: userRole || 'ADMIN',
        action: 'CREATE',
        entityType: 'CATALOG_MATERIAL',
        entityId: String(nextId),
        details: { tag, description: data.catalog_material_description, unit_price: data.catalog_material_unit_price },
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      });

      return NextResponse.json({ success: true, item: inserted });
    }

    if (type === 'LABOR') {
      const { data: maxRow } = await supabaseAdmin
        .from('catalog_labor')
        .select('id_catalog_labor')
        .order('id_catalog_labor', { ascending: false })
        .limit(1)
        .maybeSingle();

      const nextId = (maxRow?.id_catalog_labor || 0) + 1;
      const tag = data.tag_catalog_labor || `MO-${String(nextId).padStart(3, '0')}`;

      const { data: inserted, error: insertErr } = await supabaseAdmin
        .from('catalog_labor')
        .insert({
          id_catalog_labor: nextId,
          tag_catalog_labor: tag,
          catalog_labor_category: data.catalog_labor_category,
          catalog_labor_unit: data.catalog_labor_unit || 'Jornada',
          catalog_labor_unit_price: parseFloat(data.catalog_labor_unit_price) || 0,
        })
        .select()
        .single();

      if (insertErr) throw insertErr;

      await logAudit({
        userId: userId || null,
        userRole: userRole || 'ADMIN',
        action: 'CREATE',
        entityType: 'CATALOG_LABOR',
        entityId: String(nextId),
        details: { tag, category: data.catalog_labor_category, unit_price: data.catalog_labor_unit_price },
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      });

      return NextResponse.json({ success: true, item: inserted });
    }

    if (type === 'EQUIPMENT') {
      const { data: maxRow } = await supabaseAdmin
        .from('catalog_equipment')
        .select('id_catalog_equipment')
        .order('id_catalog_equipment', { ascending: false })
        .limit(1)
        .maybeSingle();

      const nextId = (maxRow?.id_catalog_equipment || 0) + 1;
      const tag = data.tag_catalog_equipment || `EQ-${String(nextId).padStart(3, '0')}`;

      const { data: inserted, error: insertErr } = await supabaseAdmin
        .from('catalog_equipment')
        .insert({
          id_catalog_equipment: nextId,
          tag_catalog_equipment: tag,
          catalog_equipment_description: data.catalog_equipment_description,
          catalog_equipment_unit: data.catalog_equipment_unit || 'HORA',
          catalog_equipment_unit_price: parseFloat(data.catalog_equipment_unit_price) || 0,
          catalog_equipment_brand: data.catalog_equipment_brand || null,
          catalog_equipment_model: data.catalog_equipment_model || null,
        })
        .select()
        .single();

      if (insertErr) throw insertErr;

      await logAudit({
        userId: userId || null,
        userRole: userRole || 'ADMIN',
        action: 'CREATE',
        entityType: 'CATALOG_EQUIPMENT',
        entityId: String(nextId),
        details: { tag, description: data.catalog_equipment_description, unit_price: data.catalog_equipment_unit_price },
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      });

      return NextResponse.json({ success: true, item: inserted });
    }

    return NextResponse.json({ error: 'Tipo de catálogo inválido.' }, { status: 400 });
  } catch (err: any) {
    console.error('Error in /api/catalog:', err);
    return NextResponse.json({ error: err?.message || 'Error al procesar el catálogo.' }, { status: 500 });
  }
}
