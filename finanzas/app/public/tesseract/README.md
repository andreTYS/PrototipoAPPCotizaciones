# Tesseract.js auto-hospedado (build web)

Estos archivos los usa `src/lib/ocr.ts` en la build web (nunca en Android/iOS,
que sigue usando ML Kit). Están commiteados a propósito en vez de dejar que
Tesseract.js los baje de su CDN por defecto en cada visita — mismo criterio
que ya usa el Cotizador ICR con CanvasKit/Roboto: una conexión de campo que
no llega a un CDN de terceros no debería poder romper el OCR.

| Archivo | Qué es | De dónde sale |
|---|---|---|
| `worker.min.js` | Worker de Tesseract.js | `node_modules/tesseract.js/dist/worker.min.js` |
| `tesseract-core-lstm.js` + `.wasm` | Motor WASM, build LSTM sin SIMD (máxima compatibilidad de navegador, a costo de algo de velocidad) | `node_modules/tesseract.js-core/tesseract-core-lstm.*` |
| `spa.traineddata.gz` | Modelo entrenado en español | `https://raw.githubusercontent.com/naptha/tessdata/gh-pages/4.0.0_fast/spa.traineddata.gz` |

## Cómo actualizar

```bash
cp node_modules/tesseract.js/dist/worker.min.js public/tesseract/
cp node_modules/tesseract.js-core/tesseract-core-lstm.js public/tesseract/
cp node_modules/tesseract.js-core/tesseract-core-lstm.wasm public/tesseract/
curl -fsSL "https://raw.githubusercontent.com/naptha/tessdata/gh-pages/4.0.0_fast/spa.traineddata.gz" -o public/tesseract/spa.traineddata.gz
```
