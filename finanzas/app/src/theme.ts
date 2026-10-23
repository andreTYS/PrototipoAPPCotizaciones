import type { TextStyle, ViewStyle } from "react-native";

/** Palette from the ICR design system: teal, cyan, navy, tint and ink, on a light blue-gray background. */
export const C = {
  bg: "#F3F7F9",
  card: "#FFFFFF",
  ink: "#0D2233",
  text: "#0D2233",
  muted: "#5B7285", // "Apoyo": blue-gray supporting text
  soft: "#44606F",
  placeholder: "#9FB6C3",
  border: "#D5E0E8", // inputs and inactive chips
  line: "#E1E9EE", // card borders and dividers
  teal: "#0E7490", // primary
  tealDark: "#0B6680", // primary pressed
  cyan: "#12A3B8",
  navy: "#124C8C",
  tint: "#D8F3F4", // access cards, AUTO badge, flash
  tintPressed: "#CBEEF0",
  red: "#B93A3A",
  mint: "#7DFFD6",
  white: "#FFFFFF",
  stripeA: "#EEF3F6",
  stripeB: "#E6EDF1",
  outIcon: "#E4ECF5",
};

/** Teal gradient (home and ingreso headers), drawn with expo-linear-gradient. */
export const TEAL_GRADIENT = { colors: ["#0E7490", "#12A3B8"] as const, start: { x: 0, y: 0 }, end: { x: 1, y: 1 } };

type Weight = 400 | 500 | 600 | 700 | 800;
const FAMILY: Record<Weight, string> = {
  400: "Manrope_400Regular",
  500: "Manrope_500Medium",
  600: "Manrope_600SemiBold",
  700: "Manrope_700Bold",
  800: "Manrope_800ExtraBold",
};

/** Text style with Manrope at the given weight (Android needs one family per weight). */
export const t = (size: number, weight: Weight = 400, color: string = C.ink, extra: TextStyle = {}): TextStyle => ({
  fontFamily: FAMILY[weight],
  fontSize: size,
  color,
  includeFontPadding: false,
  ...extra,
});

/** Etiqueta: 10.5 / 800, uppercase, tracked. */
export const kicker = (color: string = C.muted, size = 10.5): TextStyle => t(size, 800, color, { letterSpacing: size * 0.1 });

/** White card with a hairline border. */
export const card = (radius = 16): ViewStyle => ({
  backgroundColor: C.card,
  borderWidth: 1,
  borderColor: C.line,
  borderRadius: radius,
});

/** White card lifted with a soft shadow (the INGRESO / EGRESO tiles). */
export const raisedCard = (radius = 18): ViewStyle => ({
  backgroundColor: C.card,
  borderRadius: radius,
  elevation: 4,
  shadowColor: "#0D2233",
});

export const inputBox: ViewStyle = {
  backgroundColor: C.card,
  borderWidth: 1,
  borderColor: C.border,
  borderRadius: 12,
  height: 48,
  paddingHorizontal: 14,
  justifyContent: "center",
};

/** Primario: solid teal. */
export const primaryButton: ViewStyle = {
  height: 54,
  borderRadius: 14,
  alignItems: "center",
  justifyContent: "center",
  backgroundColor: C.teal,
};

/** Secundario: white with a colored outline. */
export const secondaryButton: ViewStyle = {
  height: 50,
  borderRadius: 14,
  borderWidth: 1.5,
  borderColor: C.navy,
  backgroundColor: C.card,
  alignItems: "center",
  justifyContent: "center",
};
