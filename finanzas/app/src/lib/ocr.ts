import { Platform } from "react-native";
import type { Egreso } from "./data";
import { parseComprobante, rowsFromLines, type OcrLine } from "./parseComprobante";

/**
 * Reads a receipt photo and turns the text into egreso fields.
 * - Android/iOS: Google ML Kit (bundled model, works offline).
 * - Web: Tesseract.js (runs the OCR engine in the browser via WASM). The worker/core/Spanish
 *   trained-data files are self-hosted under public/tesseract/ (see public/tesseract/README.md)
 *   instead of Tesseract.js's CDN defaults — same reasoning as the Cotizador app self-hosting
 *   CanvasKit/Roboto instead of depending on Google: a field connection that can't reach some
 *   third-party CDN shouldn't be able to break the OCR feature. The browser caches these after
 *   the first load either way.
 * Both paths produce the same OcrLine[] shape (text + bounding box), so the actual field
 * extraction (parseComprobante.ts) never needs to know which engine ran.
 */
export async function leerComprobante(uri: string): Promise<Egreso> {
  const lines = Platform.OS === "web" ? await leerConTesseract(uri) : await leerConMlKit(uri);
  if (!lines.length) throw new Error("No se detectó texto. Intenta con una foto más nítida y bien iluminada.");

  // Parse the rebuilt visual rows; fall back to the engine's own line order for anything still missing.
  const byRows = parseComprobante(rowsFromLines(lines));
  const byBlocks = parseComprobante(lines.map((l) => l.text));
  const pick = <K extends keyof Egreso>(k: K) => byRows[k] || byBlocks[k];
  const categoria = pick("categoria");
  return {
    fecha: byRows.fecha,
    persona: pick("persona"),
    desc: pick("desc"),
    ciudad: pick("ciudad"),
    categoria,
    subcategoria: categoria === "Gastos fijos" ? pick("subcategoria") : "",
    monto: pick("monto"),
  };
}

// Loaded on demand so a problem with the native OCR module can never stop the app from opening.
async function leerConMlKit(uri: string): Promise<OcrLine[]> {
  const { recognizeText } = require("@infinitered/react-native-mlkit-text-recognition") as typeof import("@infinitered/react-native-mlkit-text-recognition");
  const result = await recognizeText(uri);
  return result.blocks.flatMap((b) => b.lines);
}

async function leerConTesseract(uri: string): Promise<OcrLine[]> {
  const Tesseract = await import("tesseract.js");
  const worker = await Tesseract.createWorker("spa", undefined, {
    workerPath: "/tesseract/worker.min.js",
    corePath: "/tesseract/tesseract-core-lstm.js",
    langPath: "/tesseract/",
    // Sin esto, Tesseract.js carga worker.min.js como blob: URL — y desde ahí el glue JS del
    // núcleo WASM no puede resolver la ruta relativa de su propio .wasm ("Invalid URL" al
    // hacer fetch). Con workerBlobURL:false carga worker.min.js como script real, con una URL
    // base real contra la que sí puede resolver esa ruta relativa.
    workerBlobURL: false,
  });
  try {
    // `output: { blocks: true }` is required — without it Tesseract.js skips building the
    // blocks/paragraphs/lines hierarchy entirely (data.blocks comes back null) to save work.
    const { data } = await worker.recognize(uri, {}, { blocks: true });
    const lines = (data.blocks ?? []).flatMap((b) => b.paragraphs).flatMap((p) => p.lines);
    // Tesseract's bbox is {x0,y0,x1,y1}; OcrLine wants {left,top,right,bottom} — same corners,
    // just renamed to match what rowsFromLines (shared with the ML Kit path) expects.
    return lines
      .filter((l) => l.text.trim())
      .map((l) => ({ text: l.text, frame: { left: l.bbox.x0, top: l.bbox.y0, right: l.bbox.x1, bottom: l.bbox.y1 } }));
  } finally {
    await worker.terminate();
  }
}
