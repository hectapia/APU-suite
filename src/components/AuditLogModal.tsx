'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { AuditLog, AuditAction } from '@/types/database';
import {
  X,
  Shield,
  RefreshCw,
  Search,
  Filter,
  CheckCircle,
  AlertTriangle,
  FileText,
  Clock,
  Terminal,
  Database,
  UserCheck,
} from 'lucide-react';

interface AuditLogModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function AuditLogModal({ isOpen, onClose }: AuditLogModalProps) {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(false);
  const [actionFilter, setActionFilter] = useState<string>('ALL');
  const [searchTerm, setSearchTerm] = useState('');
  const [expandedLogId, setExpandedLogId] = useState<string | null>(null);

  const fetchLogs = useCallback(async () => {
    try {
      setLoading(true);
      const url = new URL('/api/audit-log', window.location.origin);
      if (actionFilter !== 'ALL') {
        url.searchParams.set('action', actionFilter);
      }
      url.searchParams.set('limit', '80');

      const res = await fetch(url.toString());
      const data = await res.json();
      if (data.success && Array.isArray(data.auditLogs)) {
        setLogs(data.auditLogs);
      }
    } catch (err) {
      console.error('Error fetching audit logs:', err);
    } finally {
      setLoading(false);
    }
  }, [actionFilter]);

  useEffect(() => {
    if (isOpen) {
      fetchLogs();
    }
  }, [isOpen, fetchLogs]);

  if (!isOpen) return null;

  const filteredLogs = logs.filter((log) => {
    if (!searchTerm) return true;
    const term = searchTerm.toLowerCase();
    return (
      log.user_role?.toLowerCase().includes(term) ||
      log.entity_type?.toLowerCase().includes(term) ||
      log.entity_id?.toLowerCase().includes(term) ||
      JSON.stringify(log.details || {}).toLowerCase().includes(term) ||
      log.ip_address?.toLowerCase().includes(term)
    );
  });

  const getActionBadge = (action: AuditAction) => {
    switch (action) {
      case 'CREATE':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-300">
            CREATE
          </span>
        );
      case 'UPDATE':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full bg-blue-100 text-blue-800 border border-blue-300">
            UPDATE
          </span>
        );
      case 'READ':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full bg-slate-100 text-slate-800 border border-slate-300">
            READ
          </span>
        );
      case 'DENIED':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full bg-red-100 text-red-800 border border-red-300">
            DENIED
          </span>
        );
      case 'DELETE':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 border border-amber-300">
            DELETE
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full bg-slate-100 text-slate-800">
            {action}
          </span>
        );
    }
  };

  return (
    <div
      className="fixed inset-0 bg-slate-950/75 backdrop-blur-xs flex items-center justify-center p-3 sm:p-6"
      style={{ zIndex: 100 }}
    >
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-5xl h-[88vh] flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        {/* Header */}
        <div className="bg-slate-900 text-white px-6 py-4 flex items-center justify-between border-b border-slate-800 shrink-0">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-purple-500/20 text-purple-400 border border-purple-500/30 flex items-center justify-center">
              <Shield className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-bold text-base leading-tight">
                  Bitácora de Auditoría y Seguridad
                </h3>
                <span className="text-[10px] font-mono font-semibold px-2 py-0.5 rounded-full bg-slate-800 text-purple-300 border border-slate-700">
                  audit_log
                </span>
              </div>
              <p className="text-xs text-slate-400">
                Registro inmutable de acciones realizadas por Administradores y Estimadores de Contratistas
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

        {/* Toolbar */}
        <div className="p-4 bg-slate-50 border-b border-slate-200 flex flex-wrap items-center justify-between gap-3 shrink-0">
          {/* Action pills filter */}
          <div className="flex items-center gap-1.5 overflow-x-auto pb-1 sm:pb-0">
            <span className="text-xs font-semibold text-slate-500 mr-1 flex items-center gap-1">
              <Filter className="w-3.5 h-3.5" />
              Acción:
            </span>
            {(['ALL', 'CREATE', 'UPDATE', 'READ', 'DENIED'] as const).map((act) => (
              <button
                key={act}
                onClick={() => setActionFilter(act)}
                className={`text-xs px-2.5 py-1 rounded-lg font-medium transition-colors cursor-pointer ${
                  actionFilter === act
                    ? 'bg-slate-900 text-white shadow-xs'
                    : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-100'
                }`}
              >
                {act === 'ALL' ? 'Todas' : act}
              </button>
            ))}
          </div>

          {/* Search box & refresh */}
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <div className="relative flex-1 sm:w-64">
              <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                placeholder="Buscar entidad, rol, IP, detalle..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full text-xs bg-white border border-slate-300 rounded-lg pl-8 pr-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-purple-500"
              />
            </div>
            <button
              onClick={fetchLogs}
              disabled={loading}
              className="p-1.5 bg-white border border-slate-300 text-slate-700 hover:bg-slate-100 rounded-lg transition-colors cursor-pointer shadow-2xs"
              title="Actualizar bitácora"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-purple-600' : ''}`} />
            </button>
          </div>
        </div>

        {/* Table Body */}
        <div className="flex-1 overflow-auto p-4">
          {filteredLogs.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center p-8 text-slate-400">
              <FileText className="w-12 h-12 stroke-1 mb-2 text-slate-300" />
              <p className="text-sm font-semibold text-slate-700">No hay registros de auditoría que mostrar</p>
              <p className="text-xs text-slate-400 mt-1">
                Las operaciones de guardado de APU, invitaciones y verificaciones de enlace se registrarán aquí.
              </p>
            </div>
          ) : (
            <div className="border border-slate-200 rounded-xl overflow-hidden bg-white shadow-2xs">
              <table className="w-full text-left border-collapse text-xs">
                <thead>
                  <tr className="bg-slate-100/80 border-b border-slate-200 text-slate-600 font-semibold uppercase tracking-wider text-[11px]">
                    <th className="py-2.5 px-3">Fecha y Hora</th>
                    <th className="py-2.5 px-3">Acción</th>
                    <th className="py-2.5 px-3">Rol / Usuario</th>
                    <th className="py-2.5 px-3">Entidad</th>
                    <th className="py-2.5 px-3">ID Ref</th>
                    <th className="py-2.5 px-3">Detalle Payload</th>
                    <th className="py-2.5 px-3">IP Origen</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {filteredLogs.map((log) => {
                    const isExpanded = expandedLogId === log.id_log;
                    return (
                      <React.Fragment key={log.id_log}>
                        <tr
                          onClick={() => setExpandedLogId(isExpanded ? null : log.id_log)}
                          className={`hover:bg-slate-50 transition-colors cursor-pointer ${
                            log.action === 'DENIED' ? 'bg-red-50/30' : ''
                          }`}
                        >
                          <td className="py-2.5 px-3 font-mono text-[11px] text-slate-500 whitespace-nowrap">
                            {new Date(log.created_at).toLocaleString('es-MX', {
                              dateStyle: 'short',
                              timeStyle: 'medium',
                            })}
                          </td>
                          <td className="py-2.5 px-3 whitespace-nowrap">
                            {getActionBadge(log.action)}
                          </td>
                          <td className="py-2.5 px-3 whitespace-nowrap">
                            <span className="font-semibold text-slate-800">{log.user_role}</span>
                            {log.id_user && (
                              <span className="block text-[10px] text-slate-400 font-mono">
                                {log.id_user}
                              </span>
                            )}
                          </td>
                          <td className="py-2.5 px-3 font-medium text-slate-700 whitespace-nowrap">
                            <span className="px-2 py-0.5 rounded bg-slate-100 text-slate-700 font-mono text-[10px]">
                              {log.entity_type}
                            </span>
                          </td>
                          <td className="py-2.5 px-3 font-mono text-slate-500 whitespace-nowrap">
                            {log.entity_id || '—'}
                          </td>
                          <td className="py-2.5 px-3 max-w-xs truncate text-slate-600 font-mono text-[11px]">
                            {JSON.stringify(log.details || {})}
                          </td>
                          <td className="py-2.5 px-3 text-slate-500 font-mono text-[10px] whitespace-nowrap">
                            {log.ip_address || '127.0.0.1'}
                          </td>
                        </tr>

                        {isExpanded && (
                          <tr className="bg-slate-50/90 border-y border-slate-200">
                            <td colSpan={7} className="p-4 space-y-2">
                              <div className="flex items-center justify-between text-xs font-semibold text-slate-700">
                                <span>Detalle Completo del Evento de Auditoría:</span>
                                <span className="font-mono text-[10px] text-slate-400">
                                  ID: {log.id_log}
                                </span>
                              </div>
                              <pre className="bg-slate-900 text-emerald-400 p-3 rounded-lg text-xs font-mono overflow-x-auto shadow-inner">
                                {JSON.stringify(
                                  {
                                    id_log: log.id_log,
                                    action: log.action,
                                    user_role: log.user_role,
                                    id_user: log.id_user,
                                    entity_type: log.entity_type,
                                    entity_id: log.entity_id,
                                    ip_address: log.ip_address,
                                    user_agent: log.user_agent,
                                    details: log.details,
                                    created_at: log.created_at,
                                  },
                                  null,
                                  2
                                )}
                              </pre>
                            </td>
                          </tr>
                        )}
                      </React.Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="bg-slate-50 px-6 py-3 border-t border-slate-200 flex items-center justify-between text-xs text-slate-500 shrink-0">
          <span>
            Mostrando <strong>{filteredLogs.length}</strong> eventos registrados
          </span>
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
