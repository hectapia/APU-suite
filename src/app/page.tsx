'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import {
  EventDashboardView,
  Concept,
  CatalogMaterial,
  CatalogLabor,
  CatalogEquipment,
} from '@/types/database';
import { EventCard } from '@/components/EventCard';
import { ConceptTable } from '@/components/ConceptTable';
import { ApuWorkbenchModal } from '@/components/ApuWorkbenchModal';
import { DirectPriceModal } from '@/components/DirectPriceModal';
import { AddConceptModal } from '@/components/AddConceptModal';
import { AlertCircle, RefreshCw, Database } from 'lucide-react';

export default function DashboardPage() {
  const [events, setEvents] = useState<EventDashboardView[]>([]);
  const [concepts, setConcepts] = useState<Concept[]>([]);
  const [catalogMaterials, setCatalogMaterials] = useState<CatalogMaterial[]>([]);
  const [catalogLabor, setCatalogLabor] = useState<CatalogLabor[]>([]);
  const [catalogEquipment, setCatalogEquipment] = useState<CatalogEquipment[]>([]);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Modals state
  const [selectedApuConcept, setSelectedApuConcept] = useState<Concept | null>(null);
  const [isApuOpen, setIsApuOpen] = useState(false);

  const [selectedDirectConcept, setSelectedDirectConcept] = useState<Concept | null>(null);
  const [isDirectPriceOpen, setIsDirectPriceOpen] = useState(false);

  const [isAddConceptOpen, setIsAddConceptOpen] = useState(false);

  // Fetch all core data from Supabase
  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      // 1. Fetch Dashboard Events
      const { data: eventData, error: eventErr } = await supabase
        .from('v_event_dashboard')
        .select('*');

      if (eventErr) throw eventErr;
      setEvents(eventData || []);

      // 2. Fetch Concepts (All 1,335 items)
      const { data: conceptData, error: conceptErr } = await supabase
        .from('concept')
        .select('*')
        .order('id_concept', { ascending: true });

      if (conceptErr) throw conceptErr;
      setConcepts(conceptData || []);

      // 3. Fetch Master Catalogs
      const [matRes, labRes, eqRes] = await Promise.all([
        supabase.from('catalog_material').select('*'),
        supabase.from('catalog_labor').select('*'),
        supabase.from('catalog_equipment').select('*'),
      ]);

      if (matRes.data) setCatalogMaterials(matRes.data);
      if (labRes.data) setCatalogLabor(labRes.data);
      if (eqRes.data) setCatalogEquipment(eqRes.data);
    } catch (err: any) {
      console.error('Error loading Supabase data:', err);
      setError(err?.message || 'Error al conectar con la base de datos Supabase.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  // Handler: Save APU Integration
  const handleSaveAPU = async (conceptId: number, apuData: any) => {
    const { apuOutputs, laborYield, laborYieldUnit, equipmentYield, equipmentYieldUnit } = apuData;

    // 1. Upsert intermediate performance groups
    await supabase.from('concept_performance_group').upsert([
      {
        id_concept: conceptId,
        resource_type: 'LABOR',
        performance_factor: laborYield,
        performance_unit: laborYieldUnit,
      },
      {
        id_concept: conceptId,
        resource_type: 'EQUIPMENT',
        performance_factor: equipmentYield,
        performance_unit: equipmentYieldUnit,
      },
    ]);

    // 2. Upsert APU integration header
    const { error: apuErr } = await supabase.from('concept_apu_integration').upsert(
      {
        id_concept: conceptId,
        id_provider: 1, // MHEBOSAP
        pct_indirects: apuData.pctIndirects,
        pct_financing: apuData.pctFinancing,
        pct_utility: apuData.pctUtility,
        pct_safety_equipment: apuData.pctSafetyEquipment,
        pct_hand_tools: apuData.pctHandTools,
        apply_sfp: apuData.applySfp,
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
      },
      { onConflict: 'id_concept,id_provider' }
    );

    if (apuErr) throw apuErr;

    // 3. Update concept table with computed price and text
    const { error: conceptErr } = await supabase
      .from('concept')
      .update({
        concept_price: apuOutputs.conceptPrice,
        concept_price_txt: apuOutputs.conceptPriceTxt,
      })
      .eq('id_concept', conceptId);

    if (conceptErr) throw conceptErr;

    // Refresh UI
    await loadData();
  };

  // Handler: Save Direct Price for non-service concept
  const handleSaveDirectPrice = async (conceptId: number, newPrice: number) => {
    const { error: updateErr } = await supabase
      .from('concept')
      .update({ concept_price: newPrice })
      .eq('id_concept', conceptId);

    if (updateErr) throw updateErr;

    // Refresh UI
    await loadData();
  };

  // Handler: Add new concept
  const handleAddConcept = async (newConcept: {
    tag_concept: string;
    concept_header: string;
    concept_description: string;
    concept_unit: string;
  }) => {
    // Generate next sequential ID
    const maxId = concepts.reduce((acc, c) => Math.max(acc, c.id_concept), 0);
    const nextId = maxId + 1;

    const { error: insertErr } = await supabase.from('concept').insert({
      id_concept: nextId,
      id_event: 1,
      id_client: 1,
      tag_concept: newConcept.tag_concept,
      concept_header: newConcept.concept_header || null,
      concept_description: newConcept.concept_description,
      concept_unit: newConcept.concept_unit,
      display_order: nextId,
    });

    if (insertErr) throw insertErr;

    // Refresh UI
    await loadData();
  };

  return (
    <div className="space-y-8">
      {/* Top Banner / Error notice */}
      {error && (
        <div className="p-4 bg-red-50 border border-red-200 text-red-800 rounded-xl text-xs flex items-center justify-between">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-red-600 shrink-0" />
            <span>{error}</span>
          </div>
          <button
            onClick={loadData}
            className="text-xs font-semibold px-3 py-1 bg-white border border-red-300 rounded hover:bg-red-50 cursor-pointer"
          >
            Reintentar
          </button>
        </div>
      )}

      {/* SECTION 1: EVENTS DASHBOARD GRID */}
      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-bold text-slate-900 tracking-tight flex items-center gap-2">
              <Database className="w-5 h-5 text-emerald-600" />
              Concursos y Licitaciones
            </h2>
            <p className="text-xs text-slate-500">
              Panel de control de eventos asignados al contratista
            </p>
          </div>
          <button
            onClick={loadData}
            disabled={loading}
            className="text-xs font-medium text-slate-600 hover:text-slate-900 flex items-center gap-1.5 p-1.5 rounded hover:bg-slate-200/50 cursor-pointer"
            title="Recargar datos desde Supabase"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin text-emerald-600' : ''}`} />
            <span className="hidden sm:inline">Actualizar</span>
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {events.length === 0 && !loading ? (
            <div className="col-span-full p-8 text-center bg-white rounded-xl border border-slate-200 text-slate-400 text-xs">
              No se encontraron eventos activos en la base de datos.
            </div>
          ) : (
            events.map((ev) => (
              <EventCard
                key={ev.id_event}
                event={ev}
                onExploreConcepts={() => {
                  const tableElem = document.getElementById('concept-database');
                  if (tableElem) tableElem.scrollIntoView({ behavior: 'smooth' });
                }}
                onAddConcept={() => setIsAddConceptOpen(true)}
              />
            ))
          )}
        </div>
      </section>

      {/* SECTION 2: CONCEPTS DATABASE & SEARCH EXPLORER */}
      <section id="concept-database" className="space-y-4 pt-4 border-t border-slate-200">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-bold text-slate-900 tracking-tight">
              Catálogo General de Conceptos
            </h2>
            <p className="text-xs text-slate-500">
              Localice conceptos con el buscador para integrar precios unitarios (DT-7) o asignar precios directos
            </p>
          </div>
        </div>

        <ConceptTable
          concepts={concepts}
          loading={loading}
          onOpenApu={(c) => {
            setSelectedApuConcept(c);
            setIsApuOpen(true);
          }}
          onOpenDirectPrice={(c) => {
            setSelectedDirectConcept(c);
            setIsDirectPriceOpen(true);
          }}
        />
      </section>

      {/* MODAL 1: APU WORKBENCH (DT-7) */}
      <ApuWorkbenchModal
        concept={selectedApuConcept}
        isOpen={isApuOpen}
        onClose={() => {
          setIsApuOpen(false);
          setSelectedApuConcept(null);
        }}
        onSaveAPU={handleSaveAPU}
        catalogMaterials={catalogMaterials}
        catalogLabor={catalogLabor}
        catalogEquipment={catalogEquipment}
      />

      {/* MODAL 2: DIRECT PRICE ASSIGNMENT */}
      <DirectPriceModal
        concept={selectedDirectConcept}
        isOpen={isDirectPriceOpen}
        onClose={() => {
          setIsDirectPriceOpen(false);
          setSelectedDirectConcept(null);
        }}
        onSave={handleSaveDirectPrice}
      />

      {/* MODAL 3: ADD CONCEPT */}
      <AddConceptModal
        isOpen={isAddConceptOpen}
        onClose={() => setIsAddConceptOpen(false)}
        onAdd={handleAddConcept}
      />
    </div>
  );
}
