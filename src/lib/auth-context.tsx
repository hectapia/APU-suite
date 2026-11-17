'use client';

import React, { createContext, useContext, useState, useEffect } from 'react';
import { UserRole } from '@/types/database';

export interface AuthUser {
  id_user: string;
  email: string;
  full_name: string;
  role: UserRole;
  id_provider?: number | null;
  provider_name?: string | null;
}

export interface ActiveEventHeaderInfo {
  id_event: number;
  tag_event: string;
  event_type: string;
  client_name: string;
  provider_name?: string;
}

interface AuthContextType {
  user: AuthUser | null;
  activeEvent: ActiveEventHeaderInfo | null;
  setActiveEvent: (event: ActiveEventHeaderInfo | null) => void;
  login: (userData: AuthUser) => void;
  logout: () => void;
  switchRole: (role: UserRole) => void;
  isInviteModalOpen: boolean;
  inviteModalEventId?: number;
  openInviteModal: (eventId?: number) => void;
  closeInviteModal: () => void;
}

const DEFAULT_ADMIN_USER: AuthUser = {
  id_user: 'admin-001',
  email: 'admin.licitaciones@pemex.com',
  full_name: 'Ing. Administrador de Concursos',
  role: 'ADMIN',
  id_provider: null,
  provider_name: 'PEMEX Exploración y Producción',
};

const AuthContext = createContext<AuthContextType>({
  user: null,
  activeEvent: null,
  setActiveEvent: () => {},
  login: () => {},
  logout: () => {},
  switchRole: () => {},
  isInviteModalOpen: false,
  inviteModalEventId: undefined,
  openInviteModal: () => {},
  closeInviteModal: () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [activeEvent, setActiveEvent] = useState<ActiveEventHeaderInfo | null>(null);
  const [isInviteModalOpen, setIsInviteModalOpen] = useState(false);
  const [inviteModalEventId, setInviteModalEventId] = useState<number | undefined>(undefined);

  const openInviteModal = (eventId?: number) => {
    setInviteModalEventId(eventId);
    setIsInviteModalOpen(true);
  };

  const closeInviteModal = () => {
    setIsInviteModalOpen(false);
    setInviteModalEventId(undefined);
  };

  useEffect(() => {
    // Load persisted session from localStorage if present, else default to Admin
    const stored = localStorage.getItem('apu_session_user');
    if (stored) {
      try {
        setUser(JSON.parse(stored));
      } catch {
        setUser(DEFAULT_ADMIN_USER);
      }
    } else {
      setUser(DEFAULT_ADMIN_USER);
    }
  }, []);

  const login = (userData: AuthUser) => {
    setUser(userData);
    localStorage.setItem('apu_session_user', JSON.stringify(userData));
  };

  const logout = () => {
    localStorage.removeItem('apu_session_user');
    setUser(null);
  };

  const switchRole = (newRole: UserRole) => {
    if (newRole === 'ADMIN') {
      login(DEFAULT_ADMIN_USER);
    } else {
      const providerUser: AuthUser = {
        id_user: 'prov-001',
        email: 'licitaciones@mhebosap.com.mx',
        full_name: 'Ing. Fernando Tapia (Estimador)',
        role: 'PROVIDER_ESTIMATOR',
        id_provider: 1,
        provider_name: 'MHEBOSAP, S.A. DE C.V.',
      };
      login(providerUser);
    }
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        activeEvent,
        setActiveEvent,
        login,
        logout,
        switchRole,
        isInviteModalOpen,
        inviteModalEventId,
        openInviteModal,
        closeInviteModal,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
