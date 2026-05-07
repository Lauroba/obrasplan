import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF {
    autoTable: (options: any) => jsPDF;
    lastAutoTable: { finalY: number };
  }
}

export async function generatePartePdf(parteId: string): Promise<{ pdf: string; filename: string }> {
  const supabase = createAdminClient();

  const { data: parte } = await supabase.from("partes_diarios").select("*, obra:obras(*), creator:users!partes_diarios_created_by_fkey(nombre)").eq("id", parteId).single();
  if (!parte) throw new Error("Parte not found");

  const { data: lineas } = await supabase.from("parte_lineas").select("*, tipo_trabajo:tipos_trabajo(nombre)").eq("parte_id", parteId).order("orden");

  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const w = doc.internal.pageSize.getWidth();
  const margin = 15;
  let y = 15;

  try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", margin, y, 35, 25); } catch { }

  doc.setFontSize(18);
  doc.setFont("helvetica", "bold");
  doc.text("PARTE DE TRABAJO", w / 2, y + 10, { align: "center" });

  doc.setFontSize(10);
  doc.setFont("helvetica", "normal");
  const fecha = parte.fecha ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long", year: "numeric" }) : "";
  doc.text(fecha, w - margin, y + 10, { align: "right" });

  doc.setFontSize(8);
  doc.text((parte.estado || "").toUpperCase(), w - margin, y + 16, { align: "right" });

  y = 48;
  doc.setDrawColor(220, 38, 38);
  doc.setLineWidth(0.8);
  doc.line(margin, y, w - margin, y);
  y += 6;

  doc.setFillColor(248, 248, 248);
  doc.roundedRect(margin, y, w - margin * 2, 28, 2, 2, "F");

  const labelStyle = () => { doc.setFontSize(7); doc.setFont("helvetica", "bold"); doc.setTextColor(120, 120, 120); };
  const valueStyle = () => { doc.setFontSize(9); doc.setFont("helvetica", "normal"); doc.setTextColor(0, 0, 0); };

  labelStyle(); doc.text("OBRA", margin + 4, y + 5);
  doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
  doc.text(parte.obra?.nombre || "Sin obra", margin + 4, y + 10);

  labelStyle(); doc.text("DIRECCIÓN", margin + 4, y + 14);
  valueStyle(); doc.text(parte.direccion || "—", margin + 4, y + 19);

  labelStyle(); doc.text("LOCALIDAD", w / 2, y + 14);
  valueStyle(); doc.text(parte.localidad || "—", w / 2, y + 19);

  labelStyle(); doc.text("PROVINCIA", margin + 4, y + 23);
  valueStyle(); doc.text(parte.provincia || "—", margin + 4, y + 27);

  y += 34;

  doc.setFillColor(248, 248, 248);
  doc.roundedRect(margin, y, w - margin * 2, 14, 2, 2, "F");
  const cols3 = (w - margin * 2) / 3;

  labelStyle(); doc.text("JEFE DE OBRA", margin + 4, y + 4);
  valueStyle(); doc.text(parte.jefe_obra || "—", margin + 4, y + 10);

  labelStyle(); doc.text("ENCARGADO", margin + cols3 + 4, y + 4);
  valueStyle(); doc.text(parte.encargado_obra || "—", margin + cols3 + 4, y + 10);

  labelStyle(); doc.text("RESPONSABLE", margin + cols3 * 2 + 4, y + 4);
  valueStyle(); doc.text(parte.responsable_empresa || "—", margin + cols3 * 2 + 4, y + 10);

  y += 20;

  labelStyle(); doc.text("CREADO POR", margin, y);
  valueStyle(); doc.text(parte.creator?.nombre || "—", margin + 25, y);
  y += 8;

  if (lineas && lineas.length > 0) {
    doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text("TRABAJOS / MATERIALES", margin, y);
    y += 4;

    doc.autoTable({
      startY: y,
      head: [["Tipo", "Concepto", "Fabricante", "Producto", "Cant.", "Uds."]],
      body: lineas.map((l: any) => [
        l.tipo_trabajo?.nombre || "", l.concepto || "", l.fabricante || "",
        l.producto || "", l.cantidad?.toString() || "", l.unidades || "",
      ]),
      margin: { left: margin, right: margin },
      styles: { fontSize: 8, cellPadding: 2 },
      headStyles: { fillColor: [220, 38, 38], textColor: 255, fontSize: 7, fontStyle: "bold" },
      alternateRowStyles: { fillColor: [250, 250, 250] },
      theme: "grid",
    });
    y = doc.lastAutoTable.finalY + 8;
  }

  if (parte.observaciones) {
    if (y > 230) { doc.addPage(); y = 20; }
    doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text("OBSERVACIONES", margin, y);
    y += 5;
    doc.setFontSize(8); doc.setFont("helvetica", "normal");
    const obsLines = doc.splitTextToSize(parte.observaciones, w - margin * 2);
    doc.text(obsLines, margin, y);
    y += obsLines.length * 4 + 6;
  }

  if (parte.firma_data || parte.firma_cliente) {
    if (y > 210) { doc.addPage(); y = 20; }
    doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text("FIRMAS", margin, y);
    y += 6;
    const sigWidth = (w - margin * 2 - 10) / 2;
    const sigHeight = 30;

    doc.setDrawColor(200, 200, 200); doc.setLineWidth(0.3);
    doc.rect(margin, y, sigWidth, sigHeight);
    doc.rect(margin + sigWidth + 10, y, sigWidth, sigHeight);

    labelStyle();
    doc.text("RESPONSABLE", margin + 2, y + 4);
    doc.text("CLIENTE", margin + sigWidth + 12, y + 4);

    if (parte.firma_data) { try { doc.addImage(parte.firma_data, "PNG", margin + 2, y + 6, sigWidth - 4, sigHeight - 10); } catch { } }
    if (parte.firma_cliente) { try { doc.addImage(parte.firma_cliente, "PNG", margin + sigWidth + 12, y + 6, sigWidth - 4, sigHeight - 10); } catch { } }
  }

  const pageCount = doc.getNumberOfPages();
  for (let i = 1; i <= pageCount; i++) {
    doc.setPage(i);
    doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
    doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", margin, 290);
    doc.text(`Página ${i} de ${pageCount}`, w - margin, 290, { align: "right" });
  }

  const pdfBase64 = doc.output("datauristring").split(",")[1];
  const filename = `parte_${parte.fecha}_${(parte.obra?.nombre || "sin-obra").replace(/\s+/g, "_")}.pdf`;

  return { pdf: pdfBase64, filename };
}
