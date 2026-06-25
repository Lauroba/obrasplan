/**
 * src/app/api/almacen/alertas-email/route.ts
 *
 * Envía email de alertas de stock bajo y caducidad usando Resend,
 * siguiendo el mismo patrón que /api/partes/email.
 * Se llama desde el cron nocturno o manualmente desde Configuracion.
 */
import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  const RESEND_API_KEY = process.env.RESEND_API_KEY;
  if (!RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY no configurada" }, { status: 500 });

  try {
    const admin = createAdminClient();

    // Leer configuracion de alertas
    const { data: settingsRow } = await admin.from("app_settings").select("value").eq("key", "almacen_alertas").single();
    const config = (settingsRow?.value as any) || {};
    const emails: string[] = config.emails || [];
    const asunto: string = config.asunto || "Alertas de almacen - ObrasPlan";
    const diasAviso: number = config.dias_aviso_caducidad || 30;

    if (!emails.length) return NextResponse.json({ sent: false, reason: "Sin emails configurados" });

    // Obtener alertas
    const { data: alertas } = await admin.from("v_alertas_almacen" as any).select("*");
    if (!alertas || alertas.length === 0) return NextResponse.json({ sent: false, reason: "Sin alertas activas" });

    const stockBajo = alertas.filter((a: any) => a.alerta_stock);
    const caducados = alertas.filter((a: any) => a.alerta_caducidad === "caducado");
    const caducaProto = alertas.filter((a: any) => a.alerta_caducidad === "caduca_pronto");

    const rowHTML = (a: any) => `
      <tr>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0">${a.nombre}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0">${a.almacen_nombre}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0;text-align:right">${Number(a.stock_qty ?? 0).toFixed(2)}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0;text-align:right">${Number(a.stock_minimo_def ?? 0).toFixed(2)}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0">${a.caducidad ? new Date(a.caducidad).toLocaleDateString("es-ES") : "—"}</td>
      </tr>`;

    const section = (title: string, rows: any[], headerColor: string) => rows.length === 0 ? "" : `
      <h3 style="color:${headerColor};margin:24px 0 8px">${title} (${rows.length})</h3>
      <table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px">
        <thead><tr style="background:#f8f8f8">
          <th style="padding:6px 12px;text-align:left;color:#666">Artículo</th>
          <th style="padding:6px 12px;text-align:left;color:#666">Almacén</th>
          <th style="padding:6px 12px;text-align:right;color:#666">Stock actual</th>
          <th style="padding:6px 12px;text-align:right;color:#666">Stock mínimo</th>
          <th style="padding:6px 12px;text-align:left;color:#666">Caducidad</th>
        </tr></thead>
        <tbody>${rows.map(rowHTML).join("")}</tbody>
      </table>`;

    const html = `
      <div style="font-family:Arial,sans-serif;max-width:700px;margin:0 auto;color:#333">
        <div style="background:#DC2626;padding:20px 24px;border-radius:8px 8px 0 0">
          <h1 style="color:#fff;margin:0;font-size:20px">Alertas de almacén</h1>
          <p style="color:rgba(255,255,255,.8);margin:4px 0 0;font-size:13px">${new Date().toLocaleDateString("es-ES", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}</p>
        </div>
        <div style="padding:24px;background:#fff;border:1px solid #eee;border-top:none;border-radius:0 0 8px 8px">
          ${section("🔴 Stock por debajo del mínimo", stockBajo, "#DC2626")}
          ${section("⚫ Artículos caducados", caducados, "#7c3aed")}
          ${section("🟡 Artículos que caducan en ${diasAviso} días", caducaProto, "#d97706")}
          <p style="margin-top:24px;font-size:12px;color:#999">Generado automáticamente por ObrasPlan</p>
        </div>
      </div>`;

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${RESEND_API_KEY}` },
      body: JSON.stringify({ from: "ObrasPlan Almacén <onboarding@resend.dev>", to: emails, subject: asunto, html }),
    });

    if (!emailRes.ok) {
      const err = await emailRes.text();
      return NextResponse.json({ error: "Error Resend: " + err }, { status: 400 });
    }

    // Registrar en audit
    await admin.from("audit_log").insert({
      accion: "crear", entidad: "almacen_alertas", modulo: "almacen",
      descripcion: `Email de alertas enviado a ${emails.length} destinatarios (${alertas.length} alertas)`,
      resultado: "exito", origen: "api_route",
    } as any);

    return NextResponse.json({ sent: true, alertas: alertas.length, destinatarios: emails.length });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}