/**
 * src/lib/georadar/parseSegy.ts
 *
 * Parser de archivos SEG-Y (formato estandar de georradar/sismica).
 * Portado literal desde la app HTML original (loynek_gpr_v12_OK.html,
 * funcion parseSEGY) -- NO se ha reescrito ni "mejorado" la logica, solo
 * traducido a TypeScript, porque el comportamiento ya esta calibrado y
 * validado contra un analisis de referencia en Python sobre datos reales.
 *
 * Cualquier cambio futuro en esta funcion debe re-validarse contra el
 * mismo SGY de control que se uso para el demo (884.2m, 17684 trazas).
 */

export interface SegyData {
  data: Float32Array;
  COLS: number;
  ROWS: number;
  dtNs: number;
  /** Solo presente en datos demo, no en SGY real */
  anomDefs?: AnomDef[];
  layerDefs?: LayerDef[];
}

export interface AnomDef {
  type: "void" | "supply";
  col: number;
  row: number;
  w: number;
  h: number;
}

export interface LayerDef {
  r: number;
  a?: number;
  f?: number;
  s?: number;
}

/**
 * Parsea un buffer binario SEG-Y. Cabecera textual de 3200 bytes + cabecera
 * binaria de 400 bytes (total 3600), luego cabecera de traza de 240 bytes
 * seguida de las muestras (formato IBM float -fmt 1- o IEEE float).
 */
export function parseSegy(buf: ArrayBuffer): SegyData {
  const v = new DataView(buf);
  const dtUs = v.getInt16(3216, false);
  let spt = v.getInt16(3220, false);
  const fmt = v.getInt16(3224, false);
  const dtNs = dtUs > 0 ? dtUs / 1000 : 0.4;
  if (spt <= 0 || spt > 8192) spt = 512;

  const hB = 3600;
  const thB = 240;
  const trB = thB + spt * 4;
  const nT = Math.max(1, Math.floor((buf.byteLength - hB) / trB));
  const COLS = Math.min(nT, 4096);
  const ROWS = spt;
  const data = new Float32Array(ROWS * COLS);

  for (let t = 0; t < COLS; t++) {
    const tO = hB + t * trB;
    if (tO + trB > buf.byteLength) break;
    for (let s = 0; s < ROWS; s++) {
      const sO = tO + thB + s * 4;
      if (sO + 4 > buf.byteLength) break;
      let val = 0;
      if (fmt === 1) {
        // IBM 32-bit float
        const raw = v.getUint32(sO, false);
        const sg = raw >>> 31 ? -1 : 1;
        const ex = ((raw >>> 24) & 0x7f) - 64;
        const mn = (raw & 0xffffff) / 16777216;
        val = sg * mn * Math.pow(16, ex);
      } else {
        try {
          val = v.getFloat32(sO, false);
        } catch {
          val = 0;
        }
      }
      if (!isFinite(val)) val = 0;
      data[s * COLS + t] = val;
    }
  }

  return { data, COLS, ROWS, dtNs };
}
