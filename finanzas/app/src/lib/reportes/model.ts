/**
 * Datos de un reporte y sus resúmenes. Puro (sin red ni React Native): lo usan los tres exportadores
 * (Excel, CSV) y se prueba con Node.
 */
import { catLabel } from "../data";
import { conSaldoAcumulado, r2, saldoChica, saldosHoja, totalesHoja, type TotalesHoja } from "../caja/calc";
import { CIUDAD_LABEL, hojaKey, type Ciudad, type Hoja, type MovChica } from "../caja/types";
import type { State } from "../caja/store";
import { fdate, fdateLarga } from "../format";

export type ReporteOpciones = { ciudades: Ciudad[]; desde: string; hasta: string; diaria: boolean; chica: boolean };

export type HojaReporte = Hoja & { saldo_final_caja: number; saldo_final_cta_cte: number; totales: TotalesHoja };
export type ChicaReporte = { ciudad: Ciudad; saldoAnterior: number; saldoFinal: number; recibido: number; gastado: number; movs: (MovChica & { saldo: number })[] };

export type Reporte = ReporteOpciones & {
  generado: string; // ISO
  usuario: string;
  hojas: HojaReporte[];
  chicas: ChicaReporte[];
  /** true si no hubo conexión y se armó con lo guardado en este dispositivo (puede faltar lo de otras personas). */
  desdeLocal: boolean;
};

export const hojaReporte = (h: Hoja): HojaReporte => {
  const s = saldosHoja(h);
  return { ...h, saldo_final_caja: s.saldo_final_caja, saldo_final_cta_cte: s.saldo_final_cta_cte, totales: totalesHoja(h.filas) };
};

export function chicaReporte(ciudad: Ciudad, saldoAnterior: number, movs: MovChica[]): ChicaReporte {
  const orden = [...movs].sort((a, b) => (a.fecha === b.fecha ? (a.updated_at < b.updated_at ? -1 : 1) : a.fecha < b.fecha ? -1 : 1));
  const conSaldo = conSaldoAcumulado(saldoAnterior, orden);
  return {
    ciudad,
    saldoAnterior,
    saldoFinal: conSaldo.length ? conSaldo[conSaldo.length - 1].saldo : saldoAnterior,
    recibido: r2(orden.filter((m) => m.tipo === "TRANSFERENCIA").reduce((a, m) => a + m.monto, 0)),
    gastado: r2(orden.filter((m) => m.tipo === "EGRESO").reduce((a, m) => a + m.monto, 0)),
    movs: conSaldo,
  };
}

// ---- carga de datos --------------------------------------------------------------------------------

export type FuenteDatos = {
  hojas(ciudad: Ciudad, desde: string, hasta: string): Promise<Hoja[]>;
  chica(ciudad: Ciudad, desde: string, hasta: string): Promise<{ saldo_anterior: number; movimientos: MovChica[] }>;
};

/** Arma el reporte pidiéndole los datos al servidor; si no hay conexión, usa lo que hay en el dispositivo. */
export async function cargarReporte(o: ReporteOpciones & { usuario: string }, servidor: FuenteDatos, local: State, ahora = () => new Date().toISOString()): Promise<Reporte> {
  const hojas: HojaReporte[] = [];
  const chicas: ChicaReporte[] = [];
  let desdeLocal = false;
  for (const c of o.ciudades) {
    if (o.diaria) {
      try {
        hojas.push(...(await servidor.hojas(c, o.desde, o.hasta)).map(hojaReporte));
      } catch (e) {
        if (!sinRed(e)) throw e;
        desdeLocal = true;
        hojas.push(...Object.values(local.hojas).filter((h) => h.ciudad === c && h.fecha >= o.desde && h.fecha <= o.hasta).map(hojaReporte));
      }
    }
    if (o.chica) {
      try {
        const r = await servidor.chica(c, o.desde, o.hasta);
        chicas.push(chicaReporte(c, r.saldo_anterior, r.movimientos));
      } catch (e) {
        if (!sinRed(e)) throw e;
        desdeLocal = true;
        const { saldoBase, movs } = local.chica[c];
        const antes = movs.filter((m) => m.fecha < o.desde);
        chicas.push(chicaReporte(c, saldoChica(saldoBase, antes), movs.filter((m) => m.fecha >= o.desde && m.fecha <= o.hasta)));
      }
    }
  }
  hojas.sort((a, b) => (a.fecha === b.fecha ? (a.ciudad < b.ciudad ? -1 : 1) : a.fecha < b.fecha ? -1 : 1));
  return { ...o, generado: ahora(), hojas, chicas, desdeLocal };
}
const sinRed = (e: unknown) => {
  const x = e as { status?: number; code?: string };
  return x?.status === 0 || x?.code === "NETWORK" || (typeof x?.status === "number" && x.status >= 500);
};

// ---- resúmenes -------------------------------------------------------------------------------------

export type ResumenDia = { fecha: string; ciudad: Ciudad; saldoAnterior: number; ingresos: number; salidas: number; saldoFinal: number; ctaIngresos: number; ctaSalidas: number; ctaFinal: number; movimientos: number };

export const resumenPorDia = (hojas: HojaReporte[]): ResumenDia[] =>
  hojas.map((h) => ({
    fecha: h.fecha, ciudad: h.ciudad, saldoAnterior: h.saldo_anterior_caja, ingresos: h.totales.caja.ingreso, salidas: h.totales.caja.salida, saldoFinal: h.saldo_final_caja,
    ctaIngresos: h.totales.cta_cte.ingreso, ctaSalidas: h.totales.cta_cte.salida, ctaFinal: h.saldo_final_cta_cte, movimientos: h.filas.length,
  }));

export const totalesReporte = (r: Reporte) => ({
  ingresos: r2(r.hojas.reduce((a, h) => a + h.totales.caja.ingreso, 0)),
  salidas: r2(r.hojas.reduce((a, h) => a + h.totales.caja.salida, 0)),
  ctaIngresos: r2(r.hojas.reduce((a, h) => a + h.totales.cta_cte.ingreso, 0)),
  ctaSalidas: r2(r.hojas.reduce((a, h) => a + h.totales.cta_cte.salida, 0)),
  movimientos: r.hojas.reduce((a, h) => a + h.filas.length, 0),
  recibidoChica: r2(r.chicas.reduce((a, c) => a + c.recibido, 0)),
  gastadoChica: r2(r.chicas.reduce((a, c) => a + c.gastado, 0)),
});

// ---- textos ----------------------------------------------------------------------------------------

export const nombreCiudades = (cs: Ciudad[]) => cs.map((c) => CIUDAD_LABEL[c]).join(" y ");
export const periodoTexto = (desde: string, hasta: string) => (desde === hasta ? fdateLarga(desde) : `${fdate(desde)} al ${fdate(hasta)}`);
export const categoriaTexto = (categoria: string, subcategoria: string) => (categoria ? catLabel(categoria, subcategoria) : "");

/** "caja_AQP-MOQ_2026-10-01_a_2026-10-22" (sin extensión), para el nombre del archivo. */
export const nombreArchivo = (r: ReporteOpciones) => {
  const partes = [r.diaria && r.chica ? "caja" : r.diaria ? "caja-diaria" : "caja-chica", r.ciudades.join("-"), r.desde === r.hasta ? r.desde : `${r.desde}_a_${r.hasta}`];
  return partes.join("_");
};

export const claveHoja = hojaKey;

/** Importe con separador de miles y 2 decimales, sin "S/" (para tablas). Cero = vacío, como en el papel. */
export const num2 = (n: number, { cero = false } = {}) => {
  if (!n && !cero) return "";
  const [i, d] = Math.abs(n).toFixed(2).split(".");
  return `${n < 0 ? "-" : ""}${i.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${d}`;
};
