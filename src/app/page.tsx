'use client';

import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
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
import { CatalogPickerModal, CatalogPickerType } from '@/components/CatalogPickerModal';
import { InviteProviderModal } from '@/components/InviteProviderModal';
import { LoginScreen } from '@/components/LoginScreen';
import {
  AlertCircle,
  RefreshCw,
  Database,
  ArrowLeft,
  Layers,
  FileText,
  CheckCircle2,
  Building,
  PlusCircle,
  Clock,
  Box,
  Users,
  Wrench
} from 'lucide-react';

export default function DashboardPage() {
  const {
    user,
    activeEvent,
    isLoadingAuth,
    setActiveEvent,
    isInviteModalOpen,
    inviteModalEventId,
    openInviteModal,
    closeInviteModal,
  } = useAuth();
  const [events, setEvents] = useState<EventDashboardView[]>([]);
  const [concepts, setConcepts] = useState<Concept[]>([]);
  const [catalogMaterials, setCatalogMaterials] = useState<CatalogMaterial[]>([]);
  const [catalogLabor, setCatalogLabor] = useState<CatalogLabor[]>([]);
  const [catalogEquipment, setCatalogEquipment] = useState<CatalogEquipment[]>([]);

  // Navigation State: null = First view (Events Cards Grid), EventDashboardView = Catalog view
  const [selectedEvent, setSelectedEvent] = useState<EventDashboardView | null>(null);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Standalone Master Catalog Modal State
  const [activeCatalogType, setActiveCatalogType] = useState<CatalogPickerType | null>(null);
  const [isCatalogModalOpen, setIsCatalogModalOpen] = useState(false);

  // Modals state
  const [selectedApuConcept, setSelectedApuConcept] = useState<Concept | null>(null);
  const [isApuOpen, setIsApuOpen] = useState(false);

  const [selectedDirectConcept, setSelectedDirectConcept] = useState<Concept | null>(null);
  const [isDirectPriceOpen, setIsDirectPriceOpen] = useState(false);

  const [isAddConceptOpen, setIsAddConceptOpen] = useState(false);

  // Filter events based on role: Admins see all; Contractors see only their assigned tender
  const filteredEvents = useMemo(() => {
    if (!user) return [];
    if (user.role === 'ADMIN') return events;
    if (user.role === 'PROVIDER_ESTIMATOR') {
      const provId = user.id_provider;
      const provName = user.provider_name?.trim().toLowerCase();
      const matched = events.filter((ev) => {
        if (provId && ev.id_provider && ev.id_provider === provId) return true;
        if (provName && ev.provider_name && ev.provider_name.trim().toLowerCase().includes(provName)) return true;
        if (activeEvent && ev.id_event === activeEvent.id_event) return true;
        return false;
      });
      return matched.length > 0 ? matched : events.slice(0, 1);
    }
    return events;
  }, [events, user, activeEvent]);

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
      const fetchedEvents: EventDashboardView[] = eventData || [];
      setEvents(fetchedEvents);

      // Update selectedEvent instance if one is active
      setSelectedEvent((current) => {
        if (!current) return null;
        return fetchedEvents.find((e) => e.id_event === current.id_event) || current;
      });

      // 2. Fetch Concepts (All items in batches to bypass PostgREST 1000-row limit)
      let allConcepts: Concept[] = [];
      let from = 0;
      const batchSize = 1000;
      let hasMore = true;

      while (hasMore) {
        const { data: batch, error: batchErr } = await supabase
          .from('concept')
          .select('*')
          .order('id_concept', { ascending: true })
          .range(from, from + batchSize - 1);

        if (batchErr) throw batchErr;
        if (batch && batch.length > 0) {
          allConcepts = allConcepts.concat(batch);
          from += batchSize;
          if (batch.length < batchSize) {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      }

      setConcepts(allConcepts);

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
    if (user) {
      loadData();
    }
  }, [user, loadData]);

  // Sync activeEvent from auth-context if set (e.g. from magic link verification)
  useEffect(() => {
    if (activeEvent && events.length > 0 && (!selectedEvent || selectedEvent.id_event !== activeEvent.id_event)) {
      const match = events.find((e) => e.id_event === activeEvent.id_event);
      if (match) setSelectedEvent(match);
    }
  }, [activeEvent, events, selectedEvent]);

  const handleSelectEvent = (ev: EventDashboardView) => {
    setSelectedEvent(ev);
    setActiveEvent({
      id_event: ev.id_event,
      tag_event: ev.tag_event,
      event_type: ev.event_type,
      client_name: ev.client_name,
      provider_name: user?.provider_name || undefined,
    });
  };

  const handleBackToEvents = () => {
    setSelectedEvent(null);
    setActiveEvent(null);
  };

  // Filter concepts belonging to the currently selected event
  const currentEventConcepts = useMemo(() => {
    if (!selectedEvent) return [];
    return concepts.filter((c) => c.id_event === selectedEvent.id_event);
  }, [concepts, selectedEvent]);

  // Handler: Save APU Integration
  const handleSaveAPU = async (conceptId: number, apuData: any) => {
    const res = await fetch('/api/apu', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        conceptId,
        userId: user?.id_user,
        userRole: user?.role,
        ...apuData,
      }),
    });

    const json = await res.json();
    if (!res.ok || json.error) {
      throw new Error(json.error || 'Error al guardar la integración APU.');
    }

    // Refresh UI
    await loadData();
  };

  // Handler: Real-time sync when a new catalog item is created
  const handleCatalogItemCreated = (type: string, item: any) => {
    if (type === 'MATERIAL') {
      setCatalogMaterials((prev) => [...prev, item]);
    } else if (type === 'LABOR') {
      setCatalogLabor((prev) => [...prev, item]);
    } else if (type === 'EQUIPMENT') {
      setCatalogEquipment((prev) => [...prev, item]);
    }
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
    const maxId = concepts.reduce((acc, c) => Math.max(acc, c.id_concept), 0);
    const nextId = maxId + 1;
    const targetEventId = selectedEvent?.id_event || 1;
    const targetClientId = concepts.find((c) => c.id_event === targetEventId)?.id_client || 1;

    const { error: insertErr } = await supabase.from('concept').insert({
      id_concept: nextId,
      id_event: targetEventId,
      id_client: targetClientId,
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

  // Auth Guard: Show loader while restoring session
  if (isLoadingAuth) {
    return (
      <div className="min-h-[60vh] flex flex-col items-center justify-center space-y-3">
        <RefreshCw className="w-8 h-8 text-emerald-600 animate-spin" />
        <p className="text-xs text-slate-500 font-medium">Verificando credenciales de acceso...</p>
      </div>
    );
  }

  // Auth Guard: Require login to enter APU studio
  if (!user) {
    return <LoginScreen />;
  }

  return (
    <div className="space-y-6">
      {/* Global Error Banner */}
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

      {/* VIEW 1: FIRST VIEW - CARDS OF EVENTS */}
      {!selectedEvent ? (
        <section className="space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-200 pb-5">
            <div>
              <div className="flex items-center gap-2">
                <span className="p-2 bg-emerald-100 text-emerald-800 rounded-lg">
                  <Database className="w-5 h-5 text-emerald-700" />
                </span>
                <div>
                  <h1 className="text-xl font-bold text-slate-900 tracking-tight">
                    Concursos y Licitaciones
                  </h1>
                  <p className="text-xs text-slate-500">
                    Panel general de eventos licitatorios asignados. Seleccione un concurso para explorar su catálogo de conceptos.
                  </p>
                </div>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <button
                onClick={loadData}
                disabled={loading}
                className="text-xs font-medium text-slate-600 hover:text-slate-900 flex items-center gap-1.5 px-3 py-2 bg-white border border-slate-300 rounded-lg shadow-2xs hover:bg-slate-50 cursor-pointer"
                title="Recargar datos desde Supabase"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin text-emerald-600' : ''}`} />
                <span>Actualizar Datos</span>
              </button>
            </div>
          </div>

          {/* Grid of Event Cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {filteredEvents.length === 0 && !loading ? (
              <div className="col-span-full p-12 text-center bg-white rounded-xl border border-slate-200 text-slate-500 text-sm">
                No se encontraron eventos o concursos asignados a este usuario.
              </div>
            ) : (
              filteredEvents.map((ev) => (
                <EventCard
                  key={ev.id_event}
                  event={ev}
                  onOpenCatalog={() => handleSelectEvent(ev)}
                  onAddConcept={
                    user?.role === 'ADMIN'
                      ? () => {
                          handleSelectEvent(ev);
                          setIsAddConceptOpen(true);
                        }
                      : undefined
                  }
                  onInviteProvider={
                    user?.role === 'ADMIN'
                      ? () => openInviteModal(ev.id_event)
                      : undefined
                  }
                />
              ))
            )}
          </div>
        </section>
      ) : (
        /* VIEW 2: SECOND VIEW - CATÁLOGO GENERAL DE CONCEPTOS */
        <section className="space-y-6">
          {/* Breadcrumb & Navigation Bar */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <button
              onClick={handleBackToEvents}
              className="inline-flex items-center gap-2 text-xs font-semibold text-slate-600 hover:text-slate-900 bg-white hover:bg-slate-100 border border-slate-300 px-3.5 py-2 rounded-lg transition-colors cursor-pointer shadow-2xs self-start"
            >
              <ArrowLeft className="w-4 h-4 text-slate-500" />
              <span>Volver a Concursos y Licitaciones</span>
            </button>

            <div className="flex flex-wrap items-center gap-2">
              {/* Master Catalogs Buttons */}
              <div className="flex items-center gap-1.5 bg-slate-100 p-1 rounded-lg border border-slate-200">
                <button
                  onClick={() => {
                    setActiveCatalogType('MATERIAL');
                    setIsCatalogModalOpen(true);
                  }}
                  className="text-xs font-semibold px-2 py-1 rounded bg-white hover:bg-slate-50 text-slate-700 border border-slate-200/80 shadow-2xs flex items-center gap-1 cursor-pointer"
                  title="Catálogo General de Materiales"
                >
                  <Box className="w-3.5 h-3.5 text-emerald-600" />
                  <span>Materiales ({catalogMaterials.length})</span>
                </button>
                <button
                  onClick={() => {
                    setActiveCatalogType('LABOR');
                    setIsCatalogModalOpen(true);
                  }}
                  className="text-xs font-semibold px-2 py-1 rounded bg-white hover:bg-slate-50 text-slate-700 border border-slate-200/80 shadow-2xs flex items-center gap-1 cursor-pointer"
                  title="Catálogo General de Mano de Obra"
                >
                  <Users className="w-3.5 h-3.5 text-amber-600" />
                  <span>Mano de Obra ({catalogLabor.length})</span>
                </button>
                <button
                  onClick={() => {
                    setActiveCatalogType('EQUIPMENT');
                    setIsCatalogModalOpen(true);
                  }}
                  className="text-xs font-semibold px-2 py-1 rounded bg-white hover:bg-slate-50 text-slate-700 border border-slate-200/80 shadow-2xs flex items-center gap-1 cursor-pointer"
                  title="Catálogo General de Maquinaria y Equipos"
                >
                  <Wrench className="w-3.5 h-3.5 text-blue-600" />
                  <span>Equipos ({catalogEquipment.length})</span>
                </button>
              </div>

              {user?.role === 'ADMIN' && (
                <button
                  onClick={() => setIsAddConceptOpen(true)}
                  className="bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold py-1.5 px-3 rounded-lg flex items-center gap-1.5 transition-colors cursor-pointer shadow-xs"
                >
                  <PlusCircle className="w-4 h-4" />
                  <span>Agregar Concepto</span>
                </button>
              )}
              <button
                onClick={loadData}
                disabled={loading}
                className="text-xs font-medium text-slate-600 hover:text-slate-900 flex items-center gap-1.5 p-1.5 bg-white border border-slate-300 rounded-lg shadow-2xs hover:bg-slate-50 cursor-pointer"
                title="Recargar datos"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin text-emerald-600' : ''}`} />
              </button>
            </div>
          </div>

          {/* Event Header Banner */}
          <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-6 overflow-hidden">
            <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6">
              <div className="space-y-2 max-w-3xl">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-mono font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-slate-900 text-white">
                    {selectedEvent.tag_event}
                  </span>
                  <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                    {selectedEvent.status}
                  </span>
                  <span className="text-xs text-slate-500 flex items-center gap-1">
                    <Clock className="w-3.5 h-3.5 text-slate-400" />
                    Licitación Activa
                  </span>
                </div>
                <h1 className="text-xl font-bold text-slate-900">
                  {selectedEvent.event_type}
                </h1>
                <p className="text-xs text-slate-600 leading-relaxed">
                  {selectedEvent.event_description}
                </p>
                <div className="flex flex-wrap items-center gap-4 text-xs text-slate-600 font-medium pt-1">
                  <div className="flex items-center gap-1.5">
                    <Building className="w-4 h-4 text-slate-400 shrink-0" />
                    <span><strong className="text-slate-700">Convocante:</strong> {selectedEvent.client_name}</span>
                  </div>
                  <div className="flex items-center gap-1.5 bg-emerald-50 text-emerald-800 border border-emerald-200 px-2.5 py-1 rounded-md">
                    <span className="w-2 h-2 rounded-full bg-emerald-600"></span>
                    <span>
                      <strong className="text-emerald-950">Contratista Asignado:</strong>{' '}
                      {selectedEvent.provider_name || (user?.role === 'PROVIDER_ESTIMATOR' && user.provider_name ? user.provider_name : 'MHEBOSAP, S.A. DE C.V.')}
                    </span>
                    {user?.role === 'ADMIN' && (
                      <button
                        onClick={() => openInviteModal(selectedEvent.id_event)}
                        className="ml-2 text-[10px] font-bold text-emerald-700 hover:text-emerald-950 underline cursor-pointer"
                        title="Vincular o editar contratista asignado a este concurso"
                      >
                        (Editar / Vincular)
                      </button>
                    )}
                  </div>
                </div>
              </div>

              {/* Progress Summary Cards */}
              <div className="bg-slate-50 rounded-xl p-4 border border-slate-200/80 shrink-0 lg:w-96 space-y-3">
                <div className="flex justify-between items-center text-xs">
                  <span className="font-semibold text-slate-700 flex items-center gap-1.5">
                    <Layers className="w-3.5 h-3.5 text-emerald-600" />
                    Avance APU
                  </span>
                  <span className="font-bold text-slate-900">
                    {selectedEvent.overall_completion_percentage}%
                  </span>
                </div>
                <div className="w-full bg-slate-200 rounded-full h-2 overflow-hidden">
                  <div
                    className="bg-emerald-600 h-2 transition-all duration-500"
                    style={{ width: `${Math.min(selectedEvent.overall_completion_percentage, 100)}%` }}
                  ></div>
                </div>

                <div className="grid grid-cols-2 gap-2 pt-2 border-t border-slate-200/60 text-xs">
                  <div>
                    <span className="text-[11px] font-semibold text-emerald-700 flex items-center gap-1">
                      <FileText className="w-3 h-3" /> Servicios (APU)
                    </span>
                    <p className="font-bold text-slate-800 mt-0.5">
                      {selectedEvent.integrated_services_count}{' '}
                      <span className="font-normal text-slate-400 text-[10px]">
                        / {selectedEvent.total_services} ({selectedEvent.service_completion_percentage}%)
                      </span>
                    </p>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-blue-700 flex items-center gap-1">
                      <CheckCircle2 className="w-3 h-3" /> Suministros
                    </span>
                    <p className="font-bold text-slate-800 mt-0.5">
                      {selectedEvent.priced_parts_count}{' '}
                      <span className="font-normal text-slate-400 text-[10px]">
                        / {selectedEvent.total_parts} ({selectedEvent.parts_completion_percentage}%)
                      </span>
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Catálogo General de Conceptos */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-lg font-bold text-slate-900 tracking-tight">
                  Catálogo General de Conceptos ({currentEventConcepts.length})
                </h2>
                <p className="text-xs text-slate-500">
                  Conceptos correspondientes al concurso {selectedEvent.tag_event}. Integre precios unitarios (DT-7) para SERVICIO o asigne precio directo a suministros.
                </p>
              </div>
            </div>

            <ConceptTable
              event={selectedEvent}
              concepts={currentEventConcepts}
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
          </div>
        </section>
      )}

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
        onCatalogItemCreated={handleCatalogItemCreated}
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

      {/* MODAL 4: ROOT MASTER CATALOGS VIEWER / CREATOR */}
      <CatalogPickerModal
        type={activeCatalogType}
        isOpen={isCatalogModalOpen}
        onClose={() => {
          setIsCatalogModalOpen(false);
          setActiveCatalogType(null);
        }}
        catalogMaterials={catalogMaterials}
        catalogLabor={catalogLabor}
        catalogEquipment={catalogEquipment}
        onItemCreated={handleCatalogItemCreated}
      />

      {/* MODAL 5: INVITE / LINK PROVIDER MODAL */}
      <InviteProviderModal
        isOpen={isInviteModalOpen}
        onClose={closeInviteModal}
        events={events}
        defaultEventId={inviteModalEventId}
        onEventUpdated={loadData}
      />
    </div>
  );
}