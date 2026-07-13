import { NextRequest, NextResponse } from "next/server";
// eslint-disable-next-line @typescript-eslint/no-require-imports
const sharp = require("sharp") as typeof import("sharp").default;
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
      .select("*, obra:obras(nombre, contacto_obra_nombre), creator:users!partes_diarios_created_by_fkey(nombre)")
      .eq("id", parteId)
      .single();
    if (!parte) return NextResponse.json({ error: "Parte not found" }, { status: 404 });

    const obraName   = parte.obra?.nombre || "Sin obra";
    const creador    = (parte as any).creator?.nombre || "—";
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
        const rawBuf = Buffer.from(await resp.arrayBuffer());
        const isImage = d.tipo === "foto" || /\.(jpg|jpeg|png|webp)$/i.test(d.nombre_archivo);
        let finalBuf = rawBuf;
        let filename = d.nombre_archivo;
        if (isImage) {
          // Comprimir fotos antes de adjuntar: max 1600px, JPEG 75%
          finalBuf = await sharp(rawBuf)
            .resize({ width: 1600, height: 1600, fit: "inside", withoutEnlargement: true })
            .jpeg({ quality: 75 })
            .toBuffer();
          // Asegurar extensión .jpg
          filename = filename.replace(/\.(png|webp|heic|heif)$/i, ".jpg");
        }
        const b64 = finalBuf.toString("base64");
        attachments.push({ filename, content: b64 });
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
      subject: `Parte: ${obraName} | ${fecha} | ${creador}`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
          <div style="background:${colorPrimario};padding:20px;text-align:center;border-radius:8px 8px 0 0">
            <h1 style="color:white;margin:0;font-size:20px">${empresaNombre} — Parte de Trabajo</h1>
          </div>
          <div style="padding:20px;background:#f9f9f9">
            <p style="color:#333">Parte de trabajo de la obra <strong>${obraName}</strong>, fecha <strong>${fecha}</strong>.</p>
            <p style="color:#333">Creado por: <strong>${creador}</strong></p>
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