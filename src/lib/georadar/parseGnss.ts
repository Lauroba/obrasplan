/**
 * src/lib/georadar/parseGnss.ts
 *
 * Parseo de tracks GNSS (sentencias NMEA $GNGGA/$GPGGA) exportados por la
 * app Proceq, y de archivos de parametros CSV. Portado literal desde la
 * app HTML original (funciones loadGNSS y loadParams), separando la parte
 * de calculo puro (esta funcion) de la parte de DOM/UI (que vive en el
 * componente de pagina).
 */

import type { GpsPoint } from "./detectAnomalies";

/**
 * Parsea el contenido de texto de un CSV GNSS (formato Proceq App, UTF-16,
 * sentencias NMEA GGA) y devuelve un track con distancia acumulada y
 * numero de traza estimado, igual que el original.
 */
export function parseGnssText(txt: string): GpsPoint[] {
  const lines = txt.split("\n");
  const pts: { lat: number; lon: number; elev: number }[] = [];

  lines.forEach((l) => {
    if (l.indexOf("$GNGGA") < 0 && l.indexOf("$GPGGA") < 0) return;
    const m = l.match(/\$(G[NP]GGA,[^";\r\n]+)/);
    if (!m) return;
    const fs = m[1].split(",");
    if (fs.length < 10) return;
    try {
      const lr = fs[2];
      const ld = fs[3];
      const lor = fs[4];
      const lod = fs[5];
      if (!lr || !lor) return;
      const latD = parseInt(String(Number(lr) / 100));
      const latM = parseFloat(lr) - latD * 100;
      let lat = latD + latM / 60;
      if (ld === "S") lat = -lat;
      const lonD = parseInt(String(Number(lor) / 100));
      const lonM = parseFloat(lor) - lonD * 100;
      let lon = lonD + lonM / 60;
      if (lod === "W") lon = -lon;
      if (isFinite(lat) && isFinite(lon)) pts.push({ lat, lon, elev: parseFloat(fs[9]) || 0 });
    } catch {
      // Linea NMEA malformada, se ignora igual que en el original
    }
  });

  if (pts.length === 0) return [];

  let dist = 0;
  const full: GpsPoint[] = pts.map((p, i) => {
    if (i > 0) {
      const prev = pts[i - 1];
      const dlat = (p.lat - prev.lat) * 111000;
      const dlon = (p.lon - prev.lon) * 111000 * Math.cos((p.lat * Math.PI) / 180);
      dist += Math.sqrt(dlat * dlat + dlon * dlon);
    }
    return { lat: p.lat, lon: p.lon, elev: p.elev, dist: +dist.toFixed(2), traza: Math.round(dist * 20) };
  });

  // Muestreo a maximo 500 puntos, igual que el original
  const step = Math.max(1, Math.floor(full.length / 500));
  return full.filter((_, i) => i % step === 0);
}

/**
 * Extrae la longitud de perfil (campo "Line 1") de un CSV de parametros
 * exportado por la app Proceq. Devuelve null si no se encuentra.
 */
export function parseParamsText(txt: string): { longitudM: number } | null {
  const lines = txt.split("\n");
  for (const l of lines) {
    const p = l.split("\t");
    if (p[0] && p[0].includes("Line 1") && p[1]) {
      const len = parseFloat(p[1]);
      if (isFinite(len) && len > 0) return { longitudM: len };
    }
  }
  return null;
}
