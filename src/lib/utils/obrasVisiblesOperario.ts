// Reglas de visibilidad de obras para el rol operario ("partes"):
// - Vigente o futura: alguna asignación suya cuya fecha_fin >= hoy.
// - Pasada: solo si tiene un parte en estado 'pendiente' para esa obra,
//   o si hubo algún día trabajado (dentro de su asignación) sin parte creado.
// El admin no pasa por este filtro (ve todas las obras).

const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export interface AsignacionMin { obra_id: string; fecha_inicio: string; fecha_fin: string }
export interface ParteMin { obra_id: string; fecha: string; estado: string }

function obraVisible(obraId: string, asignacionesObra: AsignacionMin[], partesObra: ParteMin[], today: string): boolean {
  if (asignacionesObra.length === 0) return false;
  if (asignacionesObra.some((a) => a.fecha_fin >= today)) return true;

  const pastAsigs = asignacionesObra.filter((a) => a.fecha_fin < today);
  if (partesObra.some((p) => p.estado === "pendiente")) return true;

  const existingDates = new Set(partesObra.map((p) => p.fecha));
  for (const a of pastAsigs) {
    const start = new Date(a.fecha_inicio + "T12:00:00");
    const end = new Date(a.fecha_fin + "T12:00:00");
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      const ds = toDS(d);
      if (ds >= today) break;
      if (!existingDates.has(ds)) return true;
    }
  }
  return false;
}

export function filtrarObrasVisiblesOperario<T extends { id: string }>(
  obras: T[],
  misAsignaciones: AsignacionMin[],
  misPartes: ParteMin[]
): T[] {
  const today = toDS(new Date());
  const asigByObra: Record<string, AsignacionMin[]> = {};
  misAsignaciones.forEach((a) => { (asigByObra[a.obra_id] ||= []).push(a); });
  const partesByObra: Record<string, ParteMin[]> = {};
  misPartes.forEach((p) => { (partesByObra[p.obra_id] ||= []).push(p); });
  return obras.filter((o) => obraVisible(o.id, asigByObra[o.id] || [], partesByObra[o.id] || [], today));
}
