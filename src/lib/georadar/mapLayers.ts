/**
 * src/lib/georadar/mapLayers.ts
 *
 * Logica de los dos mapas Leaflet (OSM sincronizado + mapa de calor de
 * anomalias), portada de la app HTML original (initMaps, updateMaps,
 * renderHeat). Adaptada para usarse desde refs de React en vez de
 * document.getElementById, y con la paleta de colores de ObrasPlan
 * (decision confirmada: estilo claro, no el tema oscuro original).
 */

import L from "leaflet";
import type { AnomalyResult, GpsPoint } from "./detectAnomalies";

export interface MapPair {
  m1: L.Map;
  m2: L.Map;
  layers1: L.Layer[];
  layers2: L.Layer[];
}

const DEFAULT_CENTER: L.LatLngTuple = [43.3585, -3.0518];

export function initMaps(container1: HTMLElement, container2: HTMLElement, onMove: () => void): MapPair {
  const m1 = L.map(container1, { center: DEFAULT_CENTER, zoom: 16, zoomControl: true, preferCanvas: true });
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    maxZoom: 20,
    minZoom: 1,
    crossOrigin: true,
  }).addTo(m1);

  const m2 = L.map(container2, { center: DEFAULT_CENTER, zoom: 16, zoomControl: false, attributionControl: false, preferCanvas: true });
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 20, minZoom: 1, crossOrigin: true }).addTo(m2);

  let syncing = false;
  m1.on("move zoom", () => {
    if (syncing) return;
    syncing = true;
    m2.setView(m1.getCenter(), m1.getZoom(), { animate: false });
    syncing = false;
    onMove();
  });
  m2.on("move zoom", () => {
    if (syncing) return;
    syncing = true;
    m1.setView(m2.getCenter(), m2.getZoom(), { animate: false });
    syncing = false;
    onMove();
  });

  return { m1, m2, layers1: [], layers2: [] };
}

function clearLayers(pair: MapPair) {
  pair.layers1.forEach((l) => {
    try { l.remove(); } catch { /* capa ya eliminada */ }
  });
  pair.layers2.forEach((l) => {
    try { l.remove(); } catch { /* capa ya eliminada */ }
  });
  pair.layers1 = [];
  pair.layers2 = [];
}

function addToBoth(pair: MapPair, layer1: L.Layer, layer2: L.Layer) {
  layer1.addTo(pair.m1);
  layer2.addTo(pair.m2);
  pair.layers1.push(layer1);
  pair.layers2.push(layer2);
}

const TRACK_COLOR = "#dc2626";
const RISK_COLOR: Record<string, string> = { high: "#dc2626", med: "#d97706", low: "#2563eb" };

export function updateMapLayers(
  pair: MapPair,
  gps: GpsPoint[],
  anoms: AnomalyResult[],
  longitudPerfilM: number,
  onSelectAnom: (i: number) => void
) {
  clearLayers(pair);
  if (!gps.length) return;

  const lls: L.LatLngTuple[] = gps.map((p) => [p.lat, p.lon]);

  const track1 = L.polyline(lls, { color: TRACK_COLOR, weight: 3, opacity: 0.85, smoothFactor: 1 });
  const track2 = L.polyline(lls, { color: TRACK_COLOR, weight: 3, opacity: 0.85, smoothFactor: 1 });
  addToBoth(pair, track1, track2);

  const glow1 = L.polyline(lls, { color: TRACK_COLOR, weight: 8, opacity: 0.12, smoothFactor: 1 });
  const glow2 = L.polyline(lls, { color: TRACK_COLOR, weight: 8, opacity: 0.12, smoothFactor: 1 });
  addToBoth(pair, glow1, glow2);

  const bounds = track1.getBounds();
  pair.m1.fitBounds(bounds, { padding: [50, 50], maxZoom: 17, animate: false });
  pair.m2.fitBounds(bounds, { padding: [50, 50], maxZoom: 17, animate: false });

  const mkStyle = { radius: 7, fillOpacity: 0.9, weight: 2, color: "#ffffff" };
  const start = gps[0];
  const end = gps[gps.length - 1];
  addToBoth(
    pair,
    L.circleMarker([start.lat, start.lon], { ...mkStyle, fillColor: "#16a34a" }).bindTooltip("Inicio - 0m"),
    L.circleMarker([start.lat, start.lon], { ...mkStyle, fillColor: "#16a34a" })
  );
  addToBoth(
    pair,
    L.circleMarker([end.lat, end.lon], { ...mkStyle, fillColor: TRACK_COLOR }).bindTooltip("Fin - " + longitudPerfilM.toFixed(1) + "m"),
    L.circleMarker([end.lat, end.lon], { ...mkStyle, fillColor: TRACK_COLOR })
  );

  anoms.forEach((a, i) => {
    if (!a.gpt) return;
    const isVoid = a.type === "void";
    const col = isVoid ? "#dc2626" : "#d97706";
    const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28">' +
      (a.risk === "high" ? '<circle cx="14" cy="14" r="13" fill="none" stroke="' + col + '" stroke-width="2" stroke-dasharray="3,2" opacity=".6"/>' : "") +
      '<circle cx="14" cy="14" r="10" fill="' + col + '" fill-opacity=".95" stroke="#ffffff" stroke-width="2"/>' +
      '<text x="14" y="17" text-anchor="middle" fill="#ffffff" font-size="7" font-weight="bold" font-family="monospace">' + (isVoid ? "H" : "S") + (i + 1) + "</text></svg>";
    const icon = L.divIcon({ html: svg, className: "", iconSize: [28, 28], iconAnchor: [14, 14] });
    const riskColor = a.risk ? RISK_COLOR[a.risk] : "#6b7280";
    const popupHtml =
      '<div style="font-family:system-ui,sans-serif;font-size:12px;min-width:160px">' +
      '<div style="font-weight:700;color:' + col + ';margin-bottom:4px">' + (isVoid ? "Hueco " : "Suministro ") + (i + 1) + "</div>" +
      '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Distancia</span><span>' + a.distM + " m</span></div>" +
      '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Profundidad</span><span>' + a.dM + " m</span></div>" +
      '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Dimensiones</span><span>' + a.wM + "x" + a.hM + " m</span></div>" +
      (isVoid
        ? '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Vol. bruto</span><span>' + a.vBruto.toFixed(4) + " m3</span></div>" +
          '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Riesgo</span><span style="color:' + riskColor + ';font-weight:700">' + (a.risk?.toUpperCase() || "-") + "</span></div>"
        : "") +
      "</div>";
    const mk1 = L.marker([a.gpt.lat, a.gpt.lon], { icon }).bindPopup(popupHtml);
    const mk2 = L.marker([a.gpt.lat, a.gpt.lon], { icon }).bindPopup(popupHtml);
    mk1.on("click", () => onSelectAnom(i));
    mk2.on("click", () => onSelectAnom(i));
    addToBoth(pair, mk1, mk2);
  });
}

export interface HeatmapParams {
  minDepthFrac: number;
  maxDepthFrac: number;
  radiusPx: number;
}

export function renderHeatmap(
  canvas: HTMLCanvasElement,
  map2: L.Map,
  anoms: AnomalyResult[],
  maxDepthM: number,
  params: HeatmapParams
): { voidsInRange: number } {
  const wrap = canvas.parentElement;
  const W = wrap?.clientWidth || 2;
  const H = wrap?.clientHeight || 2;
  canvas.width = W;
  canvas.height = H;
  canvas.style.width = W + "px";
  canvas.style.height = H + "px";
  const ctx = canvas.getContext("2d");
  if (!ctx) return { voidsInRange: 0 };
  ctx.clearRect(0, 0, W, H);

  if (!anoms.length) return { voidsInRange: 0 };

  const minDepth = params.minDepthFrac * maxDepthM;
  const maxDepth = params.maxDepthFrac * maxDepthM;
  const voids = anoms.filter(
    (a) => a.type === "void" && a.gpt && a.dM >= minDepth && (params.maxDepthFrac >= 1 || a.dM <= maxDepth)
  );
  if (!voids.length) return { voidsInRange: 0 };

  const pts = voids
    .map((a) => {
      try {
        const pt = map2.latLngToContainerPoint([a.gpt!.lat, a.gpt!.lon]);
        return { x: pt.x, y: pt.y, vol: a.vBruto, risk: a.risk };
      } catch {
        return null;
      }
    })
    .filter((p): p is { x: number; y: number; vol: number; risk: AnomalyResult["risk"] } => !!p && isFinite(p.x) && isFinite(p.y));

  if (!pts.length) return { voidsInRange: voids.length };

  const rad = params.radiusPx;
  const maxV = Math.max(...pts.map((p) => p.vol), 1e-12);
  const field = new Float32Array(W * H);
  pts.forEach((pt) => {
    const w = pt.vol / maxV + 0.15;
    const x0 = Math.max(0, Math.round(pt.x - rad));
    const x1 = Math.min(W - 1, Math.round(pt.x + rad));
    const y0 = Math.max(0, Math.round(pt.y - rad));
    const y1 = Math.min(H - 1, Math.round(pt.y + rad));
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const d = Math.sqrt((x - pt.x) ** 2 + (y - pt.y) ** 2);
        if (d < rad) field[y * W + x] += w * (1 - d / rad) ** 2;
      }
    }
  });

  let fmax = 0;
  for (let i = 0; i < field.length; i++) if (field[i] > fmax) fmax = field[i];
  if (!fmax) return { voidsInRange: voids.length };

  const img = ctx.createImageData(W, H);
  for (let i = 0; i < W * H; i++) {
    const t = field[i] / fmax;
    if (t < 0.04) continue;
    let r: number, g: number, b: number;
    if (t < 0.25) {
      r = 0; g = Math.round(t * 4 * 180); b = Math.round(80 + t * 4 * 175);
    } else if (t < 0.5) {
      const s = (t - 0.25) / 0.25; r = 0; g = Math.round(180 + s * 75); b = Math.round(255 - s * 255);
    } else if (t < 0.75) {
      const s = (t - 0.5) / 0.25; r = Math.round(s * 255); g = 255; b = 0;
    } else {
      const s = (t - 0.75) / 0.25; r = 255; g = Math.round(255 - s * 230); b = 0;
    }
    const idx = i * 4;
    img.data[idx] = r; img.data[idx + 1] = g; img.data[idx + 2] = b;
    img.data[idx + 3] = Math.round(Math.min(t * 1.5, 1) * 180);
  }
  ctx.putImageData(img, 0, 0);

  pts.forEach((pt) => {
    if (pt.x < 0 || pt.x > W || pt.y < 0 || pt.y > H) return;
    const rc = pt.risk === "high" ? "#dc2626" : pt.risk === "med" ? "#d97706" : "#2563eb";
    ctx.beginPath();
    ctx.arc(pt.x, pt.y, 6, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(255,255,255,0.92)";
    ctx.fill();
    ctx.strokeStyle = rc;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = "#111827";
    ctx.font = "bold 8px monospace";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText((pt.vol * 1e4).toFixed(0), pt.x, pt.y);
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
  });

  const lx = 8;
  const ly = H - 46;
  const gg = ctx.createLinearGradient(lx, ly, lx + 90, ly);
  gg.addColorStop(0, "rgba(0,80,200,.9)");
  gg.addColorStop(0.33, "rgba(0,220,255,.9)");
  gg.addColorStop(0.55, "rgba(0,255,50,.9)");
  gg.addColorStop(0.75, "rgba(255,230,0,.9)");
  gg.addColorStop(1, "rgba(255,20,0,.9)");
  ctx.fillStyle = gg;
  ctx.fillRect(lx, ly, 90, 8);
  ctx.strokeStyle = "rgba(0,0,0,.2)";
  ctx.lineWidth = 0.5;
  ctx.strokeRect(lx, ly, 90, 8);
  ctx.fillStyle = "rgba(255,255,255,.95)";
  ctx.font = "7px monospace";
  ctx.shadowColor = "rgba(0,0,0,0.6)";
  ctx.shadowBlur = 2;
  ctx.fillText("Bajo", lx, ly + 17);
  ctx.fillText("Alto", lx + 62, ly + 17);
  ctx.fillText("Vol. x10-4 m3", lx, ly + 26);
  ctx.shadowBlur = 0;

  return { voidsInRange: voids.length };
}