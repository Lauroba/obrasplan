/**
 * src/lib/audit/logAuditError.ts
 *
 * Helper único para registrar en audit_log los intentos fallidos de una
 * acción (permiso denegado, validación, error de Supabase, etc.).
 *
 * Por qué existe esta capa además de los triggers de PostgreSQL:
 * los triggers (audit_log_trigger) solo se disparan si el INSERT/UPDATE/DELETE
 * llega a ejecutarse con éxito. Si una operación falla antes de eso (RLS la
 * deniega, falla una validación de negocio, hay un error de red...) el trigger
 * nunca se entera. Esta capa cubre ese hueco.
 *
 * Dos formas de uso:
 *   1) Desde un API route de Next.js (server-side, ya tienes la request):
 *        await logAuditErrorServer({ ... })
 *   2) Desde un componente cliente (ej. catch de un formulario de maestros):
 *        await logAuditErrorClient({ ... })   // hace fetch a /api/audit/log-error
 *
 * No debe usarse para registrar éxitos — esos siguen cubiertos por los
 * triggers de BD, que son la fuente de verdad y no pueden evitarse desde
 * el frontend.
 */

import { createAdminClient } from "@/lib/supabase/admin";

export type AuditErrorInput = {
  modulo: string;          // ej. "maestros.tipos_obra"
  entidad: string;          // ej. "tipos_obra"
  entidadId?: string | null;
  accion: "crear" | "editar" | "eliminar" | "asignar" | "desasignar" | "otro";
  descripcion: string;      // texto legible, ej. "Intentó crear un tipo de obra"
  errorDetalle: string;     // mensaje de error capturado
  userId?: string | null;
  userRol?: string | null;
  ip?: string | null;
  userAgent?: string | null;
};

/**
 * Uso server-side (dentro de un API route, donde ya tienes acceso a `req`
 * y normalmente al usuario autenticado vía cookies/sesión).
 */
export async function logAuditErrorServer(input: AuditErrorInput) {
  try {
    const supabase = createAdminClient();
    await supabase.from("audit_log").insert({
      user_id: input.userId ?? null,
      user_rol: input.userRol ?? null,
      accion: mapAccion(input.accion),
      entidad: input.entidad,
      entidad_id: input.entidadId ?? null,
      modulo: input.modulo,
      descripcion: input.descripcion,
      resultado: "error",
      error_detalle: input.errorDetalle,
      origen: "api_route",
      ip_address: input.ip ?? null,
      user_agent: input.userAgent ?? null,
    } as any);
  } catch (e) {
    // Nunca dejar que un fallo al auditar tire abajo el flujo principal.
    // Si esto falla, solo lo dejamos en consola del servidor.
    console.error("[logAuditErrorServer] No se pudo registrar el error de auditoría:", e);
  }
}

/**
 * Uso client-side (dentro del catch de un formulario que escribe directo
 * contra Supabase, ej. maestros). Hace POST a /api/audit/log-error, que es
 * quien realmente inserta la fila usando el cliente admin.
 */
export async function logAuditErrorClient(input: Omit<AuditErrorInput, "ip" | "userAgent">) {
  try {
    await fetch("/api/audit/log-error", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
    });
  } catch (e) {
    // Igual que arriba: nunca debe romper la experiencia del usuario.
    console.error("[logAuditErrorClient] No se pudo registrar el error de auditoría:", e);
  }
}

function mapAccion(a: AuditErrorInput["accion"]): "crear" | "editar" | "eliminar" {
  // audit_accion (enum de BD) no incluye 'asignar'/'desasignar'/'otro';
  // se mapean a la acción más cercana para no romper el CHECK del enum.
  if (a === "crear") return "crear";
  if (a === "eliminar") return "eliminar";
  return "editar";
}
