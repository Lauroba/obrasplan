"use client";

import { useAuthStore } from "@/hooks/useAuth";
import { useLayoutStore } from "@/hooks/useLayout";
import Sidebar from "@/components/layout/Sidebar";
import Topbar from "@/components/layout/Topbar";
import { Loader2, Menu, LogOut } from "lucide-react";
import Image from "next/image";
import { createClient } from "@/lib/supabase/client";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, isLoading } = useAuthStore();
  const { sidebarCollapsed, setMobileMenu } = useLayoutStore();

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-surface-50">
        <div className="text-center">
          <Loader2 className="w-8 h-8 text-brand-500 animate-spin mx-auto" />
          <p className="text-sm text-surface-400 mt-3">Cargando ObrasPlan...</p>
        </div>
      </div>
    );
  }

  if (!user) return null;

  return (
    <div className="min-h-screen bg-surface-50">
      <Sidebar />

      {/* Mobile header */}
      <div className="lg:hidden fixed top-0 left-0 right-0 z-30 bg-white border-b border-surface-200 h-14 flex items-center justify-between px-4">
        <div className="flex items-center gap-3">
          <button onClick={() => setMobileMenu(true)} className="p-2 rounded-lg text-surface-600 hover:bg-surface-100">
            <Menu className="w-5 h-5" />
          </button>
          <div className="w-7 h-7 relative shrink-0">
            <Image src="/logo.png" alt="Loynek" fill className="object-contain" />
          </div>
          <span className="font-display font-bold text-surface-900 text-sm">ObrasPlan</span>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-xs text-surface-500 hidden sm:block">{user?.nombre?.split(" ")[0]}</span>
          <button onClick={async () => { const s = createClient(); await s.auth.signOut(); }}
            className="p-2 rounded-lg text-surface-400 hover:bg-surface-100 hover:text-red-500">
            <LogOut className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Main content */}
      <div className={`transition-all duration-300 ${sidebarCollapsed ? "lg:pl-[72px]" : "lg:pl-[260px]"}`}>
        <div className="hidden lg:block"><Topbar /></div>
        <main className="p-4 lg:p-6 pt-[72px] lg:pt-6">{children}</main>
      </div>
    </div>
  );
}
