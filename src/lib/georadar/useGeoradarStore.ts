/**
 * src/lib/georadar/useGeoradarStore.ts
 *
 * Estado del modulo de interpretacion de georradar. Reemplaza las
 * variables globales mutables S / ZONES de la app HTML original por un
 * store de Zustand, siguiendo el mismo patron que el resto de ObrasPlan
 * (ver src/hooks/useLayout.ts).
 */

import { create } from "zustand";
import type { SegyData } from "./parseSegy";
import type { AnomalyResult, LayerResult, GpsPoint, MaterialKey } from "./detectAnomalies";

export interface ZoomState {
  lf: number;
  hf: number;
}

// Modos de vista del panel de visualizacion, equivalentes a LAYOUTS del
// HTML original: all=4 paneles, lf/hf=radar individual, mapa/calor=mapas
// individuales, radares=LF+HF, mapas=mapa+calor.
export type LayoutMode = "all" | "lf" | "hf" | "mapa" | "calor" | "radares" | "mapas";

interface GeoradarState {
  rdLF: SegyData | null;
  rdHF: SegyData | null;
  gps: GpsPoint[];

  anoms: AnomalyResult[];
  layers: LayerResult[];
  selectedIndex: number;

  clienteNombre: string;
  proyecto: string;
  zonaNombre: string;
  velocidadEm: number;
  anchuraM: number;
  longitudSeccionM: number;
  material: MaterialKey;
  longitudPerfilM: number;

  zoomLevel: ZoomState;
  zoomStart: ZoomState;

  analisisTexto: string | null;
  analisisModelo: string | null;
  analizando: boolean;

  layoutMode: LayoutMode;
  fullscreen: boolean;
  heatmapMinFrac: number;
  heatmapMaxFrac: number;
  heatmapRadiusPx: number;

  setRdLF: (rd: SegyData | null) => void;
  setRdHF: (rd: SegyData | null) => void;
  setGps: (gps: GpsPoint[]) => void;
  setAnoms: (anoms: AnomalyResult[], layers: LayerResult[]) => void;
  setSelectedIndex: (i: number) => void;
  setClienteNombre: (v: string) => void;
  setProyecto: (v: string) => void;
  setZonaNombre: (v: string) => void;
  setVelocidadEm: (v: number) => void;
  setAnchuraM: (v: number) => void;
  setLongitudSeccionM: (v: number) => void;
  setMaterial: (v: MaterialKey) => void;
  setLongitudPerfilM: (v: number) => void;
  setZoom: (ch: "lf" | "hf", level: number, start: number) => void;
  setAnalisis: (texto: string | null, modelo: string | null) => void;
  setAnalizando: (v: boolean) => void;
  setLayoutMode: (m: LayoutMode) => void;
  setFullscreen: (v: boolean) => void;
  toggleFullscreen: () => void;
  setHeatmapParams: (min: number, max: number, radius: number) => void;
  reset: () => void;
}

const initialState = {
  rdLF: null,
  rdHF: null,
  gps: [] as GpsPoint[],
  anoms: [] as AnomalyResult[],
  layers: [] as LayerResult[],
  selectedIndex: -1,
  clienteNombre: "",
  proyecto: "",
  zonaNombre: "ZONA 1",
  velocidadEm: 0.09,
  anchuraM: 0,
  longitudSeccionM: 1.5,
  material: "gr" as MaterialKey,
  longitudPerfilM: 884.2,
  zoomLevel: { lf: 1, hf: 1 },
  zoomStart: { lf: 0, hf: 0 },
  analisisTexto: null,
  analisisModelo: null,
  analizando: false,
  layoutMode: "all" as LayoutMode,
  fullscreen: false,
  heatmapMinFrac: 0,
  heatmapMaxFrac: 1,
  heatmapRadiusPx: 30,
};

export const useGeoradarStore = create<GeoradarState>((set) => ({
  ...initialState,
  setRdLF: (rd) => set({ rdLF: rd }),
  setRdHF: (rd) => set({ rdHF: rd }),
  setGps: (gps) => set({ gps }),
  setAnoms: (anoms, layers) => set({ anoms, layers }),
  setSelectedIndex: (i) => set({ selectedIndex: i }),
  setClienteNombre: (v) => set({ clienteNombre: v }),
  setProyecto: (v) => set({ proyecto: v }),
  setZonaNombre: (v) => set({ zonaNombre: v }),
  setVelocidadEm: (v) => set({ velocidadEm: v }),
  setAnchuraM: (v) => set({ anchuraM: v }),
  setLongitudSeccionM: (v) => set({ longitudSeccionM: v }),
  setMaterial: (v) => set({ material: v }),
  setLongitudPerfilM: (v) => set({ longitudPerfilM: v }),
  setZoom: (ch, level, start) =>
    set((s) => ({ zoomLevel: { ...s.zoomLevel, [ch]: level }, zoomStart: { ...s.zoomStart, [ch]: start } })),
  setAnalisis: (texto, modelo) => set({ analisisTexto: texto, analisisModelo: modelo }),
  setAnalizando: (v) => set({ analizando: v }),
  setLayoutMode: (m) => set({ layoutMode: m }),
  setFullscreen: (v) => set({ fullscreen: v }),
  toggleFullscreen: () => set((s) => ({ fullscreen: !s.fullscreen })),
  setHeatmapParams: (min, max, radius) => set({ heatmapMinFrac: min, heatmapMaxFrac: max, heatmapRadiusPx: radius }),
  reset: () => set(initialState),
}));