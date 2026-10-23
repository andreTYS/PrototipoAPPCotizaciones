/**
 * Cálculos de la caja. Funciones puras (sin React ni red) para poder probarlas con Node.
 * La API de referencia (api/) calcula lo mismo en SQL; api/src/crosscheck.test.ts comprueba que
 * ambos den exactamente los mismos números.
 */
import type { Adjunto, Config, Fila, Hoja, MovChica } from "./types";

/** Redondea a centavos para que las sumas de decimales no arrastren 0.30000000000000004. */
export const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const sum = (xs: number[]) => r2(xs.reduce((a, b) => a + b, 0));

export type Par = { ingreso: number; salida: number; total: number };
export type TotalesHoja = { efectivo: Par; transf: Par; caja: Par; cta_cte: Par };

const par = (ingreso: number, salida: number): Par => ({ ingreso: r2(ingreso), salida: r2(salida), total: r2(ingreso - salida) });

/** Los cuatro recuadros del pie de la planilla: Efectivo, Transf/Yape, Caja (suma) y Cuenta corriente. */
export function totalesHoja(filas: Pick<Fila, "caja_ingreso_efectivo" | "caja_ingreso_transf" | "caja_salida_efectivo" | "caja_salida_transf" | "cta_cte_ingreso" | "cta_cte_salida">[]): TotalesHoja {
  const ingEf = sum(filas.map((f) => f.caja_ingreso_efectivo));
  const ingTr = sum(filas.map((f) => f.caja_ingreso_transf));
  const salEf = sum(filas.map((f) => f.caja_salida_efectivo));
  const salTr = sum(filas.map((f) => f.caja_salida_transf));
  return {
    efectivo: par(ingEf, salEf),
    transf: par(ingTr, salTr),
    caja: par(ingEf + ingTr, salEf + salTr),
    cta_cte: par(sum(filas.map((f) => f.cta_cte_ingreso)), sum(filas.map((f) => f.cta_cte_salida))),
  };
}

export type SaldosHoja = { totales: TotalesHoja; saldo_final_caja: number; saldo_final_cta_cte: number };

export function saldosHoja(h: Pick<Hoja, "filas" | "saldo_anterior_caja" | "saldo_anterior_cta_cte">): SaldosHoja {
  const totales = totalesHoja(h.filas);
  return {
    totales,
    saldo_final_caja: r2(h.saldo_anterior_caja + totales.caja.total),
    saldo_final_cta_cte: r2(h.saldo_anterior_cta_cte + totales.cta_cte.total),
  };
}

/**
 * Lo que de una fila llega al ERP (Contabilidad → Flujo de caja). Los movimientos internos
 * (depósito a banco, retiro, envío a caja chica) no se reflejan: sería contar dos veces el mismo dinero.
 */
export function montosParaErp(f: Pick<Fila, "interno" | "caja_ingreso_efectivo" | "caja_ingreso_transf" | "cta_cte_ingreso" | "caja_salida_efectivo" | "caja_salida_transf" | "cta_cte_salida">) {
  if (f.interno) return { ingreso: 0, salida: 0 };
  return {
    ingreso: r2(f.caja_ingreso_efectivo + f.caja_ingreso_transf + f.cta_cte_ingreso),
    salida: r2(f.caja_salida_efectivo + f.caja_salida_transf + f.cta_cte_salida),
  };
}

export type ErroresFila = Partial<Record<"descripcion" | "responsable" | "montos" | "categoria" | "subcategoria", string>>;

export function validarFila(f: Fila): ErroresFila {
  const e: ErroresFila = {};
  if (!f.descripcion.trim()) e.descripcion = "Escribe la descripción";
  if (!f.responsable.trim()) e.responsable = "Indica el responsable";
  const importes = [f.caja_ingreso_efectivo, f.caja_ingreso_transf, f.caja_salida_efectivo, f.caja_salida_transf, f.cta_cte_ingreso, f.cta_cte_salida];
  if (importes.some((n) => !(n >= 0))) e.montos = "Los importes no pueden ser negativos";
  else if (importes.every((n) => n === 0)) e.montos = "Ingresa al menos un importe";
  const { salida } = montosParaErp(f);
  if (salida > 0) {
    if (!f.categoria) e.categoria = "Elige la categoría del gasto";
    else if (f.categoria === "Gastos fijos" && !f.subcategoria) e.subcategoria = "Elige el tipo de gasto fijo";
  }
  return e;
}

export const efectoChica = (m: Pick<MovChica, "tipo" | "monto">) => (m.tipo === "TRANSFERENCIA" ? m.monto : -m.monto);

/** Saldo de la caja chica = lo que había antes de los movimientos guardados aquí + el efecto de cada uno. */
export function saldoChica(saldoBase: number, movs: Pick<MovChica, "tipo" | "monto">[]) {
  return r2(saldoBase + movs.reduce((a, m) => a + efectoChica(m), 0));
}

/** Movimientos de caja chica con su saldo acumulado, del más antiguo al más nuevo. */
export function conSaldoAcumulado<T extends Pick<MovChica, "tipo" | "monto">>(saldoBase: number, movs: T[]) {
  let acc = saldoBase;
  return movs.map((m) => {
    acc = r2(acc + efectoChica(m));
    return { ...m, saldo: acc };
  });
}

/**
 * Saldos de apertura de una hoja que todavía no existe en el servidor: el cierre de la hoja anterior
 * más reciente que conocemos, o los saldos iniciales de la ciudad si es la primera. El servidor
 * recalcula esto al sincronizar, así que es solo una estimación para poder trabajar sin conexión.
 */
export function aperturaEstimada(hojas: Pick<Hoja, "fecha" | "filas" | "saldo_anterior_caja" | "saldo_anterior_cta_cte">[], fecha: string, config: Pick<Config, "saldo_inicial_caja" | "saldo_inicial_cta_cte">) {
  const previa = hojas.filter((h) => h.fecha < fecha).sort((a, b) => (a.fecha < b.fecha ? 1 : -1))[0];
  if (!previa) return { saldo_anterior_caja: config.saldo_inicial_caja, saldo_anterior_cta_cte: config.saldo_inicial_cta_cte };
  const s = saldosHoja(previa);
  return { saldo_anterior_caja: s.saldo_final_caja, saldo_anterior_cta_cte: s.saldo_final_cta_cte };
}

// ---- Fusión de lo que trae el servidor con lo que hay pendiente de enviar -------------------------

export type Pendientes = {
  filasPendientes: Set<string>; // filas con un cambio local aún sin enviar: gana la versión local
  filasBorradas: Set<string>; // filas que el usuario borró y el servidor todavía muestra
  adjuntosBorrados: Set<string>;
  hojaSucia: boolean; // encabezado/observaciones editados localmente sin enviar
};

const ordenar = <T extends { orden: number; id: string }>(xs: T[]) => [...xs].sort((a, b) => a.orden - b.orden || (a.id < b.id ? -1 : 1));

/** Une una hoja del servidor con la copia local sin perder nada que aún no se haya enviado. */
export function fusionarHoja(local: Hoja | undefined, servidor: Hoja, p: Pendientes): Hoja {
  const locales = new Map((local?.filas ?? []).map((f) => [f.id, f]));
  const filas: Fila[] = [];
  const vistas = new Set<string>();
  for (const sf of servidor.filas) {
    vistas.add(sf.id);
    if (p.filasBorradas.has(sf.id)) continue;
    const lf = locales.get(sf.id);
    if (lf && p.filasPendientes.has(sf.id)) {
      filas.push(lf);
      continue;
    }
    // Conserva la copia local de la foto (localKey) y las fotos que aún no subieron.
    const localAdj = new Map((lf?.adjuntos ?? []).map((a) => [a.id, a]));
    const adjuntos: Adjunto[] = sf.adjuntos
      .filter((a) => !p.adjuntosBorrados.has(a.id))
      .map((a) => ({ ...a, synced: true, localKey: localAdj.get(a.id)?.localKey }));
    for (const a of lf?.adjuntos ?? []) if (!a.synced && !adjuntos.some((x) => x.id === a.id)) adjuntos.push(a);
    filas.push({ ...sf, adjuntos });
  }
  for (const lf of local?.filas ?? []) if (!vistas.has(lf.id) && p.filasPendientes.has(lf.id)) filas.push(lf);

  const cab = p.hojaSucia && local ? local : servidor;
  return {
    ...servidor,
    responsable_caja: cab.responsable_caja,
    obras_realizadas: cab.obras_realizadas,
    maletas: cab.maletas,
    escaleras: cab.escaleras,
    encargado_obra: cab.encargado_obra,
    estimado: false,
    filas: ordenar(filas),
  };
}

/** Une los movimientos de caja chica: el servidor manda, salvo lo pendiente (gana local) y lo borrado. */
export function fusionarMovs(local: MovChica[], servidor: MovChica[], pendientes: Set<string>, borrados: Set<string>): MovChica[] {
  const porId = new Map(local.map((m) => [m.id, m]));
  const out: MovChica[] = [];
  const vistos = new Set<string>();
  for (const sm of servidor) {
    vistos.add(sm.id);
    if (borrados.has(sm.id)) continue;
    const lm = porId.get(sm.id);
    if (lm && pendientes.has(sm.id)) {
      out.push(lm);
      continue;
    }
    const localAdj = new Map((lm?.adjuntos ?? []).map((a) => [a.id, a]));
    const adjuntos: Adjunto[] = sm.adjuntos.map((a) => ({ ...a, synced: true, localKey: localAdj.get(a.id)?.localKey }));
    for (const a of lm?.adjuntos ?? []) if (!a.synced && !adjuntos.some((x) => x.id === a.id)) adjuntos.push(a);
    out.push({ ...sm, adjuntos });
  }
  for (const lm of local) if (!vistos.has(lm.id) && pendientes.has(lm.id)) out.push(lm);
  return out.sort((a, b) => (a.fecha === b.fecha ? (a.updated_at < b.updated_at ? -1 : 1) : a.fecha < b.fecha ? -1 : 1));
}
