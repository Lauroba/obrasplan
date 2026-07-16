import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF { autoTable: (options: any) => jsPDF; lastAutoTable: { finalY: number }; }
}

function fmtFecha(iso: string | null | undefined): string {
  if (!iso) return "";
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      obras,                  // array de obras ya filtradas desde el cliente
      archivedFilter,         // "activas" | "archivadas" | "todas"
      estadoFilterLabel,      // nombre del estado seleccionado o ""
      searchQuery,            // texto de búsqueda o ""
    } = body as {
      obras: any[];
      archivedFilter: string;
      estadoFilterLabel: string;
      searchQuery: string;
    };

    if (!obras || obras.length === 0) {
      return NextResponse.json(
        { error: "No hay obras con los filtros actuales." },
        { status: 400 }
      );
    }

    // PDF — A4 Horizontal
    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
    const W = doc.internal.pageSize.getWidth();   // 297
    const H = doc.internal.pageSize.getHeight();  // 210
    const M = 14;

    // Fecha y hora de generación
    const ahora = new Date();
    const fmtAhora = ahora.toLocaleDateString("es-ES", {
      day: "2-digit", month: "2-digit", year: "numeric",
    }) + " " + ahora.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });

    // ── Función cabecera (se repite en cada página) ──────────────────
    const addHeader = (pageNum: number, totalPages: number) => {
      // Logo
      try {
        doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", M, 6, 28, 18);
      } catch { /* logo opcional */ }

      // Empresa
      doc.setFontSize(6.5); doc.setFont("helvetica", "normal"); doc.setTextColor(120);
      doc.text("Loynek Soluciones Técnicas", M + 30, 12);

      // Título
      doc.setFontSize(14); doc.setFont("helvetica", "bold"); doc.setTextColor(20);
      doc.text("Informe de Obras", W / 2, 13, { align: "center" });

      // Subtítulo con filtros
      const filtros: string[] = [];
      if (archivedFilter === "activas") filtros.push("Activas");
      else if (archivedFilter === "archivadas") filtros.push("Archivadas");
      else filtros.push("Todas");
      if (estadoFilterLabel) filtros.push(`Estado: ${estadoFilterLabel}`);
      if (searchQuery) filtros.push(`Búsqueda: "${searchQuery}"`);

      doc.setFontSize(8); doc.setFont("helvetica", "normal"); doc.setTextColor(80);
      doc.text(filtros.join("  ·  "), W / 2, 20, { align: "center" });

      // Fecha generación + página
      doc.setFontSize(7); doc.setTextColor(130);
      doc.text(`Generado el ${fmtAhora}`, W - M, 10, { align: "right" });
      doc.text(`${pageNum} / ${totalPages}`, W - M, 15, { align: "right" });
      doc.text(`${obras.length} obra${obras.length !== 1 ? "s" : ""}`, W - M, 20, { align: "right" });

      // Línea separadora
      doc.setDrawColor(220); doc.setLineWidth(0.4);
      doc.line(M, 24, W - M, 24);
    };

    // ── Filas de la tabla ────────────────────────────────────────────
    const rows = obras.map((o: any) => [
      o.cliente?.nombre || o.cliente_id || "—",
      o.nombre || "—",
      o.estado_custom?.nombre || "—",
      o.num_presupuesto || "—",
      "",   // Anotaciones — celda vacía para escritura manual
    ]);

    // ── Generar tabla ────────────────────────────────────────────────
    // Primera pasada para calcular páginas (jsPDF no tiene API de "preview")
    // Generamos directamente; el totalPages lo ponemos en el footer
    doc.autoTable({
      startY: 27,
      head: [["CLIENTE", "OBRA", "ESTADO", "N.º PRESUPUESTO", "ANOTACIONES"]],
      body: rows,
      margin: { left: M, right: M },
      tableWidth: W - M * 2,
      styles: {
        fontSize: 8.5,
        cellPadding: { top: 3, bottom: 3, left: 2.5, right: 2.5 },
        lineColor: [210, 210, 210],
        lineWidth: 0.2,
        valign: "middle",
        overflow: "linebreak",
      },
      headStyles: {
        fillColor: [220, 38, 38],
        textColor: 255,
        fontStyle: "bold",
        fontSize: 7.5,
        halign: "center",
        cellPadding: { top: 3, bottom: 3, left: 2, right: 2 },
      },
      alternateRowStyles: { fillColor: [250, 250, 252] },
      theme: "grid",
      columnStyles: {
        0: { cellWidth: 42 },                          // Cliente
        1: { cellWidth: 70, fontStyle: "bold" },       // Obra (más ancho, negrita)
        2: { cellWidth: 38, halign: "center" },        // Estado
        3: { cellWidth: 32, halign: "center" },        // N.º Presupuesto
        4: { cellWidth: "auto", minCellHeight: 12 },   // Anotaciones (el resto del ancho)
      },
      // Evitar que filas se corten entre páginas
      rowPageBreak: "avoid",
      // Cabecera repetida en cada página (jspdf-autotable lo hace automáticamente con head)
      showHead: "everyPage",
      // Marcador visual en la columna Anotaciones
      didParseCell: (data: any) => {
        if (data.section === "body" && data.column.index === 4) {
          // Fondo ligeramente diferente para la columna de anotaciones
          data.cell.styles.fillColor = [246, 248, 255];
        }
        if (data.section === "body" && data.column.index === 2) {
          // Colorear el estado con el color de la obra si existe
          const obra = obras[data.row.index];
          const color = obra?.estado_custom?.color;
          if (color && color !== "") {
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
      didDrawPage: (data: any) => {
        // Cabecera y pie en cada página (totalPages aún no disponible aquí)
        const pageNum = (doc as any).internal.getCurrentPageInfo().pageNumber;
        addHeader(pageNum, 0); // totalPages = 0 provisional

        // Pie de página
        doc.setFontSize(6.5); doc.setFont("helvetica", "normal"); doc.setTextColor(150);
        doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", M, H - 5);
        doc.line(M, H - 8, W - M, H - 8);
      },
    });

    // ── Corregir numeración con total de páginas real ────────────────
    const totalPages = (doc as any).internal.getNumberOfPages();
    for (let i = 1; i <= totalPages; i++) {
      doc.setPage(i);
      // Sobreescribir el número de página con el total correcto
      // Fondo blanco para tapar el "0" provisional
      doc.setFillColor(255, 255, 255);
      doc.rect(W - M - 20, 12, 22, 6, "F");
      doc.setFontSize(7); doc.setFont("helvetica", "normal"); doc.setTextColor(130);
      doc.text(`${i} / ${totalPages}`, W - M, 15, { align: "right" });
    }

    // ── Columna Anotaciones: borde visible para escritura manual ─────
    // (ya viene del theme: "grid" — el borde está)

    const nombreArchivo = `obras_${archivedFilter}_${ahora.getFullYear()}${String(ahora.getMonth() + 1).padStart(2, "0")}${String(ahora.getDate()).padStart(2, "0")}.pdf`;

    const buf = Buffer.from(doc.output("datauristring").split(",")[1], "base64");
    return new NextResponse(buf, {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="${nombreArchivo}"`,
      },
    });
  } catch (err: any) {
    return NextResponse.json({ error: err?.message || "Error interno" }, { status: 500 });
  }
}
