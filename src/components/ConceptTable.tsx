'use client';

import React, { useState, useMemo } from 'react';
import { Concept } from '@/types/database';
import { Search, Calculator, Edit3, CheckCircle, AlertCircle, ChevronLeft, ChevronRight, Layers } from 'lucide-react';

interface ConceptTableProps {
  concepts: Concept[];
  onOpenApu: (concept: Concept) => void;
  onOpenDirectPrice: (concept: Concept) => void;
  loading?: boolean;
}

export const ConceptTable: React.FC<ConceptTableProps> = ({
  concepts,
  onOpenApu,
  onOpenDirectPrice,
  loading = false,
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [scopeFilter, setScopeFilter] = useState<'ALL' | 'SERVICIO' | 'DIRECT'>('ALL');
  const [statusFilter, setStatusFilter] = useState<'ALL' | 'PRICED' | 'PENDING'>('ALL');
  const [currentPage, setCurrentPage] = useState(1);
  const pageSize = 25;

  // Filter concepts based on search, scope, and status
  const filteredConcepts = useMemo(() => {
    return concepts.filter((c) => {
      // Scope filter
      if (scopeFilter === 'SERVICIO' && c.concept_unit !== 'SERVICIO') return false;
      if (scopeFilter === 'DIRECT' && c.concept_unit === 'SERVICIO') return false;

      // Status filter
      const hasPrice = c.concept_price != null && c.concept_price > 0;
      if (statusFilter === 'PRICED' && !hasPrice) return false;
      if (statusFilter === 'PENDING' && hasPrice) return false;

      // Search term
      if (!searchTerm) return true;
      const lower = searchTerm.toLowerCase();
      return (
        c.tag_concept?.toLowerCase().includes(lower) ||
        c.concept_description?.toLowerCase().includes(lower) ||
        c.concept_header?.toLowerCase().includes(lower)
      );
    });
  }, [concepts, searchTerm, scopeFilter, statusFilter]);

  // Pagination
  const totalPages = Math.ceil(filteredConcepts.length / pageSize) || 1;
  const paginatedConcepts = useMemo(() => {
    const start = (currentPage - 1) * pageSize;
    return filteredConcepts.slice(start, start + pageSize);
  }, [filteredConcepts, currentPage, pageSize]);

  const counts = useMemo(() => {
    const total = concepts.length;
    const services = concepts.filter((c) => c.concept_unit === 'SERVICIO').length;
    const direct = total - services;
    return { total, services, direct };
  }, [concepts]);

  return (
    <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden flex flex-col">
      {/* Filters Bar */}
      <div className="p-4 sm:p-6 border-b border-slate-200 bg-slate-50/50 space-y-4">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          {/* Scope Tabs */}
          <div className="flex items-center gap-1 bg-slate-200/80 p-1 rounded-lg text-xs font-semibold">
            <button
              onClick={() => {
                setScopeFilter('ALL');
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-md transition-colors cursor-pointer ${
                scopeFilter === 'ALL'
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              Todos ({counts.total})
            </button>
            <button
              onClick={() => {
                setScopeFilter('SERVICIO');
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-md transition-colors cursor-pointer flex items-center gap-1.5 ${
                scopeFilter === 'SERVICIO'
                  ? 'bg-emerald-600 text-white shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              <Calculator className="w-3.5 h-3.5" />
              Servicios APU ({counts.services})
            </button>
            <button
              onClick={() => {
                setScopeFilter('DIRECT');
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-md transition-colors cursor-pointer flex items-center gap-1.5 ${
                scopeFilter === 'DIRECT'
                  ? 'bg-blue-600 text-white shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              <Edit3 className="w-3.5 h-3.5" />
              Suministros Directos ({counts.direct})
            </button>
          </div>

          {/* Status Radio Filter */}
          <div className="flex items-center gap-2 text-xs text-slate-600">
            <span className="font-medium text-slate-500">Estado:</span>
            <select
              value={statusFilter}
              onChange={(e) => {
                setStatusFilter(e.target.value as any);
                setCurrentPage(1);
              }}
              className="bg-white border border-slate-300 rounded-md px-2.5 py-1.5 text-xs text-slate-800 focus:outline-none focus:ring-1 focus:ring-emerald-500 cursor-pointer"
            >
              <option value="ALL">Cualquiera</option>
              <option value="PRICED">Con Precio Integrado</option>
              <option value="PENDING">Pendientes</option>
            </select>
          </div>
        </div>

        {/* Search Bar */}
        <div className="relative">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => {
              setSearchTerm(e.target.value);
              setCurrentPage(1);
            }}
            placeholder="Buscar por clave (ej. 1.3.0106), descripción de concepto o capítulo..."
            className="w-full pl-9 pr-4 py-2 bg-white border border-slate-300 rounded-lg text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
          />
          {searchTerm && (
            <button
              onClick={() => setSearchTerm('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400 hover:text-slate-600"
            >
              Limpiar
            </button>
          )}
        </div>
      </div>

      {/* Table Content */}
      <div className="overflow-x-auto flex-1">
        <table className="w-full text-left text-xs text-slate-600 divide-y divide-slate-200">
          <thead className="bg-slate-100 text-slate-700 font-semibold uppercase tracking-wider text-[11px]">
            <tr>
              <th className="py-3 px-4 w-28">Clave</th>
              <th className="py-3 px-4 min-w-[280px]">Descripción del Concepto</th>
              <th className="py-3 px-4 w-24">Unidad</th>
              <th className="py-3 px-4 w-36 text-right">Precio Unitario</th>
              <th className="py-3 px-4 min-w-[200px]">Importe en Letra</th>
              <th className="py-3 px-4 w-32 text-center">Acción</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 bg-white">
            {loading ? (
              <tr>
                <td colSpan={6} className="py-12 text-center text-slate-400">
                  Cargando catálogo de conceptos...
                </td>
              </tr>
            ) : paginatedConcepts.length === 0 ? (
              <tr>
                <td colSpan={6} className="py-12 text-center text-slate-400">
                  No se encontraron conceptos con los filtros aplicados.
                </td>
              </tr>
            ) : (
              paginatedConcepts.map((c) => {
                const isService = c.concept_unit === 'SERVICIO';
                const hasPrice = c.concept_price != null && c.concept_price > 0;

                return (
                  <tr key={c.id_concept} className="hover:bg-slate-50/80 transition-colors">
                    {/* Clave */}
                    <td className="py-3 px-4 font-mono font-bold text-slate-900">
                      {c.tag_concept}
                    </td>

                    {/* Descripción & Header */}
                    <td className="py-3 px-4">
                      {c.concept_header && (
                        <p className="text-[10px] uppercase font-bold text-slate-400 line-clamp-1 mb-0.5">
                          {c.concept_header}
                        </p>
                      )}
                      <p className="text-slate-800 font-medium line-clamp-2 leading-relaxed">
                        {c.concept_description}
                      </p>
                    </td>

                    {/* Unidad con Badge */}
                    <td className="py-3 px-4">
                      <span
                        className={`inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold tracking-wider ${
                          isService
                            ? 'bg-emerald-100 text-emerald-800 border border-emerald-200'
                            : 'bg-blue-100 text-blue-800 border border-blue-200'
                        }`}
                      >
                        {c.concept_unit}
                      </span>
                    </td>

                    {/* Precio Unitario */}
                    <td className="py-3 px-4 text-right font-mono text-sm font-bold">
                      {hasPrice ? (
                        <span className="text-slate-900">
                          ${c.concept_price?.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                        </span>
                      ) : (
                        <span className="text-slate-300 font-normal text-xs">Sin precio</span>
                      )}
                    </td>

                    {/* Importe con Letra */}
                    <td className="py-3 px-4 text-[11px] text-slate-500 italic line-clamp-2">
                      {c.concept_price_txt || <span className="text-slate-300">—</span>}
                    </td>

                    {/* Botón de Acción */}
                    <td className="py-3 px-4 text-center">
                      {isService ? (
                        <button
                          onClick={() => onOpenApu(c)}
                          className={`w-full text-xs font-semibold py-1.5 px-2.5 rounded-lg flex items-center justify-center gap-1.5 transition-colors cursor-pointer ${
                            hasPrice
                              ? 'bg-emerald-50 text-emerald-700 hover:bg-emerald-100 border border-emerald-300'
                              : 'bg-emerald-600 hover:bg-emerald-700 text-white shadow-xs'
                          }`}
                        >
                          <Calculator className="w-3.5 h-3.5" />
                          {hasPrice ? 'Editar APU' : 'Integrar APU'}
                        </button>
                      ) : (
                        <button
                          onClick={() => onOpenDirectPrice(c)}
                          className={`w-full text-xs font-semibold py-1.5 px-2.5 rounded-lg flex items-center justify-center gap-1.5 transition-colors cursor-pointer ${
                            hasPrice
                              ? 'bg-blue-50 text-blue-700 hover:bg-blue-100 border border-blue-300'
                              : 'bg-blue-600 hover:bg-blue-700 text-white shadow-xs'
                          }`}
                        >
                          <Edit3 className="w-3.5 h-3.5" />
                          {hasPrice ? 'Editar Precio' : 'Asignar Precio'}
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination Footer */}
      <div className="p-4 border-t border-slate-200 bg-slate-50 flex items-center justify-between text-xs text-slate-500">
        <div>
          Mostrando{' '}
          <span className="font-semibold text-slate-700">
            {filteredConcepts.length === 0 ? 0 : (currentPage - 1) * pageSize + 1}
          </span>{' '}
          a{' '}
          <span className="font-semibold text-slate-700">
            {Math.min(currentPage * pageSize, filteredConcepts.length)}
          </span>{' '}
          de <span className="font-semibold text-slate-700">{filteredConcepts.length}</span> conceptos
        </div>

        <div className="flex items-center gap-2">
          <button
            disabled={currentPage === 1}
            onClick={() => setCurrentPage((p) => Math.max(p - 1, 1))}
            className="p-1.5 rounded border border-slate-300 bg-white hover:bg-slate-100 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
          >
            <ChevronLeft className="w-4 h-4" />
          </button>
          <span className="font-medium text-slate-700">
            Página {currentPage} de {totalPages}
          </span>
          <button
            disabled={currentPage === totalPages}
            onClick={() => setCurrentPage((p) => Math.min(p + 1, totalPages))}
            className="p-1.5 rounded border border-slate-300 bg-white hover:bg-slate-100 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
          >
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
};
