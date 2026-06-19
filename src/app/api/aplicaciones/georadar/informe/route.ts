/**
 * src/app/api/aplicaciones/georadar/informe/route.ts
 *
 * Genera el informe Word de una pasada de georradar (datos + tabla de
 * anomalias + analisis IA si existe), lo sube al bucket 'georadar' y
 * devuelve una URL firmada para descarga.
 */

import { NextRequest, NextResponse } from "next/server";
import { generateInformeDocx, type InformeData } from "@/lib/georadar/generateInformeDocx";
import { createServerSupabase } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { logAuditErrorServer } from "@/lib/audit/logAuditError";

export async function POST(req: NextRequest) {
  let userId: string | null = null;
  let userRol: string | null = null;

  try {
    const supabase = createServerSupabase();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      userId = user.id;
      const { data: profile } = await supabase.from("users").select("role").eq("id", user.id).single();
      userRol = (profile as any)?.role ?? null;
    }
  } catch {
    // La comprobacion explicita de abajo exige usuario autenticado.
  }

  if (!userId) {
    return NextResponse.json({ error: "No autenticado" }, { status: 401 });
  }

  try {
    const body = (await req.json()) as { informeData: InformeData; pasadaId?: string };
    const { informeData, pasadaId } = body;

    if (!informeData || !informeData.anoms) {
      return NextResponse.json({ error: "Faltan datos del informe" }, { status: 400 });
    }

    const buffer = await generateInformeDocx(informeData);

    const fileName =
      "informe-georadar-" +
      (informeData.proyecto || "pasada").replace(/[^a-zA-Z0-9_-]/g, "_") +
      "-" +
      Date.now() +
      ".docx";
    const storagePath = "informes/" + fileName;

    const admin = createAdminClient();
    const { error: uploadErr } = await admin.storage.from("georadar").upload(storagePath, buffer, {
      contentType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    });
    if (uploadErr) throw new Error("Error subiendo informe: " + uploadErr.message);

    const { data: signed } = await admin.storage.from("georadar").createSignedUrl(storagePath, 600);

    if (pasadaId) {
      await admin
        .from("georadar_pasadas")
        .update({ informe_storage_path: storagePath, updated_at: new Date().toISOString() } as any)
        .eq("id", pasadaId);
    }

    await admin.from("audit_log").insert({
      user_id: userId,
      user_rol: userRol,
      accion: "crear",
      entidad: "georadar_pasadas",
      entidad_id: pasadaId ?? null,
      modulo: "aplicaciones.georadar",
      descripcion: "Genero informe Word de pasada de georradar",
      resultado: "exito",
      origen: "api_route",
    } as any);

    return NextResponse.json({ url: signed?.signedUrl, storagePath });
  } catch (err: any) {
    const mensaje = err?.message || "Error desconocido al generar el informe";
    await logAuditErrorServer({
      modulo: "aplicaciones.georadar",
      entidad: "georadar_pasadas",
      accion: "crear",
      descripcion: "Fallo al generar el informe Word de la pasada de georradar",
      errorDetalle: mensaje,
      userId,
      userRol,
    });
    return NextResponse.json({ error: mensaje }, { status: 500 });
  }
}
