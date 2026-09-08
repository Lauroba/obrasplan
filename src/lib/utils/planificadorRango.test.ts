/**
 * Pruebas de regresión para el fix del bug:
 * "el Planificador no muestra asignaciones históricas de julio 2026 y
 * meses anteriores" (informe 08/09/2026).
 *
 * Causa raíz: el rango de fechas pedido a Supabase se calculaba UNA SOLA
 * VEZ al montar el componente (useCallback con dependencias vacías) a
 * partir del `startDate` de ese instante, y nunca se recalculaba al
 * navegar con las flechas / "Hoy" / cambiar de vista (semana/mes/año).
 * Estas pruebas cubren la lógica PURA que sustituye a ese cálculo
 * (extraída a getRangoFetchAsignaciones), usando como trazador el caso
 * real verificado en Supabase: MURPROTEC - ESTELLA (R), Ionut F / Zigor O
 * / KANGOO-1852MZF, 07/07/2026.
 *
 * Nota de cobertura: los tests 1-5 del informe se verifican aquí a nivel
 * de la función pura que decide qué rango se pide a Supabase (que es
 * exactamente donde estaba el bug). El test 6 (obra Facturada / Finalizada
 * / Archivada sigue mostrando histórico) no depende de esta función --ni
 * esta ni la query real de Supabase filtran por estado de la obra en
 * ningún punto-- y se verifica por inspección de código más la
 * comprobación manual de aceptación (sección 14 del informe: MURPROTEC
 * está actualmente "6-Facturado" y su asignación del 07/07 se localizó
 * sin problema). No hay infraestructura de tests de componentes (RTL) en
 * el repo todavía; añadirla es un cambio mayor que no se ha hecho para no
 * sobredimensionar este fix.
 */
import { describe, expect, it } from "vitest";
import { asignacionSolapaRango, fechaEnRango, getRangoFetchAsignaciones } from "./planificadorRango";

const WEEK = 7;
const MONTH = 31;
const YEAR = 364;

// Ionut F / Zigor O, MURPROTEC - ESTELLA (R)
const asignacionIonut7Julio = { fecha_inicio: "2026-07-07", fecha_fin: "2026-07-07" };
// KANGOO-1852MZF (mismo día, otra obra/recurso, misma fecha)
const asignacionKangoo7Julio = { fecha_inicio: "2026-07-07", fecha_fin: "2026-07-07" };
// Ejemplo de sección 14: 11/05/2026
const asignacion11Mayo = { fecha_inicio: "2026-05-11", fecha_fin: "2026-05-11" };
// Asignación de agosto (ejemplo del informe: Lucian C / Mihail B / Vasile E, 13/08/2026)
const asignacion13Agosto = { fecha_inicio: "2026-08-13", fecha_fin: "2026-08-13" };

describe("getRangoFetchAsignaciones — Planificador (fix histórico julio/agosto 2026)", () => {
  it("Test 1: una asignación de persona en julio aparece al abrir julio", () => {
    // Lunes de la semana que contiene el 07/07/2026
    const rango = getRangoFetchAsignaciones(new Date(2026, 6, 6), WEEK);
    expect(asignacionSolapaRango(asignacionIonut7Julio, rango)).toBe(true);
  });

  it("Test 2: una asignación de vehículo en julio aparece al abrir julio", () => {
    const rango = getRangoFetchAsignaciones(new Date(2026, 6, 6), WEEK);
    expect(asignacionSolapaRango(asignacionKangoo7Julio, rango)).toBe(true);
  });

  it("Test 3: una asignación de persona en mayo aparece al abrir mayo", () => {
    // Lunes de la semana que contiene el 11/05/2026
    const rango = getRangoFetchAsignaciones(new Date(2026, 4, 11), WEEK);
    expect(asignacionSolapaRango(asignacion11Mayo, rango)).toBe(true);
  });

  it("Test 4: una asignación de agosto sigue funcionando", () => {
    const rango = getRangoFetchAsignaciones(new Date(2026, 7, 10), WEEK);
    expect(asignacionSolapaRango(asignacion13Agosto, rango)).toBe(true);
  });

  it("Test 5: navegar julio → agosto → julio muestra las asignaciones correctamente en ambos pasos por julio", () => {
    const rangoJulio1 = getRangoFetchAsignaciones(new Date(2026, 6, 6), WEEK);
    expect(asignacionSolapaRango(asignacionIonut7Julio, rangoJulio1)).toBe(true);

    const rangoAgosto = getRangoFetchAsignaciones(new Date(2026, 7, 10), WEEK);
    expect(asignacionSolapaRango(asignacion13Agosto, rangoAgosto)).toBe(true);
    // Al estar en agosto, julio puede o no estar cubierto por el margen de prefetch,
    // pero eso es aceptable: lo que NUNCA debe pasar es que julio deje de cargarse
    // al volver a navegar hacia atrás (lo que sí comprueba la siguiente aserción).

    const rangoJulio2 = getRangoFetchAsignaciones(new Date(2026, 6, 6), WEEK);
    expect(rangoJulio2).toEqual(rangoJulio1); // función pura: mismo input -> mismo output, sin caché ni estado colgado
    expect(asignacionSolapaRango(asignacionIonut7Julio, rangoJulio2)).toBe(true);
  });

  it("antes del fix (rango fijo calculado solo al montar) este mismo escenario fallaba: navegar a julio no recalculaba el rango y la ventana quedaba anclada a la fecha de apertura de la página", () => {
    // Simulamos el comportamiento ANTIGUO: el rango se calcula una vez con el
    // startDate de "hoy" (apertura de página, p.ej. principios de septiembre) y
    // nunca se vuelve a calcular al navegar a julio.
    const rangoCalculadoAlAbrirLaPagina = getRangoFetchAsignaciones(new Date(2026, 8, 7), WEEK); // lunes 07/09/2026
    // Julio queda fuera de esa ventana congelada -> este es el bug reportado.
    expect(asignacionSolapaRango(asignacionIonut7Julio, rangoCalculadoAlAbrirLaPagina)).toBe(false);

    // Con el fix, al navegar a julio SÍ se recalcula el rango con el startDate real de julio:
    const rangoRecalculadoAlNavegarAJulio = getRangoFetchAsignaciones(new Date(2026, 6, 6), WEEK);
    expect(asignacionSolapaRango(asignacionIonut7Julio, rangoRecalculadoAlNavegarAJulio)).toBe(true);
  });

  it("la vista 'año' (364 días visibles) también queda cubierta, no solo 'semana'/'mes'", () => {
    // Antes del fix, incluso SIN navegar, la vista año pintaba 364 días pero solo se
    // cargaba una ventana fija de 84 días -> gran parte del año quedaba vacía.
    const inicioAnio = new Date(2026, 0, 5); // lunes 05/01/2026
    const rango = getRangoFetchAsignaciones(inicioAnio, YEAR);
    const finVisible = new Date(2026, 0, 5); finVisible.setDate(finVisible.getDate() + YEAR - 1);
    expect(fechaEnRango("2026-01-05", rango)).toBe(true); // primer día visible
    expect(fechaEnRango(toDS(finVisible), rango)).toBe(true); // último día visible
  });

  it("el rango depende tanto de startDate como del número de días visibles (viewMode)", () => {
    const rangoSemana = getRangoFetchAsignaciones(new Date(2026, 6, 6), WEEK);
    const rangoMes = getRangoFetchAsignaciones(new Date(2026, 6, 6), MONTH);
    expect(rangoMes.toDs > rangoSemana.toDs).toBe(true); // vista mes pide más días hacia adelante que vista semana
  });

  it("fechaEnRango es inclusivo en ambos extremos", () => {
    const rango = { fromDs: "2026-07-01", toDs: "2026-07-31" };
    expect(fechaEnRango("2026-07-01", rango)).toBe(true);
    expect(fechaEnRango("2026-07-31", rango)).toBe(true);
    expect(fechaEnRango("2026-06-30", rango)).toBe(false);
    expect(fechaEnRango("2026-08-01", rango)).toBe(false);
  });
});

function toDS(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
