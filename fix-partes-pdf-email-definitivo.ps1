#Requires -Version 5.1
# fix-partes-pdf-email-definitivo.ps1
# 3 mejoras en 2 archivos:
#
# PDF (generatePartePdf.ts):
#   - Eliminada seccion Trabajos / Materiales
#   - Solo firma del CLIENTE (no la del responsable)
#   - Fotos incluidas en el PDF: 2 por fila, 3 por pagina, con nombre
#   - Layout de fotos: fila 1 izq+der, fila 2 centrada; luego nueva pagina
#   - Si una foto falla, continua con las demas
#
# EMAIL (route.ts):
#   - Siempre y solo a lauroba.eneko@gmail.com (FIXED_TO hardcodeado)
#   - Sin logica de toEmail ni calculos de email de obra
#   - Adjuntos REALES (no links): descarga bytes de Supabase con signed URL
#     y los envia base64 en el campo attachments de Resend
#   - Adjunta: PDF del parte + todos los documentos + todos los audios
#   - Logs detallados en Vercel Functions para depurar

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Fix PDF + email partes definitivo" -ForegroundColor Cyan

Write-Host "  -> src\lib\pdf\generatePartePdf.ts" -ForegroundColor Gray
$dst = "src\lib\pdf\generatePartePdf.ts"
$content = @'
import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF {
    autoTable: (options: any) => jsPDF;
    lastAutoTable: { finalY: number };
  }
}

const PAGE_H  = 297;
const PAGE_W  = 210;
const MARGIN  = 15;
const FOOTER_Y = 290;

// ── Helpers de estilo ─────────────────────────────────────────────────────────
function label(doc: jsPDF) {
  doc.setFontSize(7);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(120, 120, 120);
}
function value(doc: jsPDF) {
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.setTextColor(0, 0, 0);
}
function sectionTitle(doc: jsPDF, text: string, y: number) {
  doc.setFontSize(9);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(220, 38, 38);
  doc.text(text, MARGIN, y);
  doc.setDrawColor(220, 38, 38);
  doc.setLineWidth(0.3);
  doc.line(MARGIN, y + 1.5, PAGE_W - MARGIN, y + 1.5);
  doc.setTextColor(0, 0, 0);
  return y + 6;
}
function addFooters(doc: jsPDF) {
  const total = doc.getNumberOfPages();
  for (let i = 1; i <= total; i++) {
    doc.setPage(i);
    doc.setFontSize(7);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(150, 150, 150);
    doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", MARGIN, FOOTER_Y);
    doc.text(`Página ${i} de ${total}`, PAGE_W - MARGIN, FOOTER_Y, { align: "right" });
  }
}
function checkPage(doc: jsPDF, y: number, need = 20): number {
  if (y + need > FOOTER_Y - 5) {
    doc.addPage();
    return 20;
  }
  return y;
}

// ── Función principal ─────────────────────────────────────────────────────────
export async function generatePartePdf(
  parteId: string
): Promise<{ pdf: string; filename: string }> {
  const supabase = createAdminClient();

  const { data: parte } = await supabase
    .from("partes_diarios")
    .select("*, obra:obras(*), creator:users!partes_diarios_created_by_fkey(nombre)")
    .eq("id", parteId)
    .single();
  if (!parte) throw new Error("Parte not found");

  // Documentos (fotos y otros)
  const { data: docs } = await supabase
    .from("documentos")
    .select("nombre_archivo, storage_path, tipo")
    .eq("parte_id", parteId);

  const fotos = (docs || []).filter(
    (d) => d.tipo === "foto" || /\.(jpg|jpeg|png|webp|gif)$/i.test(d.nombre_archivo)
  );
  const otrosDocs = (docs || []).filter(
    (d) => !fotos.includes(d)
  );

  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const w = PAGE_W;
  let y = 15;

  // ── CABECERA ────────────────────────────────────────────────────────────────
  try {
    doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", MARGIN, y, 32, 22);
  } catch {}

  doc.setFontSize(18);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(0, 0, 0);
  doc.text("PARTE DE TRABAJO", w / 2, y + 9, { align: "center" });

  const fecha = parte.fecha
    ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", {
        weekday: "long", day: "numeric", month: "long", year: "numeric",
      })
    : "";
  doc.setFontSize(10);
  doc.setFont("helvetica", "normal");
  doc.text(fecha, w - MARGIN, y + 9, { align: "right" });
  doc.setFontSize(8);
  doc.setTextColor(150, 150, 150);
  doc.text((parte.estado || "").toUpperCase(), w - MARGIN, y + 14, { align: "right" });
  doc.setTextColor(0, 0, 0);

  y = 44;
  doc.setDrawColor(220, 38, 38);
  doc.setLineWidth(0.8);
  doc.line(MARGIN, y, w - MARGIN, y);
  y += 5;

  // ── DATOS DE LA OBRA ────────────────────────────────────────────────────────
  y = sectionTitle(doc, "DATOS DE LA OBRA", y);

  doc.setFillColor(248, 249, 250);
  doc.roundedRect(MARGIN, y, w - MARGIN * 2, 32, 2, 2, "F");

  label(doc); doc.text("OBRA", MARGIN + 4, y + 5);
  doc.setFontSize(10); doc.setFont("helvetica", "bold"); doc.setTextColor(0, 0, 0);
  doc.text(parte.obra?.nombre || "Sin obra", MARGIN + 4, y + 11);

  label(doc); doc.text("DIRECCIÓN", MARGIN + 4, y + 17);
  value(doc); doc.text(parte.direccion || "—", MARGIN + 4, y + 22);

  const midX = w / 2;
  label(doc); doc.text("LOCALIDAD", midX + 4, y + 17);
  value(doc); doc.text(parte.localidad || "—", midX + 4, y + 22);

  label(doc); doc.text("PROVINCIA", MARGIN + 4, y + 27);
  value(doc); doc.text(parte.provincia || "—", MARGIN + 4, y + 31);
  y += 38;

  // ── RESPONSABLES ────────────────────────────────────────────────────────────
  y = checkPage(doc, y, 22);
  y = sectionTitle(doc, "RESPONSABLES", y);

  doc.setFillColor(248, 249, 250);
  doc.roundedRect(MARGIN, y, w - MARGIN * 2, 16, 2, 2, "F");
  const col3 = (w - MARGIN * 2) / 3;

  label(doc); doc.text("JEFE DE OBRA", MARGIN + 4, y + 5);
  value(doc); doc.text(parte.jefe_obra || "—", MARGIN + 4, y + 11);

  label(doc); doc.text("ENCARGADO", MARGIN + col3 + 4, y + 5);
  value(doc); doc.text(parte.encargado_obra || "—", MARGIN + col3 + 4, y + 11);

  label(doc); doc.text("EMPRESA RESPONSABLE", MARGIN + col3 * 2 + 4, y + 5);
  value(doc); doc.text(parte.responsable_empresa || "—", MARGIN + col3 * 2 + 4, y + 11);
  y += 22;

  label(doc); doc.text("CREADO POR", MARGIN, y);
  value(doc); doc.text(parte.creator?.nombre || "—", MARGIN + 28, y);
  y += 10;

  // ── OBSERVACIONES ───────────────────────────────────────────────────────────
  if (parte.observaciones) {
    y = checkPage(doc, y, 30);
    y = sectionTitle(doc, "OBSERVACIONES", y);
    doc.setFontSize(8);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(0, 0, 0);
    const lines = doc.splitTextToSize(parte.observaciones, w - MARGIN * 2);
    doc.text(lines, MARGIN, y);
    y += lines.length * 4 + 8;
  }

  // ── DOCUMENTOS ADJUNTOS (no fotos) ──────────────────────────────────────────
  if (otrosDocs.length > 0) {
    y = checkPage(doc, y, 20);
    y = sectionTitle(doc, "DOCUMENTOS ADJUNTOS", y);
    doc.setFontSize(8);
    doc.setFont("helvetica", "normal");
    for (const d of otrosDocs) {
      y = checkPage(doc, y, 6);
      doc.text(`• ${d.nombre_archivo}`, MARGIN + 2, y);
      y += 5;
    }
    y += 4;
  }

  // ── FIRMA DEL CLIENTE ────────────────────────────────────────────────────────
  y = checkPage(doc, y, 50);
  y = sectionTitle(doc, "FIRMA DEL CLIENTE", y);

  const sigW = 80;
  const sigH = 35;
  doc.setDrawColor(180, 180, 180);
  doc.setLineWidth(0.3);
  doc.roundedRect(MARGIN, y, sigW, sigH, 2, 2);

  if (parte.firma_cliente) {
    try {
      doc.addImage(parte.firma_cliente, "PNG", MARGIN + 2, y + 2, sigW - 4, sigH - 4);
    } catch {}
  }

  doc.setFillColor(240, 240, 240);
  doc.rect(MARGIN, y + sigH, sigW, 6, "F");
  label(doc);
  doc.text("Firma del cliente", MARGIN + sigW / 2, y + sigH + 4, { align: "center" });
  y += sigH + 12;

  // ── FOTOS (3 por página) ──────────────────────────────────────────────────────
  if (fotos.length > 0) {
    doc.addPage();
    y = 20;
    y = sectionTitle(doc, `FOTOGRAFÍAS (${fotos.length})`, y);
    y += 2;

    const imgW  = (w - MARGIN * 2 - 8) / 2; // 2 columnas
    const imgH  = 65;
    const perPage = 3;  // 3 fotos por página (2 arriba, 1 abajo centrada)

    let slot = 0;
    for (let i = 0; i < fotos.length; i++) {
      const foto = fotos[i];

      // Cada 3 fotos: nueva página
      if (i > 0 && i % perPage === 0) {
        doc.addPage();
        y = 20;
        y = sectionTitle(doc, `FOTOGRAFÍAS (cont.)`, y);
        y += 2;
        slot = 0;
      }

      slot = i % perPage;

      // Layout: fila 0 = izquierda, fila 1 = derecha, fila 2 = centrada
      let imgX: number;
      let rowY: number;
      if (slot === 0) {
        imgX = MARGIN;
        rowY = y;
      } else if (slot === 1) {
        imgX = MARGIN + imgW + 8;
        rowY = y;
      } else {
        // 3ª foto: nueva fila, centrada
        rowY = y + imgH + 14;
        imgX = MARGIN + (w - MARGIN * 2 - imgW) / 2;
      }

      // Descargar imagen desde Supabase
      try {
        const { data: signedData } = await supabase.storage
          .from("documentos")
          .createSignedUrl(foto.storage_path, 60);

        if (signedData?.signedUrl) {
          const resp = await fetch(signedData.signedUrl);
          const buf  = await resp.arrayBuffer();
          const b64  = Buffer.from(buf).toString("base64");
          const ext  = foto.nombre_archivo.split(".").pop()?.toLowerCase() || "jpeg";
          const mime = ext === "png" ? "PNG" : "JPEG";
          const dataUri = `data:image/${ext === "png" ? "png" : "jpeg"};base64,${b64}`;

          // Recuadro
          doc.setDrawColor(200, 200, 200);
          doc.setLineWidth(0.3);
          doc.roundedRect(imgX, rowY, imgW, imgH, 2, 2);
          doc.addImage(dataUri, mime, imgX + 1, rowY + 1, imgW - 2, imgH - 8);

          // Nombre del archivo
          doc.setFontSize(6);
          doc.setFont("helvetica", "normal");
          doc.setTextColor(100, 100, 100);
          const shortName = foto.nombre_archivo.length > 28
            ? foto.nombre_archivo.substring(0, 25) + "..."
            : foto.nombre_archivo;
          doc.text(shortName, imgX + imgW / 2, rowY + imgH - 2, { align: "center" });
        }
      } catch { /* si falla una imagen, continuar */ }

      // Avanzar y cuando completamos la fila 2 o es la última
      if (slot === 2 || i === fotos.length - 1) {
        y = (slot === 2 ? y + imgH + 14 : y) + imgH + 14;
      }
    }
  }

  addFooters(doc);

  const pdfBase64 = doc.output("datauristring").split(",")[1];
  const filename = `parte_${parte.fecha}_${
    (parte.obra?.nombre || "sin-obra").replace(/\s+/g, "_")
  }.pdf`;

  return { pdf: pdfBase64, filename };
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\app\api\partes\email\route.ts" -ForegroundColor Gray
$dst = "src\app\api\partes\email\route.ts"
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { generatePartePdf } from "@/lib/pdf/generatePartePdf";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  try {
    const { parteId } = await req.json();
    if (!parteId) return NextResponse.json({ error: "parteId required" }, { status: 400 });

    const RESEND_API_KEY = process.env.RESEND_API_KEY;
    if (!RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY not configured" }, { status: 500 });

    const FIXED_TO = "lauroba.eneko@gmail.com";
    const supabase = createAdminClient();

    // ── Configuración de la empresa ──────────────────────────────────────────
    const { data: settings } = await supabase
      .from("app_settings").select("value").eq("key", "partes_email").single();
    const config = settings?.value || {};
    const empresaNombre  = config.empresa_nombre  || "LOYNEK Soluciones Técnicas";
    const footerText     = config.footer_text     || "Email generado automáticamente desde ObrasPlan";
    const colorPrimario  = config.color_primario  || "#DC2626";

    // ── Datos del parte ──────────────────────────────────────────────────────
    const { data: parte } = await supabase
      .from("partes_diarios")
      .select("*, obra:obras(nombre, contacto_obra_nombre)")
      .eq("id", parteId)
      .single();
    if (!parte) return NextResponse.json({ error: "Parte not found" }, { status: 404 });

    const obraName   = parte.obra?.nombre || "Sin obra";
    const fecha      = parte.fecha
      ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", {
          day: "numeric", month: "long", year: "numeric",
        })
      : "";

    // ── Generar PDF ──────────────────────────────────────────────────────────
    console.log("[partes/email] Generando PDF para parte", parteId);
    const pdfData = await generatePartePdf(parteId);

    // ── Adjuntos: descargar bytes reales de Supabase ──────────────────────────
    const { data: docs   } = await supabase
      .from("documentos")
      .select("nombre_archivo, storage_path, tipo")
      .eq("parte_id", parteId);
    const { data: audios } = await supabase
      .from("parte_audios")
      .select("nombre_archivo, storage_path")
      .eq("parte_id", parteId);

    // Resend acepta attachments con { filename, content } donde content es base64
    const attachments: { filename: string; content: string }[] = [
      { filename: pdfData.filename, content: pdfData.pdf },
    ];

    // Documentos (fotos, PDFs, etc.)
    for (const d of (docs || [])) {
      try {
        const { data: signed } = await supabase.storage
          .from("documentos")
          .createSignedUrl(d.storage_path, 300);
        if (!signed?.signedUrl) continue;
        const resp = await fetch(signed.signedUrl);
        if (!resp.ok) continue;
        const buf = await resp.arrayBuffer();
        const b64 = Buffer.from(buf).toString("base64");
        attachments.push({ filename: d.nombre_archivo, content: b64 });
      } catch { /* ignorar archivos que fallen */ }
    }

    // Audios
    for (const a of (audios || [])) {
      try {
        const { data: signed } = await supabase.storage
          .from("audios")
          .createSignedUrl(a.storage_path, 300);
        if (!signed?.signedUrl) continue;
        const resp = await fetch(signed.signedUrl);
        if (!resp.ok) continue;
        const buf = await resp.arrayBuffer();
        const b64 = Buffer.from(buf).toString("base64");
        attachments.push({ filename: a.nombre_archivo, content: b64 });
      } catch { /* ignorar audios que fallen */ }
    }

    const nAdj = attachments.length - 1; // sin contar el PDF
    console.log(`[partes/email] ${attachments.length} adjuntos (PDF + ${nAdj} archivos)`);

    // ── Construir email ──────────────────────────────────────────────────────
    const emailPayload = {
      from: `${empresaNombre} <onboarding@resend.dev>`,
      to:   [FIXED_TO],
      subject: `Parte de trabajo — ${obraName} — ${fecha}`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
          <div style="background:${colorPrimario};padding:20px;text-align:center;border-radius:8px 8px 0 0">
            <h1 style="color:white;margin:0;font-size:20px">${empresaNombre} — Parte de Trabajo</h1>
          </div>
          <div style="padding:20px;background:#f9f9f9">
            <p style="color:#333">Parte de trabajo de la obra <strong>${obraName}</strong>, fecha <strong>${fecha}</strong>.</p>
            <p style="color:#333">Se adjuntan el PDF del parte${nAdj > 0 ? ` y ${nAdj} archivo${nAdj > 1 ? "s" : ""} adicional${nAdj > 1 ? "es" : ""}` : ""}.</p>
            <hr style="border:none;border-top:1px solid #ddd;margin:20px 0"/>
            <p style="color:#999;font-size:12px">${footerText}</p>
          </div>
        </div>
      `,
      attachments,
    };

    // ── Enviar via Resend ────────────────────────────────────────────────────
    console.log(`[partes/email] Enviando a ${FIXED_TO} — parte ${parteId}`);
    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify(emailPayload),
    });

    if (!emailRes.ok) {
      const errText = await emailRes.text();
      let errMsg = errText;
      try { errMsg = JSON.parse(errText).message || errText; } catch {}
      console.error("[partes/email] Error Resend:", errMsg);
      return NextResponse.json({ error: `Error Resend: ${errMsg}` }, { status: 400 });
    }

    const emailResult = await emailRes.json();
    console.log("[partes/email] OK — emailId:", emailResult.id);
    return NextResponse.json({ success: true, emailId: emailResult.id });

  } catch (err: any) {
    console.error("[partes/email] Excepción:", err?.message);
    return NextResponse.json({ error: err.message || "Error sending email" }, { status: 500 });
  }
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

$ok1 = !(Select-String -LiteralPath (Join-Path $RepoPath "src\lib\pdf\generatePartePdf.ts") -Pattern "TRABAJOS" -Quiet)
$ok2 = Select-String -LiteralPath (Join-Path $RepoPath "src\lib\pdf\generatePartePdf.ts") -Pattern "perPage = 3" -Quiet
$ok3 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\api\partes\email\route.ts") -Pattern "FIXED_TO" -Quiet
$ok4 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\api\partes\email\route.ts") -Pattern "arrayBuffer" -Quiet
if ($ok1) { Write-Host "    OK: sin materiales en PDF" -ForegroundColor Green }
else { Write-Host "    WARN: pueden quedar materiales" -ForegroundColor Yellow }
if ($ok2) { Write-Host "    OK: fotos 3 por pagina" -ForegroundColor Green }
else { Write-Host "    ERROR: falta layout fotos" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: FIXED_TO en route.ts" -ForegroundColor Green }
else { Write-Host "    ERROR: falta FIXED_TO" -ForegroundColor Red }
if ($ok4) { Write-Host "    OK: adjuntos reales (arrayBuffer)" -ForegroundColor Green }
else { Write-Host "    ERROR: falta descarga real de adjuntos" -ForegroundColor Red }
Write-Host ""
Write-Host "VERIFICAR:" -ForegroundColor Cyan
Write-Host "  1. Firma un parte con fotos adjuntas"
Write-Host "  2. Vercel Logs -> buscar [partes/email]"
Write-Host "  3. Deberia llegar a lauroba.eneko@gmail.com con PDF + fotos adjuntas"
Write-Host ""
Write-Host '  git add src\lib\pdf\generatePartePdf.ts src\app\api\partes\email\route.ts'
Write-Host '  git commit -m "feat: partes PDF sin materiales, fotos 3/pagina, adjuntos reales en email"'
Write-Host '  git push'
