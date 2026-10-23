/** Descarga un archivo generado en el navegador (Excel, CSV) con un enlace temporal. */
export function descargar(bytes: Uint8Array, nombre: string, mime: string): void {
  const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: mime }));
  const a = document.createElement("a");
  a.href = url;
  a.download = nombre;
  document.body.appendChild(a);
  a.click();
  a.remove();
  // el navegador necesita un momento para empezar la descarga antes de soltar la URL
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
