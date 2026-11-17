'use client';

import React, { useState, useMemo } from 'react';
import { CatalogMaterial, CatalogLabor, CatalogEquipment } from '@/types/database';
import { X, Search, Plus, Check, Box, Users, Wrench, AlertCircle, Sparkles } from 'lucide-react';

export type CatalogPickerType = 'MATERIAL' | 'LABOR' | 'EQUIPMENT';

interface CatalogPickerModalProps {
  type: CatalogPickerType | null;
  isOpen: boolean;
  onClose: () => void;
  catalogMaterials: CatalogMaterial[];
  catalogLabor: CatalogLabor[];
  catalogEquipment: CatalogEquipment[];
  onSelectMaterial?: (item: CatalogMaterial) => void;
  onSelectLabor?: (item: CatalogLabor) => void;
  onSelectEquipment?: (item: CatalogEquipment) => void;
  onItemCreated: (type: CatalogPickerType, newItem: any) => void;
}

export const CatalogPickerModal: React.FC<CatalogPickerModalProps> = ({
  type,
  isOpen,
  onClose,
  catalogMaterials,
  catalogLabor,
  catalogEquipment,
  onSelectMaterial,
  onSelectLabor,
  onSelectEquipment,
  onItemCreated,
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [isCreating, setIsCreating] = useState(false);
  const [saving, setSaving] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  // New Item Form States
  const [materialForm, setMaterialForm] = useState({
    description: '',
    unit: 'PZA',
    unitPrice: 0,
    brand: '',
    model: '',
  });

  const [laborForm, setLaborForm] = useState({
    category: '',
    unit: 'JORNADA',
    unitPrice: 0,
  });

  const [equipmentForm, setEquipmentForm] = useState({
    description: '',
    unit: 'HORA',
    unitPrice: 0,
    brand: '',
    model: '',
  });

  // Filtered lists
  const filteredMaterials = useMemo(() => {
    if (type !== 'MATERIAL') return [];
    if (!searchTerm) return catalogMaterials;
    const lower = searchTerm.toLowerCase();
    return catalogMaterials.filter(
      (m) =>
        m.catalog_material_description.toLowerCase().includes(lower) ||
        m.tag_catalog_material?.toLowerCase().includes(lower) ||
        m.catalog_material_brand?.toLowerCase().includes(lower)
    );
  }, [catalogMaterials, searchTerm, type]);

  const filteredLabor = useMemo(() => {
    if (type !== 'LABOR') return [];
    if (!searchTerm) return catalogLabor;
    const lower = searchTerm.toLowerCase();
    return catalogLabor.filter(
      (l) =>
        l.catalog_labor_category.toLowerCase().includes(lower) ||
        l.tag_catalog_labor?.toLowerCase().includes(lower)
    );
  }, [catalogLabor, searchTerm, type]);

  const filteredEquipment = useMemo(() => {
    if (type !== 'EQUIPMENT') return [];
    if (!searchTerm) return catalogEquipment;
    const lower = searchTerm.toLowerCase();
    return catalogEquipment.filter(
      (e) =>
        e.catalog_equipment_description.toLowerCase().includes(lower) ||
        e.tag_catalog_equipment?.toLowerCase().includes(lower) ||
        e.catalog_equipment_brand?.toLowerCase().includes(lower)
    );
  }, [catalogEquipment, searchTerm, type]);

  if (!isOpen || !type) return null;

  const getTitle = () => {
    switch (type) {
      case 'MATERIAL':
        return {
          title: 'Catálogo General de Materiales (catalog_material)',
          desc: 'Seleccione un material existente para asignarlo a material_by_concept o dé de alta un nuevo material en el catálogo maestro.',
          icon: Box,
          color: 'text-emerald-700 bg-emerald-100',
        };
      case 'LABOR':
        return {
          title: 'Catálogo de Mano de Obra y Cuadrillas (catalog_labor)',
          desc: 'Seleccione la categoría o cuadrilla para labor_by_concept o dé de alta una nueva categoría en el catálogo maestro.',
          icon: Users,
          color: 'text-amber-700 bg-amber-100',
        };
      case 'EQUIPMENT':
        return {
          title: 'Catálogo de Maquinaria y Equipo (catalog_equipment)',
          desc: 'Seleccione un equipo especializado para equipment_by_concept o agregue un nuevo equipo al catálogo maestro.',
          icon: Wrench,
          color: 'text-blue-700 bg-blue-100',
        };
    }
  };

  const info = getTitle();
  const Icon = info.icon;

  const handleCreateNew = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setCreateError(null);

    try {
      let payload: any = {};
      if (type === 'MATERIAL') {
        if (!materialForm.description.trim()) throw new Error('La descripción del material es requerida.');
        payload = {
          type: 'MATERIAL',
          data: {
            catalog_material_description: materialForm.description.trim(),
            catalog_material_unit: materialForm.unit.trim().toUpperCase(),
            catalog_material_unit_price: materialForm.unitPrice,
            catalog_material_brand: materialForm.brand.trim() || null,
            catalog_material_model: materialForm.model.trim() || null,
          },
        };
      } else if (type === 'LABOR') {
        if (!laborForm.category.trim()) throw new Error('La categoría de mano de obra es requerida.');
        payload = {
          type: 'LABOR',
          data: {
            catalog_labor_category: laborForm.category.trim(),
            catalog_labor_unit: laborForm.unit.trim().toUpperCase() || 'JORNADA',
            catalog_labor_unit_price: laborForm.unitPrice,
          },
        };
      } else if (type === 'EQUIPMENT') {
        if (!equipmentForm.description.trim()) throw new Error('La descripción del equipo es requerida.');
        payload = {
          type: 'EQUIPMENT',
          data: {
            catalog_equipment_description: equipmentForm.description.trim(),
            catalog_equipment_unit: equipmentForm.unit.trim().toUpperCase() || 'HORA',
            catalog_equipment_unit_price: equipmentForm.unitPrice,
            catalog_equipment_brand: equipmentForm.brand.trim() || null,
            catalog_equipment_model: equipmentForm.model.trim() || null,
          },
        };
      }

      const res = await fetch('/api/catalog', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      const json = await res.json();
      if (!res.ok || json.error) {
        throw new Error(json.error || 'Error al guardar en el catálogo.');
      }

      const createdItem = json.item;
      onItemCreated(type, createdItem);

      // Automatically select and add to concept
      if (type === 'MATERIAL' && onSelectMaterial) onSelectMaterial(createdItem);
      if (type === 'LABOR' && onSelectLabor) onSelectLabor(createdItem);
      if (type === 'EQUIPMENT' && onSelectEquipment) onSelectEquipment(createdItem);

      // Reset form
      setIsCreating(false);
      onClose();
    } catch (err: any) {
      setCreateError(err?.message || 'Error al dar de alta en catálogo.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div 
      style={{ zIndex: 100 }}
      className="fixed inset-0 z-[100] bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-3 sm:p-6 animate-in fade-in duration-150"
    >
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 max-w-4xl w-full h-[85vh] flex flex-col overflow-hidden">
        {/* Modal Header */}
        <div className="px-6 py-4 border-b border-slate-200 bg-slate-900 text-white flex items-center justify-between shrink-0">
          <div className="flex items-center gap-3">
            <span className={`p-2 rounded-lg ${info.color}`}>
              <Icon className="w-5 h-5" />
            </span>
            <div>
              <h3 className="text-base font-bold text-white tracking-tight flex items-center gap-2">
                {info.title}
              </h3>
              <p className="text-xs text-slate-400">{info.desc}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-white p-1.5 rounded-lg hover:bg-slate-800 transition-colors cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Toolbar: Search & Create Toggle */}
        <div className="p-4 border-b border-slate-200 bg-slate-50/80 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shrink-0">
          <div className="relative flex-1">
            <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
            <input
              type="text"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Buscar en el catálogo por nombre, clave o descripción..."
              className="w-full pl-9 pr-4 py-2 bg-white border border-slate-300 rounded-lg text-xs text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
            />
          </div>

          <button
            onClick={() => {
              setIsCreating(!isCreating);
              setCreateError(null);
            }}
            className={`text-xs font-semibold px-3 py-2 rounded-lg flex items-center justify-center gap-1.5 transition-colors cursor-pointer shadow-xs ${
              isCreating
                ? 'bg-slate-200 text-slate-800 hover:bg-slate-300'
                : 'bg-emerald-600 hover:bg-emerald-700 text-white'
            }`}
          >
            {isCreating ? (
              <span>&larr; Volver a la Lista</span>
            ) : (
              <>
                <Plus className="w-4 h-4" />
                <span>+ Dar de Alta en Catálogo</span>
              </>
            )}
          </button>
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-4 sm:p-6">
          {createError && (
            <div className="p-3 mb-4 bg-red-50 border border-red-200 text-red-800 rounded-lg text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0 text-red-600" />
              <span>{createError}</span>
            </div>
          )}

          {isCreating ? (
            /* FORM: CREATE NEW CATALOG ITEM */
            <div className="bg-slate-50 border border-slate-200 rounded-xl p-5 max-w-2xl mx-auto shadow-xs">
              <div className="flex items-center gap-2 mb-4 pb-3 border-b border-slate-200">
                <Sparkles className="w-4 h-4 text-emerald-600" />
                <h4 className="text-sm font-bold text-slate-900">
                  Registrar Nuevo Elemento en el Catálogo Maestro
                </h4>
              </div>

              <form onSubmit={handleCreateNew} className="space-y-4 text-xs">
                {type === 'MATERIAL' && (
                  <>
                    <div>
                      <label className="block font-semibold text-slate-700 mb-1">
                        Descripción Completa del Material *
                      </label>
                      <input
                        type="text"
                        required
                        value={materialForm.description}
                        onChange={(e) => setMaterialForm({ ...materialForm, description: e.target.value })}
                        placeholder="Ej: Filtro de aceite diésel para motor Cummins ISX"
                        className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                      />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Unidad de Medida *</label>
                        <select
                          value={materialForm.unit}
                          onChange={(e) => setMaterialForm({ ...materialForm, unit: e.target.value })}
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        >
                          <option value="PZA">PIEZA (PZA)</option>
                          <option value="KIT">KIT</option>
                          <option value="LITRO">LITRO</option>
                          <option value="KG">KILO (KG)</option>
                          <option value="METRO">METRO (M)</option>
                          <option value="JUEGO">JUEGO</option>
                        </select>
                      </div>
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Precio Unitario ($ MXN) *</label>
                        <input
                          type="number"
                          step="0.01"
                          min="0"
                          required
                          value={materialForm.unitPrice || ''}
                          onChange={(e) =>
                            setMaterialForm({ ...materialForm, unitPrice: parseFloat(e.target.value) || 0 })
                          }
                          placeholder="0.00"
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 font-mono text-right focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        />
                      </div>
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Marca (Opcional)</label>
                        <input
                          type="text"
                          value={materialForm.brand}
                          onChange={(e) => setMaterialForm({ ...materialForm, brand: e.target.value })}
                          placeholder="Ej: Fleetguard, Cummins, Caterpillar"
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900"
                        />
                      </div>
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Modelo / No. Parte (Opcional)</label>
                        <input
                          type="text"
                          value={materialForm.model}
                          onChange={(e) => setMaterialForm({ ...materialForm, model: e.target.value })}
                          placeholder="Ej: FF5776"
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900"
                        />
                      </div>
                    </div>
                  </>
                )}

                {type === 'LABOR' && (
                  <>
                    <div>
                      <label className="block font-semibold text-slate-700 mb-1">
                        Categoría / Especialidad de Mano de Obra *
                      </label>
                      <input
                        type="text"
                        required
                        value={laborForm.category}
                        onChange={(e) => setLaborForm({ ...laborForm, category: e.target.value })}
                        placeholder="Ej: Operario Especialista en Instrumentación y Control"
                        className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                      />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Unidad</label>
                        <input
                          type="text"
                          disabled
                          value="JORNADA"
                          className="w-full px-3 py-2 bg-slate-100 border border-slate-300 rounded-lg text-slate-500 font-semibold text-center"
                        />
                      </div>
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">
                          Salario Base por Jornada ($ MXN) *
                        </label>
                        <input
                          type="number"
                          step="0.01"
                          min="0"
                          required
                          value={laborForm.unitPrice || ''}
                          onChange={(e) =>
                            setLaborForm({ ...laborForm, unitPrice: parseFloat(e.target.value) || 0 })
                          }
                          placeholder="0.00"
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 font-mono text-right focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        />
                      </div>
                    </div>
                  </>
                )}

                {type === 'EQUIPMENT' && (
                  <>
                    <div>
                      <label className="block font-semibold text-slate-700 mb-1">
                        Descripción de Maquinaria / Equipo Especializado *
                      </label>
                      <input
                        type="text"
                        required
                        value={equipmentForm.description}
                        onChange={(e) => setEquipmentForm({ ...equipmentForm, description: e.target.value })}
                        placeholder="Ej: Camión Grúa Articulada de 15 Toneladas con Canastilla"
                        className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 focus:outline-none focus:ring-1 focus:ring-emerald-500"
                      />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Unidad</label>
                        <input
                          type="text"
                          disabled
                          value="HORA"
                          className="w-full px-3 py-2 bg-slate-100 border border-slate-300 rounded-lg text-slate-500 font-semibold text-center"
                        />
                      </div>
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Costo Horario ($ MXN) *</label>
                        <input
                          type="number"
                          step="0.01"
                          min="0"
                          required
                          value={equipmentForm.unitPrice || ''}
                          onChange={(e) =>
                            setEquipmentForm({ ...equipmentForm, unitPrice: parseFloat(e.target.value) || 0 })
                          }
                          placeholder="0.00"
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900 font-mono text-right focus:outline-none focus:ring-1 focus:ring-emerald-500"
                        />
                      </div>
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Marca (Opcional)</label>
                        <input
                          type="text"
                          value={equipmentForm.brand}
                          onChange={(e) => setEquipmentForm({ ...equipmentForm, brand: e.target.value })}
                          placeholder="Ej: Hiab, National Crane"
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900"
                        />
                      </div>
                      <div>
                        <label className="block font-semibold text-slate-700 mb-1">Modelo (Opcional)</label>
                        <input
                          type="text"
                          value={equipmentForm.model}
                          onChange={(e) => setEquipmentForm({ ...equipmentForm, model: e.target.value })}
                          placeholder="Ej: XS 166 E-4"
                          className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-slate-900"
                        />
                      </div>
                    </div>
                  </>
                )}

                <div className="pt-3 border-t border-slate-200 flex justify-end gap-2">
                  <button
                    type="button"
                    onClick={() => setIsCreating(false)}
                    className="px-4 py-2 border border-slate-300 rounded-lg font-semibold text-slate-600 hover:bg-slate-100 cursor-pointer"
                  >
                    Cancelar
                  </button>
                  <button
                    type="submit"
                    disabled={saving}
                    className="px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg font-semibold flex items-center gap-1.5 cursor-pointer shadow-xs disabled:opacity-50"
                  >
                    <Check className="w-4 h-4" />
                    <span>{saving ? 'Guardando en catálogo...' : 'Guardar y Asignar al Concepto'}</span>
                  </button>
                </div>
              </form>
            </div>
          ) : (
            /* TABLE: LIST OF AVAILABLE ITEMS IN CATALOG */
            <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
              <table className="w-full text-xs text-left divide-y divide-slate-200">
                <thead className="bg-slate-100 text-slate-700 font-semibold uppercase text-[11px]">
                  <tr>
                    <th className="py-2.5 px-3 w-24">Clave</th>
                    <th className="py-2.5 px-3 min-w-[240px]">
                      {type === 'MATERIAL'
                        ? 'Descripción del Material'
                        : type === 'LABOR'
                        ? 'Categoría de Mano de Obra'
                        : 'Descripción del Equipo'}
                    </th>
                    <th className="py-2.5 px-3 w-20 text-center">Unidad</th>
                    <th className="py-2.5 px-3 w-32 text-right">
                      {type === 'LABOR' ? 'Salario Base' : 'Precio Unitario'}
                    </th>
                    {type !== 'LABOR' && <th className="py-2.5 px-3 w-32">Marca / Modelo</th>}
                    <th className="py-2.5 px-3 w-28 text-center">Acción</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {type === 'MATERIAL' &&
                    (filteredMaterials.length === 0 ? (
                      <tr>
                        <td colSpan={6} className="py-8 text-center text-slate-400 italic">
                          No se encontraron materiales en el catálogo. Utilice el botón superior para dar de alta uno nuevo.
                        </td>
                      </tr>
                    ) : (
                      filteredMaterials.map((m) => (
                        <tr key={m.id_catalog_material} className="hover:bg-slate-50 transition-colors">
                          <td className="py-2.5 px-3 font-mono font-bold text-slate-900">
                            {m.tag_catalog_material || `#${m.id_catalog_material}`}
                          </td>
                          <td className="py-2.5 px-3 text-slate-800 font-medium">
                            {m.catalog_material_description}
                          </td>
                          <td className="py-2.5 px-3 text-center">
                            <span className="px-1.5 py-0.5 rounded bg-slate-100 font-bold text-[10px] text-slate-700">
                              {m.catalog_material_unit}
                            </span>
                          </td>
                          <td className="py-2.5 px-3 text-right font-mono font-bold text-slate-900">
                            ${Number(m.catalog_material_unit_price).toFixed(2)}
                          </td>
                          <td className="py-2.5 px-3 text-slate-500 text-[11px]">
                            {m.catalog_material_brand || m.catalog_material_model
                              ? `${m.catalog_material_brand || ''} ${m.catalog_material_model || ''}`
                              : '—'}
                          </td>
                          <td className="py-2.5 px-3 text-center">
                            {onSelectMaterial ? (
                              <button
                                onClick={() => {
                                  onSelectMaterial(m);
                                  onClose();
                                }}
                                className="w-full bg-emerald-600 hover:bg-emerald-700 text-white font-semibold py-1 px-2.5 rounded text-[11px] flex items-center justify-center gap-1 transition-colors cursor-pointer shadow-2xs"
                              >
                                <Plus className="w-3 h-3" />
                                <span>Asignar</span>
                              </button>
                            ) : (
                              <span className="text-[10px] font-bold text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded">
                                Activo
                              </span>
                            )}
                          </td>
                        </tr>
                      ))
                    ))}

                  {type === 'LABOR' &&
                    (filteredLabor.length === 0 ? (
                      <tr>
                        <td colSpan={5} className="py-8 text-center text-slate-400 italic">
                          No se encontraron cuadrillas en el catálogo. Utilice el botón superior para registrar una nueva.
                        </td>
                      </tr>
                    ) : (
                      filteredLabor.map((l) => (
                        <tr key={l.id_catalog_labor} className="hover:bg-slate-50 transition-colors">
                          <td className="py-2.5 px-3 font-mono font-bold text-slate-900">
                            {l.tag_catalog_labor || `#${l.id_catalog_labor}`}
                          </td>
                          <td className="py-2.5 px-3 text-slate-800 font-medium">{l.catalog_labor_category}</td>
                          <td className="py-2.5 px-3 text-center">
                            <span className="px-1.5 py-0.5 rounded bg-amber-100 text-amber-800 font-bold text-[10px]">
                              {l.catalog_labor_unit}
                            </span>
                          </td>
                          <td className="py-2.5 px-3 text-right font-mono font-bold text-slate-900">
                            ${Number(l.catalog_labor_unit_price).toFixed(2)}
                          </td>
                          <td className="py-2.5 px-3 text-center">
                            {onSelectLabor ? (
                              <button
                                onClick={() => {
                                  onSelectLabor(l);
                                  onClose();
                                }}
                                className="w-full bg-amber-600 hover:bg-amber-700 text-white font-semibold py-1 px-2.5 rounded text-[11px] flex items-center justify-center gap-1 transition-colors cursor-pointer shadow-2xs"
                              >
                                <Plus className="w-3 h-3" />
                                <span>Asignar</span>
                              </button>
                            ) : (
                              <span className="text-[10px] font-bold text-amber-800 bg-amber-50 border border-amber-200 px-2 py-0.5 rounded">
                                Activo
                              </span>
                            )}
                          </td>
                        </tr>
                      ))
                    ))}

                  {type === 'EQUIPMENT' &&
                    (filteredEquipment.length === 0 ? (
                      <tr>
                        <td colSpan={6} className="py-8 text-center text-slate-400 italic">
                          No se encontraron equipos en el catálogo. Utilice el botón superior para dar de alta uno nuevo.
                        </td>
                      </tr>
                    ) : (
                      filteredEquipment.map((e) => (
                        <tr key={e.id_catalog_equipment} className="hover:bg-slate-50 transition-colors">
                          <td className="py-2.5 px-3 font-mono font-bold text-slate-900">
                            {e.tag_catalog_equipment || `#${e.id_catalog_equipment}`}
                          </td>
                          <td className="py-2.5 px-3 text-slate-800 font-medium">
                            {e.catalog_equipment_description}
                          </td>
                          <td className="py-2.5 px-3 text-center">
                            <span className="px-1.5 py-0.5 rounded bg-blue-100 text-blue-800 font-bold text-[10px]">
                              {e.catalog_equipment_unit}
                            </span>
                          </td>
                          <td className="py-2.5 px-3 text-right font-mono font-bold text-slate-900">
                            ${Number(e.catalog_equipment_unit_price).toFixed(2)}
                          </td>
                          <td className="py-2.5 px-3 text-slate-500 text-[11px]">
                            {e.catalog_equipment_brand || e.catalog_equipment_model
                              ? `${e.catalog_equipment_brand || ''} ${e.catalog_equipment_model || ''}`
                              : '—'}
                          </td>
                          <td className="py-2.5 px-3 text-center">
                            {onSelectEquipment ? (
                              <button
                                onClick={() => {
                                  onSelectEquipment(e);
                                  onClose();
                                }}
                                className="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-1 px-2.5 rounded text-[11px] flex items-center justify-center gap-1 transition-colors cursor-pointer shadow-2xs"
                              >
                                <Plus className="w-3 h-3" />
                                <span>Asignar</span>
                              </button>
                            ) : (
                              <span className="text-[10px] font-bold text-blue-800 bg-blue-50 border border-blue-200 px-2 py-0.5 rounded">
                                Activo
                              </span>
                            )}
                          </td>
                        </tr>
                      ))
                    ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-4 border-t border-slate-200 bg-slate-50 flex items-center justify-between text-xs text-slate-500 shrink-0">
          <span>
            {type === 'MATERIAL' && `${filteredMaterials.length} materiales en catálogo`}
            {type === 'LABOR' && `${filteredLabor.length} categorías en catálogo`}
            {type === 'EQUIPMENT' && `${filteredEquipment.length} equipos en catálogo`}
          </span>
          <button
            onClick={onClose}
            className="px-4 py-1.5 bg-white border border-slate-300 rounded-lg text-slate-700 font-semibold hover:bg-slate-100 cursor-pointer"
          >
            Cerrar
          </button>
        </div>
      </div>
    </div>
  );
};
