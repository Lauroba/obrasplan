/**
 * Pruebas de regresión para el bug de truncado silencioso de asignaciones
 * en el Planificador, encontrado en PRODUCCIÓN el 08/09/2026 al verificar
 * el primer fix (rango de fechas): Supabase/PostgREST limita cada respuesta
 * a un máximo de filas (1000 en este proyecto) sin avisar, aunque el
 * cliente pida `.limit(5000)`. Al ampliar correctamente el rango de fechas
 * visible, una vista con muchas obras/recursos podía superar esas 1000
 * filas y, al no llevar ORDER BY, qué filas se descartaban era arbitrario
 * — el trazador (MURPROTEC - ESTELLA (R), Ionut F / Zigor O, 07/07/2026)
 * desaparecía de forma intermitente según el rango exacto pedido.
 *
 * Confirmado directamente contra la API real de Supabase en producción:
 * un rango con 1314 asignaciones reales devolvía solo 1000 sin paginar,
 * y las 1314 completas (trazador incluido) al paginar con .range().
 */
import { describe, expect, it, vi } from "vitest";
import { fetchAllPaginated, type PageResult } from "./fetchAllPaginated";

function makeServer<T>(allRows: T[], pageSize: number) {
  // Simula un servidor tipo PostgREST: nunca devuelve más de `pageSize` filas
  // por página, igual que Supabase limita a 1000 aunque se pida más.
  return vi.fn(async (from: number, to: number): Promise<PageResult<T>> => {
    const slice = allRows.slice(from, Math.min(to + 1, from + pageSize));
    return { data: slice, error: null };
  });
}

describe("fetchAllPaginated — fix truncado silencioso de asignaciones (08/09/2026)", () => {
  it("una sola página (menos filas que el tamaño de página) se resuelve en una llamada", async () => {
    const rows = Array.from({ length: 42 }, (_, i) => ({ id: i }));
    const server = makeServer(rows, 1000);
    const result = await fetchAllPaginated((from, to) => server(from, to), 1000);
    expect(result.error).toBeNull();
    expect(result.data).toHaveLength(42);
    expect(server).toHaveBeenCalledTimes(1);
  });

  it("caso real reproducido: 1314 filas con pageSize 1000 -> se recuperan las 1314, no solo 1000", async () => {
    const rows = Array.from({ length: 1314 }, (_, i) => ({ id: i }));
    const server = makeServer(rows, 1000);
    const result = await fetchAllPaginated((from, to) => server(from, to), 1000);
    expect(result.error).toBeNull();
    expect(result.data).toHaveLength(1314); // antes del fix, esto se quedaba en 1000
    expect(server).toHaveBeenCalledTimes(2); // página 1: 0-999, página 2: 1000-1313
  });

  it("el trazador (fila concreta que sólo existe pasada la página 1) se recupera igualmente", async () => {
    const rows = Array.from({ length: 1314 }, (_, i) => ({ id: i }));
    const trazador = { id: "MURPROTEC-ESTELLA-R_Zigor-O_2026-07-07" };
    rows.splice(1200, 0, trazador as any); // se cuela dentro de la segunda pagina
    const server = makeServer(rows, 1000);
    const result = await fetchAllPaginated((from, to) => server(from, to), 1000);
    expect(result.data).toContainEqual(trazador);
  });

  it("múltiples páginas completas seguidas de una parcial se acumulan todas en orden", async () => {
    const rows = Array.from({ length: 2500 }, (_, i) => ({ id: i }));
    const server = makeServer(rows, 1000);
    const result = await fetchAllPaginated((from, to) => server(from, to), 1000);
    expect(result.data).toHaveLength(2500);
    expect(result.data.map((r: any) => r.id)).toEqual(rows.map((r) => r.id));
    expect(server).toHaveBeenCalledTimes(3); // 1000 + 1000 + 500
  });

  it("un total exactamente múltiplo del tamaño de página sigue devolviendo todas las filas (aunque cueste una página extra vacía para confirmar el final)", async () => {
    // Con 2000 filas y pageSize 1000, la página 2 (1000-1999) llega LLENA (1000 filas), así que
    // el bucle no puede saber todavía si hay más: pide una 3ª página (2000-2999), que llega vacía,
    // y ahí sí se detiene. Es una llamada de red de más en este caso límite, pero NUNCA se pierden
    // filas por asumir que "página llena" == "fin de los datos" (que es justo el bug que se corrige).
    const rows = Array.from({ length: 2000 }, (_, i) => ({ id: i }));
    const server = makeServer(rows, 1000);
    const result = await fetchAllPaginated((from, to) => server(from, to), 1000);
    expect(result.data).toHaveLength(2000);
    expect(server).toHaveBeenCalledTimes(3);
  });

  it("cero filas se resuelve sin error y sin bucle", async () => {
    const server = makeServer<{ id: number }>([], 1000);
    const result = await fetchAllPaginated((from, to) => server(from, to), 1000);
    expect(result.error).toBeNull();
    expect(result.data).toEqual([]);
    expect(server).toHaveBeenCalledTimes(1);
  });

  it("un error en una página intermedia detiene la paginación y devuelve lo acumulado hasta entonces", async () => {
    let call = 0;
    const server = vi.fn(async (_from: number, _to: number): Promise<PageResult<{ id: number }>> => {
      call++;
      if (call === 1) return { data: Array.from({ length: 1000 }, (_, i) => ({ id: i })), error: null };
      return { data: null, error: new Error("network down") };
    });
    const result = await fetchAllPaginated((from, to) => server(from, to), 1000);
    expect(result.error).not.toBeNull();
    expect(result.data).toHaveLength(1000); // conserva lo ya traido, no lo descarta
    expect(server).toHaveBeenCalledTimes(2);
  });

  it("respeta el tope de seguridad maxPages y no entra en bucle infinito", async () => {
    // Servidor "malicioso"/inesperado que siempre devuelve una pagina llena.
    const server = vi.fn(async (from: number, _to: number): Promise<PageResult<{ id: number }>> => ({
      data: Array.from({ length: 10 }, (_, i) => ({ id: from + i })),
      error: null,
    }));
    const result = await fetchAllPaginated((from, to) => server(from, to), 10, 5);
    expect(server).toHaveBeenCalledTimes(5); // se detiene en maxPages, no sigue indefinidamente
    expect(result.data).toHaveLength(50);
  });
});
