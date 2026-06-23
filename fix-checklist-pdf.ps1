#Requires -Version 5.1
# fix-checklist-pdf.ps1
# Corrige el PDF de obra: los items del checklist ahora se muestran en
# varias lineas si el texto es largo, en vez de cortarse en la primera.
# Tambien muestra si cada item esta completado (caja verde con marca).

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"

if (-not (Test-Path $RepoPath)) {
    Write-Host "ERROR: no se encuentra el repo en $RepoPath" -ForegroundColor Red
    exit 1
}
Set-Location $RepoPath

Write-Host ""
Write-Host "==> Escribiendo el archivo corregido del PDF de obra" -ForegroundColor Cyan

$dst = "src\app\api\obras\pdf\route.ts"
$content = @'
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

    // Unique resources with merged assignment date ranges
    const resPeriods: Record<string, { tipo: string; nombre: string; periods: { ini: string; fin: string }[] }> = {};
    asigs.forEach((a: any) => {
      const k = `${a.recurso_tipo}|${a.recurso_id}`;
      if (!resPeriods[k]) resPeriods[k] = { tipo: a.recurso_tipo, nombre: resName[k] || "?", periods: [] };
      if (a.fecha_inicio) resPeriods[k].periods.push({ ini: a.fecha_inicio, fin: a.fecha_fin || a.fecha_inicio });
    });

    const mergeRanges = (periods: { ini: string; fin: string }[]) => {
      const sorted = [...periods].sort((a, b) => a.ini.localeCompare(b.ini));
      const merged: { ini: string; fin: string }[] = [];
      for (const p of sorted) {
        const last = merged[merged.length - 1];
        if (last) {
          const nextDay = new Date(last.fin + "T12:00:00"); nextDay.setDate(nextDay.getDate() + 1);
          const nextDayStr = nextDay.toISOString().slice(0, 10);
          if (p.ini <= nextDayStr) { if (p.fin > last.fin) last.fin = p.fin; continue; }
        }
        merged.push({ ...p });
      }
      return merged;
    };

    const fmtShort = (f: string) => new Date(f + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "short" }).replace(".", "");
    const fmtRange = (ini: string, fin: string) => {
      if (!ini) return "—";
      if (ini === fin) return fmtShort(ini);
      const dIni = new Date(ini + "T12:00:00"), dFin = new Date(fin + "T12:00:00");
      if (dIni.getMonth() === dFin.getMonth() && dIni.getFullYear() === dFin.getFullYear()) {
        return `${dIni.getDate()}-${dFin.getDate()} ${fmtShort(fin).split(" ")[1]}`;
      }
      return `${fmtShort(ini)} - ${fmtShort(fin)}`;
    };

    const recursos = Object.values(resPeriods).map((r) => ({
      tipo: r.tipo,
      nombre: r.nombre,
      fechas: mergeRanges(r.periods).map((p) => fmtRange(p.ini, p.fin)).join(", ") || "—",
    }));
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
      const ordered = [...rrhhList, ...vehList, ...maqList];
      const typeColor: Record<string, [number, number, number]> = { humano: [37, 99, 235], vehiculo: [217, 119, 6], maquinaria: [100, 116, 139] };
      const typeLabel: Record<string, string> = { humano: "Persona", vehiculo: "Vehículo", maquinaria: "Maquinaria" };

      const rowH = 6.5;
      const gap = 2;
      const colGap = 6;
      const colW2 = (pw - m * 2 - colGap) / 2;
      const half = Math.ceil(ordered.length / 2);
      const col1 = ordered.slice(0, half);
      const col2 = ordered.slice(half);
      const maxRows = Math.max(col1.length, col2.length);
      const startY = y;

      const drawRow = (r: { tipo: string; nombre: string; fechas: string }, x: number, yy: number, w: number) => {
        const c = typeColor[r.tipo] || [150, 150, 150];
        doc.setFillColor(c[0], c[1], c[2]);
        doc.roundedRect(x, yy + 0.7, 2.4, 2.4, 0.5, 0.5, "F");
        doc.setFontSize(8); doc.setFont("helvetica", "bold"); doc.setTextColor(20, 20, 20);
        doc.text(r.nombre, x + 4.5, yy + 3);
        doc.setFontSize(6); doc.setFont("helvetica", "normal"); doc.setTextColor(150, 150, 150);
        doc.text(typeLabel[r.tipo] || r.tipo, x + 4.5, yy + 5.7);
        doc.setFontSize(6.5); doc.setFont("helvetica", "normal"); doc.setTextColor(110, 110, 110);
        doc.text(r.fechas, x + w, yy + 3.5, { align: "right" });
      };

      for (let row = 0; row < maxRows; row++) {
        const yy = startY + row * (rowH + gap);
        if (row % 2 === 0) { doc.setFillColor(248, 248, 248); doc.rect(m, yy - 0.6, pw - m * 2, rowH + gap, "F"); }
        if (col1[row]) drawRow(col1[row], m + 2, yy, colW2 - 2);
        if (col2[row]) drawRow(col2[row], m + colW2 + colGap, yy, colW2 - 2);
      }
      y = startY + maxRows * (rowH + gap) + 4;
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

      const checkSize = 7;
      const textSize = 8;
      const colW = (lw - lm * 2) / 2;
      const textOffset = checkSize + 3;
      const maxTextW = colW - textOffset - 6;
      const lineH = 3.8;
      const padV = 2.5;
      const minRowH = checkSize + padV * 2;

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
          doc.setFontSize(textSize);
          const lines1 = col1[row] ? doc.splitTextToSize(col1[row].texto || "", maxTextW) : [];
          const lines2 = col2[row] ? doc.splitTextToSize(col2[row].texto || "", maxTextW) : [];
          const numLines = Math.max(lines1.length, lines2.length, 1);
          const rowH = Math.max(minRowH, numLines * lineH + padV * 2);

          if (ly + rowH > lh - 10) {
            doc.addPage("a4", "landscape"); ly = lm;
            doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(220, 38, 38);
            doc.text(cl.titulo.toUpperCase() + " (cont.)", lm, ly + 2); ly += 7;
          }

          if (row % 2 === 0) {
            doc.setFillColor(248, 248, 248);
            doc.rect(lm, ly, lw - lm * 2, rowH, "F");
          }

          // Column 1
          if (col1[row]) {
            const x = lm + 2;
            const completed = col1[row].completado === true;
            doc.setDrawColor(completed ? 34 : 160, completed ? 197 : 160, completed ? 94 : 160);
            doc.setLineWidth(0.4);
            doc.setFillColor(completed ? 34 : 255, completed ? 197 : 255, completed ? 94 : 255);
            doc.roundedRect(x, ly + padV, checkSize, checkSize, 1, 1, completed ? "FD" : "D");
            doc.setFontSize(textSize); doc.setFont("helvetica", "normal");
            doc.setTextColor(completed ? 120 : 20, completed ? 120 : 20, completed ? 120 : 20);
            doc.text(lines1, x + textOffset, ly + padV + lineH * 0.85);
          }

          // Separator
          doc.setDrawColor(230, 230, 230); doc.setLineWidth(0.1);
          doc.line(lm + colW, ly, lm + colW, ly + rowH);

          // Column 2
          if (col2[row]) {
            const x = lm + colW + 2;
            const completed = col2[row].completado === true;
            doc.setDrawColor(completed ? 34 : 160, completed ? 197 : 160, completed ? 94 : 160);
            doc.setLineWidth(0.4);
            doc.setFillColor(completed ? 34 : 255, completed ? 197 : 255, completed ? 94 : 255);
            doc.roundedRect(x, ly + padV, checkSize, checkSize, 1, 1, completed ? "FD" : "D");
            doc.setFontSize(textSize); doc.setFont("helvetica", "normal");
            doc.setTextColor(completed ? 120 : 20, completed ? 120 : 20, completed ? 120 : 20);
            doc.text(lines2, x + textOffset, ly + padV + lineH * 0.85);
          }

          doc.setDrawColor(235, 235, 235); doc.setLineWidth(0.05);
          doc.line(lm, ly + rowH, lw - lm, ly + rowH);

          ly += rowH;
        }
        ly += 6;
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
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path $dst).Path, $content, $utf8NoBom)
Write-Host "    Escrito: $dst" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$f = "src\app\api\obras\pdf\route.ts"
if (Test-Path $f) {
    $ok = Select-String -Path $f -Pattern "splitTextToSize.*maxTextW" -Quiet -ErrorAction SilentlyContinue
    if ($ok) {
        Write-Host "    OK: $f contiene el codigo correcto" -ForegroundColor Green
    } else {
        Write-Host "    ERROR: el archivo no tiene el codigo esperado" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Todo listo. Siguiente paso:" -ForegroundColor Green
Write-Host '  git add src\app\api\obras\pdf\route.ts'
Write-Host '  git commit -m "fix: checklist PDF multilinea con altura dinamica por fila"'
Write-Host '  git push'
