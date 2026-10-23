/**
 * IndexedDB mínimo para la web: una base "icr-finanzas" con dos almacenes, `kv` (el estado de la app) y `photos`
 * (las fotos de los recibos, que son binarios y no caben en localStorage, que tiene un tope de ~5 MB).
 * Si el navegador no deja usar IndexedDB (p. ej. ventana privada de algunos navegadores) se cae a memoria:
 * la app funciona, pero los datos pendientes no sobreviven a recargar la página.
 */
type Store = "kv" | "photos";

const memoria: Record<Store, Map<string, unknown>> = { kv: new Map(), photos: new Map() };
let abierta: Promise<IDBDatabase | null> | null = null;

function abrir(): Promise<IDBDatabase | null> {
  if (abierta) return abierta;
  abierta = new Promise((resolve) => {
    try {
      if (typeof indexedDB === "undefined") return resolve(null);
      const req = indexedDB.open("icr-finanzas", 1);
      req.onupgradeneeded = () => {
        req.result.createObjectStore("kv");
        req.result.createObjectStore("photos");
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
      req.onblocked = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return abierta;
}

function pedir<T>(db: IDBDatabase, store: Store, modo: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, modo);
    const r = fn(t.objectStore(store));
    t.oncomplete = () => resolve(r.result);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}

export async function idbGet<T>(store: Store, key: string): Promise<T | undefined> {
  const db = await abrir();
  if (!db) return memoria[store].get(key) as T | undefined;
  return (await pedir(db, store, "readonly", (s) => s.get(key))) as T | undefined;
}
export async function idbSet(store: Store, key: string, value: unknown): Promise<void> {
  const db = await abrir();
  if (!db) return void memoria[store].set(key, value);
  await pedir(db, store, "readwrite", (s) => s.put(value, key));
}
export async function idbDel(store: Store, key: string): Promise<void> {
  const db = await abrir();
  if (!db) return void memoria[store].delete(key);
  await pedir(db, store, "readwrite", (s) => s.delete(key));
}
