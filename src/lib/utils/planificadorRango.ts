/**
 * src/lib/utils/planificadorRango.ts
 *
 * Calculo puro del rango de fechas que el Planificador pide a Supabase para
 * la tabla `asignaciones`, en funcion del rango REALMENTE visible
 * (startDate .. startDate + diasVisibles - 1), con un margen de prefetch
 * para que la navegacion (semana/mes/año, flechas, "Hoy") se sienta fluida
 * sin disparar una consulta por cada dia.
 *
 * Extraido de src/app/planificacion/page.tsx como parte del fix del bug:
 * "el Planificador no muestra asignaciones historicas de julio 2026 y
 * meses anteriores" (informe 08/09/2026).
 *
 * Causa raiz: el rango se calculaba UNA UNICA VEZ al montar el componente
 * (dentro de un useCallback con dependencias vacias), tomando el startDate
 * de ese instante. Al navegar con las flechas o "Hoy", startDate cambiaba
 * pero la funcion de fetch nunca se volvia a ejecutar, asi que la ventana
 * de datos cargada quedaba congelada a la fecha de apertura de la pagina:
 * todo lo anterior a esa ventana dejaba de estar en memoria y desaparecia
 * del calendario, aunque el registro siguiera intacto en Supabase (Ficha
 * Obra y Ficha RRHH, que no filtran por fecha, lo seguian mostrando bien).
 *
 * El fix: calcular el rango a partir del rango REALMENTE visible (que
 * depende de startDate Y del viewMode, ya que "año" pinta muchos mas dias
 * que "semana") y recalcularlo/refetchear cada vez que cualquiera de los
 * dos cambia.
 */

// Margen de prefetch alrededor del rango visible, en dias. Mantiene la
// navegacion fluida (no hay que refetchear en cada click si te mueves
// dentro de esta ventana) sin cargar todo el historico de golpe.
const MARGEN_ATRAS_DIAS = 28;
const MARGEN_ADELANTE_DIAS = 56;

function toDS(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export interface RangoFetchAsignaciones {
  fromDs: string;
  toDs: string;
}

/**
 * Calcula el rango [fromDs, toDs] (YYYY-MM-DD, inclusive) a pedir a
 * Supabase para cubrir todo lo que el Planificador va a pintar.
 *
 * @param startDate     Primer dia visible en el calendario (el startDate del componente).
 * @param diasVisibles  Numero de dias que se pintan a partir de startDate (DAYS_COUNT[viewMode]).
 */
export function getRangoFetchAsignaciones(startDate: Date, diasVisibles: number): RangoFetchAsignaciones {
  const visibleStart = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate());
  const visibleEnd = new Date(visibleStart);
  visibleEnd.setDate(visibleEnd.getDate() + Math.max(diasVisibles, 1) - 1);

  const rs = new Date(visibleStart);
  rs.setDate(rs.getDate() - MARGEN_ATRAS_DIAS);
  const re = new Date(visibleEnd);
  re.setDate(re.getDate() + MARGEN_ADELANTE_DIAS);

  return { fromDs: toDS(rs), toDs: toDS(re) };
}

/** true si `fecha` (YYYY-MM-DD) cae dentro de `rango` (inclusive). */
export function fechaEnRango(fecha: string, rango: RangoFetchAsignaciones): boolean {
  return fecha >= rango.fromDs && fecha <= rango.toDs;
}

/**
 * true si una asignacion (por fecha_inicio/fecha_fin) SOLAPA el rango dado.
 * Misma logica de solapamiento que aplica la query real de Supabase
 * (.gte("fecha_fin", fromDs).lte("fecha_inicio", toDs)) y que la lista de
 * requisitos del Planificador (assignment.start <= visibleEnd AND
 * assignment.end >= visibleStart).
 */
export function asignacionSolapaRango(
  asignacion: { fecha_inicio: string; fecha_fin: string },
  rango: RangoFetchAsignaciones
): boolean {
  return asignacion.fecha_fin >= rango.fromDs && asignacion.fecha_inicio <= rango.toDs;
}
