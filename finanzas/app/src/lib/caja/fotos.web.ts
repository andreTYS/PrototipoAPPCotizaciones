/**
 * Fotos de recibos en la PWA: los bytes viven en IndexedDB (almacén `photos`), así sobreviven a recargar la
 * página y se pueden subir al servidor cuando vuelva la conexión. `urlFoto` entrega una URL temporal (blob:)
 * para mostrarla en pantalla.
 */
import { idbDel, idbGet, idbSet } from "../idb.web";
import { nuevoId } from "./ids";

export type FotoGuardada = { key: string; mime: string; bytes: number };

const urls = new Map<string, string>();

export async function guardarFoto(uri: string): Promise<FotoGuardada> {
  const blob = await (await fetch(uri)).blob();
  const key = nuevoId();
  await idbSet("photos", key, blob);
  return { key, mime: blob.type || "image/jpeg", bytes: blob.size };
}

export async function blobFoto(key: string): Promise<Blob | null> {
  return ((await idbGet<Blob>("photos", key)) as Blob | undefined) ?? null;
}

export async function urlFoto(key: string): Promise<string | null> {
  const ya = urls.get(key);
  if (ya) return ya;
  const blob = await blobFoto(key);
  if (!blob) return null;
  const url = URL.createObjectURL(blob);
  urls.set(key, url);
  return url;
}

export async function borrarFoto(key: string): Promise<void> {
  const url = urls.get(key);
  if (url) URL.revokeObjectURL(url);
  urls.delete(key);
  await idbDel("photos", key);
}

/** Guarda la copia de una foto que se bajó del servidor (para no volver a bajarla); devuelve su clave. */
export async function guardarFotoRemota(id: string, blob: Blob): Promise<string> {
  const key = `remota:${id}`;
  await idbSet("photos", key, blob);
  return key;
}
