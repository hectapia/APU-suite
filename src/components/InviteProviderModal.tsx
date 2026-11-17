'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '@/lib/auth-context';
import { EventDashboardView, Provider, EventInvitation } from '@/types/database';
import { supabase } from '@/lib/supabase';
import {
  X,
  Mail,
  Building,
  User,
  Copy,
  Check,
  Send,
  ExternalLink,
  ShieldCheck,
  AlertCircle,
  Loader2,
  Edit2,
  Trash2,
  RefreshCw,
  PlusCircle,
  Link as LinkIcon,
  CheckCircle2,
  Clock,
  Search,
} from 'lucide-react';

interface InviteProviderModalProps {
  isOpen: boolean;
  onClose: () => void;
  events: EventDashboardView[];
  defaultEventId?: number;
  onEventUpdated?: () => void;
}

export function InviteProviderModal({
  isOpen,
  onClose,
  events: propEvents,
  defaultEventId,
  onEventUpdated,
}: InviteProviderModalProps) {
  const { user } = useAuth();

  // Internal events state to ensure we always have events even if prop is empty
  const [events, setEvents] = useState<EventDashboardView[]>(propEvents || []);
  const [providers, setProviders] = useState<Provider[]>([]);
  const [invitations, setInvitations] = useState<EventInvitation[]>([]);

  // Navigation mode: 'form' | 'list'
  const [activeTab, setActiveTab] = useState<'form' | 'list'>('form');

  // Form State
  const [editingInvitationId, setEditingInvitationId] = useState<string | null>(null);
  const [selectedEventId, setSelectedEventId] = useState<number>(
    defaultEventId || propEvents[0]?.id_event || 1
  );
  const [selectedProviderId, setSelectedProviderId] = useState<string>('custom');
  const [providerName, setProviderName] = useState('MHEBOSAP, S.A. DE C.V.');
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [accessRole, setAccessRole] = useState<'WRITE' | 'READ'>('WRITE');
  const [regenerateToken, setRegenerateToken] = useState(false);

  // Status & Feedback
  const [loading, setLoading] = useState(false);
  const [fetchingData, setFetchingData] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [generatedLink, setGeneratedLink] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');

  // Fetch events and invitations from server
  const loadData = useCallback(async () => {
    try {
      setFetchingData(true);
      setError(null);

      // Load events if not provided or to ensure fresh data
      const { data: evData } = await supabase.from('v_event_dashboard').select('*');
      if (evData && evData.length > 0) {
        setEvents(evData);
      }

      // Load invitations and providers via API
      const res = await fetch('/api/auth/invite');
      const data = await res.json();
      if (data.success) {
        setInvitations(data.invitations || []);
        setProviders(data.providers || []);
      }
    } catch (err: any) {
      console.warn('Error fetching invite data:', err);
    } finally {
      setFetchingData(false);
    }
  }, []);

  useEffect(() => {
    if (isOpen) {
      loadData();
      if (defaultEventId) {
        setSelectedEventId(defaultEventId);
      }
    }
  }, [isOpen, defaultEventId, loadData]);

  // When defaultEventId changes or events change, update selectedEventId
  useEffect(() => {
    if (defaultEventId) {
      setSelectedEventId(defaultEventId);
    } else if (events.length > 0 && !selectedEventId) {
      setSelectedEventId(events[0].id_event);
    }
  }, [defaultEventId, events, selectedEventId]);

  // When an existing provider is selected from dropdown
  const handleProviderSelectChange = (value: string) => {
    setSelectedProviderId(value);
    if (value === 'custom') {
      setProviderName('');
      setFullName('');
      setEmail('');
    } else {
      const found = providers.find((p) => String(p.id_provider) === value);
      if (found) {
        setProviderName(found.provider_name);
        setFullName(found.provider_representative || '');
        setEmail(found.contact_email || '');
      }
    }
  };

  // Start editing an existing invitation
  const handleEditInvitation = (inv: EventInvitation) => {
    setEditingInvitationId(inv.id_invitation);
    setSelectedEventId(inv.id_event);
    setEmail(inv.invited_email);
    setAccessRole('WRITE');
    setRegenerateToken(false);
    setGeneratedLink(null);
    setError(null);

    if (inv.id_provider && inv.provider) {
      setSelectedProviderId(String(inv.id_provider));
      setProviderName(inv.provider.provider_name);
      setFullName(inv.provider.provider_representative || '');
    } else if (inv.provider) {
      setProviderName(inv.provider.provider_name);
      setFullName(inv.provider.provider_representative || '');
    }

    setActiveTab('form');
  };

  // Cancel edit mode and reset form
  const handleResetForm = () => {
    setEditingInvitationId(null);
    setGeneratedLink(null);
    setEmail('');
    setFullName('');
    setProviderName('MHEBOSAP, S.A. DE C.V.');
    setSelectedProviderId('custom');
    setRegenerateToken(false);
    setError(null);
    setSuccessMessage(null);
  };

  // Submit Handler: Create or Update
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) {
      setError('Por favor ingresa un correo electrónico válido.');
      return;
    }
    if (!selectedEventId) {
      setError('Por favor selecciona un concurso existente.');
      return;
    }

    try {
      setLoading(true);
      setError(null);
      setSuccessMessage(null);

      const isEditing = Boolean(editingInvitationId);
      const url = '/api/auth/invite';
      const method = isEditing ? 'PUT' : 'POST';

      const payload = {
        id_invitation: editingInvitationId,
        id_event: selectedEventId,
        providerId: selectedProviderId !== 'custom' ? Number(selectedProviderId) : undefined,
        providerName: providerName.trim(),
        fullName: fullName.trim(),
        email: email.trim(),
        accessRole,
        regenerateToken,
        userId: user?.id_user,
        userRole: user?.role || 'ADMIN',
      };

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Error al procesar la invitación.');
      }

      if (data.magicLink) {
        setGeneratedLink(data.magicLink);
      }

      setSuccessMessage(
        isEditing
          ? 'Invitación y vinculación de contratista actualizadas con éxito.'
          : 'Invitación generada y contratista vinculado al concurso exitosamente.'
      );

      // Reload fresh list of invitations
      await loadData();
      if (onEventUpdated) {
        onEventUpdated();
      }
    } catch (err: any) {
      setError(err.message || 'Error de conexión.');
    } finally {
      setLoading(false);
    }
  };

  // Delete invitation
  const handleDeleteInvitation = async (id_invitation: string) => {
    if (!confirm('¿Estás seguro de que deseas revocar esta invitación? El enlace ya no funcionará.')) {
      return;
    }

    try {
      setLoading(true);
      const res = await fetch(`/api/auth/invite?id_invitation=${encodeURIComponent(id_invitation)}`, {
        method: 'DELETE',
      });
      const data = await res.json();
      if (data.success) {
        await loadData();
        if (editingInvitationId === id_invitation) {
          handleResetForm();
        }
      } else {
        alert(data.error || 'Error al eliminar');
      }
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleCopy = () => {
    if (generatedLink) {
      navigator.clipboard.writeText(generatedLink);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    }
  };

  if (!isOpen) return null;

  const currentSelectedEvent = events.find((ev) => ev.id_event === selectedEventId);

  // Filter invitations for search
  const filteredInvitations = invitations.filter((inv) => {
    if (!searchTerm) return true;
    const term = searchTerm.toLowerCase();
    return (
      inv.invited_email?.toLowerCase().includes(term) ||
      inv.provider?.provider_name?.toLowerCase().includes(term) ||
      inv.event?.tag_event?.toLowerCase().includes(term) ||
      inv.event?.event_type?.toLowerCase().includes(term)
    );
  });

  return (
    <div
      className="fixed inset-0 bg-slate-950/75 backdrop-blur-xs flex items-center justify-center p-3 sm:p-5"
      style={{ zIndex: 100 }}
    >
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-2xl max-h-[92vh] flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        {/* Header */}
        <div className="bg-slate-900 text-white p-5 flex items-center justify-between border-b border-slate-800 shrink-0">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
              <Mail className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-bold text-base leading-tight">
                  {editingInvitationId
                    ? 'Editar Invitación y Asignación de Contratista'
                    : 'Vincular e Invitar Contratista al Concurso'}
                </h3>
                {editingInvitationId && (
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-500/20 text-blue-300 border border-blue-500/30">
                    Modo Edición
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-400">
                Selecciona un concurso, asigna el contratista autorizado y genera su enlace firmado
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-white p-1 rounded-lg hover:bg-slate-800 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="flex items-center justify-between px-6 pt-3 pb-2 bg-slate-50 border-b border-slate-200 shrink-0">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setActiveTab('form')}
              className={`text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === 'form'
                  ? 'bg-emerald-600 text-white shadow-xs'
                  : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-100'
              }`}
            >
              {editingInvitationId ? <Edit2 className="w-3.5 h-3.5" /> : <PlusCircle className="w-3.5 h-3.5" />}
              <span>{editingInvitationId ? 'Editar Asignación' : 'Nueva Invitación / Asignación'}</span>
            </button>
            <button
              onClick={() => setActiveTab('list')}
              className={`text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === 'list'
                  ? 'bg-slate-900 text-white shadow-xs'
                  : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-100'
              }`}
            >
              <LinkIcon className="w-3.5 h-3.5" />
              <span>Invitaciones Activas ({invitations.length})</span>
            </button>
          </div>

          <button
            onClick={loadData}
            disabled={fetchingData}
            className="text-slate-500 hover:text-slate-800 p-1.5 bg-white border border-slate-200 rounded-lg hover:bg-slate-100 shadow-2xs transition-colors"
            title="Recargar datos"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${fetchingData ? 'animate-spin text-emerald-600' : ''}`} />
          </button>
        </div>

        {/* Modal Body */}
        <div className="p-6 overflow-y-auto flex-1">
          {error && (
            <div className="mb-4 bg-red-50 border border-red-200 rounded-xl p-3 flex items-start gap-2.5 text-xs text-red-700 animate-in fade-in duration-200">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          {successMessage && !generatedLink && (
            <div className="mb-4 bg-emerald-50 border border-emerald-200 rounded-xl p-3 flex items-start gap-2.5 text-xs text-emerald-800 animate-in fade-in duration-200">
              <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
              <span>{successMessage}</span>
            </div>
          )}

          {/* TAB 1: FORM VIEW (CREATE OR EDIT) */}
          {activeTab === 'form' && (
            <>
              {!generatedLink ? (
                <form onSubmit={handleSubmit} className="space-y-4">
                  {/* Event Selection */}
                  <div className="bg-slate-50 border border-slate-200 rounded-xl p-3.5 space-y-2">
                    <label className="block text-xs font-bold text-slate-800 uppercase tracking-wider flex items-center justify-between">
                      <span>1. Seleccionar Concurso de Obra / Licitación</span>
                      <span className="text-[11px] font-normal text-slate-500 font-mono">
                        {events.length} concursos disponibles
                      </span>
                    </label>

                    <select
                      value={selectedEventId}
                      onChange={(e) => setSelectedEventId(Number(e.target.value))}
                      className="w-full text-xs font-semibold border border-slate-300 rounded-lg p-2.5 bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 text-slate-800"
                      required
                    >
                      {events.map((ev) => (
                        <option key={ev.id_event} value={ev.id_event}>
                          [{ev.tag_event}] {ev.event_type} &mdash; Convocante: {ev.client_name}
                        </option>
                      ))}
                    </select>

                    {currentSelectedEvent && (
                      <div className="pt-2 border-t border-slate-200/60 flex flex-wrap items-center justify-between text-xs text-slate-600 gap-2">
                        <div className="flex items-center gap-1.5">
                          <Building className="w-3.5 h-3.5 text-slate-400" />
                          <span>
                            <strong>Convocante:</strong> {currentSelectedEvent.client_name}
                          </span>
                        </div>
                        <div className="flex items-center gap-1 text-[11px] bg-emerald-50 text-emerald-800 border border-emerald-200 px-2 py-0.5 rounded-md font-medium">
                          <LinkIcon className="w-3 h-3 text-emerald-600" />
                          <span>
                            Contratista en Concurso: <strong>{currentSelectedEvent.provider_name || 'Pendiente de vincular'}</strong>
                          </span>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Contractor Selection & Details */}
                  <div className="bg-white border border-slate-200 rounded-xl p-3.5 space-y-3 shadow-2xs">
                    <label className="block text-xs font-bold text-slate-800 uppercase tracking-wider">
                      2. Contratista Asignado (Razón Social y Representante)
                    </label>

                    {/* Quick Pick from Existing Providers */}
                    <div>
                      <span className="block text-[11px] font-semibold text-slate-500 mb-1">
                        Elegir de Catálogo de Contratistas Registrados o Crear Nuevo:
                      </span>
                      <select
                        value={selectedProviderId}
                        onChange={(e) => handleProviderSelectChange(e.target.value)}
                        className="w-full text-xs border border-slate-300 rounded-lg p-2 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500"
                      >
                        <option value="custom">+ Registrar / Editar Contratista Manualmente</option>
                        {providers.map((p) => (
                          <option key={p.id_provider} value={p.id_provider}>
                            {p.tag_provider ? `[${p.tag_provider}] ` : ''}
                            {p.provider_name} {p.provider_representative ? `(${p.provider_representative})` : ''}
                          </option>
                        ))}
                      </select>
                    </div>

                    {/* Contractor Name */}
                    <div>
                      <label className="block text-[11px] font-bold text-slate-700 uppercase tracking-wider mb-1 flex items-center gap-1.5">
                        <Building className="w-3.5 h-3.5 text-slate-400" />
                        Razón Social de la Empresa Contratista
                      </label>
                      <input
                        type="text"
                        value={providerName}
                        onChange={(e) => setProviderName(e.target.value)}
                        placeholder="Ej. MHEBOSAP, S.A. DE C.V."
                        className="w-full text-xs border border-slate-300 rounded-lg p-2.5 focus:outline-none focus:ring-2 focus:ring-emerald-500 font-medium"
                        required
                      />
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      {/* Representative / Full Name */}
                      <div>
                        <label className="block text-[11px] font-bold text-slate-700 uppercase tracking-wider mb-1 flex items-center gap-1.5">
                          <User className="w-3.5 h-3.5 text-slate-400" />
                          Nombre del Estimador / Representante
                        </label>
                        <input
                          type="text"
                          value={fullName}
                          onChange={(e) => setFullName(e.target.value)}
                          placeholder="Ej. Ing. Fernando Tapia"
                          className="w-full text-xs border border-slate-300 rounded-lg p-2.5 focus:outline-none focus:ring-2 focus:ring-emerald-500"
                        />
                      </div>

                      {/* Email */}
                      <div>
                        <label className="block text-[11px] font-bold text-slate-700 uppercase tracking-wider mb-1 flex items-center gap-1.5">
                          <Mail className="w-3.5 h-3.5 text-slate-400" />
                          Correo para Enlace Mágico
                        </label>
                        <input
                          type="email"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          placeholder="licitaciones@mhebosap.com.mx"
                          className="w-full text-xs border border-slate-300 rounded-lg p-2.5 focus:outline-none focus:ring-2 focus:ring-emerald-500 font-mono"
                          required
                        />
                      </div>
                    </div>

                    {/* Role & Options */}
                    <div className="pt-2 border-t border-slate-100 flex flex-wrap items-center justify-between gap-3 text-xs">
                      <div>
                        <span className="font-semibold text-slate-700 mr-2">Nivel de Acceso:</span>
                        <select
                          value={accessRole}
                          onChange={(e) => setAccessRole(e.target.value as any)}
                          className="text-xs border border-slate-300 rounded-md p-1.5 bg-slate-50 font-medium"
                        >
                          <option value="WRITE">Captura y Edición de APU (WRITE)</option>
                          <option value="READ">Solo Consulta de Concurso (READ)</option>
                        </select>
                      </div>

                      {editingInvitationId && (
                        <label className="flex items-center gap-2 cursor-pointer text-slate-700 select-none">
                          <input
                            type="checkbox"
                            checked={regenerateToken}
                            onChange={(e) => setRegenerateToken(e.target.checked)}
                            className="rounded border-slate-300 text-emerald-600 focus:ring-emerald-500"
                          />
                          <span className="text-[11px] font-semibold text-blue-700">
                            Regenerar nuevo token de acceso
                          </span>
                        </label>
                      )}
                    </div>
                  </div>

                  <div className="bg-emerald-50/70 border border-emerald-200/80 rounded-xl p-3 text-slate-700 text-xs flex items-start gap-2.5">
                    <ShieldCheck className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
                    <p className="leading-relaxed">
                      Al guardar, el contratista quedará vinculado automáticamente al concurso (actualizando el campo{' '}
                      <code className="bg-emerald-100 px-1 py-0.5 rounded text-emerald-950 font-mono font-semibold">
                        event.id_provider
                      </code>{' '}
                      y la asignación de acceso). El contratista podrá acceder exclusivamente a su concurso asignado con
                      registro en la bitácora de auditoría.
                    </p>
                  </div>

                  {/* Form Actions */}
                  <div className="pt-2 flex items-center justify-between gap-3">
                    {editingInvitationId ? (
                      <button
                        type="button"
                        onClick={handleResetForm}
                        className="text-xs font-semibold text-slate-600 hover:text-slate-900 underline"
                      >
                        Cancelar edición y crear nueva
                      </button>
                    ) : (
                      <div></div>
                    )}

                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={onClose}
                        className="text-xs font-semibold px-4 py-2 text-slate-600 hover:text-slate-900 border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors cursor-pointer"
                      >
                        Cerrar
                      </button>
                      <button
                        type="submit"
                        disabled={loading}
                        className="bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold px-5 py-2 rounded-lg flex items-center gap-2 transition-colors shadow-sm disabled:opacity-50 cursor-pointer"
                      >
                        {loading ? (
                          <>
                            <Loader2 className="w-3.5 h-3.5 animate-spin" />
                            <span>Guardando...</span>
                          </>
                        ) : (
                          <>
                            <Send className="w-3.5 h-3.5" />
                            <span>
                              {editingInvitationId
                                ? 'Actualizar Invitación y Vincular'
                                : 'Vincular y Generar Enlace Mágico'}
                            </span>
                          </>
                        )}
                      </button>
                    </div>
                  </div>
                </form>
              ) : (
                /* SUCCESS / GENERATED LINK VIEW */
                <div className="space-y-4 animate-in fade-in duration-200">
                  <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-4 text-xs text-emerald-900 space-y-2">
                    <div className="flex items-center gap-2 font-bold text-emerald-950 text-sm">
                      <CheckCircle2 className="w-5 h-5 text-emerald-600" />
                      {editingInvitationId
                        ? 'Invitación Actualizada y Contratista Vinculado'
                        : 'Contratista Vinculado con Éxito al Concurso'}
                    </div>
                    <p className="text-slate-700">
                      Se ha asociado la empresa <strong>{providerName}</strong> al concurso{' '}
                      <strong>{currentSelectedEvent?.tag_event || `#${selectedEventId}`}</strong> y se ha emitido el enlace de acceso firmado para <strong>{email}</strong>.
                    </p>
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-slate-800 uppercase tracking-wider mb-1.5 flex items-center justify-between">
                      <span>Enlace Mágico de Acceso Seguro (Sin Contraseña):</span>
                      <span className="text-[10px] text-slate-500 font-normal">Vigencia: 7 días</span>
                    </label>
                    <div className="flex items-center gap-2">
                      <input
                        type="text"
                        readOnly
                        value={generatedLink}
                        className="w-full text-xs font-mono bg-slate-50 border border-slate-300 rounded-lg p-2.5 text-slate-700 select-all"
                      />
                      <button
                        onClick={handleCopy}
                        className="bg-slate-900 hover:bg-slate-800 text-white text-xs font-semibold px-3 py-2.5 rounded-lg flex items-center gap-1.5 shrink-0 transition-colors cursor-pointer"
                        title="Copiar al portapapeles"
                      >
                        {copied ? (
                          <>
                            <Check className="w-3.5 h-3.5 text-emerald-400" />
                            <span className="text-emerald-400">Copiado</span>
                          </>
                        ) : (
                          <>
                            <Copy className="w-3.5 h-3.5" />
                            <span>Copiar</span>
                          </>
                        )}
                      </button>
                    </div>
                  </div>

                  <div className="flex items-center justify-between pt-4 border-t border-slate-100">
                    <button
                      onClick={handleResetForm}
                      className="text-xs font-semibold text-slate-600 hover:text-slate-900"
                    >
                      &larr; Crear o Editar Otra Invitación
                    </button>
                    <div className="flex gap-2">
                      <a
                        href={generatedLink}
                        target="_blank"
                        rel="noreferrer"
                        className="text-xs font-semibold px-3 py-2 text-emerald-700 bg-emerald-50 border border-emerald-200 hover:bg-emerald-100 rounded-lg flex items-center gap-1.5 transition-colors"
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                        <span>Probar Enlace</span>
                      </a>
                      <button
                        onClick={() => {
                          handleResetForm();
                          setActiveTab('list');
                        }}
                        className="text-xs font-semibold px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-lg transition-colors cursor-pointer"
                      >
                        Ver Lista de Invitaciones
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </>
          )}

          {/* TAB 2: LIST VIEW OF INVITATIONS & ASSIGNMENTS */}
          {activeTab === 'list' && (
            <div className="space-y-4">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div className="relative flex-1">
                  <Search className="w-3.5 h-3.5 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                  <input
                    type="text"
                    placeholder="Buscar por correo, contratista o concurso..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="w-full text-xs bg-slate-50 border border-slate-300 rounded-lg pl-8 pr-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-emerald-500"
                  />
                </div>
                <button
                  onClick={() => {
                    handleResetForm();
                    setActiveTab('form');
                  }}
                  className="bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold px-3 py-1.5 rounded-lg flex items-center gap-1.5 self-start cursor-pointer shadow-2xs"
                >
                  <PlusCircle className="w-3.5 h-3.5" />
                  <span>Nueva Invitación</span>
                </button>
              </div>

              {filteredInvitations.length === 0 ? (
                <div className="text-center py-10 bg-slate-50 rounded-xl border border-slate-200 text-slate-500 text-xs space-y-2">
                  <Mail className="w-8 h-8 text-slate-300 mx-auto" />
                  <p className="font-semibold text-slate-700">No se encontraron invitaciones registradas</p>
                  <p className="text-slate-400">
                    Utiliza la pestaña de creación para invitar y vincular contratistas a los concursos.
                  </p>
                </div>
              ) : (
                <div className="space-y-2.5">
                  {filteredInvitations.map((inv) => {
                    const isAccepted = inv.is_accepted;
                    const isExpired = inv.expires_at && new Date(inv.expires_at).getTime() < Date.now();
                    const origin = typeof window !== 'undefined' ? window.location.origin : '';
                    const link = `${origin}/auth/verify?token=${inv.token}`;

                    return (
                      <div
                        key={inv.id_invitation}
                        className="bg-white border border-slate-200 hover:border-slate-300 rounded-xl p-3.5 shadow-2xs transition-all space-y-2.5"
                      >
                        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="text-[11px] font-mono font-bold px-2 py-0.5 rounded bg-slate-900 text-white">
                                {inv.event?.tag_event || `Concurso #${inv.id_event}`}
                              </span>
                              <span className="text-xs font-bold text-slate-900">
                                {inv.provider?.provider_name || 'Contratista asignado'}
                              </span>
                            </div>
                            <p className="text-xs text-slate-500 font-mono mt-0.5 flex items-center gap-1">
                              <Mail className="w-3 h-3 text-slate-400" />
                              <span>{inv.invited_email}</span>
                              {inv.provider?.provider_representative && (
                                <span className="text-slate-400 text-[11px]">
                                  &bull; {inv.provider.provider_representative}
                                </span>
                              )}
                            </p>
                          </div>

                          <div className="flex items-center gap-2 self-start sm:self-center">
                            {isAccepted ? (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200 flex items-center gap-1">
                                <CheckCircle2 className="w-3 h-3 text-emerald-600" />
                                Aceptada
                              </span>
                            ) : isExpired ? (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-red-100 text-red-800 border border-red-200">
                                Expirada
                              </span>
                            ) : (
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 border border-amber-200 flex items-center gap-1">
                                <Clock className="w-3 h-3 text-amber-600" />
                                Pendiente
                              </span>
                            )}
                          </div>
                        </div>

                        {/* Event details banner */}
                        {inv.event && (
                          <div className="text-[11px] text-slate-600 bg-slate-50 px-2.5 py-1.5 rounded-lg border border-slate-200/60 flex items-center justify-between">
                            <span className="truncate">
                              <strong>Objeto:</strong> {inv.event.event_type}
                            </span>
                            <span className="text-slate-400 shrink-0 ml-2">
                              Vence: {new Date(inv.expires_at).toLocaleDateString('es-MX')}
                            </span>
                          </div>
                        )}

                        {/* Action buttons */}
                        <div className="flex items-center justify-between pt-1 border-t border-slate-100 text-xs">
                          <div className="flex items-center gap-1">
                            <button
                              onClick={() => {
                                navigator.clipboard.writeText(link);
                                alert('Enlace mágico copiado al portapapeles.');
                              }}
                              className="text-xs text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200 px-2.5 py-1 rounded-md flex items-center gap-1 cursor-pointer"
                              title="Copiar enlace"
                            >
                              <Copy className="w-3 h-3" />
                              <span>Copiar Enlace</span>
                            </button>
                            <a
                              href={link}
                              target="_blank"
                              rel="noreferrer"
                              className="text-xs text-emerald-700 hover:text-emerald-900 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 px-2.5 py-1 rounded-md flex items-center gap-1"
                            >
                              <ExternalLink className="w-3 h-3" />
                              <span>Abrir</span>
                            </a>
                          </div>

                          <div className="flex items-center gap-1">
                            <button
                              onClick={() => handleEditInvitation(inv)}
                              className="text-xs font-semibold text-blue-700 hover:text-blue-900 bg-blue-50 hover:bg-blue-100 border border-blue-200 px-2.5 py-1 rounded-md flex items-center gap-1 cursor-pointer"
                              title="Editar invitación y asignación"
                            >
                              <Edit2 className="w-3 h-3" />
                              <span>Editar</span>
                            </button>
                            <button
                              onClick={() => handleDeleteInvitation(inv.id_invitation)}
                              className="text-xs text-red-600 hover:text-red-800 p-1 hover:bg-red-50 rounded-md transition-colors cursor-pointer"
                              title="Eliminar invitación"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="bg-slate-50 px-6 py-3 border-t border-slate-200 flex items-center justify-between text-xs text-slate-500 shrink-0">
          <span>APU-suite &bull; Gestión y Asignación de Contratistas</span>
          <button
            onClick={onClose}
            className="px-4 py-1.5 bg-slate-900 hover:bg-slate-800 text-white font-semibold rounded-lg transition-colors cursor-pointer"
          >
            Cerrar
          </button>
        </div>
      </div>
    </div>
  );
}
