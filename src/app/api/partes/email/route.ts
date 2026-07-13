import { NextRequest, NextResponse } from "next/server";
import { generatePartePdf } from "@/lib/pdf/generatePartePdf";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  try {
    const { parteId, toEmail } = await req.json();
    if (!parteId || !toEmail) return NextResponse.json({ error: "parteId and toEmail required" }, { status: 400 });

    const RESEND_API_KEY = process.env.RESEND_API_KEY;
    if (!RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY not configured" }, { status: 500 });

    const supabase = createAdminClient();

    // Fetch settings for CC and design
    const { data: settings } = await supabase.from("app_settings").select("value").eq("key", "partes_email").single();
    const config = settings?.value || {};
    const ccEmails: string[] = config.cc_emails || [];
    const empresaNombre = config.empresa_nombre || "LOYNEK Soluciones Técnicas";
    const footerText = config.footer_text || "Este email ha sido enviado automáticamente desde ObrasPlan";
    const colorPrimario = config.color_primario || "#DC2626";

    // Fetch parte info for email body
    const { data: parte } = await supabase.from("partes_diarios").select("*, obra:obras(nombre, contacto_obra_nombre)").eq("id", parteId).single();
    if (!parte) return NextResponse.json({ error: "Parte not found" }, { status: 404 });

    const obraName = parte.obra?.nombre || "Sin obra";
    const contactName = parte.obra?.contacto_obra_nombre || "";
    const fecha = parte.fecha ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }) : "";

    // Generate PDF
    const pdfData = await generatePartePdf(parteId);

    // Get download links for documents and audios
    const { data: docs } = await supabase.from("documentos").select("nombre_archivo, storage_path, tipo").eq("parte_id", parteId);
    const { data: audios } = await supabase.from("parte_audios").select("nombre_archivo, storage_path").eq("parte_id", parteId);

    const attachmentLinks: { name: string; url: string; type: string }[] = [];

    for (const doc of (docs || [])) {
      const { data: signed } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 604800); // 7 days
      if (signed?.signedUrl) attachmentLinks.push({ name: doc.nombre_archivo, url: signed.signedUrl, type: doc.tipo || "documento" });
    }
    for (const audio of (audios || [])) {
      const { data: signed } = await supabase.storage.from("audios").createSignedUrl(audio.storage_path, 604800);
      if (signed?.signedUrl) attachmentLinks.push({ name: audio.nombre_archivo, url: signed.signedUrl, type: "audio" });
    }

    // Build attachments HTML
    let attachmentsHtml = "";
    if (attachmentLinks.length > 0) {
      attachmentsHtml = `
        <div style="margin-top: 20px; padding: 15px; background: #f0f0f0; border-radius: 8px;">
          <p style="color: #333; font-weight: bold; margin: 0 0 10px 0; font-size: 14px;">Documentos adjuntos:</p>
          ${attachmentLinks.map((a) => `<p style="margin: 5px 0;"><a href="${a.url}" style="color: ${colorPrimario}; text-decoration: none;">📎 ${a.name}</a> <span style="color: #999; font-size: 12px;">(${a.type})</span></p>`).join("")}
        </div>
      `;
    }

    // Build email
    // ADMIN siempre en "to" para garantizar entrega independiente del dominio
    const ADMIN_EMAIL = "lauroba.eneko@gmail.com";
    const toList = toEmail && toEmail !== ADMIN_EMAIL
      ? [toEmail, ADMIN_EMAIL]   // cliente + admin
      : [ADMIN_EMAIL];            // solo admin si no hay email de obra
    console.log("[partes/email] Enviando a:", toList, "| parteId:", parteId);
    const emailPayload: any = {
      from: `${empresaNombre} <onboarding@resend.dev>`,
      to: toList,
      subject: `Parte de trabajo — ${obraName} — ${fecha}`,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <div style="background: ${colorPrimario}; padding: 20px; text-align: center; border-radius: 8px 8px 0 0;">
            <h1 style="color: white; margin: 0; font-size: 20px;">${empresaNombre} — Parte de Trabajo</h1>
          </div>
          <div style="padding: 20px; background: #f9f9f9;">
            <p style="color: #333;">Estimado/a ${contactName || ""},</p>
            <p style="color: #333;">Adjunto el parte de trabajo correspondiente a la obra <strong>${obraName}</strong> del <strong>${fecha}</strong>.</p>
            <p style="color: #333;">Encontrará el parte en formato PDF adjunto a este email.</p>
            ${attachmentsHtml}
            <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;" />
            <p style="color: #999; font-size: 12px;">${footerText}</p>
          </div>
        </div>
      `,
      attachments: [{ filename: pdfData.filename, content: pdfData.pdf }],
    };

    // CC adicional desde configuración (opcional)
    if (ccEmails.length > 0) {
      emailPayload.cc = ccEmails;
    }

    // Send via Resend
    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${RESEND_API_KEY}` },
      body: JSON.stringify(emailPayload),
    });

    if (!emailRes.ok) {
      const errText = await emailRes.text();
      let errMsg = errText;
      try { errMsg = JSON.parse(errText).message || errText; } catch {}
      console.error("[partes/email] Error Resend:", errMsg, "| to:", toList);
      return NextResponse.json({ error: `Error Resend: ${errMsg}` }, { status: 400 });
    }

    const emailResult = await emailRes.json();
    console.log("[partes/email] Email enviado OK. ID:", emailResult.id, "| to:", toList);
    return NextResponse.json({ success: true, emailId: emailResult.id });
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error sending email" }, { status: 500 });
  }
}