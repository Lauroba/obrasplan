"use client";

import { usePathname } from "next/navigation";
import Link from "next/link";
import Image from "next/image";
import {
  LayoutDashboard,
  CalendarRange,
  Building2,
  ClipboardList,
  Users,
  Truck,
  Wrench,
  Package,
  Contact,
  Settings,
  ScrollText,
  ShieldCheck,
  ChevronLeft,
  ChevronRight,
  Tag,
  Hammer,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { useAuthStore } from "@/hooks/useAuth";
import { useLayoutStore } from "@/hooks/useLayout";

const navigation = [
  { name: "Dashboard", href: "/dashboard", icon: LayoutDashboard },
  { name: "Planificación", href: "/planificacion", icon: CalendarRange },
  { name: "Obras", href: "/obras", icon: Building2 },
  { name: "Partes Diarios", href: "/partes", icon: ClipboardList },
];

const maestros = [
  { name: "Recursos Humanos", href: "/maestros/recursos-humanos", icon: Users },
  { name: "Maquinaria", href: "/maestros/maquinaria", icon: Wrench },
  { name: "Vehículos", href: "/maestros/vehiculos", icon: Truck },
  { name: "Materiales", href: "/maestros/materiales", icon: Package },
  { name: "Clientes", href: "/maestros/clientes", icon: Contact },
  { name: "Estados de Obra", href: "/maestros/estados-obra", icon: Tag },
  { name: "Tipos de Trabajo", href: "/maestros/tipos-trabajo", icon: Hammer },
];

const admin = [
  { name: "Usuarios", href: "/usuarios", icon: ShieldCheck },
  { name: "Logs", href: "/logs", icon: ScrollText },
  { name: "Configuración", href: "/configuracion", icon: Settings },
];

export default function Sidebar() {
  const pathname = usePathname();
  const { user } = useAuthStore();
  const { sidebarCollapsed: collapsed, toggleSidebar } = useLayoutStore();

  const isActive = (href: string) => {
    if (href === "/dashboard") return pathname === "/dashboard";
    return pathname.startsWith(href);
  };

  const NavItem = ({ item }: { item: (typeof navigation)[0] }) => (
    <Link
      href={item.href}
      className={cn("nav-link group", isActive(item.href) && "active")}
      title={collapsed ? item.name : undefined}
    >
      <item.icon
        className={cn(
          "w-5 h-5 shrink-0 transition-colors",
          isActive(item.href) ? "text-brand-600" : "text-surface-400 group-hover:text-surface-600"
        )}
      />
      {!collapsed && <span className="truncate">{item.name}</span>}
    </Link>
  );

  return (
    <aside
      className={cn(
        "fixed left-0 top-0 z-40 h-screen bg-white border-r border-surface-200 flex flex-col transition-all duration-300",
        collapsed ? "w-[72px]" : "w-[260px]"
      )}
    >
      {/* Logo */}
      <div className="flex items-center gap-3 px-4 h-16 border-b border-surface-200 shrink-0">
        <div className="w-9 h-9 relative shrink-0">
          <Image src="/logo.png" alt="Loynek" fill className="object-contain" />
        </div>
        {!collapsed && (
          <div className="flex flex-col min-w-0">
            <span className="font-display font-bold text-surface-900 text-sm leading-tight">
              ObrasPlan
            </span>
            <span className="text-[10px] text-surface-400 font-medium tracking-wider uppercase">
              Loynek
            </span>
          </div>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-6">
        {/* Principal */}
        <div className="space-y-1">
          {!collapsed && (
            <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">
              Principal
            </p>
          )}
          {navigation.map((item) => (
            <NavItem key={item.href} item={item} />
          ))}
        </div>

        {/* Maestros */}
        <div className="space-y-1">
          {!collapsed && (
            <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">
              Maestros
            </p>
          )}
          {maestros.map((item) => (
            <NavItem key={item.href} item={item} />
          ))}
        </div>

        {/* Admin (solo visible para admin) */}
        {(!user || user.role === "admin") && (
          <div className="space-y-1">
            {!collapsed && (
              <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">
                Administración
              </p>
            )}
            {admin.map((item) => (
              <NavItem key={item.href} item={item} />
            ))}
          </div>
        )}
      </nav>

      {/* Collapse button */}
      <div className="px-3 py-3 border-t border-surface-200 shrink-0">
        <button
          onClick={() => toggleSidebar()}
          className="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-sm text-surface-400 hover:bg-surface-100 hover:text-surface-600 transition-colors"
        >
          {collapsed ? (
            <ChevronRight className="w-4 h-4" />
          ) : (
            <>
              <ChevronLeft className="w-4 h-4" />
              <span>Colapsar</span>
            </>
          )}
        </button>
      </div>
    </aside>
  );
}
