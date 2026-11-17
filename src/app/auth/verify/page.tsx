'use client';

import React, { useEffect, useState, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { CheckCircle2, XCircle, Loader2, ArrowRight, ShieldCheck, Building, Key } from 'lucide-react';
import Link from 'next/link';

function VerifyTokenContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const token = searchParams.get('token');
  const { login, setActiveEvent } = useAuth();

  const [status, setStatus] = useState<'verifying' | 'success' | 'error'>('verifying');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [sessionData, setSessionData] = useState<any>(null);

  // Quick link request state
  const [renewEmail, setRenewEmail] = useState('');
  const [renewLoading, setRenewLoading] = useState(false);
  const [renewError, setRenewError] = useState<string | null>(null);

  const handleRenew = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!renewEmail.trim()) {
      setRenewError('Ingresa un correo electrónico.');
      return;
    }
    try {
      setRenewLoading(true);
      setRenewError(null);
      const res = await fetch('/api/auth/request-link', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: renewEmail.trim() }),
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'No se encontró invitación para este correo.');
      }
      if (data.token) {
        router.push(`/auth/verify?token=${encodeURIComponent(data.token)}`);
      }
    } catch (err: any) {
      setRenewError(err.message || 'Error solicitando enlace.');
    } finally {
      setRenewLoading(false);
    }
  };

  useEffect(() => {
    if (!token) {
      setStatus('error');
      setErrorMessage('No se encontró ningún token de autenticación en el enlace.');
      return;
    }

    let isMounted = true;

    async function verify() {
      try {
        const res = await fetch(`/api/auth/verify?token=${encodeURIComponent(token!)}`);
        const data = await res.json();

        if (!res.ok || !data.success) {
          throw new Error(data.error || 'El enlace de acceso es inválido o ha caducado.');
        }

        if (isMounted) {
          setSessionData(data);
          setStatus('success');
          login(data.user);

          if (data.event) {
            setActiveEvent({
              id_event: data.event.id_event,
              tag_event: data.event.tag_event,
              event_type: data.event.event_type,
              client_name: data.event.client?.client_name || 'Convocante',
              provider_name: data.user.provider_name,
            });
          }

          // Auto redirect after 2.5 seconds
          setTimeout(() => {
            router.push('/');
          }, 2500);
        }
      } catch (err: any) {
        if (isMounted) {
          setStatus('error');
          setErrorMessage(err.message || 'Error al validar el enlace.');
        }
      }
    }

    verify();

    return () => {
      isMounted = false;
    };
  }, [token, login, setActiveEvent, router]);

  return (
    <div className="min-h-[70vh] flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-white rounded-2xl shadow-xl border border-slate-200 p-8 text-center space-y-6">
        {/* Header Icon */}
        <div className="flex justify-center">
          <div className="w-16 h-16 rounded-2xl bg-slate-900 text-emerald-400 flex items-center justify-center shadow-lg border border-slate-800">
            <Key className="w-8 h-8" />
          </div>
        </div>

        <div>
          <h2 className="text-2xl font-black text-slate-900 tracking-tight">
            Acceso Seguro APU-suite
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Validación de Enlace Mágico y Permisos RLS
          </p>
        </div>

        {/* State: Verifying */}
        {status === 'verifying' && (
          <div className="py-6 space-y-4">
            <Loader2 className="w-10 h-10 text-emerald-600 animate-spin mx-auto" />
            <p className="text-sm font-semibold text-slate-700">
              Validando firma digital y verificando acceso al concurso...
            </p>
            <p className="text-xs text-slate-400">
              Registrando evento en bitácora de auditoría segura.
            </p>
          </div>
        )}

        {/* State: Success */}
        {status === 'success' && sessionData && (
          <div className="py-4 space-y-4 animate-in fade-in duration-300">
            <div className="w-12 h-12 bg-emerald-100 text-emerald-600 rounded-full flex items-center justify-center mx-auto">
              <CheckCircle2 className="w-7 h-7" />
            </div>

            <div className="bg-emerald-50/80 border border-emerald-200/80 rounded-xl p-4 text-left space-y-2">
              <div className="flex items-center gap-2 text-xs font-semibold text-emerald-900">
                <ShieldCheck className="w-4 h-4 text-emerald-600" />
                <span>Autenticación Exitosa</span>
              </div>
              <p className="text-xs text-slate-700">
                <strong>Usuario:</strong> {sessionData.user?.full_name}
              </p>
              <p className="text-xs text-slate-700 flex items-center gap-1.5">
                <Building className="w-3.5 h-3.5 text-slate-400" />
                <span><strong>Empresa:</strong> {sessionData.user?.provider_name}</span>
              </p>
              {sessionData.event && (
                <div className="pt-2 border-t border-emerald-200/60 text-xs text-slate-600">
                  <span className="font-semibold text-slate-800">Concurso Asignado:</span> {sessionData.event.tag_event} &mdash; {sessionData.event.event_type}
                </div>
              )}
            </div>

            <p className="text-xs text-slate-500">
              Redirigiendo a tu espacio de trabajo en unos segundos...
            </p>

            <Link
              href="/"
              className="inline-flex items-center justify-center gap-2 w-full bg-emerald-600 hover:bg-emerald-700 text-white font-semibold py-2.5 px-4 rounded-xl text-sm transition-colors shadow-sm"
            >
              <span>Acceder Inmediatamente</span>
              <ArrowRight className="w-4 h-4" />
            </Link>
          </div>
        )}

        {/* State: Error */}
        {status === 'error' && (
          <div className="py-4 space-y-4 animate-in fade-in duration-300">
            <div className="w-12 h-12 bg-red-100 text-red-600 rounded-full flex items-center justify-center mx-auto">
              <XCircle className="w-7 h-7" />
            </div>

            <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-xs text-red-700 text-left">
              <p className="font-bold mb-1">Acceso Denegado</p>
              <p>{errorMessage}</p>
            </div>

            <div className="pt-3 border-t border-slate-200 text-left space-y-2">
              <label className="block text-[11px] font-bold text-slate-700">
                ¿Deseas reactivar o validar tu enlace con tu correo?
              </label>
              <form onSubmit={handleRenew} className="space-y-2">
                <input
                  type="email"
                  value={renewEmail}
                  onChange={(e) => setRenewEmail(e.target.value)}
                  placeholder="licitaciones@mhebosap.com.mx"
                  className="w-full text-xs border border-slate-300 rounded-lg p-2.5 font-mono bg-slate-50 focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500"
                />
                <button
                  type="submit"
                  disabled={renewLoading}
                  className="w-full bg-emerald-600 hover:bg-emerald-700 text-white font-semibold py-2 px-3 rounded-lg text-xs flex items-center justify-center gap-1.5 transition-colors cursor-pointer disabled:opacity-50"
                >
                  {renewLoading ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>Validando invitación...</span>
                    </>
                  ) : (
                    <span>Reactivar y Entrar con mi Correo</span>
                  )}
                </button>
                {renewError && (
                  <p className="text-[11px] text-red-600 bg-red-50 p-2 rounded border border-red-200">
                    {renewError}
                  </p>
                )}
              </form>
            </div>

            <Link
              href="/"
              className="inline-flex items-center justify-center gap-2 w-full bg-slate-900 hover:bg-slate-800 text-white font-semibold py-2.5 px-4 rounded-xl text-sm transition-colors"
            >
              <span>Ir al Inicio</span>
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}

export default function VerifyTokenPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-[70vh] flex items-center justify-center">
          <Loader2 className="w-8 h-8 text-emerald-600 animate-spin" />
        </div>
      }
    >
      <VerifyTokenContent />
    </Suspense>
  );
}
