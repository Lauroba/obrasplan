import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

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

    // Landscape A4, tight margins
    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
    const w = doc.internal.pageSize.getWidth(); // 297
    const h = doc.internal.pageSize.getHeight(); // 210
    const m = 8; // margin
    const contentW = w - m * 2; // 281
    const colW = contentW / 2; // 140.5
    const checkSize = 8; // big checkbox
    const rowH = 14; // big row height
    const textSize = 12; // big text
    const textOffset = checkSize + 4;
    const maxTextW = colW - textOffset - 4;

    let pageNum = 0;

    const drawHeader = () => {
      let y = m;
      // Small logo
      try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", m, y, 18, 13); } catch {}

      // "INFORME DE OBRA" small
      doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
      doc.text("INFORME DE OBRA", m + 22, y + 4);

      // Obra name BIG
      doc.setFontSize(24); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
      doc.text(obra.nombre || "", m + 22, y + 13);

      // Date top right
      doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
      doc.text(new Date().toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }), w - m, y + 4, { align: "right" });

      y += 17;

      // Red line
      doc.setDrawColor(220, 38, 38); doc.setLineWidth(0.5);
      doc.line(m, y, w - m, y);
      y += 3;

      // Info row
      const infoCol = contentW / 4;
      const drawInfo = (label: string, value: string, x: number) => {
        doc.setFontSize(6); doc.setFont("helvetica", "bold"); doc.setTextColor(140, 140, 140);
        doc.text(label, x, y);
        doc.setFontSize(9); doc.setFont("helvetica", "normal"); doc.setTextColor(0, 0, 0);
        const val = value || "—";
        doc.text(val.length > 40 ? val.substring(0, 40) + "..." : val, x, y + 4);
      };

      drawInfo("CLIENTE", obra.cliente?.nombre || "—", m);
      drawInfo("DIRECCIÓN", [obra.direccion, obra.localidad, obra.provincia].filter(Boolean).join(", ") || "—", m + infoCol);
      drawInfo("CONTACTO", obra.contacto_obra_nombre || obra.cliente?.contacto || "—", m + infoCol * 2);
      drawInfo("TELÉFONO", obra.contacto_obra_telefono || obra.cliente?.telefono || "—", m + infoCol * 3);

      y += 8;

      // Gray line
      doc.setDrawColor(200, 200, 200); doc.setLineWidth(0.2);
      doc.line(m, y, w - m, y);
      y += 3;

      return y;
    };

    const drawFooter = () => {
      doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(180, 180, 180);
      doc.text(`${obra.nombre} — LOYNEK Soluciones Técnicas`, m, h - 4);
      doc.text(`${doc.getNumberOfPages()}`, w - m, h - 4, { align: "right" });
    };

    const startY = drawHeader();
    let y = startY;
    const bottomLimit = h - 10;

    // Calculate rows that fit per page (after header)
    const rowsFirstPage = Math.floor((bottomLimit - startY - 10) / rowH); // subtract checklist title space
    const rowsNextPage = Math.floor((bottomLimit - m - 8) / rowH);

    if (!checklists || checklists.length === 0) {
      doc.setFontSize(12); doc.setFont("helvetica", "italic"); doc.setTextColor(150, 150, 150);
      doc.text("Sin checklists", w / 2, y + 20, { align: "center" });
    } else {
      for (let clIdx = 0; clIdx < checklists.length; clIdx++) {
        const cl = checklists[clIdx];
        const clItems = (items || []).filter((i: any) => i.checklist_id === cl.id);
        if (clItems.length === 0) continue;

        // If this is not the first checklist and we don't have much space, new page
        if (clIdx > 0 && y + rowH * 3 > bottomLimit) {
          drawFooter();
          doc.addPage();
          y = drawHeader();
        }

        // Checklist title
        doc.setFontSize(13); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
        doc.text(cl.titulo.toUpperCase(), m, y + 2);
        doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
        doc.text(`${clItems.length} items`, w - m, y + 2, { align: "right" });
        y += 6;

        // Thin line under title
        doc.setDrawColor(220, 220, 220); doc.setLineWidth(0.1);
        doc.line(m, y, w - m, y);
        y += 2;

        // Split into 2 columns
        const half = Math.ceil(clItems.length / 2);
        const col1 = clItems.slice(0, half);
        const col2 = clItems.slice(half);
        const maxRows = Math.max(col1.length, col2.length);

        for (let row = 0; row < maxRows; row++) {
          // New page if needed
          if (y + rowH > bottomLimit) {
            drawFooter();
            doc.addPage();
            y = m + 2;
            // Mini header on continuation page
            doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
            doc.text(cl.titulo.toUpperCase() + " (cont.)", m, y + 2);
            y += 7;
          }

          // Alternating row bg
          if (row % 2 === 0) {
            doc.setFillColor(248, 248, 248);
            doc.rect(m, y - 1.5, contentW, rowH, "F");
          }

          // Column 1
          if (col1[row]) {
            const x = m + 2;
            const centerY = y + (rowH - checkSize) / 2;
            // Checkbox
            doc.setDrawColor(160, 160, 160); doc.setLineWidth(0.4);
            doc.setFillColor(255, 255, 255);
            doc.roundedRect(x, centerY, checkSize, checkSize, 1, 1);
            // Text
            doc.setFontSize(textSize); doc.setFont("helvetica", "normal"); doc.setTextColor(20, 20, 20);
            const t1 = doc.splitTextToSize(col1[row].texto, maxTextW);
            doc.text(t1[0], x + textOffset, y + rowH / 2 + 1);
          }

          // Column separator
          doc.setDrawColor(230, 230, 230); doc.setLineWidth(0.1);
          doc.line(m + colW, y - 1.5, m + colW, y + rowH - 1.5);

          // Column 2
          if (col2[row]) {
            const x = m + colW + 2;
            const centerY = y + (rowH - checkSize) / 2;
            // Checkbox
            doc.setDrawColor(160, 160, 160); doc.setLineWidth(0.4);
            doc.setFillColor(255, 255, 255);
            doc.roundedRect(x, centerY, checkSize, checkSize, 1, 1);
            // Text
            doc.setFontSize(textSize); doc.setFont("helvetica", "normal"); doc.setTextColor(20, 20, 20);
            const t2 = doc.splitTextToSize(col2[row].texto, maxTextW);
            doc.text(t2[0], x + textOffset, y + rowH / 2 + 1);
          }

          y += rowH;
        }

        y += 5; // Space between checklists
      }
    }

    // Final footer on all pages
    const totalPages = doc.getNumberOfPages();
    for (let i = 1; i <= totalPages; i++) {
      doc.setPage(i);
      doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(180, 180, 180);
      doc.text(`${obra.nombre} — LOYNEK Soluciones Técnicas`, m, h - 4);
      doc.text(`${i}/${totalPages}`, w - m, h - 4, { align: "right" });
    }

    const pdfBase64 = doc.output("datauristring").split(",")[1];
    return NextResponse.json({ pdf: pdfBase64, filename: `informe_${obra.nombre.replace(/\s+/g, "_")}.pdf` });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
