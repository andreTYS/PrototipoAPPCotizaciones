/**
 * Modelo de la Caja diaria y la Caja chica. Es el mismo que el contrato de la API
 * (docs/API.md) y las tablas de db/migrations/001_caja.sql: los nombres de campo coinciden
 * a propósito para que lo que viaja por la red no necesite traducción.
 */
import type { Categoria, Subcategoria } from "../data";

export const CIUDADES = ["AQP", "MOQ"] as const;
export type Ciudad = (typeof CIUDADES)[number];
export const CIUDAD_LABEL: Record<Ciudad, string> = { AQP: "Arequipa", MOQ: "Moquegua" };

export const TIPOS_FILA = ["VTA", "OBRA", "OTRO"] as const;
export type TipoFila = (typeof TIPOS_FILA)[number];
export const TIPO_FILA_LABEL: Record<TipoFila, string> = { VTA: "Venta", OBRA: "Obra", OTRO: "Otro" };

export const COMPROBANTES = ["FACTURA", "BOLETA", "RECIBO", "NINGUNO"] as const;
export type Comprobante = (typeof COMPROBANTES)[number];
export const COMPROBANTE_LABEL: Record<Comprobante, string> = {
  FACTURA: "Factura",
  BOLETA: "Boleta",
  RECIBO: "Recibo",
  NINGUNO: "Sin comprobante",
};

/** Foto de un recibo. `localKey` apunta a la copia guardada en el dispositivo (IndexedDB en web). */
export type Adjunto = { id: string; mime: string; bytes: number; nombre?: string; localKey?: string; synced: boolean };

/** Una línea de la planilla "CAJA DIARIO". Los seis importes son los de las columnas del papel. */
export type Fila = {
  id: string;
  orden: number;
  tipo: TipoFila;
  descripcion: string;
  responsable: string;
  comprobante: Comprobante;
  caja_ingreso_efectivo: number;
  caja_ingreso_transf: number; // columna "YAPE/TRANSF" del ingreso
  caja_salida_efectivo: number;
  caja_salida_transf: number; // columna "YAPE/TRANSFER" de la salida
  cta_cte_ingreso: number;
  cta_cte_salida: number;
  categoria: Categoria | "";
  subcategoria: Subcategoria | "";
  /** Depósito, retiro o envío a caja chica: mueve dinero entre cajas, NO es un ingreso ni un gasto real. */
  interno: boolean;
  transferencia_id?: string | null;
  adjuntos: Adjunto[];
  updated_at: string;
  /** Versión que tiene el servidor: sirve para avisar si otra persona la cambió mientras se editaba. */
  version?: number;
  /** Solo local: ya existe en el servidor (no se manda ni se recibe). Decide si borrarla necesita avisar al servidor. */
  servidor?: boolean;
};

/** Cierre del día (arqueo): lo que se contó contra lo que calculó el sistema. diferencia > 0 sobra, < 0 falta. */
export type Cierre = { cerrada_en: string; cerrada_por: string; efectivo_contado: number; saldo_calculado: number; diferencia: number; nota: string };

export type Hoja = {
  /** Id que le puso el servidor; ausente mientras la hoja solo existe en este dispositivo. */
  id?: string;
  ciudad: Ciudad;
  fecha: string; // YYYY-MM-DD
  responsable_caja: string;
  obras_realizadas: string;
  maletas: string;
  escaleras: string;
  encargado_obra: string;
  /** Cierre del día anterior (derivado en el servidor). `estimado` = calculado aquí mientras no se sincroniza. */
  saldo_anterior_caja: number;
  saldo_anterior_cta_cte: number;
  estimado?: boolean;
  filas: Fila[];
  updated_at: string;
  version?: number;
  /** Presente cuando el día ya se cerró: queda bloqueado. */
  cierre?: Cierre | null;
};

export type TipoMovChica = "EGRESO" | "TRANSFERENCIA";
export type MovChica = {
  id: string;
  ciudad: Ciudad;
  fecha: string;
  tipo: TipoMovChica;
  descripcion: string;
  persona: string;
  categoria: Categoria | "";
  subcategoria: Subcategoria | "";
  monto: number; // siempre positivo; el tipo decide si suma o resta
  origen: "MANUAL" | "CAPTURA" | "TRANSFERENCIA";
  transferencia_id?: string | null;
  adjuntos: Adjunto[];
  updated_at: string;
  version?: number;
  /** Solo local: ya existe en el servidor. */
  servidor?: boolean;
};

export type Config = { saldo_inicial_caja: number; saldo_inicial_cta_cte: number; saldo_inicial_caja_chica: number };

export const hojaKey = (ciudad: Ciudad, fecha: string) => `${ciudad}:${fecha}`;
