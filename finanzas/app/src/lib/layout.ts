import { useWindowDimensions } from "react-native";

/** Desde este ancho (px) la app se muestra como en una computadora: menú lateral y contenido más ancho. */
export const ESCRITORIO_MIN = 900;

/** Anchos máximos del contenido (px): formularios, listas y paneles con columnas. */
export const ANCHO = { formulario: 680, lista: 780, panel: 1040 } as const;

/** ¿La ventana es lo bastante ancha para el diseño de computadora? (se actualiza sola al cambiar el tamaño) */
export function useEscritorio(): boolean {
  return useWindowDimensions().width >= ESCRITORIO_MIN;
}

/** Estilo del contenido de un formulario dentro de un ScrollView: centrado y sin estirarse en pantallas grandes. */
export const CONTENIDO_FORMULARIO = { alignSelf: "center", width: "100%", maxWidth: ANCHO.formulario } as const;
