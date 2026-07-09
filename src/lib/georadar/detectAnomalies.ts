/**
 * src/lib/georadar/detectAnomalies.ts
 *
 * Algoritmo de deteccion de anomalias (huecos/suministros) en datos de
 * georradar. Portado literal desde la app HTML original (funcion detect()),
 * incluyendo los comentarios de calibracion originales -- NO se ha tocado
 * ningun umbral ni constante. El propio codigo original documenta que esta
 * deteccion "v12" fue validada contra un analisis de referencia en Python
 * sobre un SGY real de 17685 trazas / 884.2m, dando ~4.5m3 de volumen
 * bruto. Cualquier cambio de umbral debe re-validarse contra ese mismo caso.
 *
 * Mantiene exactamente el mismo modelo de Sanders, formula de volumen
 * elipsoidal y clasificacion void/supply que la version HTML.
 */

import type { SegyData } from "./parseSegy";

export type MaterialKey = "sf" | "gr" | "cl" | "ro" | "mx";

export interface SandersEntry {
  n: string;
  p: number; // porosidad
  f: number; // factor
  inf: boolean;
  er: number;
}

export const SANDERS: Record<MaterialKey, SandersEntry> = {
  sf: { n: "Arena fina/limo", p: 0.36, f: 0.85, inf: true, er: 4.5 },
  gr: { n: "Grava/cascajo", p: 0.26, f: 0.65, inf: false, er: 5.5 },
  cl: { n: "Arcilla/lutita", p: 0.52, f: 0.15, inf: false, er: 15 },
  ro: { n: "Roca fracturada", p: 0.06, f: 0.4, inf: false, er: 6 },
  mx: { n: "Mixto", p: 0.3, f: 0.65, inf: true, er: 6.5 },
};

export interface GpsPoint {
  lat: number;
  lon: number;
  elev: number;
  dist: number;
  traza?: number;
}

export interface AnomalyResult {
  type: "void" | "supply" | "pipe" | "anomaly";
  subtype?: string;  // metal, pvc, hormigon, cable (para tuberias)
  col: number;
  row: number;
  w: number;
  h: number;
  i: number;
  dM: number;
  wM: number;
  hM: number;
  da: number;
  db: number;
  dc: number;
  vBruto: number;
  vNet: number;
  conf: number;
  distM: number;
  gpt: GpsPoint | null;
  risk: "high" | "med" | "low";
}

export interface LayerResult {
  name: string;
  depth: number;
}

export interface DetectParams {
  vel: number;
  pw: number;
  pl: number;
  material: MaterialKey;
  gps: GpsPoint[];
}

function maxDepth(rd: SegyData, vel: number): number {
  return (vel * rd.dtNs * rd.ROWS) / 2;
}

function closestGPS(gps: GpsPoint[], distM: number): GpsPoint | null {
  if (!gps.length) return null;
  return gps.reduce((b, p) => (Math.abs(p.dist - distM) < Math.abs(b.dist - distM) ? p : b), gps[0]);
}

export function calcVol(wM: number, hM: number, pl: number): { vol: number; a: number; b: number; c: number } {
  const a = wM / 2;
  const b = hM / 2;
  const c = Math.min(wM * 0.8, pl) / 2;
  return { vol: (4 / 3) * Math.PI * a * b * c, a, b, c };
}

export function riskLvl(volBruto: number, dep: number): "high" | "med" | "low" {
  if (volBruto > 0.25 || dep < 0.2) return "high";
  if (volBruto > 0.025 || dep < 0.7) return "med";
  return "low";
}

export function detectAnomalies(
  rd: SegyData,
  params: DetectParams
): { anoms: AnomalyResult[]; layers: LayerResult[] } {
  const { data, COLS, ROWS } = rd;
  const md = maxDepth(rd, params.vel);
  const dx = params.pw / COLS;
  const snd = SANDERS[params.material] || SANDERS.gr;

  let anoms: AnomalyResult[];

  if (rd.anomDefs) {
    anoms = rd.anomDefs.map((a, i) => {
      const dM = (a.row / ROWS) * md;
      const wM = a.w * dx;
      const hM = (a.h / ROWS) * md;
      const { vol, a: da, b: db, c: dc } = calcVol(wM, hM, params.pl);
      const vNet = vol * snd.f + (snd.inf ? vol * snd.p * 0.2 : 0);
      const distM = (a.col / COLS) * params.pw;
      const gpt = closestGPS(params.gps, distM);
      return {
        type: a.type,
        col: a.col,
        row: a.row,
        w: a.w,
        h: a.h,
        i,
        dM: +dM.toFixed(3),
        wM: +wM.toFixed(3),
        hM: +hM.toFixed(3),
        da,
        db,
        dc,
        vBruto: +vol.toFixed(6),
        vNet: +(a.type === "void" ? vNet : 0).toFixed(6),
        conf: +(0.72 + Math.random() * 0.22).toFixed(3),
        distM: +distM.toFixed(1),
        gpt,
        risk: riskLvl(vol, dM),
      };
    });
  } else {
    // ==========================================================
    // DETECCION PROFESIONAL v12 -- validada contra analisis Python
    // SGY real (17685 trazas, 884.2m): resultado ~4.5m3 bruto
    // BW=8: resolucion 4x, umbral adaptativo 3.5 sigma
    // Filtros fisicos eliminan capas y artefactos
    // Supply: solo si wM < 0.5m Y hM > wM en metros fisicos
    // (DX=0.4m/bloque vs DZ=0.044m/bloque -- NO comparar en bloques)
    // ==========================================================
    const BW = 8;
    const BH = 8;
    const GC = Math.floor(COLS / BW);
    const GR2 = Math.floor(ROWS / BH);
    const DZ_m = md / ROWS;
    const DX_blk = BW * dx;
    const DZ_blk = BH * DZ_m;

    const eng = new Float32Array(GR2 * GC);
    for (let gr = 0; gr < GR2; gr++) {
      for (let gc = 0; gc < GC; gc++) {
        let e = 0;
        let n = 0;
        for (let r = gr * BH; r < Math.min((gr + 1) * BH, ROWS); r++) {
          for (let c = gc * BW; c < Math.min((gc + 1) * BW, COLS); c++) {
            const v2 = data[r * COLS + c];
            e += v2 * v2;
            n++;
          }
        }
        eng[gr * GC + gc] = n ? Math.sqrt(e / n) : 0;
      }
    }

    const bg = new Float32Array(GR2);
    for (let gr = 0; gr < GR2; gr++) {
      let s = 0;
      for (let gc = 0; gc < GC; gc++) s += eng[gr * GC + gc];
      bg[gr] = s / GC;
    }
    const norm = eng.map((v2, i2) => v2 / (bg[Math.floor(i2 / GC)] || 1));

    let nSum = 0;
    let nSum2 = 0;
    for (let i2 = 0; i2 < norm.length; i2++) {
      nSum += norm[i2];
      nSum2 += norm[i2] * norm[i2];
    }
    const nMean = nSum / norm.length;
    const nStd = Math.sqrt(Math.max(0, nSum2 / norm.length - nMean * nMean));
    const THR_E = nMean + 3.5 * nStd;
    const THR_G = nMean + 2.2 * nStd;

    const GR_SKIP = Math.max(2, Math.round(0.08 / DZ_blk));
    const vis = new Uint8Array(GR2 * GC);
    const blobs: { r0: number; r1: number; c0: number; c1: number; eS: number; wM_b: number; hM_b: number }[] = [];

    for (let gr = GR_SKIP; gr < GR2 - 1; gr++) {
      for (let gc = 0; gc < GC; gc++) {
        if (vis[gr * GC + gc] || norm[gr * GC + gc] < THR_E) continue;
        const q: [number, number][] = [[gr, gc]];
        vis[gr * GC + gc] = 1;
        let r0 = gr,
          r1 = gr,
          c0 = gc,
          c1 = gc,
          eS = 0;
        while (q.length) {
          const [cr, cc] = q.pop()!;
          eS += norm[cr * GC + cc];
          for (const [dr, dc2] of [[-1, 0], [1, 0], [0, -1], [0, 1]] as const) {
            const nr = cr + dr;
            const nc = cc + dc2;
            if (nr < GR_SKIP || nr >= GR2 || nc < 0 || nc >= GC || vis[nr * GC + nc]) continue;
            if (norm[nr * GC + nc] > THR_G) {
              vis[nr * GC + nc] = 1;
              q.push([nr, nc]);
              r0 = Math.min(r0, nr);
              r1 = Math.max(r1, nr);
              c0 = Math.min(c0, nc);
              c1 = Math.max(c1, nc);
            }
          }
        }
        const wM_b = (c1 - c0 + 1) * DX_blk;
        const hM_b = (r1 - r0 + 1) * DZ_blk;
        if (wM_b < 0.2) continue;
        if (hM_b < 0.015) continue;
        if (wM_b > 10.0) continue;
        if (hM_b > 0.6) continue;
        if (wM_b / Math.max(hM_b, 0.001) > 25) continue;
        blobs.push({ r0, r1, c0, c1, eS, wM_b, hM_b });
      }
    }

    blobs.sort((a2, b2) => b2.eS - a2.eS);

    const MIN_SEP = 3;
    const kept: typeof blobs = [];
    for (const b2 of blobs) {
      const cx = (b2.c0 + b2.c1) / 2;
      const cy = (b2.r0 + b2.r1) / 2;
      let dup = false;
      for (const k of kept) {
        if (Math.abs(cx - (k.c0 + k.c1) / 2) < MIN_SEP && Math.abs(cy - (k.r0 + k.r1) / 2) < MIN_SEP) {
          dup = true;
          break;
        }
      }
      if (!dup) kept.push(b2);
    }

    anoms = kept.slice(0, 80).map((b2, i) => {
      const cC = Math.round(((b2.c0 + b2.c1) / 2) * BW + BW / 2);
      const cR = Math.round(((b2.r0 + b2.r1) / 2) * BH + BH / 2);
      const wPx = (b2.c1 - b2.c0 + 1) * BW;
      const hPx = (b2.r1 - b2.r0 + 1) * BH;
      const dM = (cR / ROWS) * md;
      const wM = wPx * dx;
      const hM = (hPx / ROWS) * md;
      const type: "void" | "supply" = wM < 0.5 && hM > wM * 0.8 ? "supply" : "void";
      const { vol, a: da, b: db, c: dc } = calcVol(wM, hM, params.pl);
      const vNet = vol * snd.f + (snd.inf ? vol * snd.p * 0.2 : 0);
      const distM = (cC / COLS) * params.pw;
      const gpt = closestGPS(params.gps, distM);
      return {
        type,
        col: cC,
        row: cR,
        w: wPx,
        h: hPx,
        i,
        dM: +dM.toFixed(3),
        wM: +wM.toFixed(3),
        hM: +hM.toFixed(3),
        da,
        db,
        dc,
        vBruto: +vol.toFixed(6),
        vNet: +(type === "void" ? vNet : 0).toFixed(6),
        conf: +Math.min(0.95, 0.5 + b2.eS * 0.003).toFixed(3),
        distM: +distM.toFixed(1),
        gpt,
        risk: riskLvl(vol, dM),
      };
    });
  }

  const layerDefs = rd.layerDefs || [0.1, 0.22, 0.4, 0.58, 0.75].map((f) => ({ r: Math.round(rd.ROWS * f) }));
  const layerNames = ["Pavimento/base", "Zona no saturada", "Transicion", "Nivel freatico", "Roca/substrato"];
  const layers: LayerResult[] = layerDefs.map((l, i) => ({
    name: layerNames[i] || "Capa " + (i + 1),
    depth: +((l.r / rd.ROWS) * md).toFixed(3),
  }));

  return { anoms, layers };
}