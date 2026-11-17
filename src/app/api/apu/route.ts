import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabase-admin';
import { logAudit, extractRequestMeta } from '@/lib/audit';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      conceptId,
      materials,
      labor,
      equipment,
      laborYield,
      laborYieldUnit,
      equipmentYield,
      equipmentYieldUnit,
      pctIndirects,
      pctFinancing,
      pctUtility,
      pctSafetyEquipment,
      pctHandTools,
      applySfp,
      apuOutputs,
    } = body;

    if (!conceptId || !apuOutputs) {
      return NextResponse.json({ error: 'Faltan parámetros requeridos para guardar el APU.' }, { status: 400 });
    }

    // 1. Upsert Labor Performance Group
    const { data: laborPg, error: laborPgErr } = await supabaseAdmin
      .from('concept_performance_group')
      .upsert(
        {
          id_concept: conceptId,
          resource_type: 'LABOR',
          performance_factor: laborYield || 1.0,
          performance_unit: laborYieldUnit || 'JOR/SERV',
          calculation_mode: 'MULTIPLICATION',
        },
        { onConflict: 'id_concept,resource_type' }
      )
      .select('id_performance_group')
      .single();

    if (laborPgErr) throw laborPgErr;

    // 2. Upsert Equipment Performance Group
    const { data: eqPg, error: eqPgErr } = await supabaseAdmin
      .from('concept_performance_group')
      .upsert(
        {
          id_concept: conceptId,
          resource_type: 'EQUIPMENT',
          performance_factor: equipmentYield || 1.0,
          performance_unit: equipmentYieldUnit || 'HORA/SERV',
          calculation_mode: 'MULTIPLICATION',
        },
        { onConflict: 'id_concept,resource_type' }
      )
      .select('id_performance_group')
      .single();

    if (eqPgErr) throw eqPgErr;

    // 3. Upsert APU Integration Header
    const { data: apuRecord, error: apuErr } = await supabaseAdmin
      .from('concept_apu_integration')
      .upsert(
        {
          id_concept: conceptId,
          id_provider: 1, // MHEBOSAP
          pct_indirects: pctIndirects,
          pct_financing: pctFinancing,
          pct_utility: pctUtility,
          pct_safety_equipment: pctSafetyEquipment,
          pct_hand_tools: pctHandTools,
          apply_sfp: Boolean(applySfp),
          subtotal_materials: apuOutputs.subtotalMaterials,
          subtotal_labor: apuOutputs.subtotalLabor,
          subtotal_equipment: apuOutputs.subtotalEquipment,
          subtotal_safety_tools: apuOutputs.subtotalSafetyTools,
          cost_direct_a: apuOutputs.costDirectA,
          cost_indirect_b: apuOutputs.costIndirectB,
          cost_sum_c: apuOutputs.costSumC,
          cost_financing_d: apuOutputs.costFinancingD,
          cost_sum_e: apuOutputs.costSumE,
          cost_utility_f: apuOutputs.costUtilityF,
          cost_sum_g: apuOutputs.costSumG,
          cost_sfp: apuOutputs.costSfp,
          concept_price: apuOutputs.conceptPrice,
          concept_price_txt: apuOutputs.conceptPriceTxt,
          status: 'COMPLETED',
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'id_concept,id_provider' }
      )
      .select('id_apu')
      .single();

    if (apuErr) throw apuErr;
    const apuId = apuRecord.id_apu;

    // 4. Clean previous line items for this APU
    await Promise.all([
      supabaseAdmin.from('material_by_concept').delete().eq('id_apu', apuId),
      supabaseAdmin.from('labor_by_concept').delete().eq('id_apu', apuId),
      supabaseAdmin.from('equipment_by_concept').delete().eq('id_apu', apuId),
    ]);

    // 5. Insert new Material lines
    if (materials && materials.length > 0) {
      const matInserts = materials.map((m: any) => ({
        id_apu: apuId,
        id_concept: conceptId,
        id_catalog_material: m.catalogId || null,
        material_description: m.description,
        unit: m.unit,
        quantity: parseFloat(m.quantity) || 0,
        unit_price: parseFloat(m.unitPrice) || 0,
      }));

      const { error: matErr } = await supabaseAdmin.from('material_by_concept').insert(matInserts);
      if (matErr) throw matErr;
    }

    // 6. Insert new Labor lines
    if (labor && labor.length > 0) {
      const labInserts = labor.map((l: any) => ({
        id_apu: apuId,
        id_concept: conceptId,
        id_performance_group: laborPg.id_performance_group,
        id_catalog_labor: l.catalogId || null,
        category: l.category,
        unit: l.unit || 'JORNADA',
        quantity: parseFloat(l.quantity) || 0,
        unit_price: parseFloat(l.unitPrice) || 0,
      }));

      const { error: labErr } = await supabaseAdmin.from('labor_by_concept').insert(labInserts);
      if (labErr) throw labErr;
    }

    // 7. Insert new Equipment lines
    if (equipment && equipment.length > 0) {
      const eqInserts = equipment.map((e: any) => ({
        id_apu: apuId,
        id_concept: conceptId,
        id_performance_group: eqPg.id_performance_group,
        id_catalog_equipment: e.catalogId || null,
        equipment_description: e.description,
        unit: e.unit || 'HORA',
        quantity: parseFloat(e.quantity) || 0,
        unit_price: parseFloat(e.unitPrice) || 0,
      }));

      const { error: eqErr } = await supabaseAdmin.from('equipment_by_concept').insert(eqInserts);
      if (eqErr) throw eqErr;
    }

    // 8. Sync price and Spanish legal text into concept table
    const { error: conceptUpdateErr } = await supabaseAdmin
      .from('concept')
      .update({
        concept_price: apuOutputs.conceptPrice,
        concept_price_txt: apuOutputs.conceptPriceTxt,
      })
      .eq('id_concept', conceptId);

    if (conceptUpdateErr) throw conceptUpdateErr;

    // 9. Write audit record
    const meta = extractRequestMeta(req);
    await logAudit({
      userId: body.userId || null,
      userRole: body.userRole || 'PROVIDER_ESTIMATOR',
      action: 'UPDATE',
      entityType: 'APU',
      entityId: String(conceptId),
      details: {
        id_apu: apuId,
        conceptPrice: apuOutputs.conceptPrice,
        conceptPriceTxt: apuOutputs.conceptPriceTxt,
        materialsCount: materials?.length || 0,
        laborCount: labor?.length || 0,
        equipmentCount: equipment?.length || 0,
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    return NextResponse.json({ success: true, id_apu: apuId });
  } catch (err: any) {
    console.error('Error in /api/apu:', err);
    return NextResponse.json({ error: err?.message || 'Error al guardar la integración APU.' }, { status: 500 });
  }
}
