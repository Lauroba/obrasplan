/**
 * src/lib/georadar/genDemo.ts
 *
 * Generador de datos sinteticos de demostracion (radargrama LF/HF con
 * anomalias predefinidas), portado literal de la funcion genDemo() del
 * HTML original. Util para probar la app sin tener un SGY real a mano.
 */

import type { SegyData, AnomDef, LayerDef } from "./parseSegy";

interface DemoChannelConfig {
  s: number;
  ns: number;
}

const DEMO_CFG: Record<"lf" | "hf", DemoChannelConfig> = {
  lf: { s: 369, ns: 45 },
  hf: { s: 655, ns: 40 },
};

export function genDemo(ch: "lf" | "hf", totalTraces = 17684): SegyData {
  const cfg = DEMO_CFG[ch];
  const COLS = Math.min(totalTraces || 17684, 2000);
  const ROWS = cfg.s;
  const data = new Float32Array(ROWS * COLS);

  for (let i = 0; i < data.length; i++) data[i] = (Math.random() - 0.5) * 0.03;
  for (let c = 0; c < COLS; c++) {
    for (let r = 0; r < 10; r++) data[r * COLS + c] += Math.exp(-r * 0.5) * Math.sin(r * 1.3) * 0.65;
  }

  const LD: LayerDef[] = [
    { r: 40, a: 6, f: 0.004, s: 0.9 },
    { r: 90, a: 10, f: 0.003, s: 0.8 },
    { r: 160, a: 8, f: 0.007, s: 0.7 },
    { r: 240, a: 12, f: 0.005, s: 0.6 },
    { r: 320, a: 5, f: 0.011, s: 0.5 },
  ];
  LD.forEach((l) => {
    for (let c = 0; c < COLS; c++) {
      const row = Math.round(
        l.r + Math.sin(c * (l.f || 0)) * (l.a || 0) + Math.cos(c * (l.f || 0) * 0.6) * (l.a || 0) * 0.4
      );
      for (let dr = -4; dr <= 4; dr++) {
        const r = row + dr;
        if (r < 0 || r >= ROWS) continue;
        data[r * COLS + c] += Math.sin(dr * 1.5) * Math.exp(-dr * dr * 0.3) * (l.s || 0);
      }
    }
  });

  const AD: AnomDef[] = [
    { type: "void", col: 180, row: 100, w: 32, h: 18 },
    { type: "void", col: 380, row: 140, w: 50, h: 28 },
    { type: "void", col: 650, row: 90, w: 28, h: 15 },
    { type: "supply", col: 260, row: 60, w: 10, h: 45 },
    { type: "supply", col: 520, row: 75, w: 12, h: 52 },
    { type: "void", col: 880, row: 200, w: 45, h: 24 },
    { type: "void", col: 1100, row: 120, w: 35, h: 19 },
    { type: "void", col: 1450, row: 160, w: 38, h: 21 },
    { type: "supply", col: 750, row: 55, w: 8, h: 38 },
    { type: "void", col: 1700, row: 210, w: 55, h: 30 },
  ];
  AD.forEach((a) => {
    for (let c = 0; c < COLS; c++) {
      const dc = c - a.col;
      if (Math.abs(dc) > 120) continue;
      const hr = Math.round(a.row + Math.sqrt(Math.max(0, dc * dc * 0.2)));
      if (hr >= ROWS) continue;
      for (let dr = -5; dr <= 5; dr++) {
        const r = hr + dr;
        if (r < 0 || r >= ROWS) continue;
        data[r * COLS + c] += Math.sin(dr * 1.8) * Math.exp(-dr * dr * 0.28) * Math.exp(-dc * dc * 0.0012) * 1.5;
      }
    }
  });

  return { data, COLS, ROWS, dtNs: cfg.ns / cfg.s, anomDefs: AD, layerDefs: LD };
}
