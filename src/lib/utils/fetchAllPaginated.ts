/**
 * src/lib/utils/fetchAllPaginated.ts
 *
 * Pagina automaticamente cualquier fuente de datos que, como PostgREST/Supabase,
 * limita cada respuesta a un numero maximo de filas SIN AVISAR (el servidor
 * puede truncar en silencio aunque el cliente pida un .limit() mayor).
 *
 * BUG REAL encontrado en produccion el 08/09/2026, DESPUES de desplegar el fix
 * de rango de fechas del Planificador (ver planificadorRango.ts): el
 * Planificador pedia `asignaciones` con `.limit(5000)`, pero Supabase
 * (PostgREST) devolvia como mucho 1000 filas por respuesta - el `.limit()`
 * del cliente NO tiene efecto por encima del limite del servidor, y no hay
 * ningun error visible, solo una respuesta truncada.
 *
 * Al corregir el rango de fechas para que cubra correctamente todo lo
 * visible (fix anterior), el numero de asignaciones que solapan ese rango en
 * TODA la empresa (no solo una obra) podia superar 1000 filas. Como la query
 * no llevaba ORDER BY, que filas se descartaban era esencialmente arbitrario:
 * la misma asignacion (la usada como trazador - MURPROTEC - ESTELLA (R),
 * Ionut F / Zigor O, 07/07/2026) podia aparecer o desaparecer segun el orden
 * fisico con el que Postgres devolviera las filas para esa query en concreto.
 * Confirmado en produccion: para un rango con 1314 asignaciones reales, la
 * API sin paginar devolvia solo 1000.
 *
 * Esta funcion pagina en bloques de `pageSize` (por defecto 1000, el limite
 * de este proyecto Supabase) hasta agotar los resultados, para que ese
 * limite del servidor nunca trunque datos en silencio.
 */

export interface PageResult<T> {
  data: T[] | null;
  error: unknown;
}

export interface FetchAllPaginatedResult<T> {
  data: T[];
  error: unknown;
}

/**
 * @param fetchPage  Devuelve UNA pagina de resultados para las filas [from, to]
 *                   (inclusive, base 0), igual que `.range(from, to)` de supabase-js.
 * @param pageSize   Filas por pagina. Debe ser <= al limite real del servidor
 *                   (en este proyecto Supabase: 1000).
 * @param maxPages   Tope de seguridad para no entrar en un bucle infinito si el
 *                   servidor se comporta de forma inesperada (por defecto 50
 *                   paginas = hasta 50.000 filas con pageSize=1000).
 */
export async function fetchAllPaginated<T>(
  fetchPage: (from: number, to: number) => Promise<PageResult<T>>,
  pageSize = 1000,
  maxPages = 50
): Promise<FetchAllPaginatedResult<T>> {
  let all: T[] = [];
  let from = 0;
  for (let i = 0; i < maxPages; i++) {
    const { data, error } = await fetchPage(from, from + pageSize - 1);
    if (error) return { data: all, error };
    all = all.concat(data || []);
    if (!data || data.length < pageSize) break;
    from += pageSize;
  }
  return { data: all, error: null };
}
