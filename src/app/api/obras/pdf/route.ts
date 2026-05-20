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
    const { data: obra } = await supabase.from("obras").select("*, estado_custom:estados_obra(*), cliente:clientes(nombre)").eq("id", obraId).single();
    if (!obra) return NextResponse.json({ error: "Obra not found" }, { status: 404 });

    const { data: checklists } = await supabase.from("checklists").select("*").eq("obra_id", obraId).order("orden");
    const clIds = (checklists || []).map((c: any) => c.id);
    const { data: items } = clIds.length > 0
      ? await supabase.from("checklist_items").select("*, asignado:recursos_humanos(nombre)").in("checklist_id", clIds).order("orden")
      : { data: [] };

    const { data: tipos } = await supabase.from("obra_tipos_obra").select("tipo:tipos_obra(nombre)").eq("obra_id", obraId);

    const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
    const w = doc.internal.pageSize.getWidth();
    const margin = 15;
    let y = 15;

    // Logo
    try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", margin, y, 35, 25); } catch {}

    // Title
    doc.setFontSize(18); doc.setFont("helvetica", "bold");
    doc.text("INFORME DE OBRA", w / 2, y + 10, { align: "center" });
    doc.setFontSize(9); doc.setFont("helvetica", "normal");
    doc.text(new Date().toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }), w - margin, y + 10, { align: "right" });

    y = 48;
    doc.setDrawColor(220, 38, 38); doc.setLineWidth(0.8);
    doc.line(margin, y, w - margin, y);
    y += 8;

    // Obra info
    const labelS = () => { doc.setFontSize(7); doc.setFont("helvetica", "bold"); doc.setTextColor(120, 120, 120); };
    const valueS = () => { doc.setFontSize(10); doc.setFont("helvetica", "normal"); doc.setTextColor(0, 0, 0); };

    doc.setFillColor(248, 248, 248); doc.roundedRect(margin, y, w - margin * 2, 28, 2, 2, "F");

    labelS(); doc.text("OBRA", margin + 4, y + 5);
    doc.setFontSize(12); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text(obra.nombre, margin + 4, y + 11);

    labelS(); doc.text("CLIENTE", w / 2, y + 5);
    valueS(); doc.text(obra.cliente?.nombre || "—", w / 2, y + 11);

    labelS(); doc.text("ESTADO", margin + 4, y + 17);
    valueS(); doc.text(obra.estado_custom?.nombre || "—", margin + 4, y + 23);

    labelS(); doc.text("DIRECCIÓN", w / 2, y + 17);
    valueS(); doc.text([obra.direccion, obra.localidad, obra.provincia].filter(Boolean).join(", ") || "—", w / 2, y + 23);

    y += 34;

    // Tipos de obra
    if (tipos && tipos.length > 0) {
      labelS(); doc.text("TIPOS DE OBRA", margin, y);
      valueS(); doc.text((tipos as any[]).map((t) => t.tipo?.nombre).filter(Boolean).join(", "), margin + 30, y);
      y += 8;
    }

    // Observaciones
    if (obra.observaciones) {
      labelS(); doc.text("OBSERVACIONES", margin, y); y += 4;
      doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(0, 0, 0);
      const lines = doc.splitTextToSize(obra.observaciones, w - margin * 2);
      doc.text(lines, margin, y); y += lines.length * 3.5 + 4;
    }

    y += 4;

    // Checklists
    if (checklists && checklists.length > 0) {
      doc.setFontSize(14); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
      doc.text("CHECKLISTS", margin, y); y += 8;

      for (const cl of checklists) {
        if (y > 250) { doc.addPage(); y = 20; }

        const clItems = (items || []).filter((i: any) => i.checklist_id === cl.id);
        const completed = clItems.filter((i: any) => i.completado).length;
        const total = clItems.length;
        const progress = total > 0 ? Math.round((completed / total) * 100) : 0;

        // Checklist header
        doc.setFontSize(11); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
        doc.text(cl.titulo, margin, y);

        // Progress badge
        const progressText = `${progress}% (${completed}/${total})`;
        doc.setFontSize(8); doc.setFont("helvetica", "normal");
        if (progress === 100) doc.setTextColor(22, 163, 74);
        else if (progress > 0) doc.setTextColor(217, 119, 6);
        else doc.setTextColor(120, 120, 120);
        doc.text(progressText, w - margin, y, { align: "right" });

        y += 3;

        // Progress bar
        doc.setFillColor(230, 230, 230);
        doc.roundedRect(margin, y, w - margin * 2, 3, 1, 1, "F");
        if (progress > 0) {
          if (progress === 100) doc.setFillColor(34, 197, 94);
          else doc.setFillColor(251, 191, 36);
          doc.roundedRect(margin, y, (w - margin * 2) * (progress / 100), 3, 1, 1, "F");
        }
        y += 7;

        // Items table
        if (clItems.length > 0) {
          const prioSymbol: Record<string, string> = { alta: "●", media: "◐", baja: "○" };
          doc.autoTable({
            startY: y,
            head: [["", "Item", "Prioridad", "Asignado", "Estado"]],
            body: clItems.map((item: any, idx: number) => [
              `${idx + 1}`,
              item.texto,
              `${prioSymbol[item.prioridad] || ""} ${item.prioridad.charAt(0).toUpperCase() + item.prioridad.slice(1)}`,
              item.asignado?.nombre || "—",
              item.completado ? "✓ Completado" : "○ Pendiente",
            ]),
            margin: { left: margin, right: margin },
            styles: { fontSize: 7.5, cellPadding: 2 },
            headStyles: { fillColor: [220, 38, 38], textColor: 255, fontSize: 7, fontStyle: "bold" },
            columnStyles: {
              0: { cellWidth: 8, halign: "center" },
              1: { cellWidth: "auto" },
              2: { cellWidth: 22 },
              3: { cellWidth: 30 },
              4: { cellWidth: 24 },
            },
            didParseCell: (data: any) => {
              if (data.section === "body" && data.column.index === 4) {
                if (data.cell.raw?.startsWith("✓")) data.cell.styles.textColor = [22, 163, 74];
                else data.cell.styles.textColor = [150, 150, 150];
              }
            },
            theme: "grid",
          });
          y = doc.lastAutoTable.finalY + 8;
        } else {
          doc.setFontSize(8); doc.setFont("helvetica", "italic"); doc.setTextColor(150, 150, 150);
          doc.text("Sin items", margin + 4, y); y += 6;
        }
      }
    }

    // Footer
    const pageCount = doc.getNumberOfPages();
    for (let i = 1; i <= pageCount; i++) {
      doc.setPage(i);
      doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
      doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", margin, 290);
      doc.text(`Página ${i} de ${pageCount}`, w - margin, 290, { align: "right" });
    }

    const pdfBase64 = doc.output("datauristring").split(",")[1];
    return NextResponse.json({ pdf: pdfBase64, filename: `obra_${obra.nombre.replace(/\s+/g, "_")}.pdf` });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
