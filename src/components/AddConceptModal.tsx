'use client';

import React, { useState } from 'react';
import { X, Plus, AlertCircle } from 'lucide-react';

interface AddConceptModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAdd: (newConcept: {
    tag_concept: string;
    concept_header: string;
    concept_description: string;
    concept_unit: string;
  }) => Promise<void>;
}

export const AddConceptModal: React.FC<AddConceptModalProps> = ({
  isOpen,
  onClose,
  onAdd,
}) => {
  const [tag, setTag] = useState('');
  const [header, setHeader] = useState('');
  const [description, setDescription] = useState('');
  const [unit, setUnit] = useState('SERVICIO');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!tag.trim() || !description.trim()) {
      setError('Por favor complete la clave y la descripción del concepto.');
      return;
    }

    try {
      setSaving(true);
      setError(null);
      await onAdd({
        tag_concept: tag.trim(),
        concept_header: header.trim(),
        concept_description: description.trim(),
        concept_unit: unit.trim().toUpperCase(),
      });
      // Reset form
      setTag('');
      setHeader('');
      setDescription('');
      setUnit('SERVICIO');
      onClose();
    } catch (err: any) {
      setError(err?.message || 'Error al agregar concepto.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-xl border border-slate-200 max-w-lg w-full overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50">
          <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">
            <Plus className="w-4 h-4 text-emerald-600" />
            Agregar Nuevo Concepto al Concurso
          </h3>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-600 p-1.5 rounded-lg hover:bg-slate-200/50 cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {error && (
            <div className="p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                Clave / Tag <span className="text-red-500">*</span>
              </label>
              <input
                type="text"
                required
                value={tag}
                onChange={(e) => setTag(e.target.value)}
                placeholder="ej. 1.3.0107"
                className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-xs font-mono font-bold text-slate-900 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                Unidad de Medida <span className="text-red-500">*</span>
              </label>
              <select
                value={unit}
                onChange={(e) => setUnit(e.target.value)}
                className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-xs font-bold text-slate-800 focus:outline-none focus:ring-1 focus:ring-emerald-500 cursor-pointer"
              >
                <option value="SERVICIO">SERVICIO (Requiere APU)</option>
                <option value="PIEZA">PIEZA (Precio Directo)</option>
                <option value="JUEGO">JUEGO (Precio Directo)</option>
                <option value="METRO">METRO (Precio Directo)</option>
                <option value="LITRO">LITRO (Precio Directo)</option>
                <option value="KIT">KIT (Precio Directo)</option>
                <option value="KILO">KILO (Precio Directo)</option>
              </select>
            </div>
          </div>

          <div>
            <label className="block text-xs font-bold text-slate-700 mb-1">
              Capítulo / Especialidad (Opcional)
            </label>
            <input
              type="text"
              value={header}
              onChange={(e) => setHeader(e.target.value)}
              placeholder="ej. 1.3.0000 MANTENIMIENTO CORRECTIVO SISTEMA DE COMBUSTIBLE"
              className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-xs text-slate-900 focus:outline-none focus:ring-1 focus:ring-emerald-500 uppercase"
            />
          </div>

          <div>
            <label className="block text-xs font-bold text-slate-700 mb-1">
              Descripción Completa del Concepto <span className="text-red-500">*</span>
            </label>
            <textarea
              required
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describa el servicio, material o refacción conforme a la convocatoria..."
              className="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-xs text-slate-900 focus:outline-none focus:ring-1 focus:ring-emerald-500 leading-relaxed"
            />
          </div>

          <div className="pt-3 border-t border-slate-100 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              disabled={saving}
              className="px-4 py-2 text-xs font-semibold text-slate-600 hover:text-slate-800 hover:bg-slate-100 rounded-lg cursor-pointer"
            >
              Cancelar
            </button>
            <button
              type="submit"
              disabled={saving}
              className="px-5 py-2 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg shadow-sm flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
            >
              {saving ? 'Guardando...' : 'Crear Concepto'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
