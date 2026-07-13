import { createAdminClient } from "@/lib/supabase/admin";
// sharp viene incluido con Next.js 14 — no necesita instalación separada
// eslint-disable-next-line @typescript-eslint/no-require-imports
const sharp = require("sharp") as typeof import("sharp").default;
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF {
    autoTable: (options: any) => jsPDF;
    lastAutoTable: { finalY: number };
  }
}

const PAGE_H  = 297;
const PAGE_W  = 210;
const MARGIN  = 15;
const FOOTER_Y = 290;

// ── Helpers de estilo ─────────────────────────────────────────────────────────
function label(doc: jsPDF) {
  doc.setFontSize(7);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(120, 120, 120);
}
function value(doc: jsPDF) {
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.setTextColor(0, 0, 0);
}
function sectionTitle(doc: jsPDF, text: string, y: number) {
  doc.setFontSize(9);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(220, 38, 38);
  doc.text(text, MARGIN, y);
  doc.setDrawColor(220, 38, 38);
  doc.setLineWidth(0.3);
  doc.line(MARGIN, y + 1.5, PAGE_W - MARGIN, y + 1.5);
  doc.setTextColor(0, 0, 0);
  return y + 6;
}
function addFooters(doc: jsPDF) {
  const total = doc.getNumberOfPages();
  for (let i = 1; i <= total; i++) {
    doc.setPage(i);
    doc.setFontSize(7);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(150, 150, 150);
    doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", MARGIN, FOOTER_Y);
    doc.text(`Página ${i} de ${total}`, PAGE_W - MARGIN, FOOTER_Y, { align: "right" });
  }
}
function checkPage(doc: jsPDF, y: number, need = 20): number {
  if (y + need > FOOTER_Y - 5) {
    doc.addPage();
    return 20;
  }
  return y;
}

// ── Función principal ─────────────────────────────────────────────────────────
export async function generatePartePdf(
  parteId: string
): Promise<{ pdf: string; filename: string }> {
  const supabase = createAdminClient();

  const { data: parte } = await supabase
    .from("partes_diarios")
    .select("*, obra:obras(*), creator:users!partes_diarios_created_by_fkey(nombre)")
    .eq("id", parteId)
    .single();
  if (!parte) throw new Error("Parte not found");

  // Documentos (fotos y otros)
  const { data: docs } = await supabase
    .from("documentos")
    .select("nombre_archivo, storage_path, tipo")
    .eq("parte_id", parteId);

  const fotos = (docs || []).filter(
    (d) => d.tipo === "foto" || /\.(jpg|jpeg|png|webp|gif)$/i.test(d.nombre_archivo)
  );
  const otrosDocs = (docs || []).filter(
    (d) => !fotos.includes(d)
  );

  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const w = PAGE_W;
  let y = 15;

  // ── CABECERA ────────────────────────────────────────────────────────────────
  try {
    doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", MARGIN, y, 32, 22);
  } catch {}

  const fecha = parte.fecha
    ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", {
        weekday: "long", day: "numeric", month: "long", year: "numeric",
      })
    : "";
  const creador = parte.creator?.nombre || parte.creator?.email || "—";

  doc.setFontSize(16);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(0, 0, 0);
  doc.text("PARTE DE TRABAJO", w / 2, y + 8, { align: "center" });

  // Obra destacada en la cabecera
  doc.setFontSize(11);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(220, 38, 38);
  doc.text(parte.obra?.nombre || "Sin obra", w / 2, y + 15, { align: "center" });

  // Fecha y creador
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.setTextColor(60, 60, 60);
  doc.text(fecha, w / 2, y + 21, { align: "center" });
  doc.setFontSize(8);
  doc.setTextColor(100, 100, 100);
  doc.text(`Creado por: ${creador}`, w / 2, y + 26, { align: "center" });

  // Estado (derecha)
  doc.setFontSize(8);
  doc.setTextColor(150, 150, 150);
  doc.text((parte.estado || "").toUpperCase(), w - MARGIN, y + 8, { align: "right" });
  doc.setTextColor(0, 0, 0);

  y = 44;
  doc.setDrawColor(220, 38, 38);
  doc.setLineWidth(0.8);
  doc.line(MARGIN, y, w - MARGIN, y);
  y += 5;

  // ── DATOS DE LA OBRA ────────────────────────────────────────────────────────
  y = sectionTitle(doc, "DATOS DE LA OBRA", y);

  doc.setFillColor(248, 249, 250);
  doc.roundedRect(MARGIN, y, w - MARGIN * 2, 22, 2, 2, "F");

  // Dirección, localidad y provincia — la obra ya aparece en cabecera
  const midX = w / 2;
  label(doc); doc.text("DIRECCIÓN", MARGIN + 4, y + 5);
  value(doc); doc.text(parte.direccion || "—", MARGIN + 4, y + 11);

  label(doc); doc.text("LOCALIDAD", midX + 4, y + 5);
  value(doc); doc.text(parte.localidad || "—", midX + 4, y + 11);

  label(doc); doc.text("PROVINCIA", MARGIN + 4, y + 16);
  value(doc); doc.text(parte.provincia || "—", MARGIN + 4, y + 21);
  y += 28;

  // ── RESPONSABLES ────────────────────────────────────────────────────────────
  y = checkPage(doc, y, 22);
  y = sectionTitle(doc, "RESPONSABLES", y);

  doc.setFillColor(248, 249, 250);
  doc.roundedRect(MARGIN, y, w - MARGIN * 2, 16, 2, 2, "F");
  const col3 = (w - MARGIN * 2) / 3;

  label(doc); doc.text("JEFE DE OBRA", MARGIN + 4, y + 5);
  value(doc); doc.text(parte.jefe_obra || "—", MARGIN + 4, y + 11);

  label(doc); doc.text("ENCARGADO", MARGIN + col3 + 4, y + 5);
  value(doc); doc.text(parte.encargado_obra || "—", MARGIN + col3 + 4, y + 11);

  label(doc); doc.text("EMPRESA RESPONSABLE", MARGIN + col3 * 2 + 4, y + 5);
  value(doc); doc.text(parte.responsable_empresa || "—", MARGIN + col3 * 2 + 4, y + 11);
  y += 22;

  y += 4; // (creador ya aparece en la cabecera del parte)

  // ── OBSERVACIONES ───────────────────────────────────────────────────────────
  if (parte.observaciones) {
    y = checkPage(doc, y, 30);
    y = sectionTitle(doc, "OBSERVACIONES", y);
    doc.setFontSize(8);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(0, 0, 0);
    const lines = doc.splitTextToSize(parte.observaciones, w - MARGIN * 2);
    doc.text(lines, MARGIN, y);
    y += lines.length * 4 + 8;
  }

  // ── DOCUMENTOS ADJUNTOS (no fotos) ──────────────────────────────────────────
  if (otrosDocs.length > 0) {
    y = checkPage(doc, y, 20);
    y = sectionTitle(doc, "DOCUMENTOS ADJUNTOS", y);
    doc.setFontSize(8);
    doc.setFont("helvetica", "normal");
    for (const d of otrosDocs) {
      y = checkPage(doc, y, 6);
      doc.text(`• ${d.nombre_archivo}`, MARGIN + 2, y);
      y += 5;
    }
    y += 4;
  }

  // ── FIRMA DEL CLIENTE ────────────────────────────────────────────────────────
  y = checkPage(doc, y, 50);
  y = sectionTitle(doc, "FIRMA DEL CLIENTE", y);

  const sigW = 80;
  const sigH = 35;
  doc.setDrawColor(180, 180, 180);
  doc.setLineWidth(0.3);
  doc.roundedRect(MARGIN, y, sigW, sigH, 2, 2);

  if (parte.firma_cliente) {
    try {
      doc.addImage(parte.firma_cliente, "PNG", MARGIN + 2, y + 2, sigW - 4, sigH - 4);
    } catch {}
  }

  doc.setFillColor(240, 240, 240);
  doc.rect(MARGIN, y + sigH, sigW, 6, "F");
  label(doc);
  doc.text("Firma del cliente", MARGIN + sigW / 2, y + sigH + 4, { align: "center" });
  y += sigH + 12;

  // ── FOTOS (3 por página) ──────────────────────────────────────────────────────
  if (fotos.length > 0) {
    doc.addPage();
    y = 20;
    y = sectionTitle(doc, `FOTOGRAFÍAS (${fotos.length})`, y);
    y += 2;

    const imgW  = (w - MARGIN * 2 - 8) / 2; // 2 columnas
    const imgH  = 65;
    const perPage = 3;  // 3 fotos por página (2 arriba, 1 abajo centrada)

    let slot = 0;
    for (let i = 0; i < fotos.length; i++) {
      const foto = fotos[i];

      // Cada 3 fotos: nueva página
      if (i > 0 && i % perPage === 0) {
        doc.addPage();
        y = 20;
        y = sectionTitle(doc, `FOTOGRAFÍAS (cont.)`, y);
        y += 2;
        slot = 0;
      }

      slot = i % perPage;

      // Layout: fila 0 = izquierda, fila 1 = derecha, fila 2 = centrada
      let imgX: number;
      let rowY: number;
      if (slot === 0) {
        imgX = MARGIN;
        rowY = y;
      } else if (slot === 1) {
        imgX = MARGIN + imgW + 8;
        rowY = y;
      } else {
        // 3ª foto: nueva fila, centrada
        rowY = y + imgH + 14;
        imgX = MARGIN + (w - MARGIN * 2 - imgW) / 2;
      }

      // Descargar y comprimir imagen antes de insertar en PDF
      try {
        const { data: signedData } = await supabase.storage
          .from("documentos")
          .createSignedUrl(foto.storage_path, 60);

        if (signedData?.signedUrl) {
          const resp = await fetch(signedData.signedUrl);
          const rawBuf = Buffer.from(await resp.arrayBuffer());

          // Comprimir con sharp: max 1200px, JPEG 72%
          // Una foto de movil pasa de ~5MB a ~150-300KB
          const compressed = await sharp(rawBuf)
            .resize({ width: 1200, height: 1200, fit: "inside", withoutEnlargement: true })
            .jpeg({ quality: 72, progressive: false })
            .toBuffer();

          const b64 = compressed.toString("base64");
          const dataUri = `data:image/jpeg;base64,${b64}`;

          // Recuadro
          doc.setDrawColor(200, 200, 200);
          doc.setLineWidth(0.3);
          doc.roundedRect(imgX, rowY, imgW, imgH, 2, 2);
          doc.addImage(dataUri, "JPEG", imgX + 1, rowY + 1, imgW - 2, imgH - 8);

          // Nombre del archivo
          doc.setFontSize(6);
          doc.setFont("helvetica", "normal");
          doc.setTextColor(100, 100, 100);
          const shortName = foto.nombre_archivo.length > 28
            ? foto.nombre_archivo.substring(0, 25) + "..."
            : foto.nombre_archivo;
          doc.text(shortName, imgX + imgW / 2, rowY + imgH - 2, { align: "center" });
        }
      } catch { /* si falla una imagen, continuar sin ella */ }

      // Avanzar y cuando completamos la fila 2 o es la última
      if (slot === 2 || i === fotos.length - 1) {
        y = (slot === 2 ? y + imgH + 14 : y) + imgH + 14;
      }
    }
  }

  addFooters(doc);

  const pdfBase64 = doc.output("datauristring").split(",")[1];
  const filename = `parte_${parte.fecha}_${
    (parte.obra?.nombre || "sin-obra").replace(/\s+/g, "_")
  }.pdf`;

  return { pdf: pdfBase64, filename };
}