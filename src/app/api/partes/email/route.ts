import { NextRequest, NextResponse } from "next/server";
import { generatePartePdf } from "@/lib/pdf/generatePartePdf";

export async function POST(req: NextRequest) {
  try {
    const { parteId, toEmail, toName, subject, body: emailBody } = await req.json();
    if (!parteId || !toEmail) return NextResponse.json({ error: "parteId and toEmail required" }, { status: 400 });

    const RESEND_API_KEY = process.env.RESEND_API_KEY;
    if (!RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY not configured. Add it in Vercel Environment Variables." }, { status: 500 });

    // Generate PDF directly (no internal fetch)
    const pdfData = await generatePartePdf(parteId);

    // Send email via Resend REST API
    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "ObrasPlan <onboarding@resend.dev>",
        to: [toEmail],
        subject: subject || `Parte de trabajo — ${pdfData.filename}`,
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: #DC2626; padding: 20px; text-align: center;">
              <h1 style="color: white; margin: 0; font-size: 20px;">LOYNEK — Parte de Trabajo</h1>
            </div>
            <div style="padding: 20px; background: #f9f9f9;">
              <p style="color: #333;">Estimado/a ${toName || ""},</p>
              <p style="color: #333;">${emailBody || "Adjunto el parte de trabajo correspondiente."}</p>
              <p style="color: #333;">Encontrará el parte adjunto en formato PDF.</p>
              <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;" />
              <p style="color: #999; font-size: 12px;">Este email ha sido enviado automáticamente desde ObrasPlan — LOYNEK Soluciones Técnicas.</p>
            </div>
          </div>
        `,
        attachments: [
          {
            filename: pdfData.filename,
            content: pdfData.pdf,
          },
        ],
      }),
    });

    if (!emailRes.ok) {
      const errText = await emailRes.text();
      let errMsg = errText;
      try { errMsg = JSON.parse(errText).message || errText; } catch {}
      return NextResponse.json({ error: `Resend error: ${errMsg}` }, { status: 400 });
    }

    const emailResult = await emailRes.json();
    return NextResponse.json({ success: true, emailId: emailResult.id });
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error sending email" }, { status: 500 });
  }
}
