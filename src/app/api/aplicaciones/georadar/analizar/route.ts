/**
 * src/app/api/aplicaciones/georadar/analizar/route.ts
 *
 * Analisis IA de las anomalias detectadas en una pasada de georradar.
 *
 * Decision de arquitectura (confirmada explicitamente): la app HTML
 * original permitia que cada usuario pegara su propia clave de OpenAI o
 * Anthropic en un campo de texto. Eso NO se traslada a ObrasPlan: aqui se
 * usa una unica clave de empresa, leida de variables de entorno de Vercel
 * (GEORADAR_ANTHROPIC_API_KEY / GEORADAR_OPENAI_API_KEY), nunca expuesta
 * al navegador. El usuario no ve ni gestiona ninguna clave.
 *
 * El cliente solo envia los datos ya calculados (anomalias, capas,
 * parametros de la pasada) -- nunca el SGY en si, que se procesa en
 * navegador segun lo acordado.
 */

import { NextRequest, NextResponse } from "next/server";
import { buildPrompt, type PromptContext } from "@/lib/georadar/buildPrompt";
import { createServerSupabase } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { logAuditErrorServer } from "@/lib/audit/logAuditError";

const MODELO_CLAUDE = "claude-opus-4-5";
const MODELO_GPT = "gpt-4o";

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
    // Si no se resuelve sesion, se continua: la comprobacion explicita de
    // abajo ya exige usuario autenticado.
  }

  if (!userId) {
    return NextResponse.json({ error: "No autenticado" }, { status: 401 });
  }

  try {
    const body = await req.json();
    const { proveedor, promptContext, pasadaId } = body as {
      proveedor: "claude" | "gpt";
      promptContext: PromptContext;
      pasadaId?: string;
    };

    if (!promptContext || !promptContext.anoms || promptContext.anoms.length === 0) {
      return NextResponse.json({ error: "Sin anomalias para analizar" }, { status: 400 });
    }

    const prompt = buildPrompt(promptContext);
    let texto = "";
    let modelo = "";

    if (proveedor === "claude") {
      const key = process.env.GEORADAR_ANTHROPIC_API_KEY;
      if (!key) {
        return NextResponse.json({ error: "Clave de Claude no configurada en el servidor" }, { status: 500 });
      }
      modelo = MODELO_CLAUDE;
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": key,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({ model: modelo, max_tokens: 4000, messages: [{ role: "user", content: prompt }] }),
      });
      if (!r.ok) throw new Error("Claude " + r.status);
      const j = await r.json();
      texto = j.content?.[0]?.text || "Sin respuesta";
    } else {
      const key = process.env.GEORADAR_OPENAI_API_KEY;
      if (!key) {
        return NextResponse.json({ error: "Clave de GPT-4o no configurada en el servidor" }, { status: 500 });
      }
      modelo = MODELO_GPT;
      const r = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + key },
        body: JSON.stringify({
          model: modelo,
          max_tokens: 4000,
          messages: [
            { role: "system", content: "Experto GPR y geotecnia. Responde en espanol tecnico." },
            { role: "user", content: prompt },
          ],
        }),
      });
      if (!r.ok) throw new Error("GPT " + r.status);
      const j = await r.json();
      texto = j.choices?.[0]?.message?.content || "Sin respuesta";
    }

    // Auditoria de exito. Esta accion no es un INSERT/UPDATE/DELETE sobre
    // una tabla con trigger -- es una llamada de servicio -- por eso se
    // registra explicitamente aqui en vez de depender de un trigger de BD.
    try {
      const admin = createAdminClient();
      await admin.from("audit_log").insert({
        user_id: userId,
        user_rol: userRol,
        accion: "editar",
        entidad: "georadar_pasadas",
        entidad_id: pasadaId ?? null,
        modulo: "aplicaciones.georadar",
        descripcion: "Ejecuto analisis IA (" + modelo + ") sobre pasada de georradar",
        resultado: "exito",
        origen: "api_route",
      } as any);
    } catch (auditErr) {
      console.error("[georadar/analizar] No se pudo registrar auditoria de exito:", auditErr);
    }

    return NextResponse.json({ texto, modelo });
  } catch (err: any) {
    const mensaje = err?.message || "Error desconocido en analisis IA";
    await logAuditErrorServer({
      modulo: "aplicaciones.georadar",
      entidad: "georadar_pasadas",
      accion: "editar",
      descripcion: "Fallo al ejecutar analisis IA sobre pasada de georradar",
      errorDetalle: mensaje,
      userId,
      userRol,
    });
    return NextResponse.json({ error: mensaje }, { status: 500 });
  }
}
