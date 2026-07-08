/**
 * buildPromptV2.ts
 * Prompt mejorado para Georadar V2:
 * - Clasificación de tuberías por material
 * - Mapa de puntos a revisar
 * - Análisis de continuidad lateral
 * - Firmas GPR detalladas
 * - Sección de artefactos
 */

export interface AnomaliaV2 {
  id: string;          // H1, T1, A1...
  tipo: string;        // hueco | tuberia | artefacto | humedad | junta
  distancia: number;   // metros desde inicio
  profundidad: number; // metros
  riesgo: "alto" | "medio" | "bajo";
  confianza: number;   // 0-100
  ancho?: number;
  alto?: number;
  volBruto?: number;
  volNeto?: number;
  gps?: { lat: number; lon: number; elev: number };
  notas?: string;
}

export interface ContextoV2 {
  proyecto: string;
  operador: string;
  fecha: string;
  equipo: string;
  vel: number;        // m/ns
  er: number;         // constante dieléctrica
  maxDepth: number;   // m
  perfilM: number;    // longitud del perfil en m
  material: string;
  porosidad: number;  // 0-1
  fSanders: number;
  capas: string;
  gpsCount: number;
  lfDt?: number; lfRows?: number; lfCols?: number;
  hfDt?: number; hfRows?: number; hfCols?: number;
  anomalias: AnomaliaV2[];
  // Imágenes base64 (opcional — si se envían, Claude puede analizarlas visualmente)
  imagenLF?: string;  // base64 PNG
  imagenHF?: string;  // base64 PNG
}

export function buildPromptV2(ctx: ContextoV2): string {
  const huecos  = ctx.anomalias.filter(a => a.tipo === "hueco");
  const tubos   = ctx.anomalias.filter(a => a.tipo === "tuberia");
  const artefac = ctx.anomalias.filter(a => a.tipo === "artefacto");
  const otros   = ctx.anomalias.filter(a => !["hueco","tuberia","artefacto"].includes(a.tipo));

  const hi = huecos.filter(a => a.riesgo === "alto").length;
  const me = huecos.filter(a => a.riesgo === "medio").length;
  const lo = huecos.filter(a => a.riesgo === "bajo").length;
  const totBruto = huecos.reduce((s,a) => s + (a.volBruto||0), 0);
  const totNeto  = huecos.reduce((s,a) => s + (a.volNeto||0),  0);

  const fmtAnom = (a: AnomaliaV2, i: number) => [
    `--- ${a.tipo.toUpperCase()} ${a.id} ---`,
    `  Distancia  : ${a.distancia.toFixed(1)} m | Profundidad: ${a.profundidad.toFixed(2)} m`,
    `  Riesgo     : ${a.riesgo.toUpperCase()} | Confianza: ${a.confianza}%${a.confianza < 60 ? " ⚠ VERIFICAR" : ""}`,
    a.ancho ? `  Dimensiones: ${a.ancho.toFixed(2)} m ancho x ${a.alto?.toFixed(2)||"?"} m alto` : "",
    a.volBruto ? `  Volumen    : ${a.volBruto.toFixed(4)} m³ bruto / ${(a.volNeto||0).toFixed(4)} m³ neto` : "",
    a.gps ? `  GPS        : ${a.gps.lat.toFixed(6)}N ${a.gps.lon.toFixed(6)}E elev=${a.gps.elev.toFixed(1)}m` : "  GPS        : sin coordenada",
    a.notas ? `  Notas      : ${a.notas}` : "",
  ].filter(Boolean).join("\n");

  return `Eres un GEOTÉCNICO SENIOR EXPERTO en interpretación de radargramas GPR (Ground Penetrating Radar) \
con experiencia contrastada en inspección de subsuelo urbano, detección de infraestructuras enterradas, \
evaluación de riesgos geotécnicos en suelos granulares y generación de informes técnicos profesionales. \
Redacta un INFORME TÉCNICO EXHAUSTIVO, RIGUROSO y en ESPAÑOL.

===================================================================
DATOS DE LA INSPECCIÓN
===================================================================
Proyecto   : ${ctx.proyecto}
Operador   : ${ctx.operador} | Fecha: ${ctx.fecha}
Equipo     : ${ctx.equipo}
Canal LF   : ${ctx.lfDt?.toFixed(2)??"—"} ns | ${ctx.lfRows??"—"} muestras/traza | ${ctx.lfCols??"—"} trazas
Canal HF   : ${ctx.hfDt?.toFixed(2)??"—"} ns | ${ctx.hfRows??"—"} muestras/traza | ${ctx.hfCols??"—"} trazas
Vel. EM    : ${ctx.vel} m/ns | Prof. máx.: ${ctx.maxDepth.toFixed(2)} m | Perfil: ${ctx.perfilM.toFixed(1)} m
Material   : ${ctx.material} | Porosidad: ${(ctx.porosidad*100).toFixed(0)}% | εr=${ctx.er} | f_Sanders=${ctx.fSanders}
Capas      : ${ctx.capas || "No definidas"}
GPS RTK    : ${ctx.gpsCount} puntos

RESUMEN ANOMALÍAS:
  Huecos/cavidades : ${huecos.length} (${hi} ALTO | ${me} MEDIO | ${lo} BAJO)
  Tuberías/sumin.  : ${tubos.length}
  Artefactos ident.: ${artefac.length}
  Otros            : ${otros.length}
  Vol. bruto total : ${totBruto.toFixed(4)} m³ | Neto: ${totNeto.toFixed(4)} m³

===================================================================
ANOMALÍAS DETECTADAS (DATOS PARA ANÁLISIS)
===================================================================
${ctx.anomalias.map(fmtAnom).join("\n\n")}

===================================================================
INSTRUCCIONES DE REDACCIÓN — SIGUE ESTE ORDEN EXACTO
===================================================================

## 1. RESUMEN EJECUTIVO
Párrafo de 6-10 líneas: diagnóstico global, estado de conservación, \
distribución y naturaleza de anomalías, presencia de infraestructuras, zonas críticas, \
valoración del riesgo agregado para las instalaciones superficiales.

## 2. DATOS DE LA INSPECCIÓN
Tabla resumen con los parámetros del equipo y del perfil. Incluir \
frecuencia efectiva de las antenas LF y HF, resolución vertical teórica (λ/4), \
y penetración máxima estimada.

## 3. INTERPRETACIÓN IA DE RADARGRAMAS
Descripción general de la calidad de la señal a lo largo del perfil: \
zonas de buena penetración, zonas de atenuación, presencia de ruido de fondo, \
calidad del acoplamiento antena-suelo, y observaciones generales sobre la \
estratigrafía visible.

## 4. ANÁLISIS DE HUECOS Y CAVIDADES
Para CADA hueco (${huecos.map(h=>h.id).join(", ")||"ninguno"}), un párrafo individual con:
- **Firma GPR**: forma de hipérbola (apertura, amplitud, simetría, limpieza de flancos), \
presencia de FASE INVERTIDA (reflexión de fase contraria → hueco de aire/agua), \
ringing o reverberaciones múltiples, confirmación en canal HF, continuidad lateral
- **Clasificación de material del relleno**: basada en la atenuación posterior a la reflexión \
(hueco seco = alta amplitud + fase invertida limpia; hueco húmedo = amplitud moderada sin fase inv.)
- **Interpretación geológica**: cavidad kárstica, conducto colapsado, zona de sifonamiento, \
vacío antrópico, cámara de servicio, etc. Justificar con profundidad + material + firma GPR
- **Cálculo volumétrico**: volumen bruto y neto, semi-ejes, fiabilidad del cálculo para \
esta anomalía concreta, rango de incertidumbre estimado (±X%)
- **Nivel de riesgo justificado**: factores considerados (profundidad, volumen, carga \
superficial, probabilidad de colapso progresivo, consecuencias)
- **Coordenadas GPS** si disponibles

## 5. ANÁLISIS DE TUBERÍAS E INFRAESTRUCTURAS ENTERRADAS
Para CADA tubería (${tubos.map(t=>t.id).join(", ")||"ninguna"}):
- **Clasificación por material** (analiza la firma GPR y elige):
  • Metal/acero/fundición: reflexión FUERTE + ringing intenso + fase invertida + hipérbola definida
  • PVC/PEAD: reflexión moderada, SIN ringing, hipérbola menos definida, posible cama visible
  • Hormigón/fibrocemento: reflexión difusa, hipérbola amplia
  • Cable eléctrico: hipérbola muy estrecha (pequeño diámetro), reflexión puntual
  • Llena de agua: sin fase invertida; vacía: con fase invertida + ringing
- **Diámetro estimado** (si la resolución lo permite)
- **Orientación** respecto al eje de medida (transversal=hipérbola clásica; paralela=plana continua)
- **Estado aparente**: buen estado / deteriorada / posible fuga (difusión lateral en radargrama)

## 6. PUNTOS A REVISAR EN CAMPO
Tabla OBLIGATORIA con TODAS las anomalías que requieren verificación, ordenada por urgencia:

| Prioridad | ID | Dist. (m) | Prof. (m) | Tipo | Razón de ambigüedad | Acción recomendada |
|-----------|----|-----------|-----------|----- |---------------------|--------------------|
| URGENTE   | H1 | X.X       | X.X       | Hueco ALTO | Hipérbola clara, fase inv., vol >0.1m³ | Perforación Ø50mm |
| PREFERENTE| T1 | X.X       | X.X       | Tubería | Sin GPS, material incierto | Cruce con planos + EM |
| VIGILAR   | H3 | X.X       | X.X       | Hueco BAJO | Confianza <60%, posible artefacto | Repetir perfil |

Rellenar con los datos reales de las anomalías detectadas.

## 7. ARTEFACTOS E INTERFERENCIAS IDENTIFICADAS
Lista de reflexiones identificadas como NO reales, con criterio de discriminación:
- Ringing de superficie (reflexión repetitiva de la antena en la interfaz aire-suelo)
- Coupling aéreo (reflexión de objetos sobre la superficie durante el barrido)
- Hipérbolas de difracción múltiple por objetos próximos
- Zonas de apantallamiento (shadow zones) por conductores superficiales
- Reflexiones laterales (side-returns) por bordillos, paredes, canalizaciones adyacentes
Si no hay artefactos identificados, indicarlo explícitamente.

## 8. ANÁLISIS DE CONTINUIDAD LATERAL
- Distribución de anomalías a lo largo del perfil: ¿zonas de concentración? ¿patrón espacial?
- ¿Alguna anomalía se repite a intervalos regulares? → posible tubería longitudinal o junta
- ¿Hay reflexión horizontal continua? → posible nivel freático, interfaz de capa, solera
- Correlación entre tuberías y zonas de pérdida de finos o huecos adyacentes
- Mecanismo de degradación: puntual vs. sistémico

## 9. ESTIMACIÓN VOLUMÉTRICA
- Consistencia global del método Sanders con el material: ${ctx.material}
- Sensibilidad a la velocidad EM (${ctx.vel} m/ns): impacto de ±0.01 m/ns en profundidad y volumen
- Volumen bruto: ${totBruto.toFixed(4)} m³ | Neto: ${totNeto.toFixed(4)} m³ (f=${ctx.fSanders})
- Huecos con mayor incertidumbre volumétrica y razones técnicas
- Recomendación de ajuste de velocidad si procede (calibración con hipérbola conocida)

## 10. RIESGO GEOTÉCNICO
- Valoración del riesgo por anomalía y global
- Factores agravantes: profundidad <1m, vol >0.1m³, zona de tráfico pesado, \
cercanía a cimentaciones, suelo granular susceptible de sifonamiento
- Escenario de evolución probable sin intervención: estabilidad, colapso progresivo, \
hundimiento súbito

## 11. PLAN DE INTERVENCIÓN PRIORIZADO
Tabla ordenada por urgencia:

| Prioridad | ID/Zona | Dist. (m) | Actuación | Método técnico | Plazo |
|-----------|---------|-----------|-----------|----------------|-------|
| 1 | H_X | X.X | Relleno confirmado | Inyección resina expansiva | Inmediato |
| 2 | T_X | X.X | Identificación tubería | Detección EM + planos | <2 semanas |
| 3 | H_Y | X.X | Monitorización | Extensómetros + GPR 3 meses | Programado |

Métodos disponibles (usar los aplicables): inyección de resina expansiva bicomponente, \
lechada cementosa/microcemento, microsilícex, perforación de confirmación Ø50-100mm, \
excavación manual controlada, extensómetros/inclinómetros, \
repetición GPR con antena mayor frecuencia (900MHz/1.6GHz), tomografía ERT.

## 12. LIMITACIONES DEL MÉTODO GPR
- Incertidumbre en la velocidad EM y su impacto en profundidad y dimensiones
- Resolución vertical teórica (λ/4 a ${ctx.vel} m/ns): indicar para cada frecuencia
- Zonas de apantallamiento o reflexiones múltiples que pueden ocultar anomalías
- Condiciones del pavimento en el momento del ensayo
- Referencias normativas aplicables (UNE-EN ISO 22476, ASTM D6432, etc.)

## 13. CONCLUSIÓN TÉCNICA FINAL
Diagnóstico definitivo, zonas de máxima criticidad, valoración del riesgo global, \
y necesidad o no de actuación inmediata vs. programada.

---
REGLAS DE REDACCIÓN OBLIGATORIAS:
- Informe EXTENSO, TÉCNICO y RIGUROSO. Mínimo 1500 palabras.
- Cada anomalía recibe su propio párrafo numerado.
- Usar terminología geotécnica y GPR precisa.
- Redactar en TERCERA PERSONA IMPERSONAL.
- Si confianza < 60%: marcar con ⚠ "verificación necesaria en campo".
- NUNCA presentar ninguna interpretación como certeza absoluta.
- El apartado 6 (Puntos a revisar) es OBLIGATORIO aunque solo haya una anomalía.
- Si no hay tuberías: apartado 5 debe indicarlo con razón técnica.
- Disclaimer OBLIGATORIO al final del informe:
  "AVISO: La presente interpretación ha sido generada mediante inteligencia artificial \
como ayuda técnica. No sustituye la revisión de un técnico competente titulado ni \
las comprobaciones en campo. Las profundidades, dimensiones y volúmenes son aproximados \
y deben validarse mediante catas, perforaciones o técnicas complementarias. \
El responsable de la obra es el único con capacidad de validar estas conclusiones."`;
}