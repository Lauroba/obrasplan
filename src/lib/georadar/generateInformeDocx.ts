/**
 * src/lib/georadar/generateInformeDocx.ts
 *
 * Genera el informe Word de una pasada de georradar para Georadar V2.
 * Sin referencias a niveles de riesgo.
 * Incluye sección de mapa de localización.
 */

import {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  HeadingLevel, AlignmentType, BorderStyle, WidthType, ShadingType,
} from "docx";
import type { AnomalyResult, LayerResult, SandersEntry } from "./detectAnomalies";

export interface InformeData {
  clienteNombre: string;
  proyecto: string;
  zonaNombre: string;
  fecha: string;
  operador: string;
  dispositivoSn: string;
  dispositivoFw: string;
  longitudM: number;
  velocidadEm: number;
  material: SandersEntry;
  anoms: AnomalyResult[];
  layers: LayerResult[];
  analisisTexto?: string;
  analisisModelo?: string;
}

const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const W = 9360; // ancho contenido en twips (A4 - márgenes)

// ── Helpers ──────────────────────────────────────────────────────────────

function headerCell(text: string, width: number, shade = "1F4E79") {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    shading: { type: ShadingType.SOLID, color: shade },
    borders,
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text, bold: true, color: "FFFFFF", size: 18 })],
    })],
  });
}

function dataCell(text: string, width: number, bold = false, color?: string) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    children: [new Paragraph({
      children: [new TextRun({ text: text ?? "—", bold, color: color || "000000", size: 18 })],
    })],
  });
}

function h1(text: string) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 300, after: 100 },
    children: [new TextRun({ text, bold: true, color: "1F4E79", size: 28 })],
  });
}

function h2(text: string) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 200, after: 80 },
    children: [new TextRun({ text, bold: true, color: "2E74B5", size: 22 })],
  });
}

function p(text: string, opts: { italics?: boolean; size?: number; color?: string } = {}) {
  return new Paragraph({
    spacing: { before: 60, after: 60 },
    children: [new TextRun({
      text,
      italics: opts.italics,
      size: opts.size || 20,
      color: opts.color || "222222",
    })],
  });
}

function separator() {
  return new Paragraph({
    spacing: { before: 120, after: 120 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: "1F4E79" } },
    children: [],
  });
}

function infoRow(label: string, value: string) {
  return new TableRow({
    children: [
      new TableCell({
        width: { size: 3000, type: WidthType.DXA },
        shading: { type: ShadingType.SOLID, color: "EEF2F7" },
        borders,
        children: [new Paragraph({
          children: [new TextRun({ text: label, bold: true, size: 18, color: "333333" })],
        })],
      }),
      new TableCell({
        width: { size: 6360, type: WidthType.DXA },
        borders,
        children: [new Paragraph({
          children: [new TextRun({ text: value || "—", size: 18 })],
        })],
      }),
    ],
  });
}

// ── Tipo de anomalía legible ───────────────────────────────────────────

function tipoLabel(type: string): string {
  const map: Record<string, string> = {
    void: "Anomalía", anomaly: "Anomalía",
    supply: "Suministro", pipe: "Tubería",
  };
  return map[type] || "Anomalía";
}

function tipoLetra(type: string, idx: number): string {
  const map: Record<string, string> = {
    void: "A", anomaly: "A", supply: "S", pipe: "T",
  };
  return (map[type] || "A") + (idx + 1);
}

// ── Función principal ─────────────────────────────────────────────────

export async function generateInformeDocx(d: InformeData): Promise<Blob> {
  const allAnoms = d.anoms;
  const anomalias = allAnoms.filter(a => a.type === "void" || a.type === "anomaly");
  const suministros = allAnoms.filter(a => a.type === "supply");
  const tuberias = allAnoms.filter(a => a.type === "pipe");
  const maxDepth = d.longitudM > 0 ? (d.velocidadEm * (d.material.er ?? 9) * 1) : 2;
  const colW = [900, 1400, 1400, 1400, 1400, 1800, 1860];

  // ── Portada ─────────────────────────────────────────────────────────
  const portada: Paragraph[] = [
    new Paragraph({ spacing: { before: 1400, after: 200 }, children: [] }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: "INFORME DE PROSPECCIÓN GEORRADAR GPR", bold: true, size: 40, color: "1F4E79" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 200, after: 600 },
      children: [new TextRun({ text: "Ground Penetrating Radar — Análisis de Subsuelo", size: 24, color: "666666", italics: true })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 100, after: 100 },
      children: [new TextRun({ text: `Proyecto: ${d.proyecto || "—"}`, bold: true, size: 24, color: "222222" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 60 },
      children: [new TextRun({ text: `Cliente: ${d.clienteNombre || "—"}`, size: 22, color: "444444" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 60 },
      children: [new TextRun({ text: `Zona: ${d.zonaNombre || "—"}`, size: 22, color: "444444" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 60 },
      children: [new TextRun({ text: `Fecha: ${d.fecha}`, size: 22, color: "444444" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 600 },
      children: [new TextRun({ text: `Operador: ${d.operador}`, size: 22, color: "444444" })],
    }),
  ];

  // ── 1. Datos de la inspección ────────────────────────────────────────
  const seccionDatos = [
    h2("1. DATOS DE LA INSPECCIÓN"),
    new Table({
      width: { size: W, type: WidthType.DXA },
      rows: [
        infoRow("Proyecto", d.proyecto),
        infoRow("Cliente", d.clienteNombre),
        infoRow("Zona / Perfil", d.zonaNombre),
        infoRow("Fecha", d.fecha),
        infoRow("Operador", d.operador),
        infoRow("Equipo GPR", `Proceq GS8000 (S/N: ${d.dispositivoSn}, FW: ${d.dispositivoFw})`),
        infoRow("Longitud del perfil", `${d.longitudM.toFixed(1)} m`),
        infoRow("Velocidad EM", `${d.velocidadEm} m/ns`),
        infoRow("Material estimado", d.material.n || "—"),
        infoRow("Anomalías detectadas", String(anomalias.length)),
        infoRow("Suministros detectados", String(suministros.length)),
        infoRow("Tuberías detectadas", String(tuberias.length)),
      ],
    }),
  ];

  // ── 2. Metodología ───────────────────────────────────────────────────
  const seccionMetodo = [
    h2("2. METODOLOGÍA"),
    p("La prospección se ha realizado mediante la tecnología GPR (Ground Penetrating Radar) utilizando el sistema Proceq GS8000 de doble antena (canal LF y canal HF). El equipo emite pulsos electromagnéticos de alta frecuencia que penetran en el subsuelo y registran las reflexiones producidas por cambios en las propiedades dieléctricas de los materiales."),
    p("Los datos han sido procesados mediante el algoritmo de detección de anomalías Sanders, que calcula el volumen de cada anomalía a partir de sus dimensiones estimadas y de los parámetros físicos del material encajante. La velocidad de propagación electromagnética utilizada ha sido de " + d.velocidadEm + " m/ns, correspondiente a material tipo " + (d.material.n || "arena húmeda") + "."),
    p("Los resultados deben ser considerados orientativos y complementados con comprobaciones en campo cuando sea necesario.", { italics: true, color: "666666" }),
  ];

  // ── 3. Mapa de localización ──────────────────────────────────────────
  const seccionMapa: (Paragraph | Table)[] = [h2("3. MAPA DE LOCALIZACIÓN DE ELEMENTOS DETECTADOS")];

  seccionMapa.push(
    p("Nota: el mapa de localización se puede visualizar en la aplicación Georadar V2 activando la vista Google Maps con los elementos detectados.", { italics: true, color: "888888" })
  );

  // Leyenda del mapa
  seccionMapa.push(
    new Paragraph({ spacing: { before: 120, after: 60 }, children: [new TextRun({ text: "Leyenda de símbolos:", bold: true, size: 20 })] }),
    new Table({
      width: { size: 5000, type: WidthType.DXA },
      rows: [
        new TableRow({ children: [
          new TableCell({ borders, width: { size: 600, type: WidthType.DXA }, shading: { type: ShadingType.SOLID, color: "DC2626" }, children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "A", bold: true, color: "FFFFFF", size: 20 })] })] }),
          dataCell("Anomalía (cavidad, discontinuidad, zona alterada)", 4400),
        ]}),
        new TableRow({ children: [
          new TableCell({ borders, width: { size: 600, type: WidthType.DXA }, shading: { type: ShadingType.SOLID, color: "2563EB" }, children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "S", bold: true, color: "FFFFFF", size: 20 })] })] }),
          dataCell("Suministro (infraestructura enterrada identificada)", 4400),
        ]}),
        new TableRow({ children: [
          new TableCell({ borders, width: { size: 600, type: WidthType.DXA }, shading: { type: ShadingType.SOLID, color: "D97706" }, children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "T", bold: true, color: "FFFFFF", size: 20 })] })] }),
          dataCell("Tubería (conducción identificada)", 4400),
        ]}),
      ],
    })
  );

  // ── 4. Tabla de resultados ───────────────────────────────────────────
  const seccionTabla: (Paragraph | Table)[] = [
    h2("4. TABLA DE RESULTADOS"),
    p(`Se han detectado un total de ${allAnoms.length} elemento(s) a lo largo del perfil de ${d.longitudM.toFixed(1)} m.`),
  ];

  if (allAnoms.length === 0) {
    seccionTabla.push(p("No se han detectado anomalías significativas en el perfil analizado."));
  } else {
    seccionTabla.push(
      new Table({
        width: { size: W, type: WidthType.DXA },
        rows: [
          new TableRow({
            tableHeader: true,
            children: [
              headerCell("ID", colW[0]),
              headerCell("Tipo", colW[1]),
              headerCell("Distancia (m)", colW[2]),
              headerCell("Profundidad (m)", colW[3]),
              headerCell("Ancho × Alto (m)", colW[4]),
              headerCell("Vol. neto (m³)", colW[5]),
              headerCell("Coordenadas GPS", colW[6]),
            ],
          }),
          ...allAnoms.map((a, i) => new TableRow({
            children: [
              dataCell(tipoLetra(a.type, i), colW[0], true),
              dataCell(tipoLabel(a.type), colW[1]),
              dataCell(String(a.distM), colW[2]),
              dataCell(String(a.dM), colW[3]),
              dataCell(`${a.wM} × ${a.hM}`, colW[4]),
              dataCell(a.type === "void" || a.type === "anomaly" ? a.vNet.toFixed(4) : "—", colW[5]),
              dataCell(a.gpt ? `${a.gpt.lat.toFixed(5)}, ${a.gpt.lon.toFixed(5)}` : "Sin GPS", colW[6]),
            ],
          })),
        ],
      })
    );
  }

  // ── 5. Interpretación IA ─────────────────────────────────────────────
  const seccionIA = [
    h2("5. INTERPRETACIÓN TÉCNICA"),
  ];
  if (d.analisisTexto) {
    seccionIA.push(
      p(`Análisis generado mediante ${d.analisisModelo || "IA"}.`, { italics: true, color: "666666", size: 18 }),
      new Paragraph({
        spacing: { before: 100, after: 100 },
        children: [new TextRun({ text: d.analisisTexto, size: 18, color: "222222" })],
      })
    );
  } else {
    seccionIA.push(p("No se ha realizado análisis IA. Ejecutar el análisis desde la aplicación Georadar V2 antes de generar el informe.", { italics: true, color: "888888" }));
  }

  // ── 6. Conclusiones ──────────────────────────────────────────────────
  const seccionConclusiones = [
    h2("6. CONCLUSIONES Y RECOMENDACIONES"),
    p(`La prospección GPR ha identificado ${allAnoms.length} elemento(s) de interés a lo largo del perfil de ${d.longitudM.toFixed(1)} m, entre los que se encuentran ${anomalias.length} anomalía(s), ${suministros.length} suministro(s) y ${tuberias.length} tubería(s).`),
    p("Se recomienda complementar los resultados con catas o sondeos de comprobación en los puntos de mayor interés, especialmente donde las anomalías presentan mayor volumen estimado o se sitúan a menor profundidad."),
    p("Los resultados de esta prospección tienen carácter orientativo y deben ser interpretados por un técnico competente.", { italics: true, color: "666666" }),
  ];

  // ── 7. Limitaciones ─────────────────────────────────────────────────
  const seccionLimitaciones = [
    h2("7. LIMITACIONES DEL MÉTODO"),
    ...[
      "La profundidad de penetración depende del contenido de agua y las propiedades del suelo.",
      "La velocidad EM asumida introduce incertidumbre en las profundidades y dimensiones estimadas (±10-15%).",
      "Objetos de dimensiones inferiores a λ/4 pueden no ser detectados.",
      "La presencia de materiales conductivos (arcillas saturadas, cables) reduce la penetración.",
      "Este informe ha sido generado con asistencia de herramientas de procesado digital y, en su caso, IA. No sustituye la revisión de un técnico titulado ni las comprobaciones en campo.",
    ].map(t => new Paragraph({
      spacing: { before: 60, after: 60 },
      bullet: { level: 0 },
      children: [new TextRun({ text: t, size: 18, color: "444444" })],
    })),
  ];

  // ── Ensamblar documento ─────────────────────────────────────────────
  const doc = new Document({
    styles: {
      default: {
        document: { run: { font: "Calibri", size: 20, color: "222222" } },
      },
    },
    sections: [{
      properties: { page: { margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } },

      children: [
        ...portada,
        separator(),
        h1("INFORME DE PROSPECCIÓN GEORRADAR"),
        ...seccionDatos,
        separator(),
        ...seccionMetodo,
        separator(),
        ...seccionMapa,
        separator(),
        ...seccionTabla,
        separator(),
        ...seccionIA,
        separator(),
        ...seccionConclusiones,
        separator(),
        ...seccionLimitaciones,
      ],
    }],
  });

  return await Packer.toBlob(doc);
}