/**
 * FotoArticulo — Miniatura con popup hover.
 * size="sm"  -> miniatura 40x40px  (movimientos, tablas densas)
 * size="md"  -> miniatura 48x48px  (listado de artículos, default)
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
  // Miniaturas visiblemente más grandes que antes
  const wh   = size === "sm" ? "w-10 h-10" : "w-12 h-12";
  const icon = size === "sm" ? "w-5 h-5"   : "w-6 h-6";

  return (
    // El contenedor tiene el tamaño real de la miniatura
    // overflow-visible es clave para que el popup salga fuera del td
    <div className={cn("relative inline-flex shrink-0 group/foto overflow-visible", wh)}>

      {/* ── Miniatura ── */}
      {url ? (
        <img
          src={url}
          alt={nombre}
          title={nombre}
          className={cn(
            wh,
            "rounded-lg object-cover border border-surface-200",
            "cursor-zoom-in select-none",
          )}
          onError={(e) => {
            const img = e.target as HTMLImageElement;
            img.style.display = "none";
            const parent = img.parentElement;
            if (parent) {
              const ph = document.createElement("div");
              ph.className = img.className.replace("cursor-zoom-in", "").trim()
                + " bg-surface-100 flex items-center justify-center border-surface-100";
              parent.appendChild(ph);
            }
          }}
        />
      ) : (
        <div className={cn(wh, "rounded-lg bg-surface-100 flex items-center justify-center border border-surface-100")}>
          <Package className={cn(icon, "text-surface-300")} />
        </div>
      )}

      {/* ── Popup hover (solo si hay foto) ── */}
      {url && (
        <div
          className={cn(
            // Posición: sobre la miniatura, centrado horizontalmente
            "absolute z-[9999]",
            "bottom-full left-1/2 -translate-x-1/2 mb-2",
            // Tamaño del popup: bien visible
            "w-56 h-56",
            // Estilo
            "rounded-2xl overflow-hidden bg-white",
            "shadow-2xl border border-surface-200",
            // Animación con invisible/visible (no desplaza el layout)
            "invisible opacity-0 scale-90 pointer-events-none",
            "group-hover/foto:visible group-hover/foto:opacity-100 group-hover/foto:scale-100",
            "transition-all duration-150 ease-out",
          )}
          style={{ transformOrigin: "bottom center" }}
        >
          <img
            src={url}
            alt={nombre}
            className="w-full h-full object-contain p-2"
          />
          {nombre && (
            <div className="absolute bottom-0 left-0 right-0 bg-black/60 text-white text-[11px] font-medium px-3 py-1.5 truncate">
              {nombre}
            </div>
          )}
        </div>
      )}
    </div>
  );
}