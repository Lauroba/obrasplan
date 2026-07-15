/**
 * src/lib/utils/disponibilidadRrhh.ts
 *
 * Función centralizada de disponibilidad de RRHH.
 * Usada en: planificador (drag&drop, modal manual, panel lateral),
 *           API server-side de validación.
 *
 * Reglas (todas deben cumplirse para que el recurso esté disponible):
 *   1. activo === true
 *   2. asignable !== false
 *   3. fecha planificada >= fecha_inicio del recurso (inclusive)
 *   4. fecha planificada <= fecha_fin del recurso (inclusive), si tiene fecha_fin
 *
 * Zonas horarias: las fechas se tratan siempre como strings YYYY-MM-DD
 * para evitar conversiones UTC que desplazan un día en UTC+2.
 */

export interface RrhhDisponibilidadInput {
  activo: boolean;
  asignable?: boolean | null;
  fecha_inicio?: string | null;  // YYYY-MM-DD
  fecha_fin?: string | null;     // YYYY-MM-DD | null = sin límite
}

export type DisponibilidadResultado =
  | { disponible: true }
  | { disponible: false; motivo: string };

/**
 * Comprueba si un recurso RRHH está disponible para una fecha concreta.
 * @param rrhh  Campos del recurso (activo, asignable, fecha_inicio, fecha_fin)
 * @param fecha Fecha a comprobar en formato YYYY-MM-DD
 */
export function checkRrhhDisponibilidad(
  rrhh: RrhhDisponibilidadInput,
  fecha: string
): DisponibilidadResultado {
  // 1. Acceso activo
  if (!rrhh.activo) {
    return { disponible: false, motivo: "Este recurso no tiene acceso activo." };
  }

  // 2. Marcado como seleccionable
  if (rrhh.asignable === false) {
    return { disponible: false, motivo: "Este recurso no está habilitado para ser seleccionado." };
  }

  // 3. Fecha planificada >= fecha_inicio (comparación de strings YYYY-MM-DD, no UTC)
  if (rrhh.fecha_inicio && fecha < rrhh.fecha_inicio) {
    const legible = formatFechaES(rrhh.fecha_inicio);
    return {
      disponible: false,
      motivo: `Este recurso todavía no está disponible en la fecha seleccionada. Disponible desde el ${legible}.`,
    };
  }

  // 4. Fecha planificada <= fecha_fin (si tiene fecha_fin)
  if (rrhh.fecha_fin && fecha > rrhh.fecha_fin) {
    const legible = formatFechaES(rrhh.fecha_fin);
    return {
      disponible: false,
      motivo: `Este recurso finalizó su disponibilidad el ${legible}.`,
    };
  }

  return { disponible: true };
}

/**
 * Filtra un array de RRHH devolviendo solo los disponibles para una fecha.
 */
export function filtrarRrhhDisponibles<T extends RrhhDisponibilidadInput>(
  recursos: T[],
  fecha: string
): T[] {
  return recursos.filter((r) => checkRrhhDisponibilidad(r, fecha).disponible);
}

/**
 * Convierte YYYY-MM-DD a DD/MM/YYYY para mostrar al usuario.
 */
export function formatFechaES(fecha: string): string {
  const [y, m, d] = fecha.split("-");
  return `${d}/${m}/${y}`;
}
