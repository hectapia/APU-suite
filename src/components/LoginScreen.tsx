'use client';

import React, { useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import {
  Shield,
  Key,
  Mail,
  User,
  Building,
  ArrowRight,
  CheckCircle2,
  Lock,
  FileCheck2,
  AlertCircle,
  Loader2,
} from 'lucide-react';

export function LoginScreen() {
  const { loginAsAdmin, loginAsProvider } = useAuth();
  const [activeTab, setActiveTab] = useState<'admin' | 'provider'>('admin');

  // Admin form state
  const [adminEmail, setAdminEmail] = useState('hectapia@outlook.com');
  const [adminName, setAdminName] = useState('Ing. Héctor Tapia (Administrador)');
  const [adminPassword, setAdminPassword] = useState('admin123');

  // Provider form state
  const [providerEmail, setProviderEmail] = useState('licitaciones@mhebosap.com.mx');
  const [providerName, setProviderName] = useState('MHEBOSAP, S.A. DE C.V.');

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleAdminSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!adminEmail.trim()) {
      setError('Por favor ingresa un correo de administrador.');
      return;
    }

    const savedPassword = localStorage.getItem('apu_admin_password') || 'admin123';
    if (adminPassword !== savedPassword) {
      setError('Contraseña incorrecta. Por favor verifica tus credenciales.');
      return;
    }

    try {
      setLoading(true);
      setError(null);

      // Log sign-in to audit log
      try {
        await fetch('/api/auth/verify?token=admin_direct', { method: 'GET' });
      } catch {
        // silent fallback
      }

      loginAsAdmin(adminEmail.trim(), adminName.trim());
    } catch (err: any) {
      setError(err?.message || 'Error al iniciar sesión.');
    } finally {
      setLoading(false);
    }
  };

  const handleProviderSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!providerEmail.trim()) {
      setError('Por favor ingresa tu correo de contratista.');
      return;
    }

    try {
      setLoading(true);
      setError(null);
      loginAsProvider(providerEmail.trim(), providerName.trim());
    } catch (err: any) {
      setError(err?.message || 'Error al iniciar sesión.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-[75vh] flex items-center justify-center py-6 px-4">
      <div className="max-w-md w-full bg-white rounded-3xl shadow-2xl border border-slate-200 overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        {/* Top Header Card */}
        <div className="bg-slate-900 text-white p-6 sm:p-8 text-center relative overflow-hidden border-b border-slate-800">
          <div className="absolute -top-12 -right-12 w-36 h-36 bg-emerald-500/10 rounded-full blur-2xl pointer-events-none"></div>
          <div className="absolute -bottom-12 -left-12 w-36 h-36 bg-purple-500/10 rounded-full blur-2xl pointer-events-none"></div>

          <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-emerald-500 text-slate-950 font-black text-2xl shadow-lg mb-4">
            APU
          </div>
          <h1 className="text-xl sm:text-2xl font-black tracking-tight text-white">
            APU-suite Studio
          </h1>
          <p className="text-xs text-slate-400 mt-1 max-w-xs mx-auto">
            Ingeniería de Costos, Análisis de Precios Unitarios (PEMEX DT-7) y Control de Licitaciones
          </p>

          {/* Persona Tabs */}
          <div className="grid grid-cols-2 gap-1.5 bg-slate-800/80 p-1 rounded-xl mt-6 border border-slate-700/60">
            <button
              type="button"
              onClick={() => {
                setActiveTab('admin');
                setError(null);
              }}
              className={`py-2 text-xs font-bold rounded-lg transition-all flex items-center justify-center gap-1.5 cursor-pointer ${
                activeTab === 'admin'
                  ? 'bg-purple-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              <Shield className="w-3.5 h-3.5" />
              <span>Administrador</span>
            </button>
            <button
              type="button"
              onClick={() => {
                setActiveTab('provider');
                setError(null);
              }}
              className={`py-2 text-xs font-bold rounded-lg transition-all flex items-center justify-center gap-1.5 cursor-pointer ${
                activeTab === 'provider'
                  ? 'bg-emerald-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              <Building className="w-3.5 h-3.5" />
              <span>Contratista</span>
            </button>
          </div>
        </div>

        {/* Form Body */}
        <div className="p-6 sm:p-8">
          {error && (
            <div className="mb-4 bg-red-50 border border-red-200 rounded-xl p-3 flex items-start gap-2 text-xs text-red-700">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          {activeTab === 'admin' ? (
            <form onSubmit={handleAdminSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <Mail className="w-3.5 h-3.5 text-purple-600" />
                  Correo del Administrador
                </label>
                <input
                  type="email"
                  value={adminEmail}
                  onChange={(e) => setAdminEmail(e.target.value)}
                  placeholder="admin.licitaciones@pemex.com"
                  className="w-full text-xs font-mono border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <User className="w-3.5 h-3.5 text-purple-600" />
                  Nombre Completo / Cargo
                </label>
                <input
                  type="text"
                  value={adminName}
                  onChange={(e) => setAdminName(e.target.value)}
                  placeholder="Ing. Administrador de Concursos"
                  className="w-full text-xs border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center justify-between">
                  <span className="flex items-center gap-1.5">
                    <Lock className="w-3.5 h-3.5 text-purple-600" />
                    Contraseña de Acceso
                  </span>
                  <span className="text-[10px] text-slate-400 font-normal">Demo: admin123</span>
                </label>
                <input
                  type="password"
                  value={adminPassword}
                  onChange={(e) => setAdminPassword(e.target.value)}
                  className="w-full text-xs border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                  required
                />
              </div>

              <div className="bg-purple-50 border border-purple-200/80 rounded-xl p-3 text-xs text-purple-950 flex items-start gap-2">
                <Shield className="w-4 h-4 text-purple-600 shrink-0 mt-0.5" />
                <p>
                  El rol <strong>Administrador</strong> tiene acceso irrestricto para gestionar concursos, catálogos maestros, emitir invitaciones RLS y consultar la bitácora de auditoría.
                </p>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full bg-slate-900 hover:bg-slate-800 text-white font-bold py-3 px-4 rounded-xl text-xs flex items-center justify-center gap-2 transition-colors shadow-sm cursor-pointer mt-2 disabled:opacity-50"
              >
                {loading ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin text-purple-400" />
                    <span>Iniciando Sesión...</span>
                  </>
                ) : (
                  <>
                    <span>Entrar a APU Studio como Administrador</span>
                    <ArrowRight className="w-4 h-4" />
                  </>
                )}
              </button>
            </form>
          ) : (
            <form onSubmit={handleProviderSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <Mail className="w-3.5 h-3.5 text-emerald-600" />
                  Correo Registrado del Contratista
                </label>
                <input
                  type="email"
                  value={providerEmail}
                  onChange={(e) => setProviderEmail(e.target.value)}
                  placeholder="licitaciones@mhebosap.com.mx"
                  className="w-full text-xs font-mono border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 text-slate-800"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <Building className="w-3.5 h-3.5 text-emerald-600" />
                  Razón Social de la Empresa
                </label>
                <input
                  type="text"
                  value={providerName}
                  onChange={(e) => setProviderName(e.target.value)}
                  placeholder="MHEBOSAP, S.A. DE C.V."
                  className="w-full text-xs border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 text-slate-800"
                  required
                />
              </div>

              <div className="bg-emerald-50 border border-emerald-200/80 rounded-xl p-3 text-xs text-emerald-950 flex items-start gap-2">
                <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
                <p>
                  Los contratistas acceden a su concurso asignado para capturar precios unitarios e integraciones DT-7 bajo políticas RLS.
                </p>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full bg-emerald-600 hover:bg-emerald-700 text-white font-bold py-3 px-4 rounded-xl text-xs flex items-center justify-center gap-2 transition-colors shadow-sm cursor-pointer mt-2 disabled:opacity-50"
              >
                {loading ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Validando Acceso...</span>
                  </>
                ) : (
                  <>
                    <span>Entrar como Contratista (MHEBOSAP)</span>
                    <ArrowRight className="w-4 h-4" />
                  </>
                )}
              </button>
            </form>
          )}
        </div>

        {/* Footer */}
        <div className="bg-slate-50 px-6 py-4 border-t border-slate-100 text-center text-[11px] text-slate-500">
          APU-suite &bull; Plataforma Segura con Row Level Security (RLS) & Bitácora de Auditoría
        </div>
      </div>
    </div>
  );
}
