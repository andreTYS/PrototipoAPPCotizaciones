/**
 * Fotos de recibos en el dispositivo (Android/iOS). Aquí la "clave" es el propio URI del archivo; la versión
 * completa con copia persistente en IndexedDB es fotos.web.ts, que es la que usa la PWA.
 */
export type FotoGuardada = { key: string; mime: string; bytes: number };

export async function guardarFoto(uri: string): Promise<FotoGuardada> {
  const blob = await (await fetch(uri)).blob();
  return { key: uri, mime: blob.type || "image/jpeg", bytes: blob.size };
}
export const urlFoto = async (key: string): Promise<string | null> => key;
export async function blobFoto(key: string): Promise<Blob | null> {
  try {
    return await (await fetch(key)).blob();
  } catch {
    return null;
  }
}
export const borrarFoto = async (_key: string): Promise<void> => {};
/** Guarda en el dispositivo una foto que se bajó del servidor; devuelve su clave. */
export const guardarFotoRemota = async (_id: string, _blob: Blob): Promise<string | null> => null;
