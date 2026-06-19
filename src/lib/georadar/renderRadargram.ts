/**
 * src/lib/georadar/renderRadargram.ts
 *
 * Render del radargrama en canvas: imagen de fondo en escala de grises
 * (drawBackground, equivalente a drawBW del original) y overlay de capas
 * geologicas + anomalias detectadas (drawOverlay, equivalente a drawOver).
 *
 * Portado de la logica original, pero las funciones reciben directamente
 * el contexto de canvas y los datos en vez de buscar elementos por
 * document.getElementById, para poder usarlas desde refs de React.
 */

import type { SegyData } from "./parseSegy";
import type { AnomalyResult, LayerResult } from "./detectAnomalies";

export interface MinMax {
  mn: number;
  mx: number;
}

/** Calcula el rango min/max de un canal, necesario para normalizar a gris. */
export function normalizeRange(rd: SegyData): MinMax {
  let mn = 1e9;
  let mx = -1e9;
  for (let i = 0; i < rd.data.length; i++) {
    if (rd.data[i] < mn) mn = rd.data[i];
    if (rd.data[i] > mx) mx = rd.data[i];
  }
  return { mn, mx };
}

function getGray(v: number, range: MinMax): [number, number, number] {
  const n = Math.max(0, Math.min(1, (v - range.mn) / (range.mx - range.mn || 1)));
  const a = Math.max(0, Math.min(1, (n - 0.5) * 1.8 + 0.5));
  const g = Math.round(a * 255);
  return [g, g, g];
}

export function maxDepthOf(rd: SegyData, vel: number): number {
  return (vel * rd.dtNs * rd.ROWS) / 2;
}

/**
 * Dibuja el radargrama de fondo en escala de grises con reglas de
 * profundidad y distancia. cS/cE acotan el rango de columnas visible
 * (para zoom horizontal).
 */
export function drawBackground(
  ctx: CanvasRenderingContext2D,
  W: number,
  H: number,
  rd: SegyData | null,
  range: MinMax,
  vel: number,
  pw: number,
  cS = 0,
  cE?: number
) {
  if (!rd) {
    ctx.fillStyle = "#0a0c12";
    ctx.fillRect(0, 0, W, H);
    return;
  }
  const { data, COLS, ROWS } = rd;
  const colS = cS;
  const colE = cE ?? COLS;
  const img = ctx.createImageData(W, H);
  for (let y = 0; y < H; y++) {
    const ri = Math.min(Math.floor((y / H) * ROWS), ROWS - 1);
    for (let x = 0; x < W; x++) {
      const ci = Math.min(Math.floor(colS + (x / W) * (colE - colS)), COLS - 1);
      const [r, g, b] = getGray(data[ri * COLS + ci], range);
      const idx = (y * W + x) * 4;
      img.data[idx] = r;
      img.data[idx + 1] = g;
      img.data[idx + 2] = b;
      img.data[idx + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);

  const md = maxDepthOf(rd, vel);
  ctx.fillStyle = "rgba(8,10,18,.88)";
  ctx.fillRect(0, 0, 38, H);
  ctx.font = "7px IBM Plex Mono, monospace";
  ctx.fillStyle = "#668";
  for (let i = 0; i <= 8; i++) {
    const yy = (i / 8) * H;
    ctx.fillText(((md * i) / 8).toFixed(2) + "m", 2, yy + 8);
    ctx.strokeStyle = "rgba(255,255,255,.05)";
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(38, yy);
    ctx.lineTo(W, yy);
    ctx.stroke();
  }

  const sD = (colS / COLS) * pw;
  const spD = ((colE - colS) / COLS) * pw;
  ctx.fillStyle = "rgba(8,10,18,.88)";
  ctx.fillRect(38, 0, W, 15);
  for (let i = 0; i <= 10; i++) {
    const xr = 38 + (i / 10) * (W - 38);
    ctx.fillText((sD + (spD * i) / 10).toFixed(0) + "m", xr, 11);
  }
}

/**
 * Dibuja el overlay: lineas de capas geologicas con etiqueta, y marcas
 * de anomalias (elipses void/supply) con su volumen.
 */
export function drawOverlay(
  ctx: CanvasRenderingContext2D,
  W: number,
  H: number,
  rd: SegyData | null,
  vel: number,
  layers: LayerResult[],
  anoms: AnomalyResult[],
  selectedIndex: number,
  cS = 0,
  cE?: number
) {
  ctx.clearRect(0, 0, W, H);
  if (!rd) return;
  const { COLS, ROWS } = rd;
  const md = maxDepthOf(rd, vel);
  const colSpan = (cE ?? COLS) - cS;
  const colS2 = cS;

  layers.forEach((l) => {
    const yy = (l.depth / md) * H;
    ctx.strokeStyle = "rgba(0,0,0,.7)";
    ctx.lineWidth = 1.2;
    ctx.setLineDash([6, 4]);
    ctx.beginPath();
    ctx.moveTo(38, yy);
    ctx.lineTo(W, yy);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = "rgba(0,0,0,.85)";
    ctx.font = "bold 8px IBM Plex Mono, monospace";
    ctx.fillText(l.name.substring(0, 16), 40, yy - 2);
  });

  anoms.forEach((a, i) => {
    if (a.col < colS2 - 20 || a.col > colS2 + colSpan + 20) return;
    const relC = (a.col - colS2) / colSpan;
    const x = relC * W;
    const y = (a.row / ROWS) * H;
    const aw = Math.max((a.w / colSpan) * W, 10);
    const ah = Math.max((a.h / ROWS) * H, 7);
    const isV = a.type === "void";
    const col = isV ? "#ff2d5e" : "#ffbe00";
    const sel = selectedIndex === i;
    ctx.save();
    ctx.strokeStyle = col;
    ctx.lineWidth = sel ? 2.5 : 1.5;
    ctx.setLineDash(sel ? [] : [4, 3]);
    ctx.beginPath();
    ctx.ellipse(x, y, aw / 2, ah / 2, 0, 0, Math.PI * 2);
    ctx.fillStyle = isV ? "rgba(255,45,94,.1)" : "rgba(255,190,0,.08)";
    ctx.fill();
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = col;
    ctx.font = "bold 9px IBM Plex Mono, monospace";
    ctx.fillText((isV ? "H" : "S") + (i + 1) + " " + a.dM + "m", x + 8, y - 6);
    if (isV && a.vBruto > 0) {
      ctx.fillStyle = "rgba(8,10,18,.82)";
      ctx.fillRect(x + 8, y + 3, 70, 11);
      ctx.fillStyle = col;
      ctx.font = "7px IBM Plex Mono, monospace";
      ctx.fillText(a.vBruto.toFixed(4) + "m3", x + 10, y + 12);
    }
    if (sel) {
      ctx.strokeStyle = "rgba(204,16,16,.5)";
      ctx.lineWidth = 0.8;
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(x, 16);
      ctx.lineTo(x, H);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.restore();
  });
}
