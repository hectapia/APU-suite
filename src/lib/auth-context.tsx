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
  isLoadingAuth: boolean;
  setActiveEvent: (event: ActiveEventHeaderInfo | null) => void;
  login: (userData: AuthUser) => void;
  logout: () => void;
  loginAsAdmin: (email?: string, name?: string) => void;
  loginAsProvider: (email?: string, providerName?: string) => void;
  switchRole: (role: UserRole) => void;
  isInviteModalOpen: boolean;
  inviteModalEventId?: number;
  openInviteModal: (eventId?: number) => void;
  closeInviteModal: () => void;
}

export const DEFAULT_ADMIN_USER: AuthUser = {
  id_user: 'admin-001',
  email: 'hectapia@outlook.com',
  full_name: 'Ing. Héctor Tapia (Administrador)',
  role: 'ADMIN',
  id_provider: null,
  provider_name: 'PEMEX Exploración y Producción',
};

export const DEFAULT_PROVIDER_USER: AuthUser = {
  id_user: 'prov-001',
  email: 'licitaciones@mhebosap.com.mx',
  full_name: 'Ing. Fernando Tapia (Estimador)',
  role: 'PROVIDER_ESTIMATOR',
  id_provider: 1,
  provider_name: 'MHEBOSAP, S.A. DE C.V.',
};

const AuthContext = createContext<AuthContextType>({
  user: null,
  activeEvent: null,
  isLoadingAuth: true,
  setActiveEvent: () => {},
  login: () => {},
  logout: () => {},
  loginAsAdmin: () => {},
  loginAsProvider: () => {},
  switchRole: () => {},
  isInviteModalOpen: false,
  inviteModalEventId: undefined,
  openInviteModal: () => {},
  closeInviteModal: () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [activeEvent, setActiveEvent] = useState<ActiveEventHeaderInfo | null>(null);
  const [isLoadingAuth, setIsLoadingAuth] = useState(true);

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
    // Only restore existing session if user previously logged in
    try {
      const stored = localStorage.getItem('apu_session_user');
      if (stored) {
        const parsed = JSON.parse(stored);
        if (parsed && parsed.email) {
          setUser(parsed);
        }
      }
    } catch {
      setUser(null);
    } finally {
      setIsLoadingAuth(false);
    }
  }, []);

  const login = (userData: AuthUser) => {
    setUser(userData);
    localStorage.setItem('apu_session_user', JSON.stringify(userData));
  };

  const logout = () => {
    localStorage.removeItem('apu_session_user');
    setUser(null);
    setActiveEvent(null);
  };

  const loginAsAdmin = (customEmail?: string, customName?: string) => {
    const adminUser: AuthUser = {
      ...DEFAULT_ADMIN_USER,
      email: customEmail || DEFAULT_ADMIN_USER.email,
      full_name: customName || DEFAULT_ADMIN_USER.full_name,
    };
    login(adminUser);
  };

  const loginAsProvider = (customEmail?: string, providerName?: string) => {
    const provUser: AuthUser = {
      ...DEFAULT_PROVIDER_USER,
      email: customEmail || DEFAULT_PROVIDER_USER.email,
      provider_name: providerName || DEFAULT_PROVIDER_USER.provider_name,
    };
    login(provUser);
  };

  const switchRole = (newRole: UserRole) => {
    if (newRole === 'ADMIN') {
      loginAsAdmin();
    } else {
      loginAsProvider();
    }
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        activeEvent,
        isLoadingAuth,
        setActiveEvent,
        login,
        logout,
        loginAsAdmin,
        loginAsProvider,
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
