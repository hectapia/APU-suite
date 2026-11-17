'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { supabase } from '@/lib/supabase';
import { Concept, CatalogMaterial, CatalogLabor, CatalogEquipment } from '@/types/database';
import { calculateAPU } from '@/lib/apu-engine';
import { CatalogPickerModal, CatalogPickerType } from './CatalogPickerModal';
import { 
  X, 
  Plus, 
  Trash2, 
  Calculator, 
  Check, 
  AlertCircle, 
  FileText, 
  Box, 
  Users, 
  Wrench, 
  Layers, 
  Sparkles,
  Search
} from 'lucide-react';

interface MaterialItemState {
  id?: string;
  catalogId?: number;
  description: string;
  unit: string;
  quantity: number;
  unitPrice: number;
}

interface LaborItemState {
  id?: string;
  catalogId?: number;
  category: string;
  unit: string;
  quantity: number;
  unitPrice: number;
}

interface EquipmentItemState {
  id?: string;
  catalogId?: number;
  description: string;
  unit: string;
  quantity: number;
  unitPrice: number;
}

interface ApuWorkbenchModalProps {
  concept: Concept | null;
  isOpen: boolean;
  onClose: () => void;
  onSaveAPU: (conceptId: number, apuData: any) => Promise<void>;
  catalogMaterials: CatalogMaterial[];
  catalogLabor: CatalogLabor[];
  catalogEquipment: CatalogEquipment[];
  onCatalogItemCreated?: (type: CatalogPickerType, item: any) => void;
}

export const ApuWorkbenchModal: React.FC<ApuWorkbenchModalProps> = ({
  concept,
  isOpen,
  onClose,
  onSaveAPU,
  catalogMaterials,
  catalogLabor,
  catalogEquipment,
  onCatalogItemCreated,
}) => {
  const [activeTab, setActiveTab] = useState<'RESOURCES' | 'CASCADE'>('RESOURCES');
  const [loadingDetails, setLoadingDetails] = useState(false);

  // Line items state (material_by_concept, labor_by_concept, equipment_by_concept)
  const [materials, setMaterials] = useState<MaterialItemState[]>([]);
  const [labor, setLabor] = useState<LaborItemState[]>([]);
  const [equipment, setEquipment] = useState<EquipmentItemState[]>([]);

  // Intermediate Performance factors (concept_performance_group)
  const [laborYield, setLaborYield] = useState<number>(1.0);
  const [laborYieldUnit, setLaborYieldUnit] = useState<string>('JOR/SERV');
  const [equipmentYield, setEquipmentYield] = useState<number>(1.0);
  const [equipmentYieldUnit, setEquipmentYieldUnit] = useState<string>('HORA/SERV');

  // Overheads and Markups (concept_apu_integration)
  const [pctIndirects, setPctIndirects] = useState<number>(0.15); // 15%
  const [pctFinancing, setPctFinancing] = useState<number>(0.015); // 1.5%
  const [pctUtility, setPctUtility] = useState<number>(0.15); // 15%
  const [pctSafetyEquipment, setPctSafetyEquipment] = useState<number>(0.015); // 1.5%
  const [pctHandTools, setPctHandTools] = useState<number>(0.03); // 3.0%
  const [applySfp, setApplySfp] = useState<boolean>(false);

  // Catalog Picker Modal State
  const [catalogPickerType, setCatalogPickerType] = useState<CatalogPickerType | null>(null);
  const [isCatalogPickerOpen, setIsCatalogPickerOpen] = useState(false);

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load real saved data from Supabase for this concept (zero fake proposals!)
  useEffect(() => {
    if (!concept || !isOpen) return;

    let isMounted = true;
    const fetchConceptData = async () => {
      setLoadingDetails(true);
      setError(null);
      try {
        const conceptId = concept.id_concept;

        // Fetch APU header, performance groups, and detail lines concurrently
        const [apuRes, perfRes, matRes, labRes, eqRes] = await Promise.all([
          supabase.from('concept_apu_integration').select('*').eq('id_concept', conceptId).maybeSingle(),
          supabase.from('concept_performance_group').select('*').eq('id_concept', conceptId),
          supabase.from('material_by_concept').select('*').eq('id_concept', conceptId),
          supabase.from('labor_by_concept').select('*').eq('id_concept', conceptId),
          supabase.from('equipment_by_concept').select('*').eq('id_concept', conceptId),
        ]);

        if (!isMounted) return;

        // 1. APU Header
        if (apuRes.data) {
          const apu = apuRes.data;
          setPctIndirects(Number(apu.pct_indirects) ?? 0.15);
          setPctFinancing(Number(apu.pct_financing) ?? 0.015);
          setPctUtility(Number(apu.pct_utility) ?? 0.15);
          setPctSafetyEquipment(Number(apu.pct_safety_equipment) ?? 0.015);
          setPctHandTools(Number(apu.pct_hand_tools) ?? 0.03);
          setApplySfp(Boolean(apu.apply_sfp));
        } else {
          // Standard defaults for new APU
          setPctIndirects(0.15);
          setPctFinancing(0.015);
          setPctUtility(0.15);
          setPctSafetyEquipment(0.015);
          setPctHandTools(0.03);
          setApplySfp(false);
        }

        // 2. Intermediate Performance Groups
        const laborPerf = perfRes.data?.find((p: any) => p.resource_type === 'LABOR');
        if (laborPerf) {
          setLaborYield(Number(laborPerf.performance_factor) || 1.0);
          setLaborYieldUnit(laborPerf.performance_unit || 'JOR/SERV');
        } else {
          setLaborYield(1.0);
          setLaborYieldUnit('JOR/SERV');
        }

        const eqPerf = perfRes.data?.find((p: any) => p.resource_type === 'EQUIPMENT');
        if (eqPerf) {
          setEquipmentYield(Number(eqPerf.performance_factor) || 1.0);
          setEquipmentYieldUnit(eqPerf.performance_unit || 'HORA/SERV');
        } else {
          setEquipmentYield(1.0);
          setEquipmentYieldUnit('HORA/SERV');
        }

        // 3. Detail lines: only populate what exists in database. Otherwise EMPTY arrays.
        if (matRes.data && matRes.data.length > 0) {
          setMaterials(
            matRes.data.map((m: any) => ({
              id: m.id_material_by_concept,
              catalogId: m.id_catalog_material,
              description: m.material_description,
              unit: m.unit,
              quantity: Number(m.quantity),
              unitPrice: Number(m.unit_price),
            }))
          );
        } else {
          setMaterials([]);
        }

        if (labRes.data && labRes.data.length > 0) {
          setLabor(
            labRes.data.map((l: any) => ({
              id: l.id_labor_by_concept,
              catalogId: l.id_catalog_labor,
              category: l.category,
              unit: l.unit,
              quantity: Number(l.quantity),
              unitPrice: Number(l.unit_price),
            }))
          );
        } else {
          setLabor([]);
        }

        if (eqRes.data && eqRes.data.length > 0) {
          setEquipment(
            eqRes.data.map((e: any) => ({
              id: e.id_equipment_by_concept,
              catalogId: e.id_catalog_equipment,
              description: e.equipment_description,
              unit: e.unit,
              quantity: Number(e.quantity),
              unitPrice: Number(e.unit_price),
            }))
          );
        } else {
          setEquipment([]);
        }
      } catch (err: any) {
        console.error('Error loading APU details:', err);
        if (isMounted) setError('Error al cargar la integración existente del concepto.');
      } finally {
        if (isMounted) setLoadingDetails(false);
      }
    };

    fetchConceptData();

    return () => {
      isMounted = false;
    };
  }, [concept, isOpen]);

  // Live calculation of APU cascade
  const apuOutputs = useMemo(() => {
    return calculateAPU({
      materialItems: materials.map((m) => ({ quantity: m.quantity, unitPrice: m.unitPrice })),
      laborItems: labor.map((l) => ({ quantity: l.quantity, unitPrice: l.unitPrice })),
      equipmentItems: equipment.map((e) => ({ quantity: e.quantity, unitPrice: e.unitPrice })),
      laborPerformanceFactor: laborYield,
      equipmentPerformanceFactor: equipmentYield,
      pctIndirects,
      pctFinancing,
      pctUtility,
      pctSafetyEquipment,
      pctHandTools,
      applySfp,
    });
  }, [
    materials,
    labor,
    equipment,
    laborYield,
    equipmentYield,
    pctIndirects,
    pctFinancing,
    pctUtility,
    pctSafetyEquipment,
    pctHandTools,
    applySfp,
  ]);

  if (!isOpen || !concept) return null;

  // Handlers to open Catalog Picker
  const handleOpenMaterialCatalog = () => {
    setCatalogPickerType('MATERIAL');
    setIsCatalogPickerOpen(true);
  };

  const handleOpenLaborCatalog = () => {
    setCatalogPickerType('LABOR');
    setIsCatalogPickerOpen(true);
  };

  const handleOpenEquipmentCatalog = () => {
    setCatalogPickerType('EQUIPMENT');
    setIsCatalogPickerOpen(true);
  };

  // Handlers when user selects an item from the catalog
  const handleSelectMaterial = (item: CatalogMaterial) => {
    setMaterials((prev) => [
      ...prev,
      {
        catalogId: item.id_catalog_material,
        description: item.catalog_material_description,
        unit: item.catalog_material_unit,
        quantity: 1,
        unitPrice: Number(item.catalog_material_unit_price),
      },
    ]);
  };

  const handleSelectLabor = (item: CatalogLabor) => {
    setLabor((prev) => [
      ...prev,
      {
        catalogId: item.id_catalog_labor,
        category: item.catalog_labor_category,
        unit: item.catalog_labor_unit,
        quantity: 1.0,
        unitPrice: Number(item.catalog_labor_unit_price),
      },
    ]);
  };

  const handleSelectEquipment = (item: CatalogEquipment) => {
    setEquipment((prev) => [
      ...prev,
      {
        catalogId: item.id_catalog_equipment,
        description: item.catalog_equipment_description,
        unit: item.catalog_equipment_unit,
        quantity: 1.0,
        unitPrice: Number(item.catalog_equipment_unit_price),
      },
    ]);
  };

  // Handler: Save APU
  const handleSave = async () => {
    try {
      setSaving(true);
      setError(null);
      await onSaveAPU(concept.id_concept, {
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
      });
      onClose();
    } catch (err: any) {
      setError(err?.message || 'Error al guardar la integración de precio unitario.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-2 sm:p-4 animate-in fade-in duration-200">
        <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 max-w-5xl w-full h-[90vh] flex flex-col overflow-hidden">
          {/* Header - DT-7 Format Details */}
          <div className="px-6 py-4 border-b border-slate-200 bg-slate-900 text-white flex items-center justify-between shrink-0">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <span className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                  Formato Oficial DT-7
                </span>
                <span className="text-xs font-mono font-bold text-slate-300">
                  Clave {concept.tag_concept}
                </span>
                <span className="text-xs font-bold px-2 py-0.5 rounded bg-slate-800 text-slate-300">
                  Unidad: {concept.concept_unit}
                </span>
              </div>
              <h2 className="text-sm sm:text-base font-bold text-white line-clamp-1">
                {concept.concept_description}
              </h2>
            </div>
            <button
              onClick={onClose}
              className="text-slate-400 hover:text-white p-1.5 rounded-lg hover:bg-slate-800 transition-colors cursor-pointer"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Navigation Tabs between Resources and Overheads */}
          <div className="px-6 py-2.5 border-b border-slate-200 bg-slate-50 flex items-center justify-between shrink-0">
            <div className="flex items-center space-x-2 text-xs font-semibold">
              <button
                onClick={() => setActiveTab('RESOURCES')}
                className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 ${
                  activeTab === 'RESOURCES'
                    ? 'bg-slate-900 text-white shadow-xs'
                    : 'text-slate-600 hover:text-slate-900'
                }`}
              >
                <Layers className="w-3.5 h-3.5" />
                <span>1. Insumos Directos (Mat / Cuadrilla / Equipo)</span>
              </button>
              <button
                onClick={() => setActiveTab('CASCADE')}
                className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 ${
                  activeTab === 'CASCADE'
                    ? 'bg-emerald-600 text-white shadow-xs'
                    : 'text-slate-600 hover:text-slate-900'
                }`}
              >
                <Calculator className="w-3.5 h-3.5" />
                <span>2. Cascada de Sobrecostos (A &rarr; G &rarr; SFP)</span>
              </button>
            </div>

            <div className="text-right">
              <span className="text-xs text-slate-500 font-medium">Precio Unitario Calculado:</span>
              <span className="text-sm font-mono font-bold text-emerald-600 ml-2">
                ${apuOutputs.conceptPrice.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} MXN
              </span>
            </div>
          </div>

          {/* Content Body */}
          <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-6">
            {error && (
              <div className="p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg text-xs flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>{error}</span>
              </div>
            )}

            {loadingDetails ? (
              <div className="p-12 text-center text-slate-400 text-xs">
                Cargando integración y análisis de precios unitarios...
              </div>
            ) : activeTab === 'RESOURCES' ? (
              <div className="space-y-6">
                {/* SECTION 1: MATERIALS (material_by_concept) */}
                <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                  <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                    <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                      <span className="w-5 h-5 rounded-full bg-emerald-700 text-white flex items-center justify-center text-[10px]">
                        1
                      </span>
                      Materiales (material_by_concept)
                    </h4>
                    <div className="flex items-center gap-4">
                      <span className="text-xs font-mono font-bold text-slate-700">
                        Subtotal: ${apuOutputs.subtotalMaterials.toFixed(2)}
                      </span>
                      <button
                        type="button"
                        onClick={handleOpenMaterialCatalog}
                        className="text-xs bg-emerald-50 hover:bg-emerald-100 text-emerald-800 border border-emerald-300 font-semibold px-2.5 py-1 rounded-md flex items-center gap-1.5 cursor-pointer shadow-2xs"
                      >
                        <Box className="w-3.5 h-3.5 text-emerald-600" />
                        <span>Catálogo de Materiales ({catalogMaterials.length})</span>
                      </button>
                    </div>
                  </div>

                  <div className="p-3 overflow-x-auto">
                    {materials.length === 0 ? (
                      <div className="py-6 text-center text-xs text-slate-400 space-y-1">
                        <p className="italic">No hay materiales asignados a este concepto.</p>
                        <p className="text-[11px] text-slate-500">
                          Haga clic en <strong>"Catálogo de Materiales"</strong> para seleccionar o registrar insumos.
                        </p>
                      </div>
                    ) : (
                      <table className="w-full text-xs text-left">
                        <thead className="text-[10px] text-slate-400 uppercase font-semibold border-b border-slate-100">
                          <tr>
                            <th className="pb-2 min-w-[240px]">Descripción del Material</th>
                            <th className="pb-2 w-20 text-center">Unidad</th>
                            <th className="pb-2 w-24 text-right">Cantidad</th>
                            <th className="pb-2 w-28 text-right">P.U. ($)</th>
                            <th className="pb-2 w-28 text-right">Importe ($)</th>
                            <th className="pb-2 w-10 text-center"></th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100">
                          {materials.map((m, idx) => (
                            <tr key={idx} className="hover:bg-slate-50">
                              <td className="py-2 pr-2">
                                <div className="flex items-center gap-2">
                                  {m.catalogId && (
                                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-emerald-100 text-emerald-800 font-mono font-bold">
                                      #{m.catalogId}
                                    </span>
                                  )}
                                  <span className="font-medium text-slate-800">{m.description}</span>
                                </div>
                              </td>
                              <td className="py-2 pr-2 text-center text-slate-600 font-semibold text-[11px]">
                                {m.unit}
                              </td>
                              <td className="py-2 pr-2">
                                <input
                                  type="number"
                                  step="0.01"
                                  min="0"
                                  value={m.quantity}
                                  onChange={(e) => {
                                    const val = parseFloat(e.target.value) || 0;
                                    setMaterials((prev) =>
                                      prev.map((item, i) => (i === idx ? { ...item, quantity: val } : item))
                                    );
                                  }}
                                  className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono focus:ring-1 focus:ring-emerald-500"
                                />
                              </td>
                              <td className="py-2 pr-2 text-right font-mono text-slate-700">
                                ${m.unitPrice.toFixed(2)}
                              </td>
                              <td className="py-2 text-right font-mono font-bold text-slate-800">
                                ${(m.quantity * m.unitPrice).toFixed(2)}
                              </td>
                              <td className="py-2 pl-2 text-center">
                                <button
                                  onClick={() => setMaterials((prev) => prev.filter((_, i) => i !== idx))}
                                  className="text-slate-400 hover:text-red-500 cursor-pointer p-1"
                                  title="Eliminar insumo del concepto"
                                >
                                  <Trash2 className="w-3.5 h-3.5" />
                                </button>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}
                  </div>
                </div>

                {/* SECTION 2: LABOR (labor_by_concept) */}
                <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                  <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                    <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                      <span className="w-5 h-5 rounded-full bg-amber-700 text-white flex items-center justify-center text-[10px]">
                        2
                      </span>
                      Mano de Obra & Cuadrillas (labor_by_concept)
                    </h4>
                    <div className="flex items-center gap-4">
                      <span className="text-xs font-mono font-bold text-slate-700">
                        Subtotal: ${apuOutputs.subtotalLabor.toFixed(2)}
                      </span>
                      <button
                        type="button"
                        onClick={handleOpenLaborCatalog}
                        className="text-xs bg-amber-50 hover:bg-amber-100 text-amber-900 border border-amber-300 font-semibold px-2.5 py-1 rounded-md flex items-center gap-1.5 cursor-pointer shadow-2xs"
                      >
                        <Users className="w-3.5 h-3.5 text-amber-700" />
                        <span>Catálogo de Mano de Obra ({catalogLabor.length})</span>
                      </button>
                    </div>
                  </div>

                  <div className="p-3 space-y-3">
                    {labor.length === 0 ? (
                      <div className="py-6 text-center text-xs text-slate-400 space-y-1">
                        <p className="italic">No hay cuadrillas asignadas a este concepto.</p>
                        <p className="text-[11px] text-slate-500">
                          Haga clic en <strong>"Catálogo de Mano de Obra"</strong> para seleccionar categorías o agregar nuevas.
                        </p>
                      </div>
                    ) : (
                      <table className="w-full text-xs text-left">
                        <thead className="text-[10px] text-slate-400 uppercase font-semibold border-b border-slate-100">
                          <tr>
                            <th className="pb-2 min-w-[240px]">Categoría de Mano de Obra</th>
                            <th className="pb-2 w-20 text-center">Unidad</th>
                            <th className="pb-2 w-24 text-right">Cantidad</th>
                            <th className="pb-2 w-28 text-right">Salario Base</th>
                            <th className="pb-2 w-28 text-right">Importe</th>
                            <th className="pb-2 w-10 text-center"></th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100">
                          {labor.map((l, idx) => (
                            <tr key={idx} className="hover:bg-slate-50">
                              <td className="py-2 pr-2">
                                <div className="flex items-center gap-2">
                                  {l.catalogId && (
                                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-amber-100 text-amber-900 font-mono font-bold">
                                      #{l.catalogId}
                                    </span>
                                  )}
                                  <span className="font-medium text-slate-800">{l.category}</span>
                                </div>
                              </td>
                              <td className="py-2 pr-2 text-center text-slate-600 font-semibold text-[11px]">
                                {l.unit}
                              </td>
                              <td className="py-2 pr-2">
                                <input
                                  type="number"
                                  step="0.1"
                                  min="0"
                                  value={l.quantity}
                                  onChange={(e) => {
                                    const val = parseFloat(e.target.value) || 0;
                                    setLabor((prev) =>
                                      prev.map((item, i) => (i === idx ? { ...item, quantity: val } : item))
                                    );
                                  }}
                                  className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono focus:ring-1 focus:ring-amber-500"
                                />
                              </td>
                              <td className="py-2 pr-2 text-right font-mono text-slate-700">
                                ${l.unitPrice.toFixed(2)}
                              </td>
                              <td className="py-2 text-right font-mono font-bold text-slate-800">
                                ${(l.quantity * l.unitPrice).toFixed(2)}
                              </td>
                              <td className="py-2 pl-2 text-center">
                                <button
                                  onClick={() => setLabor((prev) => prev.filter((_, i) => i !== idx))}
                                  className="text-slate-400 hover:text-red-500 cursor-pointer p-1"
                                  title="Eliminar de la cuadrilla"
                                >
                                  <Trash2 className="w-3.5 h-3.5" />
                                </button>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}

                    {/* Intermediate Performance Control (concept_performance_group) */}
                    <div className="bg-amber-50/70 p-3 rounded-lg border border-amber-200 flex items-center justify-between text-xs">
                      <div>
                        <span className="font-semibold text-amber-950 flex items-center gap-1.5">
                          Rendimiento Global de Mano de Obra (concept_performance_group):
                        </span>
                        <p className="text-[11px] text-amber-800">
                          Jornadas requeridas de la cuadrilla por unidad de servicio
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <input
                          type="number"
                          step="0.01"
                          min="0.0001"
                          value={laborYield}
                          onChange={(e) => setLaborYield(parseFloat(e.target.value) || 1.0)}
                          className="w-24 px-2 py-1 bg-white border border-amber-300 rounded font-mono text-right font-bold text-amber-950 focus:ring-1 focus:ring-amber-500"
                        />
                        <span className="font-mono text-amber-800 font-semibold">{laborYieldUnit}</span>
                      </div>
                    </div>
                  </div>
                </div>

                {/* SECTION 3: MACHINERY & EQUIPMENT (equipment_by_concept) */}
                <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                  <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                    <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                      <span className="w-5 h-5 rounded-full bg-blue-700 text-white flex items-center justify-center text-[10px]">
                        3
                      </span>
                      Maquinaria y Equipo (equipment_by_concept)
                    </h4>
                    <div className="flex items-center gap-4">
                      <span className="text-xs font-mono font-bold text-slate-700">
                        Subtotal: ${apuOutputs.subtotalEquipment.toFixed(2)}
                      </span>
                      <button
                        type="button"
                        onClick={handleOpenEquipmentCatalog}
                        className="text-xs bg-blue-50 hover:bg-blue-100 text-blue-900 border border-blue-300 font-semibold px-2.5 py-1 rounded-md flex items-center gap-1.5 cursor-pointer shadow-2xs"
                      >
                        <Wrench className="w-3.5 h-3.5 text-blue-700" />
                        <span>Catálogo de Equipos ({catalogEquipment.length})</span>
                      </button>
                    </div>
                  </div>

                  <div className="p-3 space-y-3">
                    {equipment.length === 0 ? (
                      <div className="py-6 text-center text-xs text-slate-400 space-y-1">
                        <p className="italic">No hay maquinaria o equipos asignados a este concepto.</p>
                        <p className="text-[11px] text-slate-500">
                          Haga clic en <strong>"Catálogo de Equipos"</strong> para seleccionar maquinaria o dar de alta nuevos equipos.
                        </p>
                      </div>
                    ) : (
                      <table className="w-full text-xs text-left">
                        <thead className="text-[10px] text-slate-400 uppercase font-semibold border-b border-slate-100">
                          <tr>
                            <th className="pb-2 min-w-[240px]">Descripción del Equipo</th>
                            <th className="pb-2 w-20 text-center">Unidad</th>
                            <th className="pb-2 w-24 text-right">Horas / Cant.</th>
                            <th className="pb-2 w-28 text-right">Costo Horario</th>
                            <th className="pb-2 w-28 text-right">Importe</th>
                            <th className="pb-2 w-10 text-center"></th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100">
                          {equipment.map((eq, idx) => (
                            <tr key={idx} className="hover:bg-slate-50">
                              <td className="py-2 pr-2">
                                <div className="flex items-center gap-2">
                                  {eq.catalogId && (
                                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-blue-100 text-blue-900 font-mono font-bold">
                                      #{eq.catalogId}
                                    </span>
                                  )}
                                  <span className="font-medium text-slate-800">{eq.description}</span>
                                </div>
                              </td>
                              <td className="py-2 pr-2 text-center text-slate-600 font-semibold text-[11px]">
                                {eq.unit}
                              </td>
                              <td className="py-2 pr-2">
                                <input
                                  type="number"
                                  step="0.1"
                                  min="0"
                                  value={eq.quantity}
                                  onChange={(e) => {
                                    const val = parseFloat(e.target.value) || 0;
                                    setEquipment((prev) =>
                                      prev.map((item, i) => (i === idx ? { ...item, quantity: val } : item))
                                    );
                                  }}
                                  className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono focus:ring-1 focus:ring-blue-500"
                                />
                              </td>
                              <td className="py-2 pr-2 text-right font-mono text-slate-700">
                                ${eq.unitPrice.toFixed(2)}
                              </td>
                              <td className="py-2 text-right font-mono font-bold text-slate-800">
                                ${(eq.quantity * eq.unitPrice).toFixed(2)}
                              </td>
                              <td className="py-2 pl-2 text-center">
                                <button
                                  onClick={() => setEquipment((prev) => prev.filter((_, i) => i !== idx))}
                                  className="text-slate-400 hover:text-red-500 cursor-pointer p-1"
                                  title="Eliminar equipo"
                                >
                                  <Trash2 className="w-3.5 h-3.5" />
                                </button>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}

                    {/* Intermediate Performance Control (concept_performance_group) */}
                    <div className="bg-blue-50/70 p-3 rounded-lg border border-blue-200 flex items-center justify-between text-xs">
                      <div>
                        <span className="font-semibold text-blue-950 flex items-center gap-1.5">
                          Rendimiento Global de Maquinaria y Equipo (concept_performance_group):
                        </span>
                        <p className="text-[11px] text-blue-800">
                          Horas de uso efectivo de maquinaria por unidad de servicio
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <input
                          type="number"
                          step="0.01"
                          min="0.0001"
                          value={equipmentYield}
                          onChange={(e) => setEquipmentYield(parseFloat(e.target.value) || 1.0)}
                          className="w-24 px-2 py-1 bg-white border border-blue-300 rounded font-mono text-right font-bold text-blue-950 focus:ring-1 focus:ring-blue-500"
                        />
                        <span className="font-mono text-blue-800 font-semibold">{equipmentYieldUnit}</span>
                      </div>
                    </div>
                  </div>
                </div>

                {/* SECTION 4: SAFETY EQUIPMENT & HAND TOOLS */}
                <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                  <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                    <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                      <span className="w-5 h-5 rounded-full bg-slate-800 text-white flex items-center justify-center text-[10px]">
                        4
                      </span>
                      Seguridad y Herramienta Menor (% sobre Mano de Obra)
                    </h4>
                    <span className="text-xs font-mono font-bold text-slate-700">
                      Subtotal: ${apuOutputs.subtotalSafetyTools.toFixed(2)}
                    </span>
                  </div>
                  <div className="p-4 grid grid-cols-2 gap-4 text-xs">
                    <div className="flex items-center justify-between bg-slate-50 p-3 rounded-lg border border-slate-200">
                      <div>
                        <p className="font-semibold text-slate-800">Equipo de Seguridad Personal</p>
                        <p className="text-[11px] text-slate-500">Aplica sobre Subtotal (2) Mano de Obra</p>
                      </div>
                      <div className="text-right">
                        <span className="font-mono font-bold text-slate-900">
                          {(pctSafetyEquipment * 100).toFixed(1)}%
                        </span>
                        <p className="font-mono text-slate-600 text-xs mt-0.5">
                          ${(pctSafetyEquipment * apuOutputs.subtotalLabor).toFixed(2)}
                        </p>
                      </div>
                    </div>

                    <div className="flex items-center justify-between bg-slate-50 p-3 rounded-lg border border-slate-200">
                      <div>
                        <p className="font-semibold text-slate-800">Herramienta Menor</p>
                        <p className="text-[11px] text-slate-500">Aplica sobre Subtotal (2) Mano de Obra</p>
                      </div>
                      <div className="text-right">
                        <span className="font-mono font-bold text-slate-900">
                          {(pctHandTools * 100).toFixed(1)}%
                        </span>
                        <p className="font-mono text-slate-600 text-xs mt-0.5">
                          ${(pctHandTools * apuOutputs.subtotalLabor).toFixed(2)}
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              /* TAB 2: CASCADE OF OVERHEADS (A .. G & SFP) */
              <div className="space-y-6">
                <div className="bg-slate-900 text-white rounded-xl p-6 shadow-md">
                  <h3 className="text-sm font-bold uppercase tracking-wider text-emerald-400 mb-4 flex items-center gap-2">
                    <Calculator className="w-4 h-4" />
                    Cascada de Integración Financiera DT-7
                  </h3>

                  <div className="space-y-3 font-mono text-xs">
                    {/* Step A */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800">
                      <div>
                        <span className="text-emerald-400 font-bold mr-2">A</span>
                        <span>COSTO DIRECTO (1 + 2 + 3 + 4)</span>
                      </div>
                      <span className="text-sm font-bold">${apuOutputs.costDirectA.toFixed(2)}</span>
                    </div>

                    {/* Step B */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800">
                      <div className="flex items-center gap-2">
                        <span className="text-emerald-400 font-bold mr-2">B</span>
                        <span>INDIRECTOS</span>
                        <input
                          type="number"
                          step="0.01"
                          value={pctIndirects}
                          onChange={(e) => setPctIndirects(parseFloat(e.target.value) || 0)}
                          className="w-16 px-1.5 py-0.5 bg-slate-800 border border-slate-700 rounded text-right text-emerald-300"
                        />
                        <span className="text-[11px] text-slate-400">({(pctIndirects * 100).toFixed(1)}% de A)</span>
                      </div>
                      <span>${apuOutputs.costIndirectB.toFixed(2)}</span>
                    </div>

                    {/* Step C */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800 text-slate-300">
                      <div>
                        <span className="text-emerald-400 font-bold mr-2">C</span>
                        <span>SUBTOTAL (A + B)</span>
                      </div>
                      <span>${apuOutputs.costSumC.toFixed(2)}</span>
                    </div>

                    {/* Step D */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800">
                      <div className="flex items-center gap-2">
                        <span className="text-emerald-400 font-bold mr-2">D</span>
                        <span>FINANCIAMIENTO</span>
                        <input
                          type="number"
                          step="0.005"
                          value={pctFinancing}
                          onChange={(e) => setPctFinancing(parseFloat(e.target.value) || 0)}
                          className="w-16 px-1.5 py-0.5 bg-slate-800 border border-slate-700 rounded text-right text-emerald-300"
                        />
                        <span className="text-[11px] text-slate-400">({(pctFinancing * 100).toFixed(2)}% de C)</span>
                      </div>
                      <span>${apuOutputs.costFinancingD.toFixed(2)}</span>
                    </div>

                    {/* Step E */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800 text-slate-300">
                      <div>
                        <span className="text-emerald-400 font-bold mr-2">E</span>
                        <span>SUBTOTAL (C + D)</span>
                      </div>
                      <span>${apuOutputs.costSumE.toFixed(2)}</span>
                    </div>

                    {/* Step F */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800">
                      <div className="flex items-center gap-2">
                        <span className="text-emerald-400 font-bold mr-2">F</span>
                        <span>UTILIDAD</span>
                        <input
                          type="number"
                          step="0.01"
                          value={pctUtility}
                          onChange={(e) => setPctUtility(parseFloat(e.target.value) || 0)}
                          className="w-16 px-1.5 py-0.5 bg-slate-800 border border-slate-700 rounded text-right text-emerald-300"
                        />
                        <span className="text-[11px] text-slate-400">({(pctUtility * 100).toFixed(1)}% de E)</span>
                      </div>
                      <span>${apuOutputs.costUtilityF.toFixed(2)}</span>
                    </div>

                    {/* Step G */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800 text-slate-300">
                      <div>
                        <span className="text-emerald-400 font-bold mr-2">G</span>
                        <span>SUBTOTAL (E + F)</span>
                      </div>
                      <span>${apuOutputs.costSumG.toFixed(2)}</span>
                    </div>

                    {/* SFP 5 al millar */}
                    <div className="flex justify-between items-center py-2 border-b border-slate-800">
                      <div className="flex items-center gap-2">
                        <span className="text-emerald-400 font-bold mr-2">SFP</span>
                        <label className="flex items-center gap-1.5 cursor-pointer">
                          <input
                            type="checkbox"
                            checked={applySfp}
                            onChange={(e) => setApplySfp(e.target.checked)}
                            className="rounded text-emerald-500 focus:ring-0 cursor-pointer"
                          />
                          <span>SFP 5 al millar [G/(1-0.005) - G]</span>
                        </label>
                      </div>
                      <span>${apuOutputs.costSfp.toFixed(2)}</span>
                    </div>

                    {/* FINAL INTEGRATED PRICE */}
                    <div className="flex justify-between items-center pt-3 text-sm font-bold text-emerald-400">
                      <span className="uppercase tracking-wider">PRECIO UNITARIO DE VENTA</span>
                      <span className="text-lg">${apuOutputs.conceptPrice.toFixed(2)} MXN</span>
                    </div>
                  </div>
                </div>

                {/* Legal Text Rendering Card */}
                <div className="bg-emerald-50 p-4 rounded-xl border border-emerald-200">
                  <div className="flex items-center gap-2 text-xs font-bold text-emerald-950 mb-1">
                    <FileText className="w-4 h-4 text-emerald-700" />
                    Importe con Letra (Generado Automáticamente)
                  </div>
                  <p className="text-xs font-medium text-emerald-900 italic leading-relaxed">
                    {apuOutputs.conceptPriceTxt}
                  </p>
                </div>
              </div>
            )}
          </div>

          {/* Modal Footer */}
          <div className="px-6 py-4 border-t border-slate-200 bg-slate-50 flex items-center justify-between shrink-0">
            <div className="text-xs text-slate-500">
              {activeTab === 'RESOURCES' ? (
                <span>Incorpore insumos desde cada catálogo antes de verificar la cascada financiera.</span>
              ) : (
                <span>El precio unitario final se sincronizará con el concepto en la base de datos.</span>
              )}
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={onClose}
                disabled={saving}
                className="px-4 py-2 text-xs font-semibold text-slate-600 hover:text-slate-800 hover:bg-slate-100 rounded-lg cursor-pointer"
              >
                Cancelar
              </button>
              <button
                onClick={handleSave}
                disabled={saving || loadingDetails}
                className="px-5 py-2 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg shadow-sm flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
              >
                <Check className="w-4 h-4" />
                <span>{saving ? 'Guardando...' : 'Guardar e Integrar APU (DT-7)'}</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Catalog Picker & Creation Modal */}
      <CatalogPickerModal
        type={catalogPickerType}
        isOpen={isCatalogPickerOpen}
        onClose={() => {
          setIsCatalogPickerOpen(false);
          setCatalogPickerType(null);
        }}
        catalogMaterials={catalogMaterials}
        catalogLabor={catalogLabor}
        catalogEquipment={catalogEquipment}
        onSelectMaterial={handleSelectMaterial}
        onSelectLabor={handleSelectLabor}
        onSelectEquipment={handleSelectEquipment}
        onItemCreated={(t, item) => {
          if (onCatalogItemCreated) onCatalogItemCreated(t, item);
        }}
      />
    </>
  );
};
