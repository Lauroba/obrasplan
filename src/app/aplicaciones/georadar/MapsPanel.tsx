"use client";

import { useEffect, useRef, useState } from "react";
import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { initMaps, updateMapLayers, renderHeatmap, type MapPair } from "@/lib/georadar/mapLayers";
import { useGeoradarStore } from "@/lib/georadar/useGeoradarStore";
import { maxDepthOf } from "@/lib/georadar/renderRadargram";

/**
 * Panel de mapas (OSM sincronizado + mapa de calor de anomalias).
 * Componente separado y cargado con next/dynamic (ssr:false) desde la
 * pagina principal, porque Leaflet accede a `window` en el momento de
 * importarse y rompe el render de servidor de Next.js si no se aisla asi.
 *
 * Los iconos por defecto de Leaflet (marker-icon.png) se referencian via
 * URL relativa al paquete y fallan en bundlers como Webpack/Next si no se
 * reconfiguran; aqui no se usan marcadores por defecto (todos los
 * marcadores de mapLayers.ts usan L.divIcon con SVG inline), asi que no
 * hace falta el workaround habitual de Leaflet+webpack.
 */
export default function MapsPanel({ showMapa, showCalor }: { showMapa: boolean; showCalor: boolean }) {
  const store = useGeoradarStore();
  const mapContainer1 = useRef<HTMLDivElement>(null);
  const mapContainer2 = useRef<HTMLDivElement>(null);
  const heatCanvas = useRef<HTMLCanvasElement>(null);
  const pairRef = useRef<MapPair | null>(null);
  const [voidsInRange, setVoidsInRange] = useState(0);

  const refreshHeat = () => {
    if (!heatCanvas.current || !pairRef.current) return;
    const rd = store.rdLF || store.rdHF;
    const md = rd ? maxDepthOf(rd, store.velocidadEm) : 3;
    const { voidsInRange: n } = renderHeatmap(heatCanvas.current, pairRef.current.m2, store.anoms, md, {
      minDepthFrac: store.heatmapMinFrac,
      maxDepthFrac: store.heatmapMaxFrac,
      radiusPx: store.heatmapRadiusPx,
    });
    setVoidsInRange(n);
  };

  // Inicializa los mapas una sola vez, cuando ambos contenedores existen.
  useEffect(() => {
    if (!mapContainer1.current || !mapContainer2.current || pairRef.current) return;
    const pair = initMaps(mapContainer1.current, mapContainer2.current, refreshHeat);
    pairRef.current = pair;
    return () => {
      pair.m1.remove();
      pair.m2.remove();
      pairRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Redibuja las capas (track GPS + anomalias) cuando cambian los datos.
  useEffect(() => {
    if (!pairRef.current) return;
    updateMapLayers(pairRef.current, store.gps, store.anoms, store.longitudPerfilM, store.setSelectedIndex);
    setTimeout(() => {
      pairRef.current?.m1.invalidateSize(false);
      pairRef.current?.m2.invalidateSize(false);
      refreshHeat();
    }, 250);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.gps, store.anoms, store.longitudPerfilM]);

  // Redibuja el heatmap cuando cambian sus parametros o la visibilidad cambia
  useEffect(() => {
    const t = setTimeout(refreshHeat, 100);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.heatmapMinFrac, store.heatmapMaxFrac, store.heatmapRadiusPx, showMapa, showCalor]);

  // Recalcular tamano de los mapas al cambiar de layout (el contenedor
  // puede pasar de oculto a visible y Leaflet necesita invalidateSize).
  useEffect(() => {
    const t = setTimeout(() => {
      pairRef.current?.m1.invalidateSize(false);
      pairRef.current?.m2.invalidateSize(false);
      refreshHeat();
    }, 80);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showMapa, showCalor]);

  const md = (store.rdLF || store.rdHF) ? maxDepthOf((store.rdLF || store.rdHF)!, store.velocidadEm) : 3;

  return (
    <>
      {showMapa && (
        <div className="bg-white flex flex-col min-h-0">
          <div className="flex items-center gap-2 px-2 py-1 border-b border-surface-100 text-[10px]">
            <span className="font-semibold text-surface-700">Mapa</span>
            <span className="text-surface-400 font-mono">
              {store.gps.length} pts RTK · {store.anoms.length} anomalías
            </span>
          </div>
          <div ref={mapContainer1} className="relative flex-1 min-h-[200px]">
            {store.gps.length === 0 && (
              <div className="absolute inset-0 z-[1000] flex items-center justify-center bg-white/90 text-surface-400 text-[11px] px-6 text-center pointer-events-none">
                Carga un GNSS CSV o pulsa &quot;Probar con datos demo&quot;
              </div>
            )}
          </div>
        </div>
      )}

      {showCalor && (
        <div className="bg-white flex flex-col min-h-0">
          <div className="flex items-center gap-2 px-2 py-1 border-b border-surface-100 text-[10px] flex-wrap">
            <span className="font-semibold text-surface-700">Mapa de calor</span>
            <span className="text-surface-400 font-mono">{voidsInRange} huecos en rango</span>
            <div className="ml-auto flex items-center gap-1.5 text-surface-500">
              <span className="font-mono">Prof:</span>
              <input
                type="range" min={0} max={100}
                value={store.heatmapMinFrac * 100}
                onChange={(e) => store.setHeatmapParams(parseInt(e.target.value) / 100, store.heatmapMaxFrac, store.heatmapRadiusPx)}
                className="w-12"
              />
              <span className="font-mono text-[9px]">{(store.heatmapMinFrac * md).toFixed(1)}m</span>
              <input
                type="range" min={0} max={100}
                value={store.heatmapMaxFrac * 100}
                onChange={(e) => store.setHeatmapParams(store.heatmapMinFrac, parseInt(e.target.value) / 100, store.heatmapRadiusPx)}
                className="w-12"
              />
              <span className="font-mono text-[9px]">{store.heatmapMaxFrac >= 1 ? "∞" : (store.heatmapMaxFrac * md).toFixed(1) + "m"}</span>
              <span className="font-mono">R:</span>
              <input
                type="range" min={10} max={120}
                value={store.heatmapRadiusPx}
                onChange={(e) => store.setHeatmapParams(store.heatmapMinFrac, store.heatmapMaxFrac, parseInt(e.target.value))}
                className="w-10"
              />
            </div>
          </div>
          <div className="relative flex-1 min-h-[200px]">
            <div ref={mapContainer2} className="absolute inset-0" />
            <canvas ref={heatCanvas} className="absolute inset-0 pointer-events-none" />
            {store.gps.length === 0 && (
              <div className="absolute inset-0 z-[1000] flex items-center justify-center bg-white/90 text-surface-400 text-[11px] px-6 text-center pointer-events-none">
                Carga un GNSS CSV o pulsa &quot;Probar con datos demo&quot;
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}