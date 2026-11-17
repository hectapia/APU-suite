'use client';

import React, { useState, useEffect } from 'react';
import { Concept } from '@/types/database';
import { numberToWordsEs } from '@/lib/number-to-words';
import { X, DollarSign, FileText, Check, AlertCircle } from 'lucide-react';

interface DirectPriceModalProps {
  concept: Concept | null;
  isOpen: boolean;
  onClose: () => void;
  onSave: (conceptId: number, newPrice: number) => Promise<void>;
}

export const DirectPriceModal: React.FC<DirectPriceModalProps> = ({
  concept,
  isOpen,
  onClose,
  onSave,
}) => {
  const [priceInput, setPriceInput] = useState<string>('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (concept) {
      setPriceInput(concept.concept_price ? concept.concept_price.toString() : '');
      setError(null);
    }
  }, [concept]);

  if (!isOpen || !concept) return null;

  const numericPrice = parseFloat(priceInput) || 0;
  const wordsPreview = numberToWordsEs(numericPrice);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isNaN(numericPrice) || numericPrice <= 0) {
      setError('Por favor ingrese un precio unitario mayor a cero.');
      return;
    }

    try {
      setSaving(true);
      setError(null);
      await onSave(concept.id_concept, numericPrice);
      onClose();
    } catch (err: any) {
      setError(err?.message || 'Error al guardar el precio unitario.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-xl border border-slate-200 max-w-lg w-full overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50">
          <div>
            <div className="flex items-center gap-2">
              <span className="text-xs font-bold uppercase px-2 py-0.5 rounded bg-blue-100 text-blue-800 border border-blue-200">
                Suministro Directo ({concept.concept_unit})
              </span>
              <span className="text-xs font-mono font-bold text-slate-700">
                {concept.tag_concept}
              </span>
            </div>
            <h3 className="text-sm font-bold text-slate-900 mt-1">
              Asignación Directa de Precio Unitario
            </h3>
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-600 p-1.5 rounded-lg hover:bg-slate-200/50 cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {error && (
            <div className="p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div>
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">
              Descripción del Concepto
            </label>
            <p className="text-xs text-slate-800 bg-slate-50 p-3 rounded-lg border border-slate-200 leading-relaxed max-h-24 overflow-y-auto">
              {concept.concept_description}
            </p>
          </div>

          <div>
            <label className="block text-xs font-bold text-slate-700 mb-1">
              Precio Unitario de Venta (MXN)
            </label>
            <div className="relative">
              <DollarSign className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                type="number"
                step="0.01"
                min="0.01"
                required
                autoFocus
                value={priceInput}
                onChange={(e) => setPriceInput(e.target.value)}
                placeholder="0.00"
                className="w-full pl-9 pr-4 py-2.5 bg-white border border-slate-300 rounded-lg text-base font-mono font-bold text-slate-900 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
              />
            </div>
          </div>

          {/* Legal Words Live Preview */}
          <div className="bg-blue-50/70 p-3.5 rounded-lg border border-blue-200/80">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-blue-900 mb-1">
              <FileText className="w-3.5 h-3.5 text-blue-700" />
              Importe con Letra (Automático)
            </div>
            <p className="text-xs font-medium text-blue-800 italic leading-snug">
              {wordsPreview}
            </p>
          </div>

          {/* Footer Actions */}
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
              className="px-5 py-2 text-xs font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-lg shadow-sm flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
            >
              <Check className="w-4 h-4" />
              {saving ? 'Guardando...' : 'Guardar Precio Directo'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
