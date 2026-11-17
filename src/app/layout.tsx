import type { Metadata } from 'next';
import './globals.css';
import { AuthProvider } from '@/lib/auth-context';
import { HeaderNav } from '@/components/HeaderNav';

export const metadata: Metadata = {
  title: 'APU-suite | Cost Engineering & Unitary Price Platform',
  description: 'Professional Unitary Price Integration platform adhering to Mexican procurement standards (PEMEX DT-7 / LOPSRM).',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es" suppressHydrationWarning>
      <body className="min-h-screen flex flex-col bg-slate-50 text-slate-900" suppressHydrationWarning>
        <AuthProvider>
          <header className="bg-slate-900 text-white border-b border-slate-800 sticky top-0 z-30 shadow-md">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
              <div className="flex items-center space-x-3">
                <div className="bg-emerald-500 text-slate-950 font-black text-xl px-2.5 py-1 rounded shadow">
                  APU
                </div>
                <div>
                  <h1 className="text-lg font-bold tracking-tight text-white flex items-center gap-2">
                    APU-suite
                  </h1>
                  <p className="text-xs text-slate-400">Análisis de Precios Unitarios</p>
                </div>
              </div>

              {/* Dynamic Header: Company logo/name after event opens or user name/badge on login */}
              <HeaderNav />
            </div>
          </header>

          <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8">
            {children}
          </main>

          <footer className="bg-white border-t border-slate-200 py-4 mt-auto text-center text-xs text-slate-500">
            APU-suite &copy; {new Date().getFullYear()} &mdash; Plataforma Profesional de Ingeniería de Costos para Concursos de Obra y Servicios
          </footer>
        </AuthProvider>
      </body>
    </html>
  );
}
