import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF { autoTable: (options: any) => jsPDF; lastAutoTable: { finalY: number }; }
}

export async function POST(req: NextRequest) {
  try {
    const { obraId } = await req.json();
    if (!obraId) return NextResponse.json({ error: "obraId required" }, { status: 400 });

    const supabase = createAdminClient();
    const { data: obra } = await supabase.from("obras").select("*, estado_custom:estados_obra(*), cliente:clientes(nombre, telefono, contacto)").eq("id", obraId).single();
    if (!obra) return NextResponse.json({ error: "Obra not found" }, { status: 404 });

    const { data: checklists } = await supabase.from("checklists").select("*").eq("obra_id", obraId).order("orden");
    const clIds = (checklists || []).map((c: any) => c.id);
    const { data: items } = clIds.length > 0
      ? await supabase.from("checklist_items").select("*").in("checklist_id", clIds).order("orden")
      : { data: [] };

    // Landscape A4, small margins
    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
    const w = doc.internal.pageSize.getWidth(); // ~297
    const h = doc.internal.pageSize.getHeight(); // ~210
    const m = 10; // margin
    const contentW = w - m * 2; // ~277
    let y = m;

    // ---- HEADER ----
    // Small logo
    try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", m, y, 20, 14); } catch {}

    // "INFORME DE OBRA" small
    doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
    doc.text("INFORME DE OBRA", m + 24, y + 4);

    // Obra name BIG
    doc.setFontSize(22); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    const obraName = obra.nombre || "Sin nombre";
    doc.text(obraName, m + 24, y + 13);

    // Date top right
    doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
    doc.text(new Date().toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }), w - m, y + 4, { align: "right" });

    y += 18;

    // Thin red line
    doc.setDrawColor(220, 38, 38); doc.setLineWidth(0.5);
    doc.line(m, y, w - m, y);
    y += 4;

    // ---- INFO ROW ----
    const infoCol = contentW / 4;
    const drawInfo = (label: string, value: string, x: number) => {
      doc.setFontSize(6); doc.setFont("helvetica", "bold"); doc.setTextColor(140, 140, 140);
      doc.text(label, x, y);
      doc.setFontSize(9); doc.setFont("helvetica", "normal"); doc.setTextColor(0, 0, 0);
      doc.text(value || "—", x, y + 4);
    };

    drawInfo("CLIENTE", obra.cliente?.nombre || "—", m);
    drawInfo("DIRECCIÓN", [obra.direccion, obra.localidad, obra.provincia].filter(Boolean).join(", ") || "—", m + infoCol);
    drawInfo("CONTACTO", obra.contacto_obra_nombre || obra.cliente?.contacto || "—", m + infoCol * 2);
    drawInfo("TELÉFONO", obra.contacto_obra_telefono || obra.cliente?.telefono || "—", m + infoCol * 3);

    y += 10;

    // Thin gray line
    doc.setDrawColor(200, 200, 200); doc.setLineWidth(0.2);
    doc.line(m, y, w - m, y);
    y += 4;

    // ---- CHECKLISTS ----
    const colW = contentW / 2; // Each column width
    const checkSize = 5; // Checkbox size in mm
    const rowH = 7; // Row height
    const textOffset = checkSize + 3; // Text offset after checkbox
    const maxTextW = colW - textOffset - 4; // Max text width

    if (!checklists || checklists.length === 0) {
      doc.setFontSize(10); doc.setFont("helvetica", "italic"); doc.setTextColor(150, 150, 150);
      doc.text("Sin checklists", w / 2, y + 10, { align: "center" });
    } else {
      for (const cl of checklists) {
        const clItems = (items || []).filter((i: any) => i.checklist_id === cl.id);
        if (clItems.length === 0) continue;

        // Check if we need a new page
        if (y > h - 25) { doc.addPage(); y = m; }

        // Checklist title
        doc.setFontSize(12); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
        doc.text(cl.titulo.toUpperCase(), m, y + 1);
        doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
        doc.text(`${clItems.length} items`, w - m, y + 1, { align: "right" });
        y += 5;

        // Light gray background for header
        doc.setDrawColor(200, 200, 200); doc.setLineWidth(0.1);
        doc.line(m, y, w - m, y);
        y += 2;

        // Items in 2 columns
        const half = Math.ceil(clItems.length / 2);
        const col1Items = clItems.slice(0, half);
        const col2Items = clItems.slice(half);
        const maxRows = Math.max(col1Items.length, col2Items.length);

        for (let row = 0; row < maxRows; row++) {
          // Check if we need a new page
          if (y + rowH > h - 12) {
            doc.addPage(); y = m;
            // Repeat checklist title on new page
            doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
            doc.text(cl.titulo.toUpperCase() + " (cont.)", m, y + 1);
            y += 5;
          }

          // Alternate row background
          if (row % 2 === 0) {
            doc.setFillColor(250, 250, 250);
            doc.rect(m, y - 1, contentW, rowH, "F");
          }

          // Column 1
          if (col1Items[row]) {
            const item = col1Items[row];
            const x = m + 1;
            // Checkbox
            doc.setDrawColor(180, 180, 180); doc.setLineWidth(0.3);
            doc.setFillColor(255, 255, 255);
            doc.rect(x, y, checkSize, checkSize);
            // Text
            doc.setFontSize(9); doc.setFont("helvetica", "normal"); doc.setTextColor(30, 30, 30);
            const text1 = doc.splitTextToSize(item.texto, maxTextW);
            doc.text(text1[0], x + textOffset, y + 3.5);
          }

          // Column 2
          if (col2Items[row]) {
            const item = col2Items[row];
            const x = m + colW + 1;
            // Separator line between columns
            doc.setDrawColor(220, 220, 220); doc.setLineWidth(0.1);
            doc.line(m + colW, y - 1, m + colW, y + rowH - 1);
            // Checkbox
            doc.setDrawColor(180, 180, 180); doc.setLineWidth(0.3);
            doc.setFillColor(255, 255, 255);
            doc.rect(x, y, checkSize, checkSize);
            // Text
            doc.setFontSize(9); doc.setFont("helvetica", "normal"); doc.setTextColor(30, 30, 30);
            const text2 = doc.splitTextToSize(item.texto, maxTextW);
            doc.text(text2[0], x + textOffset, y + 3.5);
          }

          y += rowH;
        }

        y += 4; // Space between checklists
      }
    }

    // ---- FOOTER ----
    const pageCount = doc.getNumberOfPages();
    for (let i = 1; i <= pageCount; i++) {
      doc.setPage(i);
      doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(180, 180, 180);
      doc.text(`${obra.nombre} — LOYNEK Soluciones Técnicas`, m, h - 5);
      doc.text(`${i}/${pageCount}`, w - m, h - 5, { align: "right" });
    }

    const pdfBase64 = doc.output("datauristring").split(",")[1];
    return NextResponse.json({ pdf: pdfBase64, filename: `informe_${obra.nombre.replace(/\s+/g, "_")}.pdf` });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
