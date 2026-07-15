import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { checkRrhhDisponibilidad } from "@/lib/utils/disponibilidadRrhh";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { recurso_tipo, recurso_id, fecha_inicio, fecha_fin, obra_id } = body;
    if (!recurso_tipo || !recurso_id || !fecha_inicio || !fecha_fin || !obra_id)
      return NextResponse.json({ valido: false, motivo: "Faltan campos obligatorios." }, { status: 400 });
    if (recurso_tipo !== "humano") return NextResponse.json({ valido: true });
    const supabase = createAdminClient();
    const { data: recurso, error } = await supabase
      .from("recursos_humanos")
      .select("id, activo, asignable, fecha_inicio, fecha_fin")
      .eq("id", recurso_id)
      .single();
    if (error || !recurso)
      return NextResponse.json({ valido: false, motivo: "Recurso no encontrado." }, { status: 404 });
    const s = new Date(fecha_inicio + "T12:00:00");
    const e = new Date(fecha_fin + "T12:00:00");
    for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
      const ds = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
      const check = checkRrhhDisponibilidad(recurso, ds);
      if (!check.disponible)
        return NextResponse.json({ valido: false, motivo: check.motivo }, { status: 422 });
    }
    return NextResponse.json({ valido: true });
  } catch (err: any) {
    return NextResponse.json({ valido: false, motivo: err?.message || "Error interno." }, { status: 500 });
  }
}
