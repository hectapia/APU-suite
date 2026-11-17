'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { Concept, CatalogMaterial, CatalogLabor, CatalogEquipment } from '@/types/database';
import { calculateAPU } from '@/lib/apu-engine';
import { X, Plus, Trash2, Calculator, Check, AlertCircle, FileText } from 'lucide-react';

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
}

export const ApuWorkbenchModal: React.FC<ApuWorkbenchModalProps> = ({
  concept,
  isOpen,
  onClose,
  onSaveAPU,
  catalogMaterials,
  catalogLabor,
  catalogEquipment,
}) => {
  const [activeTab, setActiveTab] = useState<'RESOURCES' | 'CASCADE'>('RESOURCES');
  const [materials, setMaterials] = useState<MaterialItemState[]>([]);
  const [labor, setLabor] = useState<LaborItemState[]>([]);
  const [equipment, setEquipment] = useState<EquipmentItemState[]>([]);

  // Performance factors
  const [laborYield, setLaborYield] = useState<number>(1.0);
  const [laborYieldUnit, setLaborYieldUnit] = useState<string>('JOR/SERV');
  const [equipmentYield, setEquipmentYield] = useState<number>(1.0);
  const [equipmentYieldUnit, setEquipmentYieldUnit] = useState<string>('HORA/SERV');

  // Overheads and Markups
  const [pctIndirects, setPctIndirects] = useState<number>(0.15); // 15%
  const [pctFinancing, setPctFinancing] = useState<number>(0.015); // 1.5%
  const [pctUtility, setPctUtility] = useState<number>(0.15); // 15%
  const [pctSafetyEquipment, setPctSafetyEquipment] = useState<number>(0.015); // 1.5%
  const [pctHandTools, setPctHandTools] = useState<number>(0.03); // 3.0%
  const [applySfp, setApplySfp] = useState<boolean>(false);

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load existing or seed data when opening Concept 480 or another concept
  useEffect(() => {
    if (concept && isOpen) {
      setError(null);
      if (concept.id_concept === 480) {
        // Pre-populate with Concept 480 verified data
        setMaterials([
          { description: 'Kit de ligas y sellos para inyector diésel Cummins ISX', unit: 'KIT', quantity: 6, unitPrice: 211.31 },
          { description: 'Líquido limpiador concentrado de inyectores diésel para laboratorio y tina ultrasónica', unit: 'LITRO', quantity: 2, unitPrice: 236.26 },
          { description: 'Filtro separador de combustible y agua Fleetguard FF5776', unit: 'PZA', quantity: 1, unitPrice: 822.00 },
          { description: 'Filtro de combustible primario enroscable Fleetguard FF2200', unit: 'PZA', quantity: 1, unitPrice: 327.40 },
          { description: 'Aditivo acondicionador y limpiador preventivo de inyectores diésel', unit: 'LITRO', quantity: 1, unitPrice: 255.00 },
          { description: 'Desengrasante dieléctrico y limpiador de contactos electrónicos para arnés de inyectores', unit: 'PZA', quantity: 1, unitPrice: 145.00 },
          { description: 'Estopa de algodón blanca para limpieza de componentes', unit: 'KG', quantity: 1, unitPrice: 65.00 },
        ]);
        setLabor([
          { category: 'Operario Especialista en Hidráulica de equipo semipesado', unit: 'JORNADA', quantity: 1, unitPrice: 2946.22 },
          { category: 'Ayudante', unit: 'JORNADA', quantity: 1, unitPrice: 1089.29 },
        ]);
        setEquipment([
          { description: 'Banco de pruebas y calibración para inyectores diésel Common Rail y EUI', unit: 'HORA', quantity: 1, unitPrice: 650.00 },
          { description: 'Tina de limpieza por ultrasonido industrial para componentes de inyección', unit: 'HORA', quantity: 1, unitPrice: 180.00 },
          { description: 'Escáner de diagnóstico electrónico para vehículos pesados protocolo J1939', unit: 'HORA', quantity: 1, unitPrice: 320.00 },
          { description: 'Compresor de aire estacionario de 5 HP para sopleteo y pruebas neumáticas', unit: 'HORA', quantity: 1, unitPrice: 110.00 },
          { description: 'Torquímetro de precisión con rango de 10 a 150 lb-pie para montaje de inyectores', unit: 'HORA', quantity: 1, unitPrice: 45.00 },
          { description: 'Juego de extractores hidráulicos y herramienta especializada para desmontaje de inyectores', unit: 'HORA', quantity: 1, unitPrice: 60.00 },
        ]);
        setLaborYield(1.0);
        setEquipmentYield(1.0);
        setPctIndirects(0.15);
        setPctFinancing(0.015);
        setPctUtility(0.15);
        setApplySfp(false);
      } else {
        // Defaults for other service concepts
        setMaterials([]);
        setLabor([
          { category: 'Operario Especialista Combustión Interna', unit: 'JORNADA', quantity: 1, unitPrice: 3507.45 },
          { category: 'Ayudante', unit: 'JORNADA', quantity: 1, unitPrice: 1089.29 },
        ]);
        setEquipment([]);
        setLaborYield(1.0);
        setEquipmentYield(1.0);
      }
    }
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

  // Add Item Handlers
  const addMaterialRow = () => {
    const defaultCatalog = catalogMaterials[0];
    setMaterials((prev) => [
      ...prev,
      {
        description: defaultCatalog ? defaultCatalog.catalog_material_description : 'Nuevo Material',
        unit: defaultCatalog ? defaultCatalog.catalog_material_unit : 'PZA',
        quantity: 1,
        unitPrice: defaultCatalog ? defaultCatalog.catalog_material_unit_price : 0,
      },
    ]);
  };

  const addLaborRow = () => {
    const defaultCatalog = catalogLabor[0];
    setLabor((prev) => [
      ...prev,
      {
        category: defaultCatalog ? defaultCatalog.catalog_labor_category : 'Operario',
        unit: defaultCatalog ? defaultCatalog.catalog_labor_unit : 'JORNADA',
        quantity: 1,
        unitPrice: defaultCatalog ? defaultCatalog.catalog_labor_unit_price : 1000,
      },
    ]);
  };

  const addEquipmentRow = () => {
    const defaultCatalog = catalogEquipment[0];
    setEquipment((prev) => [
      ...prev,
      {
        description: defaultCatalog ? defaultCatalog.catalog_equipment_description : 'Equipo especializado',
        unit: defaultCatalog ? defaultCatalog.catalog_equipment_unit : 'HORA',
        quantity: 1,
        unitPrice: defaultCatalog ? defaultCatalog.catalog_equipment_unit_price : 100,
      },
    ]);
  };

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
    <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-2 sm:p-4">
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 max-w-5xl w-full h-[90vh] flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-200">
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
            className="text-slate-400 hover:text-white p-1.5 rounded-lg hover:bg-slate-800 cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Navigation Tabs between Resources and Overheads */}
        <div className="px-6 py-2 border-b border-slate-200 bg-slate-50 flex items-center justify-between shrink-0">
          <div className="flex items-center space-x-2 text-xs font-semibold">
            <button
              onClick={() => setActiveTab('RESOURCES')}
              className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer ${
                activeTab === 'RESOURCES'
                  ? 'bg-slate-900 text-white shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              1. Insumos Directos (Mat / MO / Eq / Herr)
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
              2. Cascada de Sobrecostos (A &rarr; G &rarr; SFP)
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
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {error && (
            <div className="p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {activeTab === 'RESOURCES' ? (
            <div className="space-y-6">
              {/* SECTION 1: MATERIALS */}
              <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                  <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-slate-800 text-white flex items-center justify-center text-[10px]">1</span>
                    Materiales (catalog_material)
                  </h4>
                  <div className="flex items-center gap-4">
                    <span className="text-xs font-mono font-bold text-slate-700">
                      Subtotal: ${apuOutputs.subtotalMaterials.toFixed(2)}
                    </span>
                    <button
                      type="button"
                      onClick={addMaterialRow}
                      className="text-xs text-emerald-600 hover:text-emerald-700 font-semibold flex items-center gap-1 cursor-pointer"
                    >
                      <Plus className="w-3.5 h-3.5" /> Agregar Material
                    </button>
                  </div>
                </div>

                <div className="p-3 overflow-x-auto">
                  {materials.length === 0 ? (
                    <p className="text-xs text-slate-400 py-3 text-center italic">No hay materiales asignados a este concepto.</p>
                  ) : (
                    <table className="w-full text-xs text-left">
                      <thead className="text-[10px] text-slate-400 uppercase font-semibold border-b border-slate-100">
                        <tr>
                          <th className="pb-2">Descripción</th>
                          <th className="pb-2 w-20">Unidad</th>
                          <th className="pb-2 w-20 text-right">Cant.</th>
                          <th className="pb-2 w-28 text-right">P.U.</th>
                          <th className="pb-2 w-28 text-right">Importe</th>
                          <th className="pb-2 w-8"></th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100">
                        {materials.map((m, idx) => (
                          <tr key={idx} className="hover:bg-slate-50">
                            <td className="py-2 pr-2">
                              <input
                                type="text"
                                value={m.description}
                                onChange={(e) => {
                                  const val = e.target.value;
                                  setMaterials((prev) => prev.map((item, i) => (i === idx ? { ...item, description: val } : item)));
                                }}
                                className="w-full px-2 py-1 border border-slate-200 rounded text-xs focus:ring-1 focus:ring-emerald-500"
                              />
                            </td>
                            <td className="py-2 pr-2">
                              <input
                                type="text"
                                value={m.unit}
                                onChange={(e) => {
                                  const val = e.target.value;
                                  setMaterials((prev) => prev.map((item, i) => (i === idx ? { ...item, unit: val } : item)));
                                }}
                                className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-center"
                              />
                            </td>
                            <td className="py-2 pr-2">
                              <input
                                type="number"
                                step="0.01"
                                min="0"
                                value={m.quantity}
                                onChange={(e) => {
                                  const val = parseFloat(e.target.value) || 0;
                                  setMaterials((prev) => prev.map((item, i) => (i === idx ? { ...item, quantity: val } : item)));
                                }}
                                className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono"
                              />
                            </td>
                            <td className="py-2 pr-2">
                              <input
                                type="number"
                                step="0.01"
                                min="0"
                                value={m.unitPrice}
                                onChange={(e) => {
                                  const val = parseFloat(e.target.value) || 0;
                                  setMaterials((prev) => prev.map((item, i) => (i === idx ? { ...item, unitPrice: val } : item)));
                                }}
                                className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono"
                              />
                            </td>
                            <td className="py-2 text-right font-mono font-bold text-slate-800">
                              ${(m.quantity * m.unitPrice).toFixed(2)}
                            </td>
                            <td className="py-2 pl-2 text-right">
                              <button
                                onClick={() => setMaterials((prev) => prev.filter((_, i) => i !== idx))}
                                className="text-slate-400 hover:text-red-500 cursor-pointer"
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

              {/* SECTION 2: LABOR (Cuadrilla & Rendimiento) */}
              <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                  <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-slate-800 text-white flex items-center justify-center text-[10px]">2</span>
                    Mano de Obra & Cuadrilla (catalog_labor)
                  </h4>
                  <div className="flex items-center gap-4">
                    <span className="text-xs font-mono font-bold text-slate-700">
                      Subtotal: ${apuOutputs.subtotalLabor.toFixed(2)}
                    </span>
                    <button
                      type="button"
                      onClick={addLaborRow}
                      className="text-xs text-emerald-600 hover:text-emerald-700 font-semibold flex items-center gap-1 cursor-pointer"
                    >
                      <Plus className="w-3.5 h-3.5" /> Agregar Cuadrilla
                    </button>
                  </div>
                </div>

                <div className="p-3 space-y-3">
                  <table className="w-full text-xs text-left">
                    <thead className="text-[10px] text-slate-400 uppercase font-semibold border-b border-slate-100">
                      <tr>
                        <th className="pb-2">Categoría</th>
                        <th className="pb-2 w-20">Unidad</th>
                        <th className="pb-2 w-20 text-right">Cant.</th>
                        <th className="pb-2 w-28 text-right">Salario Base</th>
                        <th className="pb-2 w-28 text-right">Importe</th>
                        <th className="pb-2 w-8"></th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {labor.map((l, idx) => (
                        <tr key={idx} className="hover:bg-slate-50">
                          <td className="py-2 pr-2">
                            <input
                              type="text"
                              value={l.category}
                              onChange={(e) => {
                                const val = e.target.value;
                                setLabor((prev) => prev.map((item, i) => (i === idx ? { ...item, category: val } : item)));
                              }}
                              className="w-full px-2 py-1 border border-slate-200 rounded text-xs"
                            />
                          </td>
                          <td className="py-2 pr-2 text-center text-slate-500 font-semibold text-[11px]">
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
                                setLabor((prev) => prev.map((item, i) => (i === idx ? { ...item, quantity: val } : item)));
                              }}
                              className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono"
                            />
                          </td>
                          <td className="py-2 pr-2">
                            <input
                              type="number"
                              step="0.01"
                              min="0"
                              value={l.unitPrice}
                              onChange={(e) => {
                                const val = parseFloat(e.target.value) || 0;
                                setLabor((prev) => prev.map((item, i) => (i === idx ? { ...item, unitPrice: val } : item)));
                              }}
                              className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono"
                            />
                          </td>
                          <td className="py-2 text-right font-mono font-bold text-slate-800">
                            ${(l.quantity * l.unitPrice).toFixed(2)}
                          </td>
                          <td className="py-2 pl-2 text-right">
                            <button
                              onClick={() => setLabor((prev) => prev.filter((_, i) => i !== idx))}
                              className="text-slate-400 hover:text-red-500 cursor-pointer"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>

                  {/* Intermediate Performance Control */}
                  <div className="bg-emerald-50/60 p-3 rounded-lg border border-emerald-200/80 flex items-center justify-between text-xs">
                    <span className="font-semibold text-emerald-900 flex items-center gap-1.5">
                      Rendimiento Global de Mano de Obra (Intermediate Table):
                    </span>
                    <div className="flex items-center gap-2">
                      <input
                        type="number"
                        step="0.01"
                        min="0.0001"
                        value={laborYield}
                        onChange={(e) => setLaborYield(parseFloat(e.target.value) || 1.0)}
                        className="w-20 px-2 py-1 bg-white border border-emerald-300 rounded font-mono text-right font-bold text-emerald-900"
                      />
                      <span className="font-mono text-emerald-700 font-semibold">{laborYieldUnit}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* SECTION 3: MACHINERY & EQUIPMENT */}
              <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                  <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-slate-800 text-white flex items-center justify-center text-[10px]">3</span>
                    Maquinaria y Equipo (catalog_equipment)
                  </h4>
                  <div className="flex items-center gap-4">
                    <span className="text-xs font-mono font-bold text-slate-700">
                      Subtotal: ${apuOutputs.subtotalEquipment.toFixed(2)}
                    </span>
                    <button
                      type="button"
                      onClick={addEquipmentRow}
                      className="text-xs text-emerald-600 hover:text-emerald-700 font-semibold flex items-center gap-1 cursor-pointer"
                    >
                      <Plus className="w-3.5 h-3.5" /> Agregar Equipo
                    </button>
                  </div>
                </div>

                <div className="p-3 space-y-3">
                  <table className="w-full text-xs text-left">
                    <thead className="text-[10px] text-slate-400 uppercase font-semibold border-b border-slate-100">
                      <tr>
                        <th className="pb-2">Descripción</th>
                        <th className="pb-2 w-20">Unidad</th>
                        <th className="pb-2 w-20 text-right">Cant.</th>
                        <th className="pb-2 w-28 text-right">Costo Horario</th>
                        <th className="pb-2 w-28 text-right">Importe</th>
                        <th className="pb-2 w-8"></th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {equipment.map((eq, idx) => (
                        <tr key={idx} className="hover:bg-slate-50">
                          <td className="py-2 pr-2">
                            <input
                              type="text"
                              value={eq.description}
                              onChange={(e) => {
                                const val = e.target.value;
                                setEquipment((prev) => prev.map((item, i) => (i === idx ? { ...item, description: val } : item)));
                              }}
                              className="w-full px-2 py-1 border border-slate-200 rounded text-xs"
                            />
                          </td>
                          <td className="py-2 pr-2 text-center text-slate-500 font-semibold text-[11px]">
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
                                setEquipment((prev) => prev.map((item, i) => (i === idx ? { ...item, quantity: val } : item)));
                              }}
                              className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono"
                            />
                          </td>
                          <td className="py-2 pr-2">
                            <input
                              type="number"
                              step="0.01"
                              min="0"
                              value={eq.unitPrice}
                              onChange={(e) => {
                                const val = parseFloat(e.target.value) || 0;
                                setEquipment((prev) => prev.map((item, i) => (i === idx ? { ...item, unitPrice: val } : item)));
                              }}
                              className="w-full px-2 py-1 border border-slate-200 rounded text-xs text-right font-mono"
                            />
                          </td>
                          <td className="py-2 text-right font-mono font-bold text-slate-800">
                            ${(eq.quantity * eq.unitPrice).toFixed(2)}
                          </td>
                          <td className="py-2 pl-2 text-right">
                            <button
                              onClick={() => setEquipment((prev) => prev.filter((_, i) => i !== idx))}
                              className="text-slate-400 hover:text-red-500 cursor-pointer"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>

                  {/* Intermediate Performance Control */}
                  <div className="bg-emerald-50/60 p-3 rounded-lg border border-emerald-200/80 flex items-center justify-between text-xs">
                    <span className="font-semibold text-emerald-900 flex items-center gap-1.5">
                      Rendimiento Global de Maquinaria y Equipo (Intermediate Table):
                    </span>
                    <div className="flex items-center gap-2">
                      <input
                        type="number"
                        step="0.01"
                        min="0.0001"
                        value={equipmentYield}
                        onChange={(e) => setEquipmentYield(parseFloat(e.target.value) || 1.0)}
                        className="w-20 px-2 py-1 bg-white border border-emerald-300 rounded font-mono text-right font-bold text-emerald-900"
                      />
                      <span className="font-mono text-emerald-700 font-semibold">{equipmentYieldUnit}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* SECTION 4: SAFETY EQUIPMENT & HAND TOOLS */}
              <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                <div className="bg-slate-100/80 px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                  <h4 className="text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-slate-800 text-white flex items-center justify-center text-[10px]">4</span>
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
                      <span className="font-mono font-bold text-slate-900">{(pctSafetyEquipment * 100).toFixed(1)}%</span>
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
                      <span className="font-mono font-bold text-slate-900">{(pctHandTools * 100).toFixed(1)}%</span>
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
              <span>Revisa los insumos antes de validar la cascada de sobrecostos.</span>
            ) : (
              <span>El precio unitario final se sincronizará con el catálogo de conceptos.</span>
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
              disabled={saving}
              className="px-5 py-2 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg shadow-sm flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
            >
              <Check className="w-4 h-4" />
              {saving ? 'Guardando...' : 'Guardar e Integrar APU'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
