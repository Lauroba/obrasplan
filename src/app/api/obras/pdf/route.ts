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

    // Fetch all data
    const [obraR, asigR, checkR, tiposR, notasR, responsableR] = await Promise.all([
      supabase.from("obras").select("*, estado_custom:estados_obra(*), cliente:clientes(nombre, nif, tipo_cliente)").eq("id", obraId).single(),
      supabase.from("asignaciones").select("recurso_tipo, recurso_id, fecha_inicio, fecha_fin").eq("obra_id", obraId),
      supabase.from("checklists").select("*").eq("obra_id", obraId).order("orden"),
      supabase.from("obra_tipos_obra").select("tipo:tipos_obra(nombre)").eq("obra_id", obraId),
      supabase.from("planificador_notas").select("fecha, texto").eq("obra_id", obraId).order("fecha"),
      supabase.from("recursos_humanos").select("id, nombre"),
    ]);

    const obra = obraR.data;
    if (!obra) return NextResponse.json({ error: "Obra not found" }, { status: 404 });

    const asigs = asigR.data || [];
    const notas = notasR.data || [];
    const tiposNombres = ((tiposR.data || []) as any[]).map((t) => t.tipo?.nombre).filter(Boolean);

    // Checklist items
    const clIds = ((checkR.data || []) as any[]).map((c) => c.id);
    const { data: itemsRaw } = clIds.length > 0
      ? await supabase.from("checklist_items").select("*, asignado:recursos_humanos(nombre)").in("checklist_id", clIds).order("orden")
      : { data: [] };
    const items = itemsRaw || [];

    // Resource names
    const { data: rrhhAll } = await supabase.from("recursos_humanos").select("id, nombre");
    const { data: vehAll } = await supabase.from("vehiculos").select("id, nombre");
    const { data: maqAll } = await supabase.from("maquinaria").select("id, nombre");
    const resName: Record<string, string> = {};
    (rrhhAll || []).forEach((r: any) => { resName[`humano|${r.id}`] = r.nombre; });
    (vehAll || []).forEach((r: any) => { resName[`vehiculo|${r.id}`] = r.nombre; });
    (maqAll || []).forEach((r: any) => { resName[`maquinaria|${r.id}`] = r.nombre; });

    // Dates
    let fechaInicio = "", fechaFin = "";
    if (asigs.length > 0) {
      const fechas = asigs.flatMap((a: any) => [a.fecha_inicio, a.fecha_fin]).filter(Boolean).sort();
      fechaInicio = fechas[0] || "";
      fechaFin = fechas[fechas.length - 1] || "";
    }
    const fmtDate = (f: string) => f ? new Date(f + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }) : "—";

    // Unique resources
    const uniqueRes: Record<string, { tipo: string; nombre: string }> = {};
    asigs.forEach((a: any) => {
      const k = `${a.recurso_tipo}|${a.recurso_id}`;
      if (!uniqueRes[k]) uniqueRes[k] = { tipo: a.recurso_tipo, nombre: resName[k] || "?" };
    });
    const recursos = Object.values(uniqueRes);
    const rrhhList = recursos.filter((r) => r.tipo === "humano");
    const vehList = recursos.filter((r) => r.tipo === "vehiculo");
    const maqList = recursos.filter((r) => r.tipo === "maquinaria");

    // Responsable
    const responsable = (rrhhAll || []).find((r: any) => r.id === obra.responsable_obra_id);

    // ════════════════════════════════════════════
    // PAGE 1: VERTICAL — Datos de obra
    // ════════════════════════════════════════════
    const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
    const pw = doc.internal.pageSize.getWidth(); // 210
    const ph = doc.internal.pageSize.getHeight(); // 297
    const m = 12;
    let y = m;

    // Logo + title
    try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", m, y, 22, 16); } catch {}
    doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
    doc.text("INFORME DE OBRA", m + 26, y + 5);
    doc.setFontSize(20); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text(obra.nombre, m + 26, y + 14);
    y += 22;

    // Red line
    doc.setDrawColor(220, 38, 38); doc.setLineWidth(0.6);
    doc.line(m, y, pw - m, y);
    y += 6;

    // Helper for info blocks
    const label = (text: string, x: number, yy: number) => { doc.setFontSize(6.5); doc.setFont("helvetica", "bold"); doc.setTextColor(140, 140, 140); doc.text(text, x, yy); };
    const value = (text: string, x: number, yy: number) => { doc.setFontSize(9); doc.setFont("helvetica", "normal"); doc.setTextColor(30, 30, 30); doc.text(text || "—", x, yy); };

    // ── Datos principales ──
    doc.setFillColor(248, 248, 248); doc.roundedRect(m, y, pw - m * 2, 32, 2, 2, "F");
    const col3 = (pw - m * 2) / 3;

    label("CLIENTE", m + 4, y + 4); value(obra.cliente?.nombre || "—", m + 4, y + 9);
    label("CIF/NIF", m + 4, y + 14); value(obra.cliente?.nif || "—", m + 4, y + 19);
    label("TIPO CLIENTE", m + 4, y + 24); value(obra.cliente?.tipo_cliente || "—", m + 4, y + 29);

    label("DIRECCIÓN", m + col3 + 4, y + 4); value(obra.direccion || "—", m + col3 + 4, y + 9);
    label("LOCALIDAD", m + col3 + 4, y + 14); value(obra.localidad || "—", m + col3 + 4, y + 19);
    label("PROVINCIA", m + col3 + 4, y + 24); value(obra.provincia || "—", m + col3 + 4, y + 29);

    label("ESTADO", m + col3 * 2 + 4, y + 4); value(obra.estado_custom?.nombre || "—", m + col3 * 2 + 4, y + 9);
    label("TIPOS DE OBRA", m + col3 * 2 + 4, y + 14); value(tiposNombres.join(", ") || "—", m + col3 * 2 + 4, y + 19);
    label("RESPONSABLE", m + col3 * 2 + 4, y + 24); value(responsable?.nombre || "—", m + col3 * 2 + 4, y + 29);

    y += 38;

    // ── Fechas + presupuesto ──
    doc.setFillColor(248, 248, 248); doc.roundedRect(m, y, pw - m * 2, 12, 2, 2, "F");
    const col4 = (pw - m * 2) / 4;
    label("FECHA INICIO", m + 4, y + 4); value(fmtDate(fechaInicio), m + 4, y + 9);
    label("FECHA FIN", m + col4 + 4, y + 4); value(fmtDate(fechaFin), m + col4 + 4, y + 9);
    label("Nº PRESUPUESTO", m + col4 * 2 + 4, y + 4); value(obra.num_presupuesto || "—", m + col4 * 2 + 4, y + 9);
    label("Nº FACTURA", m + col4 * 3 + 4, y + 4); value(obra.num_factura || "—", m + col4 * 3 + 4, y + 9);
    y += 18;

    // ── Contacto obra ──
    doc.setFillColor(248, 248, 248); doc.roundedRect(m, y, pw - m * 2, 12, 2, 2, "F");
    label("CONTACTO OBRA", m + 4, y + 4); value(obra.contacto_obra_nombre || "—", m + 4, y + 9);
    label("TELÉFONO", m + col3 + 4, y + 4); value(obra.contacto_obra_telefono || "—", m + col3 + 4, y + 9);
    label("EMAIL", m + col3 * 2 + 4, y + 4); value(obra.contacto_obra_email || "—", m + col3 * 2 + 4, y + 9);
    y += 18;

    // ── Equipo asignado ──
    doc.setFontSize(11); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
    doc.text("EQUIPO ASIGNADO", m, y); y += 5;

    if (recursos.length > 0) {
      const teamData: string[][] = [];
      rrhhList.forEach((r) => teamData.push(["👤", r.nombre, "Persona"]));
      vehList.forEach((r) => teamData.push(["🚗", r.nombre, "Vehículo"]));
      maqList.forEach((r) => teamData.push(["⚙️", r.nombre, "Maquinaria"]));

      doc.autoTable({
        startY: y,
        head: [["", "Recurso", "Tipo"]],
        body: teamData,
        margin: { left: m, right: m },
        styles: { fontSize: 8, cellPadding: 2 },
        headStyles: { fillColor: [60, 60, 60], textColor: 255, fontSize: 7 },
        columnStyles: { 0: { cellWidth: 8, halign: "center" }, 2: { cellWidth: 25 } },
        theme: "grid",
      });
      y = doc.lastAutoTable.finalY + 6;
    } else {
      doc.setFontSize(8); doc.setFont("helvetica", "italic"); doc.setTextColor(150, 150, 150);
      doc.text("Sin recursos asignados", m + 4, y + 2); y += 8;
    }

    // ── Observaciones ──
    if (obra.observaciones) {
      if (y > 240) { doc.addPage("a4", "portrait"); y = m; }
      doc.setFontSize(11); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
      doc.text("OBSERVACIONES", m, y); y += 5;
      doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(30, 30, 30);
      const obsLines = doc.splitTextToSize(obra.observaciones, pw - m * 2);
      doc.text(obsLines, m, y); y += obsLines.length * 3.5 + 6;
    }

    // ── Notas del planificador ──
    if (notas.length > 0) {
      if (y > 240) { doc.addPage("a4", "portrait"); y = m; }
      doc.setFontSize(11); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
      doc.text("NOTAS DEL PLANIFICADOR", m, y); y += 5;

      doc.autoTable({
        startY: y,
        head: [["Fecha", "Nota"]],
        body: notas.map((n: any) => [
          new Date(n.fecha + "T12:00:00").toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" }),
          n.texto,
        ]),
        margin: { left: m, right: m },
        styles: { fontSize: 8, cellPadding: 2 },
        headStyles: { fillColor: [60, 60, 60], textColor: 255, fontSize: 7 },
        columnStyles: { 0: { cellWidth: 30 } },
        theme: "grid",
      });
      y = doc.lastAutoTable.finalY + 6;
    }

    // Footer page 1
    doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
    doc.text(`${obra.nombre} — LOYNEK Soluciones Técnicas`, m, ph - 5);
    doc.text("1", pw - m, ph - 5, { align: "right" });

    // ════════════════════════════════════════════
    // PAGE 2+: HORIZONTAL — Checklists
    // ════════════════════════════════════════════
    const checklists = (checkR.data || []) as any[];
    if (checklists.length > 0) {
      doc.addPage("a4", "landscape");
      const lw = 297; // landscape width
      const lh = 210; // landscape height
      const lm = 8;
      let ly = lm;

      const checkSize = 8;
      const rowH = 14;
      const textSize = 12;
      const colW = (lw - lm * 2) / 2;
      const textOffset = checkSize + 4;
      const maxTextW = colW - textOffset - 4;

      for (const cl of checklists) {
        const clItems = items.filter((i: any) => i.checklist_id === cl.id);
        if (clItems.length === 0) continue;

        if (ly > lh - 25) { doc.addPage("a4", "landscape"); ly = lm; }

        // Title
        doc.setFontSize(13); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
        doc.text(cl.titulo.toUpperCase(), lm, ly + 2);
        doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
        doc.text(`${clItems.length} items`, lw - lm, ly + 2, { align: "right" });
        ly += 6;
        doc.setDrawColor(220, 220, 220); doc.setLineWidth(0.1); doc.line(lm, ly, lw - lm, ly); ly += 2;

        // 2 columns
        const half = Math.ceil(clItems.length / 2);
        const col1 = clItems.slice(0, half);
        const col2 = clItems.slice(half);
        const maxRows = Math.max(col1.length, col2.length);

        for (let row = 0; row < maxRows; row++) {
          if (ly + rowH > lh - 10) {
            doc.addPage("a4", "landscape"); ly = lm;
            doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
            doc.text(cl.titulo.toUpperCase() + " (cont.)", lm, ly + 2); ly += 7;
          }

          if (row % 2 === 0) { doc.setFillColor(248, 248, 248); doc.rect(lm, ly - 1.5, lw - lm * 2, rowH, "F"); }

          // Column 1
          if (col1[row]) {
            const x = lm + 2; const centerY = ly + (rowH - checkSize) / 2;
            doc.setDrawColor(160, 160, 160); doc.setLineWidth(0.4); doc.setFillColor(255, 255, 255);
            doc.roundedRect(x, centerY, checkSize, checkSize, 1, 1);
            doc.setFontSize(textSize); doc.setFont("helvetica", "normal"); doc.setTextColor(20, 20, 20);
            const t = doc.splitTextToSize(col1[row].texto, maxTextW);
            doc.text(t[0], x + textOffset, ly + rowH / 2 + 1);
          }

          // Separator
          doc.setDrawColor(230, 230, 230); doc.setLineWidth(0.1);
          doc.line(lm + colW, ly - 1.5, lm + colW, ly + rowH - 1.5);

          // Column 2
          if (col2[row]) {
            const x = lm + colW + 2; const centerY = ly + (rowH - checkSize) / 2;
            doc.setDrawColor(160, 160, 160); doc.setLineWidth(0.4); doc.setFillColor(255, 255, 255);
            doc.roundedRect(x, centerY, checkSize, checkSize, 1, 1);
            doc.setFontSize(textSize); doc.setFont("helvetica", "normal"); doc.setTextColor(20, 20, 20);
            const t = doc.splitTextToSize(col2[row].texto, maxTextW);
            doc.text(t[0], x + textOffset, ly + rowH / 2 + 1);
          }

          ly += rowH;
        }
        ly += 5;
      }

      // Footers for landscape pages
      const totalPages = doc.getNumberOfPages();
      for (let i = 2; i <= totalPages; i++) {
        doc.setPage(i);
        const pw2 = doc.internal.pageSize.getWidth();
        const ph2 = doc.internal.pageSize.getHeight();
        doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
        doc.text(`${obra.nombre} — LOYNEK Soluciones Técnicas`, lm, ph2 - 4);
        doc.text(`${i}/${totalPages}`, pw2 - lm, ph2 - 4, { align: "right" });
      }
      // Fix page 1 footer with total
      doc.setPage(1);
      doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
      doc.text(`1/${totalPages}`, pw - m, ph - 5, { align: "right" });
    }

    const pdfBase64 = doc.output("datauristring").split(",")[1];
    return NextResponse.json({ pdf: pdfBase64, filename: `informe_${obra.nombre.replace(/\s+/g, "_")}.pdf` });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
