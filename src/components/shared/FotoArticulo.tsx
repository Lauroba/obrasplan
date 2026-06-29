/**
 * FotoArticulo — Miniatura con popup hover que muestra la imagen en tamaño medio.
 * Usado en listados de artículos, movimientos e históricos.
 */
"use client";
import { Package } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface Props {
  url?: string | null;
  nombre?: string;
  size?: "sm" | "md";
}

export function FotoArticulo({ url, nombre = "", size = "md" }: Props) {
  const dim = size === "sm" ? "w-7 h-7" : "w-8 h-8";

  return (
    <div className={cn("relative inline-flex shrink-0 group/foto", dim)}>
      {/* Miniatura */}
      {url ? (
        <img
          src={url}
          alt={nombre}
          title={nombre}
          className={cn(dim, "rounded object-cover border border-surface-200 cursor-zoom-in")}
          onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
        />
      ) : (
        <div className={cn(dim, "rounded bg-surface-100 flex items-center justify-center border border-surface-100")}>
          <Package className="w-3.5 h-3.5 text-surface-300" />
        </div>
      )}

      {/* Popup hover: solo si hay foto */}
      {url && (
        <div
          className={cn(
            // Posición: encima y centrado
            "absolute z-[9999] bottom-full left-1/2 -translate-x-1/2 mb-2",
            // Tamaño fijo del popup
            "w-44 h-44 rounded-xl overflow-hidden",
            // Estilo visual
            "bg-white shadow-2xl border border-surface-200 ring-1 ring-black/5",
            // Visibilidad controlada con invisible/visible para no ocupar espacio en DOM
            "invisible opacity-0 scale-90 pointer-events-none",
            "group-hover/foto:visible group-hover/foto:opacity-100 group-hover/foto:scale-100",
            "transition-all duration-150 ease-out",
          )}
          style={{ transformOrigin: "bottom center" }}
        >
          <img
            src={url}
            alt={nombre}
            className="w-full h-full object-contain bg-white p-1"
          />
          {nombre && (
            <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-[10px] px-2 py-1 truncate">
              {nombre}
            </div>
          )}
        </div>
      )}
    </div>
  );
}