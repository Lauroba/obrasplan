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
    const supabase = createAdminClient();
    const { data: clientes } = await supabase.from("clientes").select("*").eq("activo", true).order("nombre");
    const { data: contactos } = await supabase.from("contactos").select("*").order("nombre");

    const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
    const w = doc.internal.pageSize.getWidth();
    const m = 12;
    let y = m;

    // Header
    try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", m, y, 20, 14); } catch {}
    doc.setFontSize(16); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
    doc.text("INFORME DE CLIENTES Y CONTACTOS", m + 24, y + 8);
    doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
    doc.text(new Date().toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }), w - m, y + 8, { align: "right" });
    doc.text(`${(clientes || []).length} clientes · ${(contactos || []).length} contactos`, w - m, y + 12, { align: "right" });
    y += 20;
    doc.setDrawColor(220, 38, 38); doc.setLineWidth(0.5); doc.line(m, y, w - m, y); y += 6;

    for (const cliente of (clientes || [])) {
      if (y > 260) { doc.addPage(); y = m; }
      const cts = (contactos || []).filter((c: any) => c.cliente_id === cliente.id);

      // Client header
      doc.setFillColor(245, 245, 245); doc.roundedRect(m, y, w - m * 2, 12, 2, 2, "F");
      doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
      doc.text(cliente.nombre, m + 3, y + 5);
      doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(100, 100, 100);
      const info = [cliente.tipo_cliente, cliente.nif, cliente.telefono, cliente.email].filter(Boolean).join(" · ");
      doc.text(info, m + 3, y + 10);
      if (cliente.direccion) doc.text(cliente.direccion + (cliente.web ? ` · ${cliente.web}` : ""), w - m - 3, y + 5, { align: "right" });
      y += 16;

      // Contacts table
      if (cts.length > 0) {
        doc.autoTable({
          startY: y,
          head: [["Nombre", "Cargo", "Teléfono", "Email", "Notas"]],
          body: cts.map((ct: any) => [ct.nombre, ct.cargo || "—", ct.telefono || "—", ct.email || "—", ct.notas || ""]),
          margin: { left: m + 2, right: m },
          styles: { fontSize: 7, cellPadding: 1.5 },
          headStyles: { fillColor: [100, 100, 100], textColor: 255, fontSize: 6.5 },
          columnStyles: { 4: { cellWidth: 35 } },
          theme: "grid",
        });
        y = doc.lastAutoTable.finalY + 6;
      } else {
        doc.setFontSize(7); doc.setFont("helvetica", "italic"); doc.setTextColor(150, 150, 150);
        doc.text("Sin contactos", m + 5, y); y += 6;
      }
    }

    // Footer
    const pages = doc.getNumberOfPages();
    for (let i = 1; i <= pages; i++) {
      doc.setPage(i);
      doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
      doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", m, 290);
      doc.text(`${i}/${pages}`, w - m, 290, { align: "right" });
    }

    const pdfBase64 = doc.output("datauristring").split(",")[1];
    const pdfBuffer = Buffer.from(pdfBase64, "base64");
    return new NextResponse(pdfBuffer, { headers: { "Content-Type": "application/pdf", "Content-Disposition": "inline; filename=clientes_contactos.pdf" } });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
