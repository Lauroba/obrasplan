/**
 * src/lib/georadar/buildPrompt.ts
 *
 * Construye el prompt tecnico para el analisis IA, portado literal de la
 * funcion buildPrompt() del HTML original. El contenido y estructura del
 * prompt (secciones del informe, terminologia geotecnica) se mantienen
 * identicos; solo cambia que ahora corre en servidor en vez de en cliente.
 */

import type { AnomalyResult, LayerResult, MaterialKey, SandersEntry } from "./detectAnomalies";

export interface PromptContext {
  sand: SandersEntry;
  maxDepthM: number;
  anoms: AnomalyResult[];
  layers: LayerResult[];
  vel: number;
  pw: number;
  dispositivoSn: string;
  dispositivoFw: string;
  operador: string;
  fecha: string;
  proyecto: string;
  lfDtNs?: number;
  lfRows?: number;
  lfCols?: number;
  hfDtNs?: number;
  hfRows?: number;
  hfCols?: number;
  gpsCount: number;
}

export function buildPrompt(ctx: PromptContext): string {
  const { sand, anoms, layers, vel, pw, maxDepthM } = ctx;
  const voids = anoms.filter((a) => a.type === "void");
  const hi = voids.filter((a) => a.risk === "high").length;
  const me = voids.filter((a) => a.risk === "med").length;
  const lo = voids.filter((a) => a.risk === "low").length;
  const totBruto = voids.reduce((t, a) => t + a.vBruto, 0);
  const totNeto = voids.reduce((t, a) => t + a.vNet, 0);

  const layerDesc = [
    "pavimento/hormigon/relleno",
    "zona vadosa no saturada",
    "transicion granular",
    "interfaz freatico/arcilla",
    "roca madre/substrato",
  ];
  const capas = layers.map((l, i) => l.name + " a " + l.depth + "m (" + (layerDesc[i] || "capa") + ")").join("; ");

  const layerOf = (depthM: number): string => {
    let lyr = "Sin clasificar";
    layers.forEach((l) => {
      if (depthM >= l.depth) lyr = l.name;
    });
    return lyr;
  };

  const anomLines = anoms
    .map((a, i) => {
      const iv = a.type === "void";
      const rid = a.risk ? a.risk.toUpperCase() : "?";
      const pct = Math.round(a.conf * 100);
      const rowLF = ctx.lfRows ? Math.round(a.row) : "?";
      const rowHF = ctx.hfRows && ctx.lfRows ? Math.round((a.row / ctx.lfRows) * ctx.hfRows) : "?";
      const hwM = (a.wM / 2).toFixed(3);
      const lyr = iv ? layerOf(a.dM) : "-";
      const distCenter = a.distM;
      const distStart = (a.distM - a.wM / 2).toFixed(1);
      const distEnd = (a.distM + a.wM / 2).toFixed(1);
      return [
        "--- " + (iv ? "HUECO" : "SUMINISTRO") + " " + (i + 1) + " ---------------------------------------------",
        "  Tipo        : " + (iv ? "Hueco/cavidad" : "Infraestructura enterrada") + "   Riesgo: " + rid + "   Confianza: " + pct + "%",
        "  Posicion X  : " + distCenter + " m del inicio  (hiperbola entre " + distStart + "m y " + distEnd + "m)",
        "  Profundidad : " + a.dM + " m (centro)   Capa estratigrafica: " + lyr,
        "  Dimensiones : " + a.wM + " m ancho x " + a.hM + " m alto  (semiancho=" + hwM + "m)",
        "  Semi-ejes   : a=" + a.da.toFixed(4) + "m  b=" + a.db.toFixed(4) + "m  c=" + a.dc.toFixed(4) + "m",
        iv
          ? "  Vol. bruto  : " + a.vBruto + " m3   Vol. neto: " + a.vNet + " m3   (f=" + sand.f + ")"
          : "  Tipo sumin. : tuberia / cable enterrado",
        "  Radargrama  : traza#" + a.col + " - LF fila " + rowLF + "/" + (ctx.lfRows || "?") + (ctx.hfRows ? "  HF fila " + rowHF + "/" + ctx.hfRows : ""),
        a.gpt
          ? "  GPS         : " + a.gpt.lat.toFixed(6) + " N  " + a.gpt.lon.toFixed(6) + " E  elev=" + a.gpt.elev.toFixed(2) + "m"
          : "  GPS         : sin coordenada asociada",
      ].join("\n");
    })
    .join("\n\n");

  return (
    "Eres geotecnico senior especialista en interpretacion de radargramas GPR y evaluacion de riesgos geotecnicos en suelos granulares urbanos. " +
    "Redacta un informe tecnico EXHAUSTIVO, PROFESIONAL y en ESPANOL. Evalua INDIVIDUALMENTE cada anomalia detectada.\n\n" +
    "===================================================================\n" +
    "DATOS DE LA INSPECCION\n" +
    "===================================================================\n" +
    "Equipo     : Proceq GS8000 Pro - S/N: " + ctx.dispositivoSn + " - FW v" + ctx.dispositivoFw + "\n" +
    "Operador   : " + ctx.operador + " - Fecha: " + ctx.fecha + "\n" +
    "Proyecto   : " + ctx.proyecto + "\n" +
    "Canal LF   : " + (ctx.lfDtNs?.toFixed(2) ?? "45") + " ns - " + (ctx.lfRows ?? "369") + " muestras/traza - " + (ctx.lfCols ?? "--") + " trazas\n" +
    "Canal HF   : " + (ctx.hfDtNs?.toFixed(2) ?? "40") + " ns - " + (ctx.hfRows ?? "655") + " muestras/traza" + (ctx.hfCols ? " - " + ctx.hfCols + " trazas" : "") + "\n" +
    "Vel. EM    : " + vel + " m/ns - Prof. max. LF: " + maxDepthM.toFixed(3) + " m - Perfil: " + pw.toFixed(1) + " m\n" +
    "Material   : " + sand.n + " - Porosidad: " + (sand.p * 100).toFixed(0) + "% - er=" + sand.er + " - f_Sanders=" + sand.f + " - Infilt.arena: " + (sand.inf ? "SI" : "NO") + "\n" +
    "Capas      : " + (capas || "No definidas") + "\n" +
    "GPS RTK    : " + ctx.gpsCount + " pts\n\n" +
    "RESUMEN ANOMALIAS: " + anoms.length + " totales -> " + voids.length + " HUECOS (" + hi + " ALTO - " + me + " MEDIO - " + lo + " BAJO) + " + anoms.filter((a) => a.type === "supply").length + " suministros\n" +
    "Vol. bruto total: " + totBruto.toFixed(4) + " m3   Vol. neto total: " + totNeto.toFixed(4) + " m3\n\n" +
    "===================================================================\n" +
    "DATOS DETALLADOS DE CADA ANOMALIA\n" +
    "===================================================================\n" +
    anomLines +
    "\n\n" +
    "===================================================================\n" +
    "INSTRUCCIONES DE REDACCION DEL INFORME\n" +
    "===================================================================\n" +
    "Redacta el informe con las siguientes secciones en ESTE ORDEN EXACTO:\n\n" +
    "## 1. RESUMEN EJECUTIVO\n" +
    "Parrafo de 5-8 lineas con el diagnostico global del subsuelo inspeccionado, estado general de conservacion, " +
    "tipo y distribucion de los huecos detectados, y valoracion del riesgo agregado para la seguridad de las instalaciones.\n\n" +
    "## 2. ANALISIS DETALLADO POR HUECO\n" +
    "Para CADA hueco (H1, H2, H3... hasta el ultimo), redacta un parrafo individual con:\n" +
    "  - Identificacion: ID, distancia en el perfil, profundidad, capa estratigrafica en la que se ubica\n" +
    "  - Descripcion de la firma GPR: forma de la hiperbola en el canal LF (apertura, amplitud, simetria, limpieza), " +
    "confirmacion o matiz en el canal HF (mayor resolucion superficial), presencia de reflexiones multiples o ringing\n" +
    "  - Interpretacion geologica: naturaleza probable (cavidad karstica, vacio en relleno antropico, conducto, " +
    "zona de perdida de finos, fractura abierta, etc.) basada en las dimensiones, profundidad y material\n" +
    "  - Volumen: bruto, neto, semi-ejes, valoracion de fiabilidad del calculo para esta anomalia especifica\n" +
    "  - Justificacion del nivel de riesgo asignado (HIGH/MED/LOW): razona en funcion de profundidad, volumen, " +
    "carga superficial esperada, probabilidad de colapso progresivo y consecuencias\n" +
    "  - Coordenadas GPS si disponibles\n\n" +
    "## 3. PATRON ESPACIAL Y AGRUPACIONES\n" +
    "Analiza la distribucion de los huecos a lo largo del perfil: existen agrupaciones o zonas de concentracion? " +
    "Hay correlacion con la profundidad, el tipo de material o las capas estratigraficas? " +
    "Los huecos sugieren un mecanismo de degradacion puntual o sistemico?\n\n" +
    "## 4. VERIFICACION DEL CALCULO VOLUMETRICO\n" +
    "Evalua la consistencia global del calculo Sanders: margen de error estimado, " +
    "sensibilidad a la velocidad EM asumida (" + vel + " m/ns), y si el volumen total " +
    totBruto.toFixed(4) +
    " m3 bruto / " +
    totNeto.toFixed(4) +
    " m3 neto es coherente " +
    "con las anomalias observadas. Indica los huecos con mayor incertidumbre en la estimacion volumetrica.\n\n" +
    "## 5. CONCLUSIONES Y DIAGNOSTICO FINAL\n" +
    "Diagnostico definitivo del estado del subsuelo con enfasis en los puntos de mayor criticidad. " +
    "Valoracion del riesgo global para las instalaciones.\n\n" +
    "## 6. PLAN DE INTERVENCION PRIORIZADO\n" +
    "Lista ordenada de actuaciones (de mas a menos urgente) con:\n" +
    "  - Identificacion del hueco o zona a tratar\n" +
    "  - Metodo tecnico recomendado (inyeccion de resina expansiva, lechada cementosa, microsilex, " +
    "excavacion controlada, perforacion de confirmacion, monitorizacion con extensometros, etc.)\n" +
    "  - Urgencia y plazo estimado\n\n" +
    "## 7. LIMITACIONES Y CONDICIONANTES\n" +
    "Factores que afectan la precision del analisis: incertidumbre en la velocidad EM, " +
    "limitaciones de resolucion por frecuencia de antena, posibles artefactos, " +
    "zonas no inspeccionadas, recomendacion de tecnicas complementarias (ensayos destructivos, " +
    "tomografia electrica, etc.).\n\n" +
    "IMPORTANTE: el analisis debe ser EXTENSO, TECNICO y RIGUROSO. " +
    "Cada hueco debe recibir su parrafo propio. No omitas ninguno. " +
    "Usa terminologia geotecnica y GPR precisa. Redacta en tercera persona impersonal."
  );
}
