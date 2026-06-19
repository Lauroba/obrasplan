/**
 * src/app/api/audit/log-error/route.ts
 *
 * Endpoint único reutilizable por cualquier formulario/módulo que escriba
 * directo contra Supabase desde el cliente (patrón actual de los maestros:
 * tipos_obra, clientes, vehiculos, maquinaria, materiales, tipos_trabajo,
 * estados_obra) y necesite registrar un intento fallido.
 *
 * No usar este endpoint para registrar éxitos: los éxitos ya quedan
 * cubiertos automáticamente por los triggers de PostgreSQL sobre cada
 * tabla (ver migración 026), que no dependen del frontend.
 *
 * Intencionadamente NO se valida aquí el rol del usuario contra la acción:
 * el objetivo es simplemente dejar constancia de que algo falló. La
 * autorización real ya la decide RLS en la operación original.
 */

import { NextRequest, NextResponse } from "next/server";
import { logAuditErrorServer } from "@/lib/audit/logAuditError";
import { createServerSupabase } from "@/lib/supabase/server";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { modulo, entidad, entidadId, accion, descripcion, errorDetalle } = body;

    if (!modulo || !entidad || !accion || !descripcion || !errorDetalle) {
      return NextResponse.json(
        { error: "Faltan campos obligatorios: modulo, entidad, accion, descripcion, errorDetalle" },
        { status: 400 }
      );
    }

    // Intentar resolver el usuario autenticado y su rol desde la cookie de sesión.
    let userId: string | null = null;
    let userRol: string | null = null;
    try {
      const supabase = createServerSupabase();
      const { data: { user } } = await supabase.auth.getUser();
      if (user) {
        userId = user.id;
        const { data: profile } = await supabase.from("users").select("role").eq("id", user.id).single();
        userRol = (profile as any)?.role ?? null;
      }
    } catch {
      // Si no se puede resolver el usuario, se registra igualmente como anónimo.
    }

    const ip =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      req.headers.get("x-real-ip") ||
      null;
    const userAgent = req.headers.get("user-agent") || null;

    await logAuditErrorServer({
      modulo,
      entidad,
      entidadId: entidadId ?? null,
      accion,
      descripcion,
      errorDetalle,
      userId,
      userRol,
      ip,
      userAgent,
    });

    return NextResponse.json({ success: true });
  } catch (e: any) {
    // Este endpoint nunca debe devolver un error que rompa el flujo del
    // formulario que lo llama; se responde 200 igualmente y se deja constancia
    // en consola del servidor para depuración.
    console.error("[/api/audit/log-error] Error inesperado:", e);
    return NextResponse.json({ success: false });
  }
}
