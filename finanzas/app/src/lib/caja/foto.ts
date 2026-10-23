/** Elegir o tomar la foto de un recibo y dejarla lista (reducida) para guardar y subir. */
import * as ImagePicker from "expo-image-picker";
import { ImageManipulator, SaveFormat } from "expo-image-manipulator";
import { guardarFoto, type FotoGuardada } from "./fotos";

export type Origen = "galeria" | "camara";

/** Reduce la foto para que pese poco (celulares nuevos dan 5-10 MB) pero el texto siga legible. */
export async function reducir(uri: string, width: number, height: number, maxLado = 1600, calidad = 0.8): Promise<string> {
  const ctx = ImageManipulator.manipulate(uri);
  if (Math.max(width, height) > maxLado) ctx.resize(width >= height ? { width: maxLado } : { height: maxLado });
  return (await (await ctx.renderAsync()).saveAsync({ compress: calidad, format: SaveFormat.JPEG })).uri;
}

export class FotoError extends Error {}

/** Abre la galería o la cámara. Devuelve null si la persona cancela; lanza FotoError si no hay permiso o falla. */
export async function elegirFoto(origen: Origen, opts: { maxLado?: number; calidad?: number } = {}): Promise<{ uri: string; guardada: FotoGuardada } | null> {
  if (origen === "camara") {
    const perm = await ImagePicker.requestCameraPermissionsAsync();
    if (!perm.granted) throw new FotoError("Necesitamos permiso de cámara para tomar la foto.");
  }
  const res = origen === "camara" ? await ImagePicker.launchCameraAsync({ mediaTypes: ["images"], quality: 1 }) : await ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images"], quality: 1 });
  if (res.canceled || !res.assets[0]) return null;
  const a = res.assets[0];
  try {
    const uri = await reducir(a.uri, a.width, a.height, opts.maxLado, opts.calidad);
    return { uri, guardada: await guardarFoto(uri) };
  } catch {
    throw new FotoError("No se pudo leer la imagen.");
  }
}
