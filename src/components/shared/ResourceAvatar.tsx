"use client";

import { Users, Wrench, Truck, Package } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import type { RecursoTipo } from "@/lib/types/database";

const TIPO_ICON: Record<RecursoTipo, typeof Users> = { humano: Users, maquinaria: Wrench, vehiculo: Truck, material: Package };
const TIPO_BG: Record<RecursoTipo, string> = {
  humano: "bg-violet-100 text-violet-700",
  maquinaria: "bg-amber-100 text-amber-700",
  vehiculo: "bg-teal-100 text-teal-700",
  material: "bg-blue-100 text-blue-700",
};

interface ResourceAvatarProps {
  nombre: string;
  foto_url?: string | null;
  tipo?: RecursoTipo;
  size?: "xs" | "sm" | "md";
  showName?: boolean;
  className?: string;
}

const SIZES = { xs: "w-5 h-5", sm: "w-6 h-6", md: "w-8 h-8" };
const TEXT_SIZES = { xs: "text-[7px]", sm: "text-[8px]", md: "text-[10px]" };
const ICON_SIZES = { xs: "w-2.5 h-2.5", sm: "w-3 h-3", md: "w-4 h-4" };
const NAME_SIZES = { xs: "text-[10px]", sm: "text-[11px]", md: "text-xs" };

export default function ResourceAvatar({ nombre, foto_url, tipo = "humano", size = "sm", showName = true, className }: ResourceAvatarProps) {
  const Icon = TIPO_ICON[tipo];
  const initials = nombre.split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase();

  return (
    <div className={cn("flex items-center gap-1.5", className)}>
      {foto_url ? (
        <img src={foto_url} alt={nombre} className={cn("rounded-full object-cover shrink-0", SIZES[size])} />
      ) : (
        <div className={cn("rounded-full flex items-center justify-center shrink-0 font-bold", SIZES[size], TIPO_BG[tipo], TEXT_SIZES[size])}>
          {tipo === "humano" ? initials : <Icon className={ICON_SIZES[size]} />}
        </div>
      )}
      {showName && <span className={cn("text-surface-700 truncate", NAME_SIZES[size])}>{nombre}</span>}
    </div>
  );
}
