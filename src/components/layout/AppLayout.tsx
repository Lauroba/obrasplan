"use client";

import { useAuthStore } from "@/hooks/useAuth";
import { useRouteGuard } from "@/hooks/useRouteGuard";
import { useLayoutStore } from "@/hooks/useLayout";
import Sidebar from "./Sidebar";
import Topbar from "./Topbar";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { cn } from "@/lib/utils/cn";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuthStore();
  const { sidebarCollapsed } = useLayoutStore();
  const router = useRouter();

  // Route guard - redirects if no permission
  useRouteGuard();

  useEffect(() => {
    if (!loading && !user) router.push("/login");
  }, [loading, user, router]);

  if (loading) return <div className="flex items-center justify-center h-screen"><div className="w-8 h-8 border-4 border-brand-500 border-t-transparent rounded-full animate-spin" /></div>;
  if (!user) return null;

  return (
    <div className="min-h-screen bg-surface-50">
      <Sidebar />
      <div className={cn("transition-all duration-300", sidebarCollapsed ? "lg:ml-[72px]" : "lg:ml-[260px]")}>
        <Topbar />
        <main className="p-4 lg:p-6">{children}</main>
      </div>
    </div>
  );
}
