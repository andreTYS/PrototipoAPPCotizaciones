/** Almacén clave-valor del dispositivo (Android/iOS): AsyncStorage. En la web se usa kv.web.ts (IndexedDB). */
import AsyncStorage from "@react-native-async-storage/async-storage";

export async function kvGet<T>(key: string): Promise<T | undefined> {
  try {
    const raw = await AsyncStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : undefined;
  } catch {
    return undefined;
  }
}
export async function kvSet(key: string, value: unknown): Promise<void> {
  await AsyncStorage.setItem(key, JSON.stringify(value));
}
export async function kvDel(key: string): Promise<void> {
  await AsyncStorage.removeItem(key);
}
