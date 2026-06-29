/**
 * FotoArticulo — Miniatura de artículo con popup al hacer hover.
 * Se usa en listados de artículos, movimientos e histórico.
 *
 * Props:
 *   url       URL pública de la foto (null = icono Package)
 *   nombre    Nombre del artículo (alt + tooltip)
 *   size      Tamaño de la miniatura: "sm" (7×7) | "md" (8×8, default)
 *
 * El popup aparece sobre la miniatura en desktop (pointer:fine).
 * En móvil/táctil el popup no interfiere porque depende de :hover.
 */
"use client";
import { Package } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface FotoArticuloProps {
  url?: string | null;
  nombre?: string;
  size?: "sm" | "md";
}

export function FotoArticulo({ url, nombre = "", size = "md" }: FotoArticuloProps) {
  const dim = size === "sm" ? "w-7 h-7" : "w-8 h-8";

  return (
    <div className="relative group inline-flex">
      {/* Miniatura */}
      {url ? (
        <img
          src={url}
          alt={nombre}
          title={nombre}
          className={cn(dim, "rounded object-cover shrink-0 border border-surface-200 cursor-zoom-in")}
        />
      ) : (
        <div className={cn(dim, "rounded bg-surface-100 flex items-center justify-center shrink-0 border border-surface-100")}>
          <Package className={size === "sm" ? "w-3.5 h-3.5" : "w-4 h-4"} style={{ color: "#9CA3AF" }} />
        </div>
      )}

      {/* Popup hover — solo si hay foto */}
      {url && (
        <div className={cn(
          // Posición: encima de la miniatura, centrado horizontalmente
          "absolute bottom-full left-1/2 -translate-x-1/2 mb-2 z-50",
          // Tamaño y forma
          "w-40 h-40 rounded-xl overflow-hidden shadow-xl border-2 border-white ring-1 ring-surface-200",
          // Animación y visibilidad — solo visible en dispositivos con puntero fino (desktop)
          "opacity-0 scale-90 pointer-events-none",
          "@media(hover:hover){group-hover:opacity-100 group-hover:scale-100}",
          "transition-all duration-150 ease-out",
          // Clase Tailwind estándar para hover en grupo
          "group-hover:opacity-100 group-hover:scale-100",
        )}>
          <img src={url} alt={nombre} className="w-full h-full object-contain bg-white" />
        </div>
      )}
    </div>
  );
}