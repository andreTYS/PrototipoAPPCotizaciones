/**
 * Las instancias reales del almacén y la sincronización (con el almacenamiento del dispositivo y la API del ERP),
 * más los ganchos de React para que las pantallas se actualicen solas.
 */
import { useEffect, useSyncExternalStore } from "react";
import { today } from "../format";
import { apiBajarFoto, apiJson, apiSubirFoto, currentSession } from "../api";
import { blobFoto, borrarFoto, guardarFotoRemota, urlFoto } from "./fotos";
import { crearStore, pendientes } from "./store";
import { crearSync } from "./sync";
import type { Adjunto } from "./types";

type Red = { onLine?: boolean; addEventListener?: (t: string, f: () => void) => void; removeEventListener?: (t: string, f: () => void) => void };
const g = globalThis as { navigator?: Red; addEventListener?: (t: string, f: () => void) => void; removeEventListener?: (t: string, f: () => void) => void; document?: { visibilityState?: string } };

/** ¿El navegador dice que hay internet? */
export const hayInternet = () => g.navigator?.onLine !== false;

/**
 * La app trabaja siempre conectada: los datos son los del servidor y no se guardan en el dispositivo (solo la sesión).
 * Sin conexión no se aceptan cambios nuevos, para que nadie crea que algo quedó guardado cuando no es así.
 */
export const store = crearStore({ hoy: today, borrarFoto, puedeEscribir: () => hayInternet() && sync.estado().fase !== "sin-conexion" });
export const sync = crearSync({ store, api: { json: apiJson, subirFoto: apiSubirFoto, bajarFoto: apiBajarFoto }, blobFoto, hoy: today });

/** Cada cuánto se pregunta al servidor si otra persona cambió algo (la consulta es liviana). */
export const CADA_MS = 6_000;

export const useCaja = () => useSyncExternalStore(store.subscribe, store.get);
export const useEstadoSync = () => useSyncExternalStore(sync.subscribe, sync.estado);

const suscribirRed = (f: () => void) => {
  g.addEventListener?.("online", f);
  g.addEventListener?.("offline", f);
  const quitar = sync.subscribe(f);
  return () => {
    g.removeEventListener?.("online", f);
    g.removeEventListener?.("offline", f);
    quitar();
  };
};
/** Hook: ¿se puede guardar ahora? (hay internet y el servidor responde) */
export const useEnLinea = () => useSyncExternalStore(suscribirRed, () => hayInternet() && sync.estado().fase !== "sin-conexion");

/**
 * Se mantiene al día sola: al abrir, al volver la conexión, al volver a la pestaña, cada pocos segundos mientras la
 * pestaña está a la vista, y enseguida después de cada cambio propio. Solo si hay sesión. Devuelve la función que lo apaga.
 */
export function iniciarSyncAutomatica(): () => void {
  let espera: ReturnType<typeof setTimeout> | null = null;
  const visible = () => g.document?.visibilityState !== "hidden";
  const intentar = (forzar = false) => {
    if (currentSession() && (visible() || forzar)) void sync.sincronizar();
  };
  const trasCambio = () => {
    if (!currentSession() || pendientes(store.get()) === 0) return;
    if (espera) clearTimeout(espera);
    espera = setTimeout(() => intentar(true), 150);
  };
  const quitar = store.subscribe(trasCambio);
  const cada = setInterval(() => intentar(), CADA_MS);
  const alVolver = () => visible() && intentar();
  const alConectar = () => intentar(true);
  g.addEventListener?.("online", alConectar);
  g.addEventListener?.("visibilitychange", alVolver);
  intentar(true);
  return () => {
    quitar();
    clearInterval(cada);
    if (espera) clearTimeout(espera);
    g.removeEventListener?.("online", alConectar);
    g.removeEventListener?.("visibilitychange", alVolver);
  };
}

/** Hook: ejecuta `iniciarSyncAutomatica` mientras `activo` sea verdadero (hay sesión). */
export function useSyncAutomatica(activo: boolean) {
  useEffect(() => (activo ? iniciarSyncAutomatica() : undefined), [activo]);
}

/** URL para mostrar la foto de un recibo: la copia local si la hay; si no (la subió otra persona), se baja y se guarda. */
export async function urlAdjunto(adj: Adjunto): Promise<string | null> {
  if (adj.localKey) {
    const u = await urlFoto(adj.localKey);
    if (u) return u;
  }
  const guardada = await urlFoto(`remota:${adj.id}`);
  if (guardada) return guardada;
  try {
    const blob = await sync.traerFotoRemota(adj.id);
    const key = await guardarFotoRemota(adj.id, blob);
    return key ? await urlFoto(key) : null;
  } catch {
    return null; // sin conexión y sin copia local: se muestra el marcador de foto
  }
}
