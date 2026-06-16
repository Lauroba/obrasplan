import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF { autoTable: (options: any) => jsPDF; lastAutoTable: { finalY: number }; }
}

function toDS(d: Date) { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; }

export async function GET(req: NextRequest) {
  try {
    const url = new URL(req.url);
    const dateParam = url.searchParams.get("date") || toDS(new Date());

    // Calculate week Mon-Sun
    const ref = new Date(dateParam + "T12:00:00");
    const day = ref.getDay(); const diff = ref.getDate() - day + (day === 0 ? -6 : 1);
    const mon = new Date(ref); mon.setDate(diff);
    const days: Date[] = [];
    for (let i = 0; i < 7; i++) { const d = new Date(mon); d.setDate(mon.getDate() + i); days.push(d); }
    const dateStrs = days.map(toDS);
    const weekLabel = `${days[0].toLocaleDateString("es-ES", { day: "numeric", month: "short" })} — ${days[6].toLocaleDateString("es-ES", { day: "numeric", month: "short", year: "numeric" })}`;

    const supabase = createAdminClient();
    const [obrasR, asigR, rrhhR, vehR, notasR] = await Promise.all([
      supabase.from("obras").select("id, nombre, color").eq("archivada", false).order("orden_gantt"),
      supabase.from("asignaciones").select("*"),
      supabase.from("recursos_humanos").select("id, nombre").eq("activo", true),
      supabase.from("vehiculos").select("id, nombre").eq("activo", true),
      supabase.from("planificador_notas").select("*"),
    ]);

    const obras = obrasR.data || [];
    const asigs = asigR.data || [];
    const rrhh: Record<string, string> = {};
    (rrhhR.data || []).forEach((r: any) => { rrhh[r.id] = r.nombre; });
    const vehs: Record<string, string> = {};
    (vehR.data || []).forEach((r: any) => { vehs[r.id] = r.nombre; });
    const notasMap: Record<string, string> = {};
    (notasR.data || []).forEach((n: any) => { notasMap[`${n.obra_id}|${n.fecha}`] = n.texto; });

    // Filter obras that have assignments this week
    const obrasConAsig = new Set<string>();
    asigs.forEach((a: any) => {
      const ini = String(a.fecha_inicio).substring(0, 10);
      const fin = String(a.fecha_fin).substring(0, 10);
      dateStrs.forEach((ds) => { if (ini <= ds && fin >= ds) obrasConAsig.add(a.obra_id); });
    });
    const activeObras = obras.filter((o: any) => obrasConAsig.has(o.id));

    // Build grid
    const grid: Record<string, { personas: string[]; vehiculos: string[]; nota?: string }> = {};
    asigs.forEach((a: any) => {
      const ini = String(a.fecha_inicio).substring(0, 10);
      const fin = String(a.fecha_fin).substring(0, 10);
      dateStrs.forEach((ds) => {
        if (ini <= ds && fin >= ds) {
          const k = `${a.obra_id}|${ds}`;
          if (!grid[k]) grid[k] = { personas: [], vehiculos: [] };
          const name = a.recurso_tipo === "humano" ? rrhh[a.recurso_id] : a.recurso_tipo === "vehiculo" ? vehs[a.recurso_id] : null;
          if (name) {
            if (a.recurso_tipo === "humano") grid[k].personas.push(name.split(" ")[0]);
            else grid[k].vehiculos.push(name);
          }
        }
      });
    });
    // Add notes
    activeObras.forEach((o: any) => {
      dateStrs.forEach((ds) => {
        const k = `${o.id}|${ds}`;
        const nota = notasMap[k];
        if (nota) { if (!grid[k]) grid[k] = { personas: [], vehiculos: [] }; grid[k].nota = nota; }
      });
    });

    // Generate PDF — Landscape
    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
    const w = doc.internal.pageSize.getWidth();
    const h = doc.internal.pageSize.getHeight();
    const m = 8;

    // Header
    try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", m, m, 18, 13); } catch {}
    doc.setFontSize(14); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text("PLANIFICACIÓN SEMANAL", m + 22, m + 6);
    doc.setFontSize(10); doc.setFont("helvetica", "normal"); doc.setTextColor(80, 80, 80);
    doc.text(weekLabel, m + 22, m + 12);

    const DAY_NAMES = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];

    // Build table data
    const headers = ["OBRA", ...days.map((d) => `${DAY_NAMES[d.getDay()]} ${d.getDate()}`)];
    const body = activeObras.map((obra: any) => {
      const row = [obra.nombre];
      dateStrs.forEach((ds) => {
        const cell = grid[`${obra.id}|${ds}`];
        if (!cell) { row.push(""); return; }
        let text = cell.personas.join(", ");
        if (cell.vehiculos.length > 0) text += (text ? "\n" : "") + "🚗 " + cell.vehiculos.join(", ");
        if (cell.nota) text += (text ? "\n" : "") + "📝 " + cell.nota;
        row.push(text);
      });
      return row;
    });

    doc.autoTable({
      startY: m + 18,
      head: [headers],
      body,
      margin: { left: m, right: m },
      styles: { fontSize: 6.5, cellPadding: 1.5, lineWidth: 0.1, valign: "top" },
      headStyles: { fillColor: [220, 38, 38], textColor: 255, fontSize: 6, fontStyle: "bold", halign: "center" },
      columnStyles: { 0: { cellWidth: 40, fontStyle: "bold", fontSize: 7 } },
      alternateRowStyles: { fillColor: [252, 252, 252] },
      theme: "grid",
      didParseCell: (data: any) => {
        // Color obra column with obra color
        if (data.section === "body" && data.column.index === 0) {
          const obra = activeObras[data.row.index];
          if (obra?.color) {
            const hex = obra.color.replace("#", "");
            const r = parseInt(hex.substring(0, 2), 16);
            const g = parseInt(hex.substring(2, 4), 16);
            const b = parseInt(hex.substring(4, 6), 16);
            data.cell.styles.fillColor = [r, g, b];
            data.cell.styles.textColor = [255, 255, 255];
          }
        }
      },
    });

    // Footer
    const pages = doc.getNumberOfPages();
    for (let i = 1; i <= pages; i++) {
      doc.setPage(i);
      doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
      doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", m, h - 4);
      doc.text(`${i}/${pages}`, w - m, h - 4, { align: "right" });
    }

    const buf = Buffer.from(doc.output("datauristring").split(",")[1], "base64");
    return new NextResponse(buf, { headers: { "Content-Type": "application/pdf", "Content-Disposition": `inline; filename=planificacion_${dateParam}.pdf` } });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
