'use client';

import React from 'react';
import { EventDashboardView } from '@/types/database';
import { Layers, FileText, CheckCircle2, Clock, Building, ArrowRight, PlusCircle, Mail, UserCheck } from 'lucide-react';

interface EventCardProps {
  event: EventDashboardView;
  onOpenCatalog: () => void;
  onAddConcept: () => void;
  onInviteProvider?: () => void;
}

export const EventCard: React.FC<EventCardProps> = ({
  event,
  onOpenCatalog,
  onAddConcept,
  onInviteProvider,
}) => {
  return (
    <div className="bg-white rounded-xl border border-slate-200 shadow-sm hover:shadow-md transition-all duration-200 overflow-hidden flex flex-col group">
      {/* Header */}
      <div 
        onClick={onOpenCatalog}
        className="p-6 border-b border-slate-100 bg-gradient-to-r from-slate-50 to-white cursor-pointer hover:bg-slate-50/80 transition-colors"
      >
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-slate-900 text-white shadow-xs">
                {event.tag_event}
              </span>
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200 flex items-center gap-1">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-600 animate-pulse"></span>
                {event.status}
              </span>
            </div>
            <h2 className="text-base font-bold text-slate-900 group-hover:text-emerald-700 transition-colors line-clamp-1">
              {event.event_type}
            </h2>
          </div>
          <div className="text-right shrink-0">
            <span className="text-xs text-slate-500 flex items-center gap-1 bg-slate-100 px-2 py-1 rounded-md">
              <Clock className="w-3.5 h-3.5 text-slate-400" />
              Licitación Activa
            </span>
          </div>
        </div>

        <p className="mt-3 text-xs text-slate-600 line-clamp-2 leading-relaxed">
          {event.event_description}
        </p>

        <div className="mt-4 flex items-center justify-between text-xs text-slate-500 font-medium gap-2">
          <div className="flex items-center gap-1.5 truncate">
            <Building className="w-4 h-4 text-slate-400 shrink-0" />
            <span className="truncate">{event.client_name}</span>
          </div>

          {onInviteProvider && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onInviteProvider();
              }}
              className="text-[11px] font-semibold text-emerald-800 hover:text-emerald-950 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 px-2 py-0.5 rounded-md flex items-center gap-1 shrink-0 transition-colors cursor-pointer"
              title="Vincular o invitar contratista a este concurso"
            >
              <Mail className="w-3 h-3 text-emerald-600" />
              <span className="truncate max-w-[130px]">
                {event.provider_name ? event.provider_name : 'Asignar Contratista'}
              </span>
            </button>
          )}
        </div>
      </div>

      {/* Multi-Track Metrics & Progress */}
      <div className="p-6 bg-slate-50/50 flex-1 flex flex-col justify-between space-y-5">
        <div>
          <div className="flex justify-between items-center text-xs mb-1.5">
            <span className="font-semibold text-slate-700 flex items-center gap-1.5">
              <Layers className="w-3.5 h-3.5 text-emerald-600" />
              Avance General del Concurso
            </span>
            <span className="font-bold text-slate-900">
              {event.overall_completion_percentage}%
            </span>
          </div>
          {/* Main segmented progress bar */}
          <div className="w-full bg-slate-200 rounded-full h-2.5 overflow-hidden flex">
            <div
              className="bg-emerald-600 h-2.5 transition-all duration-500"
              style={{ width: `${Math.min(event.overall_completion_percentage, 100)}%` }}
            ></div>
          </div>
        </div>

        {/* Dual Track Detail Cards */}
        <div className="grid grid-cols-2 gap-3">
          {/* Track 1: Services APU */}
          <div className="bg-white p-3 rounded-lg border border-slate-200 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-slate-500 mb-1">
              <span className="font-semibold text-emerald-700 flex items-center gap-1">
                <FileText className="w-3 h-3" />
                Servicios (APU)
              </span>
              <span className="font-bold text-slate-800">
                {event.service_completion_percentage}%
              </span>
            </div>
            <p className="text-sm font-bold text-slate-900">
              {event.integrated_services_count}{' '}
              <span className="text-xs font-normal text-slate-500">
                / {event.total_services}
              </span>
            </p>
            <div className="w-full bg-slate-100 rounded-full h-1.5 mt-2">
              <div
                className="bg-emerald-500 h-1.5 rounded-full"
                style={{ width: `${Math.min(event.service_completion_percentage, 100)}%` }}
              ></div>
            </div>
          </div>

          {/* Track 2: Direct Supplies */}
          <div className="bg-white p-3 rounded-lg border border-slate-200 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-slate-500 mb-1">
              <span className="font-semibold text-blue-700 flex items-center gap-1">
                <CheckCircle2 className="w-3 h-3" />
                Suministros Directos
              </span>
              <span className="font-bold text-slate-800">
                {event.parts_completion_percentage}%
              </span>
            </div>
            <p className="text-sm font-bold text-slate-900">
              {event.priced_parts_count}{' '}
              <span className="text-xs font-normal text-slate-500">
                / {event.total_parts}
              </span>
            </p>
            <div className="w-full bg-slate-100 rounded-full h-1.5 mt-2">
              <div
                className="bg-blue-500 h-1.5 rounded-full"
                style={{ width: `${Math.min(event.parts_completion_percentage, 100)}%` }}
              ></div>
            </div>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="pt-2 flex items-center gap-2 border-t border-slate-200">
          <button
            onClick={onOpenCatalog}
            className="flex-1 bg-slate-900 hover:bg-slate-800 text-white text-xs font-semibold py-2.5 px-4 rounded-lg flex items-center justify-center gap-2 transition-colors cursor-pointer shadow-xs"
          >
            Abrir Catálogo de Conceptos ({event.total_concepts})
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
          <button
            onClick={onAddConcept}
            className="bg-white hover:bg-slate-100 text-slate-700 border border-slate-300 text-xs font-semibold py-2.5 px-3 rounded-lg flex items-center gap-1.5 transition-colors cursor-pointer"
            title="Agregar nuevo concepto"
          >
            <PlusCircle className="w-4 h-4 text-emerald-600" />
            <span className="hidden sm:inline">Agregar</span>
          </button>
        </div>
      </div>
    </div>
  );
};
