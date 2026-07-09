/**
 * src/lib/georadar/generateInformeDocx.ts
 *
 * Genera el informe Word de una pasada de georradar usando docx-js,
 * siguiendo la skill de docx de ObrasPlan (no el generador XML manual de
 * la app HTML original -- decision confirmada explicitamente: se prioriza
 * mantenibilidad sobre fidelidad exacta de formato).
 *
 * Contenido del informe: datos de la pasada, tabla resumen de resultados,
 * tabla de anomalias detectadas, y el texto del analisis IA si existe.
 */

import {
  Document,
  Packer,
  Paragraph,
  TextRun,
  Table,
  TableRow,
  TableCell,
  HeadingLevel,
  AlignmentType,
  BorderStyle,
  WidthType,
  ShadingType,
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
const CONTENT_WIDTH = 9360;

function headerCell(text: string, width: number) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: "1A2438", type: ShadingType.CLEAR },
    margins: { top: 80, bottom: 80, left: 120, right: 120 },
    children: [new Paragraph({ children: [new TextRun({ text, bold: true, color: "FFFFFF", size: 18 })] })],
  });
}

function dataCell(text: string, width: number) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    margins: { top: 80, bottom: 80, left: 120, right: 120 },
    children: [new Paragraph({ children: [new TextRun({ text, size: 18 })] })],
  });
}

export async function generateInformeDocx(d: InformeData): Promise<Buffer> {
  const voids = d.anoms.filter((a) => a.type === "void");
  const supplies = d.anoms.filter((a) => a.type === "supply");
  const hi = voids.filter((a) => a.risk === "high").length;
  const me = voids.filter((a) => a.risk === "med").length;
  const lo = voids.filter((a) => a.risk === "low").length;
  const totBruto = voids.reduce((t, a) => t + a.vBruto, 0);
  const totNeto = voids.reduce((t, a) => t + a.vNet, 0);

  const riskLabel: Record<string, string> = { high: "ALTO", med: "MEDIO", low: "BAJO" };
  const typeLabel: Record<string, string> = { void: "Anomalía", supply: "Suministro", pipe: "Tubería", anomaly: "Anomalía" };

  const resumenRows: [string, string][] = [
    ["Cliente", d.clienteNombre || "-"],
    ["Proyecto", d.proyecto || "-"],
    ["Zona", d.zonaNombre],
    ["Fecha", d.fecha],
    ["Operador", d.operador || "-"],
    ["Equipo", "Proceq GS8000 Pro (S/N " + d.dispositivoSn + ", FW " + d.dispositivoFw + ")"],
    ["Longitud de perfil", d.longitudM.toFixed(1) + " m"],
    ["Velocidad EM", d.velocidadEm + " m/ns"],
    ["Material", d.material.n + " (porosidad " + (d.material.p * 100).toFixed(0) + "%, factor Sanders " + d.material.f + ")"],
  ];

  const resumenTable = new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: [3120, 6240],
    rows: resumenRows.map(
      ([k, v]) =>
        new TableRow({
          children: [
            new TableCell({
              borders,
              width: { size: 3120, type: WidthType.DXA },
              shading: { fill: "F0F2F5", type: ShadingType.CLEAR },
              margins: { top: 80, bottom: 80, left: 120, right: 120 },
              children: [new Paragraph({ children: [new TextRun({ text: k, bold: true, size: 18 })] })],
            }),
            dataCell(v, 6240),
          ],
        })
    ),
  });

  const resultadosRows: [string, string][] = [
    ["Anomalías detectadas", String(voids.length)],
    ["Numero de suministros detectados", String(supplies.length)],
    ["Riesgo ALTO", String(hi)],
    ["Riesgo MEDIO", String(me)],
    ["Riesgo BAJO", String(lo)],
    ["Volumen bruto total", totBruto.toFixed(4) + " m3"],
    ["Volumen neto total", totNeto.toFixed(4) + " m3"],
  ];

  const resultadosTable = new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: [5360, 4000],
    rows: resultadosRows.map(
      ([k, v]) =>
        new TableRow({
          children: [
            new TableCell({
              borders,
              width: { size: 5360, type: WidthType.DXA },
              shading: { fill: "F0F2F5", type: ShadingType.CLEAR },
              margins: { top: 80, bottom: 80, left: 120, right: 120 },
              children: [new Paragraph({ children: [new TextRun({ text: k, bold: true, size: 18 })] })],
            }),
            dataCell(v, 4000),
          ],
        })
    ),
  });

  const anomColWidths = [700, 1400, 1400, 1400, 1860, 2000];
  const anomHeaderRow = new TableRow({
    children: ["ID", "Tipo", "Riesgo", "Profundidad", "Dimensiones", "Vol. bruto / neto"].map((t, i) =>
      headerCell(t, anomColWidths[i])
    ),
  });
  const anomRows = d.anoms.map(
    (a, i) =>
      new TableRow({
        children: [
          dataCell((a.type === "void" || a.type === "anomaly" ? "A" : a.type === "supply" ? "S" : "T") + (i + 1), anomColWidths[0]),
          dataCell(typeLabel[a.type], anomColWidths[1]),
          dataCell(a.risk ? riskLabel[a.risk] : "-", anomColWidths[2]),
          dataCell(a.dM + " m", anomColWidths[3]),
          dataCell(a.wM + " x " + a.hM + " m", anomColWidths[4]),
          dataCell(a.type === "void" ? a.vBruto.toFixed(4) + " / " + a.vNet.toFixed(4) + " m3" : "-", anomColWidths[5]),
        ],
      })
  );
  const anomTable = new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: anomColWidths,
    rows: [anomHeaderRow, ...anomRows],
  });

  const analisisParagraphs: Paragraph[] = [];
  if (d.analisisTexto) {
    analisisParagraphs.push(
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Analisis tecnico (IA)")] })
    );
    analisisParagraphs.push(
      new Paragraph({
        children: [
          new TextRun({ text: "Generado con " + (d.analisisModelo || "modelo IA"), italics: true, size: 16, color: "667085" }),
        ],
        spacing: { after: 200 },
      })
    );
    d.analisisTexto.split("\n").forEach((line) => {
      if (line.trim().startsWith("## ")) {
        analisisParagraphs.push(
          new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(line.replace(/^##\s*/, ""))] })
        );
      } else if (line.trim().length > 0) {
        analisisParagraphs.push(new Paragraph({ children: [new TextRun(line)] }));
      }
    });
  }

  const doc = new Document({
    styles: {
      default: { document: { run: { font: "Arial", size: 22 } } },
      paragraphStyles: [
        {
          id: "Heading1",
          name: "Heading 1",
          basedOn: "Normal",
          next: "Normal",
          quickFormat: true,
          run: { size: 28, bold: true, font: "Arial", color: "1A2438" },
          paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 0 },
        },
        {
          id: "Heading2",
          name: "Heading 2",
          basedOn: "Normal",
          next: "Normal",
          quickFormat: true,
          run: { size: 24, bold: true, font: "Arial", color: "CC1010" },
          paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 1 },
        },
      ],
    },
    sections: [
      {
        properties: {
          page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } },
        },
        children: [
          new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ text: "INFORME DE INTERPRETACION DE GEORRADAR", bold: true, size: 36, color: "CC1010" })],
            spacing: { after: 60 },
          }),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ text: "LOYNEK Soluciones Tecnicas", size: 20, color: "667085" })],
            spacing: { after: 360 },
          }),

          new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Datos de la inspeccion")] }),
          resumenTable,

          new Paragraph({ children: [new TextRun("")], spacing: { after: 200 } }),
          new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Resultados")] }),
          resultadosTable,

          new Paragraph({ children: [new TextRun("")], spacing: { after: 200 } }),
          new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Anomalias detectadas")] }),
          anomTable,

          new Paragraph({ children: [new TextRun("")], spacing: { after: 200 } }),
          ...analisisParagraphs,
        ],
      },
    ],
  });

  return Packer.toBuffer(doc);
}