#Requires -Version 5.1
# fix-foto-articulo-portal.ps1
# Corrige el preview de fotos de articulos usando position:fixed + createPortal.
# El popup ya no queda cortado por overflow:hidden de tablas ni cards.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo FotoArticulo.tsx" -ForegroundColor Cyan

$dst = "src\components\shared\FotoArticulo.tsx"
$content = @'
"use client";
/**
 * FotoArticulo — Miniatura con preview flotante via position:fixed.
 * El preview se renderiza en un portal pegado a window, por encima de
 * cualquier overflow:hidden de tablas o cards. Sin dependencias externas.
 *
 * size="sm"  -> miniatura 40×40  (movimientos, tablas densas)
 * size="md"  -> miniatura 48×48  (listado artículos, default)
 */
import { useState, useRef, useCallback, useEffect } from "react";
import { createPortal } from "react-dom";
import { Package } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface Props {
  url?: string | null;
  nombre?: string;
  size?: "sm" | "md";
}

interface Pos { x: number; y: number }

export function FotoArticulo({ url, nombre = "", size = "md" }: Props) {
  const wh   = size === "sm" ? "w-10 h-10" : "w-12 h-12";
  const icon = size === "sm" ? "w-5 h-5"   : "w-6 h-6";

  const [visible, setVisible]   = useState(false);
  const [pos, setPos]           = useState<Pos>({ x: 0, y: 0 });
  const [mounted, setMounted]   = useState(false);
  const thumbRef                = useRef<HTMLDivElement>(null);
  const hideTimer               = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Solo montar el portal en cliente
  useEffect(() => { setMounted(true); }, []);

  const showPreview = useCallback(() => {
    if (!url || !thumbRef.current) return;
    if (hideTimer.current) { clearTimeout(hideTimer.current); hideTimer.current = null; }

    const rect = thumbRef.current.getBoundingClientRect();
    const POPUP_W = 320;
    const POPUP_H = 320;
    const GAP     = 12;

    // Centrar horizontalmente sobre la miniatura, arriba por defecto
    let x = rect.left + rect.width / 2 - POPUP_W / 2;
    let y = rect.top - POPUP_H - GAP;

    // Si se sale por la izquierda
    if (x < 8) x = 8;
    // Si se sale por la derecha
    if (x + POPUP_W > window.innerWidth - 8) x = window.innerWidth - POPUP_W - 8;
    // Si se sale por arriba, mostrar debajo
    if (y < 8) y = rect.bottom + GAP;

    setPos({ x, y });
    setVisible(true);
  }, [url]);

  const hidePreview = useCallback(() => {
    hideTimer.current = setTimeout(() => setVisible(false), 80);
  }, []);

  useEffect(() => () => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
  }, []);

  const preview = mounted && url && visible ? createPortal(
    <div
      onMouseEnter={() => {
        if (hideTimer.current) { clearTimeout(hideTimer.current); hideTimer.current = null; }
      }}
      onMouseLeave={hidePreview}
      style={{
        position:  "fixed",
        left:      pos.x,
        top:       pos.y,
        width:     320,
        height:    320,
        zIndex:    99999,
        pointerEvents: "auto",
      }}
      className="rounded-2xl bg-white border border-surface-200 shadow-2xl overflow-hidden flex flex-col"
    >
      <img
        src={url}
        alt={nombre}
        className="flex-1 w-full object-contain p-3"
        style={{ minHeight: 0 }}
      />
      {nombre && (
        <div className="shrink-0 bg-surface-900/80 text-white text-xs font-medium px-3 py-2 truncate">
          {nombre}
        </div>
      )}
    </div>,
    document.body,
  ) : null;

  return (
    <>
      <div
        ref={thumbRef}
        className={cn("relative inline-flex shrink-0", wh)}
        onMouseEnter={showPreview}
        onMouseLeave={hidePreview}
      >
        {url ? (
          <img
            src={url}
            alt={nombre}
            title={nombre}
            draggable={false}
            className={cn(wh, "rounded-lg object-cover border border-surface-200 cursor-zoom-in select-none")}
            onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
          />
        ) : (
          <div className={cn(wh, "rounded-lg bg-surface-100 flex items-center justify-center border border-surface-100")}>
            <Package className={cn(icon, "text-surface-300")} />
          </div>
        )}
      </div>

      {preview}
    </>
  );
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: $dst" -ForegroundColor Green

$ok = Select-String -Path "src\components\shared\FotoArticulo.tsx" -Pattern "createPortal" -Quiet
if ($ok) { Write-Host "    OK: portal implementado" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add src\components\shared\FotoArticulo.tsx'
Write-Host '  git commit -m "fix: foto articulo preview via portal position:fixed"'
Write-Host '  git push'
