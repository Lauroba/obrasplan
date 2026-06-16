import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF { autoTable: (options: any) => jsPDF; lastAutoTable: { finalY: number }; }
}

export async function GET(req: NextRequest) {
  try {
    const url = new URL(req.url);
    const soloActivos = url.searchParams.get("activos") !== "false";

    const supabase = createAdminClient();
    let query = supabase.from("recursos_humanos").select("*").order("nombre");
    if (soloActivos) query = query.eq("activo", true);
    const { data: rrhh } = await query;

    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
    const w = doc.internal.pageSize.getWidth();
    const m = 10;
    let y = m;

    try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", m, y, 20, 14); } catch {}
    doc.setFontSize(16); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text("INFORME DE RECURSOS HUMANOS", m + 24, y + 8);
    doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
    doc.text(new Date().toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }), w - m, y + 8, { align: "right" });
    doc.text(`${(rrhh || []).length} trabajadores${soloActivos ? " activos" : ""}`, w - m, y + 12, { align: "right" });
    y += 20;
    doc.setDrawColor(220, 38, 38); doc.setLineWidth(0.5); doc.line(m, y, w - m, y); y += 4;

    doc.autoTable({
      startY: y,
      head: [["Nombre", "Perfil", "Teléfono", "Email", "Asignable"]],
      body: (rrhh || []).map((r: any) => [
        r.nombre, r.perfil || "—", r.telefono || "—", r.email || "—",
        r.asignable !== false ? "Sí" : "No",
      ]),
      margin: { left: m, right: m },
      styles: { fontSize: 8, cellPadding: 2.5 },
      headStyles: { fillColor: [220, 38, 38], textColor: 255, fontSize: 7.5, fontStyle: "bold" },
      alternateRowStyles: { fillColor: [250, 250, 250] },
      theme: "grid",
    });

    const pages = doc.getNumberOfPages();
    for (let i = 1; i <= pages; i++) {
      doc.setPage(i);
      doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
      doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", m, doc.internal.pageSize.getHeight() - 5);
      doc.text(`${i}/${pages}`, w - m, doc.internal.pageSize.getHeight() - 5, { align: "right" });
    }

    const buf = Buffer.from(doc.output("datauristring").split(",")[1], "base64");
    return new NextResponse(buf, { headers: { "Content-Type": "application/pdf", "Content-Disposition": "inline; filename=recursos_humanos.pdf" } });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
