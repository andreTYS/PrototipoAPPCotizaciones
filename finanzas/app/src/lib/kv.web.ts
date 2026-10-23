/** Almacén clave-valor en la web: IndexedDB (ver idb.web.ts). Guarda objetos tal cual, sin pasar por JSON. */
import { idbDel, idbGet, idbSet } from "./idb.web";

export const kvGet = <T>(key: string) => idbGet<T>("kv", key);
export const kvSet = (key: string, value: unknown) => idbSet("kv", key, value);
export const kvDel = (key: string) => idbDel("kv", key);
