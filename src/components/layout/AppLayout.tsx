"use client";

import { useAuthStore } from "@/hooks/useAuth";
import { useLayoutStore } from "@/hooks/useLayout";
import Sidebar from "@/components/layout/Sidebar";
import Topbar from "@/components/layout/Topbar";
import { Loader2 } from "lucide-react";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, isLoading } = useAuthStore();
  const { sidebarCollapsed } = useLayoutStore();

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
      <div className={`transition-all duration-300 ${sidebarCollapsed ? "pl-[72px]" : "pl-[260px]"}`}>
        <Topbar />
        <main className="p-6">{children}</main>
      </div>
    </div>
  );
}
