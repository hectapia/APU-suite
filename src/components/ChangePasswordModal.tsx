'use client';

import React, { useState, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { useAuth } from '@/lib/auth-context';
import {
  X,
  Key,
  Lock,
  Eye,
  EyeOff,
  CheckCircle2,
  AlertCircle,
  Loader2,
  ShieldCheck,
} from 'lucide-react';

interface ChangePasswordModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function ChangePasswordModal({ isOpen, onClose }: ChangePasswordModalProps) {
  const { user } = useAuth();
  const [mounted, setMounted] = useState(false);

  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!isOpen || !mounted) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const savedPassword = localStorage.getItem('apu_admin_password') || 'admin123';

    // Verify current password
    if (currentPassword !== savedPassword) {
      setError('La contraseña actual no es correcta.');
      return;
    }

    if (newPassword.length < 6) {
      setError('La nueva contraseña debe contener al menos 6 caracteres.');
      return;
    }

    if (newPassword !== confirmPassword) {
      setError('La confirmación de la contraseña no coincide.');
      return;
    }

    try {
      setLoading(true);

      const res = await fetch('/api/auth/change-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: user?.email || 'hectapia@outlook.com',
          currentPassword,
          newPassword,
          userId: user?.id_user || 'admin-001',
        }),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Error al actualizar la contraseña.');
      }

      // Save locally for browser persistence
      localStorage.setItem('apu_admin_password', newPassword);

      setSuccess(true);
      setTimeout(() => {
        setSuccess(false);
        setCurrentPassword('');
        setNewPassword('');
        setConfirmPassword('');
        onClose();
      }, 2000);
    } catch (err: any) {
      setError(err?.message || 'Error de conexión.');
    } finally {
      setLoading(false);
    }
  };

  const modalContent = (
    <div
      className="fixed inset-0 bg-slate-950/80 backdrop-blur-xs flex items-center justify-center p-4"
      style={{ zIndex: 99999 }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-md overflow-hidden animate-in fade-in zoom-in-95 duration-200"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="bg-slate-900 text-white p-5 flex items-center justify-between border-b border-slate-800">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-purple-500/20 text-purple-400 border border-purple-500/30 flex items-center justify-center">
              <Key className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-base leading-tight">Cambiar Contraseña</h3>
              <p className="text-xs text-slate-400">
                Administrador: {user?.email || 'hectapia@outlook.com'}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="text-slate-400 hover:text-white p-1 rounded-lg hover:bg-slate-800 transition-colors cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Body */}
        <div className="p-6">
          {error && (
            <div className="mb-4 bg-red-50 border border-red-200 rounded-xl p-3 flex items-start gap-2 text-xs text-red-700 animate-in fade-in">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          {success ? (
            <div className="py-6 text-center space-y-3 animate-in fade-in">
              <div className="w-12 h-12 bg-emerald-100 text-emerald-600 rounded-full flex items-center justify-center mx-auto">
                <CheckCircle2 className="w-7 h-7" />
              </div>
              <p className="text-sm font-bold text-slate-900">
                ¡Contraseña Actualizada con Éxito!
              </p>
              <p className="text-xs text-slate-500">
                Tu nueva contraseña ya se encuentra activa para tus próximos inicios de sesión.
              </p>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              {/* Contraseña Actual */}
              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <Lock className="w-3.5 h-3.5 text-purple-600" />
                  Contraseña Actual
                </label>
                <div className="relative">
                  <input
                    type={showCurrent ? 'text' : 'password'}
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    placeholder="Contraseña actual"
                    className="w-full text-xs border border-slate-300 rounded-xl p-2.5 pr-9 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                    required
                  />
                  <button
                    type="button"
                    onClick={() => setShowCurrent(!showCurrent)}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1 cursor-pointer"
                  >
                    {showCurrent ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                  </button>
                </div>
              </div>

              {/* Nueva Contraseña */}
              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <Key className="w-3.5 h-3.5 text-purple-600" />
                  Nueva Contraseña
                </label>
                <div className="relative">
                  <input
                    type={showNew ? 'text' : 'password'}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="Mínimo 6 caracteres"
                    className="w-full text-xs border border-slate-300 rounded-xl p-2.5 pr-9 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                    required
                    minLength={6}
                  />
                  <button
                    type="button"
                    onClick={() => setShowNew(!showNew)}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1 cursor-pointer"
                  >
                    {showNew ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                  </button>
                </div>
              </div>

              {/* Confirmar Contraseña */}
              <div>
                <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <ShieldCheck className="w-3.5 h-3.5 text-purple-600" />
                  Confirmar Nueva Contraseña
                </label>
                <div className="relative">
                  <input
                    type={showConfirm ? 'text' : 'password'}
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="Vuelve a escribir la nueva contraseña"
                    className="w-full text-xs border border-slate-300 rounded-xl p-2.5 pr-9 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500 text-slate-800"
                    required
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirm(!showConfirm)}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1 cursor-pointer"
                  >
                    {showConfirm ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                  </button>
                </div>
              </div>

              <div className="pt-2 flex justify-end gap-2 border-t border-slate-100">
                <button
                  type="button"
                  onClick={onClose}
                  className="text-xs font-semibold px-4 py-2 text-slate-600 hover:text-slate-900 border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors cursor-pointer"
                >
                  Cancelar
                </button>
                <button
                  type="submit"
                  disabled={loading}
                  className="bg-purple-600 hover:bg-purple-700 text-white text-xs font-semibold px-5 py-2 rounded-lg flex items-center gap-2 transition-colors shadow-sm disabled:opacity-50 cursor-pointer"
                >
                  {loading ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>Actualizando...</span>
                    </>
                  ) : (
                    <span>Guardar Nueva Contraseña</span>
                  )}
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );

  return createPortal(modalContent, document.body);
}
