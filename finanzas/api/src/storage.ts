/** Dónde viven los bytes de las fotos. Disco para producción (un volumen de Docker), memoria para pruebas. */
import fs from "node:fs/promises";
import path from "node:path";

export interface Storage {
  put(id: string, bytes: Buffer): Promise<void>;
  get(id: string): Promise<Buffer | null>;
  del(id: string): Promise<void>;
}

export const diskStorage = (dir: string): Storage => ({
  async put(id, bytes) {
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, id), bytes);
  },
  async get(id) {
    return fs.readFile(path.join(dir, id)).catch(() => null);
  },
  async del(id) {
    await fs.rm(path.join(dir, id), { force: true });
  },
});

export const memoryStorage = (): Storage & { size(): number } => {
  const m = new Map<string, Buffer>();
  return {
    put: async (id, b) => void m.set(id, b),
    get: async (id) => m.get(id) ?? null,
    del: async (id) => void m.delete(id),
    size: () => m.size,
  };
};
