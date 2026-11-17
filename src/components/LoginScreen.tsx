'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
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
  AlertCircle,
  Loader2,
  ExternalLink,
  Copy,
  Check,
  Send,
} from 'lucide-react';

export function LoginScreen() {
  const router = useRouter();
  const { loginAsAdmin } = useAuth();
  const [activeTab, setActiveTab] = useState<'admin' | 'provider'>('admin');

  // Admin form state - strictly empty by default (no credentials pre-loaded)
  const [adminEmail, setAdminEmail] = useState('');
  const [adminName, setAdminName] = useState('');
  const [adminPassword, setAdminPassword] = useState('');

  // Contractor request link state - strictly empty by default
  const [providerEmail, setProviderEmail] = useState('');
  const [directTokenInput, setDirectTokenInput] = useState('');
  const [showDirectToken, setShowDirectToken] = useState(false);

  // Link request result state
  const [requestResult, setRequestResult] = useState<{
    success: boolean;
    magicLink?: string;
    token?: string;
    eventTag?: string;
    eventTitle?: string;
    providerName?: string;
  } | null>(null);

  const [copied, setCopied] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleAdminSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const emailTrim = adminEmail.trim().toLowerCase();
    const passTrim = adminPassword.trim();

    if (!emailTrim) {
      setError('Por favor ingresa el correo del administrador.');
      return;
    }

    if (!passTrim) {
      setError('Por favor ingresa la contraseña de acceso.');
      return;
    }

    // Verify admin email
    if (emailTrim !== 'hectapia@outlook.com') {
      setError('El correo ingresado no cuenta con privilegios de Administrador.');
      return;
    }

    // Verify admin password
    const savedPassword = localStorage.getItem('apu_admin_password') || 'admin123';
    if (passTrim !== savedPassword) {
      setError('Contraseña incorrecta. Por favor verifica tus credenciales.');
      return;
    }

    try {
      setLoading(true);

      // Log sign-in to audit log
      try {
        await fetch('/api/auth/verify?token=admin_direct', { method: 'GET' });
      } catch {
        // silent fallback
      }

      loginAsAdmin(
        adminEmail.trim(),
        adminName.trim() || 'Ing. Héctor Tapia (Administrador)'
      );
    } catch (err: any) {
      setError(err?.message || 'Error al iniciar sesión como administrador.');
    } finally {
      setLoading(false);
    }
  };

  const handleRequestProviderLink = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setRequestResult(null);

    const emailTrim = providerEmail.trim().toLowerCase();
    if (!emailTrim) {
      setError('Por favor ingresa el correo de la empresa contratista.');
      return;
    }

    try {
      setLoading(true);
      const res = await fetch('/api/auth/request-link', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: emailTrim }),
      });

      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || 'No se encontró una invitación activa para este correo.');
      }

      setRequestResult(data);
    } catch (err: any) {
      setError(err?.message || 'Error al solicitar el enlace de acceso.');
    } finally {
      setLoading(false);
    }
  };

  const handleDirectTokenSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    let token = directTokenInput.trim();
    if (!token) {
      setError('Por favor ingresa el token o la URL completa de tu enlace.');
      return;
    }

    // Extract token if user pasted full URL
    if (token.includes('token=')) {
      try {
        const urlObj = new URL(token);
        token = urlObj.searchParams.get('token') || token;
      } catch {
        const parts = token.split('token=');
        if (parts[1]) token = parts[1].split('&')[0];
      }
    }

    router.push(`/auth/verify?token=${encodeURIComponent(token)}`);
  };

  const copyMagicLink = () => {
    if (requestResult?.magicLink) {
      navigator.clipboard.writeText(requestResult.magicLink);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
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
                setRequestResult(null);
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
              <span>Contratista Invitado</span>
            </button>
          </div>
        </div>

        {/* Form Body */}
        <div className="p-6 sm:p-8">
          {error && (
            <div className="mb-4 bg-red-50 border border-red-200 rounded-xl p-3 flex items-start gap-2 text-xs text-red-700 animate-in fade-in">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5 text-red-600" />
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
                  placeholder="hectapia@outlook.com"
                  className="w-full text-xs font-mono border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                  required
                  autoComplete="email"
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
                  placeholder="Ing. Héctor Tapia (Administrador)"
                  className="w-full text-xs border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                  autoComplete="name"
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center justify-between">
                  <span className="flex items-center gap-1.5">
                    <Lock className="w-3.5 h-3.5 text-purple-600" />
                    Contraseña de Acceso
                  </span>
                </label>
                <input
                  type="password"
                  value={adminPassword}
                  onChange={(e) => setAdminPassword(e.target.value)}
                  placeholder="Ingresa tu contraseña"
                  className="w-full text-xs border border-slate-300 rounded-xl p-3 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                  required
                  autoComplete="current-password"
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
                    <span>Verificando Credenciales...</span>
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
            <div className="space-y-4">
              <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-3.5 text-xs text-emerald-950 flex items-start gap-2.5">
                <Key className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
                <div className="space-y-1">
                  <p className="font-bold text-emerald-900">Acceso Seguro mediante Enlace Mágico</p>
                  <p className="text-[11px] text-emerald-800 leading-relaxed">
                    Los contratistas acceden a su concurso asignado exclusivamente a través de un enlace firmado único. Introduce tu correo registrado para solicitar o verificar tu enlace de acceso.
                  </p>
                </div>
              </div>

              {/* Request Link Form */}
              {!requestResult ? (
                <form onSubmit={handleRequestProviderLink} className="space-y-3.5">
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

                  <button
                    type="submit"
                    disabled={loading}
                    className="w-full bg-emerald-600 hover:bg-emerald-700 text-white font-bold py-3 px-4 rounded-xl text-xs flex items-center justify-center gap-2 transition-colors shadow-sm cursor-pointer disabled:opacity-50"
                  >
                    {loading ? (
                      <>
                        <Loader2 className="w-4 h-4 animate-spin" />
                        <span>Buscando Invitación Activa...</span>
                      </>
                    ) : (
                      <>
                        <Send className="w-4 h-4" />
                        <span>Solicitar Enlace de Acceso</span>
                      </>
                    )}
                  </button>
                </form>
              ) : (
                /* Verified Invitation Card with Access Button */
                <div className="space-y-3 bg-emerald-50/70 border border-emerald-300 rounded-2xl p-4 animate-in fade-in">
                  <div className="flex items-center gap-2 text-xs font-bold text-emerald-900">
                    <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                    <span>¡Invitación Activa Localizada!</span>
                  </div>

                  <div className="bg-white rounded-xl p-3 border border-emerald-200 text-xs space-y-1.5">
                    <p className="text-slate-700">
                      <strong>Empresa:</strong> {requestResult.providerName}
                    </p>
                    <p className="text-slate-700">
                      <strong>Concurso:</strong>{' '}
                      <span className="font-mono font-bold text-emerald-800 bg-emerald-100 px-1.5 py-0.5 rounded">
                        {requestResult.eventTag}
                      </span>{' '}
                      &mdash; {requestResult.eventTitle}
                    </p>
                  </div>

                  <div className="pt-1 flex flex-col gap-2">
                    <button
                      type="button"
                      onClick={() => {
                        if (requestResult.token) {
                          router.push(`/auth/verify?token=${encodeURIComponent(requestResult.token)}`);
                        }
                      }}
                      className="w-full bg-emerald-600 hover:bg-emerald-700 text-white font-bold py-2.5 px-4 rounded-xl text-xs flex items-center justify-center gap-2 transition-colors shadow-sm cursor-pointer"
                    >
                      <span>Abrir APU Studio con Enlace Firmado</span>
                      <ArrowRight className="w-4 h-4" />
                    </button>

                    <button
                      type="button"
                      onClick={copyMagicLink}
                      className="w-full bg-white hover:bg-slate-50 text-slate-700 border border-slate-300 font-semibold py-2 px-3 rounded-xl text-xs flex items-center justify-center gap-1.5 transition-colors cursor-pointer"
                    >
                      {copied ? (
                        <>
                          <Check className="w-3.5 h-3.5 text-emerald-600" />
                          <span className="text-emerald-700">Enlace Copiado al Portapapeles</span>
                        </>
                      ) : (
                        <>
                          <Copy className="w-3.5 h-3.5 text-slate-500" />
                          <span>Copiar Enlace Mágico</span>
                        </>
                      )}
                    </button>

                    <button
                      type="button"
                      onClick={() => setRequestResult(null)}
                      className="text-[11px] text-slate-500 hover:text-slate-700 text-center py-1 cursor-pointer"
                    >
                      Probar con otro correo
                    </button>
                  </div>
                </div>
              )}

              {/* Direct Token Paste Accordion */}
              <div className="pt-2 border-t border-slate-200/80">
                <button
                  type="button"
                  onClick={() => setShowDirectToken(!showDirectToken)}
                  className="w-full text-left text-[11px] text-slate-500 hover:text-emerald-700 flex items-center justify-between font-medium cursor-pointer"
                >
                  <span>¿Ya tienes un token o enlace directo?</span>
                  <span className="text-emerald-600 font-bold">{showDirectToken ? '▲' : '▼'}</span>
                </button>

                {showDirectToken && (
                  <form onSubmit={handleDirectTokenSubmit} className="mt-2.5 space-y-2">
                    <input
                      type="text"
                      value={directTokenInput}
                      onChange={(e) => setDirectTokenInput(e.target.value)}
                      placeholder="Pega tu token o URL /auth/verify?token=..."
                      className="w-full text-xs font-mono border border-slate-300 rounded-xl p-2.5 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 text-slate-800"
                    />
                    <button
                      type="submit"
                      className="w-full bg-slate-800 hover:bg-slate-900 text-white font-semibold py-2 px-3 rounded-xl text-xs flex items-center justify-center gap-1.5 cursor-pointer"
                    >
                      <span>Validar y Entrar</span>
                      <ArrowRight className="w-3.5 h-3.5" />
                    </button>
                  </form>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="bg-slate-50 px-6 py-4 border-t border-slate-100 text-center text-[11px] text-slate-500">
          APU-suite &bull; Acceso Seguro con Row Level Security (RLS) & Bitácora de Auditoría
        </div>
      </div>
    </div>
  );
}
