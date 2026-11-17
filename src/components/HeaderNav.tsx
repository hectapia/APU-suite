'use client';

import React, { useState, useEffect } from 'react';
import { useAuth } from '@/lib/auth-context';
import { InviteProviderModal } from './InviteProviderModal';
import { AuditLogModal } from './AuditLogModal';
import { EventDashboardView } from '@/types/database';
import { supabase } from '@/lib/supabase';
import {
  Building,
  Shield,
  User,
  Mail,
  FileText,
  ChevronDown,
  LogOut,
  ExternalLink,
  CheckCircle2,
  Lock,
} from 'lucide-react';

export function HeaderNav() {
  const { user, activeEvent, switchRole, logout } = useAuth();
  const [isInviteOpen, setIsInviteOpen] = useState(false);
  const [isAuditOpen, setIsAuditOpen] = useState(false);
  const [events, setEvents] = useState<EventDashboardView[]>([]);
  const [userDropdownOpen, setUserDropdownOpen] = useState(false);

  useEffect(() => {
    async function loadEvents() {
      const { data } = await supabase.from('v_event_dashboard').select('*');
      if (data) setEvents(data);
    }
    loadEvents();
  }, []);

  return (
    <>
      <div className="flex items-center space-x-3">
        {/* Dynamic Event Company / Logo section when an event card is opened */}
        {activeEvent ? (
          <div className="flex items-center gap-2 bg-slate-800/90 border border-slate-700 px-3 py-1.5 rounded-xl shadow-xs animate-in fade-in duration-200">
            <div className="w-6 h-6 rounded-lg bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
              <Building className="w-3.5 h-3.5" />
            </div>
            <div className="text-left">
              <span className="block text-[10px] text-slate-400 uppercase tracking-wider font-semibold">
                Convocante / Proyecto
              </span>
              <span className="text-xs font-bold text-white flex items-center gap-1.5">
                {activeEvent.client_name}
                <span className="text-emerald-400 font-mono text-[11px] font-normal">
                  ({activeEvent.tag_event})
                </span>
              </span>
            </div>

            {user?.role === 'PROVIDER_ESTIMATOR' && user.provider_name && (
              <div className="hidden md:flex items-center gap-1.5 pl-3 border-l border-slate-700 text-xs text-emerald-300">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
                <span className="font-semibold">{user.provider_name}</span>
              </div>
            )}
          </div>
        ) : (
          /* When on the dashboard without an event opened */
          <div className="hidden sm:flex items-center gap-2 text-xs text-slate-400 bg-slate-800/60 border border-slate-700/60 px-3 py-1.5 rounded-xl">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            <span>Panel de Concursos de Obra & Servicios (LOPSRM / PEMEX)</span>
          </div>
        )}

        {/* Admin Tools: Invite & Audit Log */}
        {user?.role === 'ADMIN' && (
          <div className="hidden lg:flex items-center space-x-1.5">
            <button
              onClick={() => setIsInviteOpen(true)}
              className="bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold py-1.5 px-2.5 rounded-lg flex items-center gap-1.5 transition-colors shadow-2xs cursor-pointer"
              title="Invitar Contratista con Enlace Mágico"
            >
              <Mail className="w-3.5 h-3.5" />
              <span>Invitar Contratista</span>
            </button>
            <button
              onClick={() => setIsAuditOpen(true)}
              className="bg-slate-800 hover:bg-slate-700 text-purple-300 border border-purple-500/30 text-xs font-semibold py-1.5 px-2.5 rounded-lg flex items-center gap-1.5 transition-colors cursor-pointer"
              title="Ver Bitácora de Auditoría"
            >
              <Shield className="w-3.5 h-3.5 text-purple-400" />
              <span>Bitácora</span>
            </button>
          </div>
        )}

        {/* User Profile & Persona Switcher */}
        {user && (
          <div className="relative">
            <button
              onClick={() => setUserDropdownOpen(!userDropdownOpen)}
              className="flex items-center gap-2 bg-slate-800/80 hover:bg-slate-800 border border-slate-700 py-1 px-2.5 rounded-xl text-left transition-colors cursor-pointer"
            >
              <div
                className={`w-7 h-7 rounded-lg flex items-center justify-center font-bold text-xs ${
                  user.role === 'ADMIN'
                    ? 'bg-purple-600 text-white'
                    : 'bg-emerald-600 text-white'
                }`}
              >
                {user.role === 'ADMIN' ? 'A' : 'C'}
              </div>
              <div className="hidden md:block">
                <span className="block text-xs font-bold text-white leading-tight">
                  {user.full_name.split(' ')[0]} {user.full_name.split(' ')[1] || ''}
                </span>
                <span className="block text-[10px] text-slate-400 leading-none">
                  {user.role === 'ADMIN' ? 'ADMINISTRADOR' : 'CONTRATISTA'}
                </span>
              </div>
              <ChevronDown className="w-3.5 h-3.5 text-slate-400" />
            </button>

            {userDropdownOpen && (
              <div
                className="absolute right-0 mt-2 w-64 bg-white rounded-xl shadow-xl border border-slate-200 py-2 text-xs text-slate-700 animate-in fade-in duration-150"
                style={{ zIndex: 60 }}
              >
                <div className="px-3 py-2 border-b border-slate-100">
                  <p className="font-bold text-slate-900">{user.full_name}</p>
                  <p className="text-[11px] text-slate-500 font-mono">{user.email}</p>
                  <span
                    className={`inline-block mt-1 text-[10px] font-bold px-2 py-0.5 rounded-full ${
                      user.role === 'ADMIN'
                        ? 'bg-purple-100 text-purple-800'
                        : 'bg-emerald-100 text-emerald-800'
                    }`}
                  >
                    Rol: {user.role}
                  </span>
                </div>

                {/* Mobile Admin Action Shortcuts */}
                {user.role === 'ADMIN' && (
                  <div className="py-1 border-b border-slate-100 lg:hidden">
                    <button
                      onClick={() => {
                        setUserDropdownOpen(false);
                        setIsInviteOpen(true);
                      }}
                      className="w-full text-left px-3 py-1.5 hover:bg-slate-50 flex items-center gap-2 text-slate-700"
                    >
                      <Mail className="w-3.5 h-3.5 text-emerald-600" />
                      <span>Invitar Contratista</span>
                    </button>
                    <button
                      onClick={() => {
                        setUserDropdownOpen(false);
                        setIsAuditOpen(true);
                      }}
                      className="w-full text-left px-3 py-1.5 hover:bg-slate-50 flex items-center gap-2 text-slate-700"
                    >
                      <Shield className="w-3.5 h-3.5 text-purple-600" />
                      <span>Bitácora de Auditoría</span>
                    </button>
                  </div>
                )}

                {/* Persona Switcher for testing/demo */}
                <div className="py-1 border-b border-slate-100">
                  <p className="px-3 py-1 text-[10px] font-bold text-slate-400 uppercase tracking-wider">
                    Cambiar Perfil de Demostración
                  </p>
                  <button
                    onClick={() => {
                      switchRole('ADMIN');
                      setUserDropdownOpen(false);
                    }}
                    className={`w-full text-left px-3 py-1.5 hover:bg-slate-50 flex items-center justify-between ${
                      user.role === 'ADMIN' ? 'font-bold text-purple-700' : 'text-slate-600'
                    }`}
                  >
                    <span>Administrador (PEMEX)</span>
                    {user.role === 'ADMIN' && <CheckCircle2 className="w-3.5 h-3.5 text-purple-600" />}
                  </button>
                  <button
                    onClick={() => {
                      switchRole('PROVIDER_ESTIMATOR');
                      setUserDropdownOpen(false);
                    }}
                    className={`w-full text-left px-3 py-1.5 hover:bg-slate-50 flex items-center justify-between ${
                      user.role === 'PROVIDER_ESTIMATOR'
                        ? 'font-bold text-emerald-700'
                        : 'text-slate-600'
                    }`}
                  >
                    <span>Contratista (MHEBOSAP)</span>
                    {user.role === 'PROVIDER_ESTIMATOR' && (
                      <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                    )}
                  </button>
                </div>

                <div className="pt-1">
                  <button
                    onClick={() => {
                      logout();
                      setUserDropdownOpen(false);
                    }}
                    className="w-full text-left px-3 py-1.5 hover:bg-red-50 text-red-600 flex items-center gap-2"
                  >
                    <LogOut className="w-3.5 h-3.5" />
                    <span>Cerrar Sesión</span>
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Admin Modals */}
      <InviteProviderModal
        isOpen={isInviteOpen}
        onClose={() => setIsInviteOpen(false)}
        events={events}
        defaultEventId={activeEvent?.id_event}
      />
      <AuditLogModal
        isOpen={isAuditOpen}
        onClose={() => setIsAuditOpen(false)}
      />
    </>
  );
}
