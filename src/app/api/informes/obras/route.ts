import { NextRequest, NextResponse } from "next/server";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF { autoTable: (options: any) => jsPDF; lastAutoTable: { finalY: number }; }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      obras,               // array ya filtrado desde el cliente
      archivedFilter,      // "activas" | "archivadas" | "todas"
      estadosFilterLabels, // string[] — nombres de estados seleccionados (vacío = todos)
      searchQuery,         // texto de búsqueda
    } = body as {
      obras: any[];
      archivedFilter: string;
      estadosFilterLabels: string[];
      searchQuery: string;
    };

    if (!obras || obras.length === 0)
      return NextResponse.json({ error: "No hay obras con los filtros actuales." }, { status: 400 });

    // Ordenar: por nombre de estado → num_presupuesto natural → nombre
    function naturalCmp(a: string, b: string): number {
      const re = /(\d+)/g;
      const ap = a.split(re); const bp = b.split(re);
      for (let i = 0; i < Math.max(ap.length, bp.length); i++) {
        const ai = ap[i] || ""; const bi = bp[i] || "";
        const an = parseInt(ai); const bn = parseInt(bi);
        if (!isNaN(an) && !isNaN(bn) && an !== bn) return an - bn;
        const c = ai.localeCompare(bi, "es"); if (c !== 0) return c;
      }
      return 0;
    }

    const sorted = [...obras].sort((a, b) => {
      // 1. Estado
      const ea = a.estado_custom?.nombre || "ZZZZ";
      const eb = b.estado_custom?.nombre || "ZZZZ";
      const ec = ea.localeCompare(eb, "es");
      if (ec !== 0) return ec;
      // 2. N.º presupuesto natural (sin presupuesto al final)
      const pa = a.num_presupuesto || ""; const pb = b.num_presupuesto || "";
      if (!pa && pb) return 1; if (pa && !pb) return -1;
      if (pa && pb) { const nc = naturalCmp(pa, pb); if (nc !== 0) return nc; }
      // 3. Nombre
      return (a.nombre || "").localeCompare(b.nombre || "", "es");
    });

    // PDF — A4 horizontal
    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
    const W = doc.internal.pageSize.getWidth();  // 297
    const H = doc.internal.pageSize.getHeight(); // 210
    const M = 14;

    const ahora = new Date();
    const fmtAhora = ahora.toLocaleDateString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric" })
      + " " + ahora.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });

    const filtrosTexto: string[] = [];
    if (archivedFilter === "activas") filtrosTexto.push("Activas");
    else if (archivedFilter === "archivadas") filtrosTexto.push("Archivadas");
    else filtrosTexto.push("Todas");
    if (estadosFilterLabels?.length > 0) filtrosTexto.push(`Estados: ${estadosFilterLabels.join(", ")}`);
    if (searchQuery) filtrosTexto.push(`Búsqueda: "${searchQuery}"`);

    const addHeader = () => {
      try { doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", M, 5, 26, 17); } catch { /* */ }
      doc.setFontSize(6.5); doc.setFont("helvetica", "normal"); doc.setTextColor(120);
      doc.text("Loynek Soluciones Técnicas", M + 28, 11);
      doc.setFontSize(13); doc.setFont("helvetica", "bold"); doc.setTextColor(20);
      doc.text("Informe de Obras", W / 2, 12, { align: "center" });
      doc.setFontSize(7.5); doc.setFont("helvetica", "normal"); doc.setTextColor(80);
      const fl = filtrosTexto.join("  ·  ");
      if (fl.length > 90) {
        // Partir en dos líneas si es muy largo
        const mid = filtrosTexto.slice(0, Math.ceil(filtrosTexto.length / 2)).join("  ·  ");
        const rest = filtrosTexto.slice(Math.ceil(filtrosTexto.length / 2)).join("  ·  ");
        doc.text(mid, W / 2, 18, { align: "center" });
        doc.text(rest, W / 2, 22, { align: "center" });
      } else {
        doc.text(fl, W / 2, 19, { align: "center" });
      }
      doc.setFontSize(6.5); doc.setTextColor(130);
      doc.text(`Generado: ${fmtAhora}`, W - M, 9, { align: "right" });
      doc.text(`${sorted.length} obra${sorted.length !== 1 ? "s" : ""}`, W - M, 14, { align: "right" });
      doc.setDrawColor(220); doc.setLineWidth(0.4);
      doc.line(M, 25, W - M, 25);
    };

    // Filas: columnas N.º Presupuesto | Cliente | Obra | Estado | Anotaciones
    const rows = sorted.map((o: any) => [
      o.num_presupuesto || "—",
      o.cliente?.nombre || "—",
      o.nombre || "—",
      o.estado_custom?.nombre || "Sin estado",
      "",  // Anotaciones vacías
    ]);

    doc.autoTable({
      startY: 28,
      head: [["N.º PRESUPUESTO", "CLIENTE", "OBRA", "ESTADO", "ANOTACIONES"]],
      body: rows,
      margin: { left: M, right: M },
      tableWidth: W - M * 2,
      styles: {
        fontSize: 8,
        cellPadding: { top: 2.5, bottom: 2.5, left: 2.5, right: 2.5 },
        lineColor: [210, 210, 210],
        lineWidth: 0.2,
        valign: "middle",
        overflow: "linebreak",
      },
      headStyles: {
        fillColor: [220, 38, 38],
        textColor: 255,
        fontStyle: "bold",
        fontSize: 7,
        halign: "center",
        cellPadding: { top: 3, bottom: 3, left: 2, right: 2 },
      },
      alternateRowStyles: { fillColor: [250, 250, 252] },
      theme: "grid",
      columnStyles: {
        0: { cellWidth: 28, halign: "center", fontStyle: "bold", fontSize: 7.5 },  // N.º presupuesto
        1: { cellWidth: 45 },                                                        // Cliente
        2: { cellWidth: 72, fontStyle: "bold" },                                    // Obra (más ancho)
        3: { cellWidth: 36, halign: "center" },                                      // Estado
        4: { cellWidth: "auto", minCellHeight: 10 },                                // Anotaciones
      },
      rowPageBreak: "avoid",
      showHead: "everyPage",
      didParseCell: (data: any) => {
        // Columna Anotaciones — fondo tintado para distinguir
        if (data.section === "body" && data.column.index === 4) {
          data.cell.styles.fillColor = [245, 248, 255];
        }
        // Columna Estado — colorear con el color del estado
        if (data.section === "body" && data.column.index === 3) {
          const obra = sorted[data.row.index];
          const color = obra?.estado_custom?.color;
          if (color) {
            const hex = color.replace("#", "");
            const r = parseInt(hex.substring(0, 2), 16);
            const g = parseInt(hex.substring(2, 4), 16);
            const b = parseInt(hex.substring(4, 6), 16);
            if (!isNaN(r) && !isNaN(g) && !isNaN(b)) {
              data.cell.styles.fillColor = [r, g, b];
              data.cell.styles.textColor = [255, 255, 255];
              data.cell.styles.fontStyle = "bold";
            }
          }
        }
      },
      didDrawPage: () => {
        addHeader();
        doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150);
        doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", M, H - 5);
        doc.line(M, H - 8, W - M, H - 8);
      },
    });

    // Numeración correcta (dos pasadas)
    const totalPages = (doc as any).internal.getNumberOfPages();
    for (let i = 1; i <= totalPages; i++) {
      doc.setPage(i);
      doc.setFillColor(255, 255, 255);
      doc.rect(W - M - 22, 11, 24, 6, "F");
      doc.setFontSize(6.5); doc.setFont("helvetica", "normal"); doc.setTextColor(130);
      doc.text(`Pág. ${i} / ${totalPages}`, W - M, 15, { align: "right" });
    }

    const fecha = `${ahora.getFullYear()}${String(ahora.getMonth()+1).padStart(2,"0")}${String(ahora.getDate()).padStart(2,"0")}`;
    const buf = Buffer.from(doc.output("datauristring").split(",")[1], "base64");
    return new NextResponse(buf, {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="informe_obras_${archivedFilter}_${fecha}.pdf"`,
      },
    });
  } catch (err: any) {
    return NextResponse.json({ error: err?.message || "Error interno" }, { status: 500 });
  }
}
