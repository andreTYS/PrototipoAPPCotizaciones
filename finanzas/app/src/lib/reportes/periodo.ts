/** Períodos rápidos del selector de reportes. Puro (sin React Native) para poder probarlo con Node. */
import { isoDate, parseIso, sumarDias } from "../format";

export type Preset = "hoy" | "ayer" | "semana" | "mes" | "mes-pasado" | "otro";

export const PRESETS: { id: Preset; label: string }[] = [
  { id: "hoy", label: "Hoy" },
  { id: "ayer", label: "Ayer" },
  { id: "semana", label: "Esta semana" },
  { id: "mes", label: "Este mes" },
  { id: "mes-pasado", label: "Mes pasado" },
  { id: "otro", label: "Personalizado" },
];

/** Máximo de días por reporte: más que eso tarda demasiado en armarse en el teléfono. */
export const MAX_DIAS = 366;

/** Rango [desde, hasta] de un período rápido. La semana empieza el lunes. `otro` no tiene rango propio. */
export function rangoPreset(p: Exclude<Preset, "otro">, hoy: string): { desde: string; hasta: string } {
  const d = parseIso(hoy);
  switch (p) {
    case "hoy":
      return { desde: hoy, hasta: hoy };
    case "ayer": {
      const a = sumarDias(hoy, -1);
      return { desde: a, hasta: a };
    }
    case "semana":
      return { desde: sumarDias(hoy, -((d.getDay() + 6) % 7)), hasta: hoy };
    case "mes":
      return { desde: isoDate(new Date(d.getFullYear(), d.getMonth(), 1)), hasta: hoy };
    case "mes-pasado":
      return { desde: isoDate(new Date(d.getFullYear(), d.getMonth() - 1, 1)), hasta: isoDate(new Date(d.getFullYear(), d.getMonth(), 0)) };
  }
}

/** Días que abarca el rango, ambos extremos incluidos. */
export const diasDeRango = (desde: string, hasta: string) => Math.round((parseIso(hasta).getTime() - parseIso(desde).getTime()) / 86_400_000) + 1;

/** Mensaje si el rango no sirve (vacío si está bien). */
export function errorDeRango(desde: string, hasta: string): string {
  if (!desde || !hasta) return "Elige las dos fechas.";
  if (desde > hasta) return "La fecha inicial es posterior a la final.";
  if (diasDeRango(desde, hasta) > MAX_DIAS) return `Elige un período de hasta ${MAX_DIAS} días.`;
  return "";
}
