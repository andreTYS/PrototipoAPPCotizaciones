/** La exportación de archivos es de la versión web (PWA); en el teléfono nativo no está disponible. */
export function descargar(_bytes: Uint8Array, _nombre: string, _mime: string): void {
  throw new Error("Exportar archivos solo está disponible en la versión web.");
}
