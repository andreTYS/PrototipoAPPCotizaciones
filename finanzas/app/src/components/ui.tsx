import { useEffect, useRef, useState, type ReactNode } from "react";
import { Animated, Easing, Pressable, Text, TextInput, View, type StyleProp, type TextInputProps, type ViewStyle } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { ANCHO } from "../lib/layout";
import { C, TEAL_GRADIENT, card, inputBox, kicker, primaryButton, secondaryButton, t } from "../theme";

export { DateField } from "./DateField";

/** Full-screen container that fades in on mount (design: `animation: fadeIn .2s`). */
export function Screen({ children }: { children: ReactNode }) {
  const o = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(o, { toValue: 1, duration: 200, useNativeDriver: true }).start();
  }, [o]);
  return <Animated.View style={{ flex: 1, opacity: o }}>{children}</Animated.View>;
}

/** Teal gradient (ingreso) or solid ink (egreso and settings), as in the design. */
export function Header({ kicker: k, title, sub, onBack, topInset, tone = "ink" }: {
  kicker: string;
  title: string;
  sub: string;
  onBack: () => void;
  topInset: number;
  tone?: "teal" | "ink";
}) {
  const teal = tone === "teal";
  const soft = teal ? 0.85 : 0.75;
  const Wrap = teal ? TealGradient : View;
  return (
    <Wrap style={[{ paddingTop: 20 + topInset, paddingHorizontal: 22, paddingBottom: 22 }, !teal && { backgroundColor: C.ink }]}>
      <Cuerpo ancho={ANCHO.formulario - 40}>
        <Pressable
          onPress={onBack}
          accessibilityLabel="Volver"
          hitSlop={8}
          style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: teal ? "rgba(255,255,255,.2)" : "rgba(255,255,255,.14)", alignItems: "center", justifyContent: "center", marginBottom: 14 }}
        >
          <Text style={t(22, 600, C.white, { marginTop: -3 })}>‹</Text>
        </Pressable>
        <Text style={kicker(`rgba(255,255,255,${teal ? 0.9 : 0.75})`, 10.5)}>{k}</Text>
        <Text style={t(24, 800, C.white, { marginTop: 4 })}>{title}</Text>
        <Text style={t(12, 400, `rgba(255,255,255,${soft})`, { marginTop: 4 })}>{sub}</Text>
      </Cuerpo>
    </Wrap>
  );
}

/** Teal gradient container for the home and ingreso headers. */
export function TealGradient({ style, children, ancho }: { style?: StyleProp<ViewStyle>; children?: ReactNode; /** Ancho máximo del contenido (en computadora el degradado ocupa todo, el texto se alinea con el cuerpo). */ ancho?: number }) {
  return (
    <LinearGradient colors={TEAL_GRADIENT.colors} start={TEAL_GRADIENT.start} end={TEAL_GRADIENT.end} style={style}>
      {ancho ? <Cuerpo ancho={ancho - 36}>{children}</Cuerpo> : children}
    </LinearGradient>
  );
}

/** Contenido centrado con ancho máximo: en el teléfono ocupa todo; en una pantalla grande no se estira. */
export function Cuerpo({ ancho, children, style }: { ancho: number; children?: ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[{ width: "100%", maxWidth: ancho, alignSelf: "center" }, style]}>{children}</View>;
}

export function FieldLabel({ children, auto, optional }: { children: string; auto?: boolean; optional?: boolean }) {
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 6, marginBottom: 8 }}>
      <Text style={kicker()}>
        {children}
        {optional ? <Text style={t(10.5, 600, C.muted)}> (opcional)</Text> : null}
      </Text>
      {auto ? (
        <View style={{ paddingHorizontal: 6, paddingVertical: 2, borderRadius: 5, backgroundColor: C.tint }}>
          <Text style={t(9, 800, C.teal, { letterSpacing: 0.9 })}>AUTO</Text>
        </View>
      ) : null}
    </View>
  );
}

export function ErrorText({ children }: { children?: string | null }) {
  if (!children) return null;
  return <Text style={t(11.5, 400, C.red, { marginTop: 6 })}>{children}</Text>;
}

const focusRing: ViewStyle = { borderColor: C.teal };

export function TextField(props: TextInputProps) {
  const [focus, setFocus] = useState(false);
  return (
    <TextInput
      placeholderTextColor={C.placeholder}
      selectionColor={C.teal}
      cursorColor={C.teal}
      {...props}
      onFocus={(e) => {
        setFocus(true);
        props.onFocus?.(e);
      }}
      onBlur={(e) => {
        setFocus(false);
        props.onBlur?.(e);
      }}
      style={[inputBox, t(14, 600), { outlineWidth: 0 }, focus && focusRing, props.style]}
    />
  );
}

export function AmountField({ value, onChangeText, accent }: { value: string; onChangeText: (v: string) => void; accent: string }) {
  const [focus, setFocus] = useState(false);
  return (
    <View style={[card(14), { flexDirection: "row", alignItems: "center", gap: 8, paddingVertical: 6, paddingHorizontal: 16, borderColor: C.border }, focus && focusRing]}>
      <Text style={t(22, 800, accent)}>S/</Text>
      <TextInput
        keyboardType="decimal-pad"
        value={value}
        onChangeText={onChangeText}
        placeholder="0.00"
        placeholderTextColor={C.placeholder}
        selectionColor={C.teal}
        cursorColor={C.teal}
        onFocus={() => setFocus(true)}
        onBlur={() => setFocus(false)}
        style={[t(28, 800), { flex: 1, minWidth: 0, height: 52, padding: 0, outlineWidth: 0 }]}
      />
    </View>
  );
}

/** Grid of selectable options (tipo de ingreso / categoría): teal when selected, white otherwise. */
export function OptionGrid<T extends string>({ options, value, onPick, columns, height, fontSize, labels }: {
  options: readonly T[];
  value: string;
  onPick: (v: T) => void;
  columns: number;
  height: number;
  fontSize: number;
  /** Texto a mostrar si es distinto del valor (p. ej. VTA → "Venta"). */
  labels?: Partial<Record<T, string>>;
}) {
  const gap = 8;
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", marginHorizontal: -gap / 2, rowGap: gap }}>
      {options.map((o) => {
        const active = o === value;
        return (
          <View key={o} style={{ width: `${100 / columns}%`, paddingHorizontal: gap / 2 }}>
            <Pressable
              onPress={() => onPick(o)}
              style={{
                height,
                borderRadius: columns > 3 ? 11 : 12,
                alignItems: "center",
                justifyContent: "center",
                paddingHorizontal: 4,
                borderWidth: 1,
                backgroundColor: active ? C.teal : C.card,
                borderColor: active ? C.teal : C.border,
              }}
            >
              <Text numberOfLines={1} style={t(fontSize, 700, active ? C.white : C.ink)}>
                {labels?.[o] ?? o}
              </Text>
            </Pressable>
          </View>
        );
      })}
    </View>
  );
}

/** Pill filter (Todos / Ingresos / Egresos): ink when active, white with border otherwise. */
export function Chip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      style={{
        paddingVertical: 8,
        paddingHorizontal: 14,
        borderRadius: 999,
        borderWidth: 1,
        backgroundColor: active ? C.ink : C.card,
        borderColor: active ? C.ink : C.border,
      }}
    >
      <Text style={t(12, 700, active ? C.white : C.ink)}>{label}</Text>
    </Pressable>
  );
}

export function PrimaryButton({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [primaryButton, pressed && { backgroundColor: C.tealDark }]}>
      <Text style={t(14, 800, C.white, { letterSpacing: 0.56 })}>{label}</Text>
    </Pressable>
  );
}

/** Secundario (navy outline) or Destructivo (red outline, pass `danger`). */
export function SecondaryButton({ label, onPress, danger }: { label: string; onPress: () => void; danger?: boolean }) {
  const color = danger ? C.red : C.navy;
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [secondaryButton, { borderColor: color }, pressed && { backgroundColor: C.bg }]}>
      <Text style={t(13.5, 800, color)}>{label}</Text>
    </Pressable>
  );
}

/** Sticky bottom action bar used by both forms. */
export function BottomBar({ children, bottomInset }: { children: ReactNode; bottomInset: number }) {
  return (
    <View style={{ paddingTop: 14, paddingHorizontal: 20, paddingBottom: 22 + bottomInset, backgroundColor: C.card, borderTopWidth: 1, borderTopColor: C.line }}>
      <Cuerpo ancho={ANCHO.formulario - 40} style={{ gap: 10 }}>
        {children}
      </Cuerpo>
    </View>
  );
}

/** Mint dot with the "livePulse" ring. */
export function LiveDot() {
  const p = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(Animated.timing(p, { toValue: 1, duration: 1800, easing: Easing.out(Easing.quad), useNativeDriver: true }));
    loop.start();
    return () => loop.stop();
  }, [p]);
  const ringOpacity = p.interpolate({ inputRange: [0, 0.7, 1], outputRange: [0.7, 0, 0] });
  const ringScale = p.interpolate({ inputRange: [0, 0.7, 1], outputRange: [1, 3, 3] });
  return (
    <View style={{ width: 7, height: 7 }}>
      <Animated.View style={{ position: "absolute", width: 7, height: 7, borderRadius: 4, backgroundColor: C.mint, opacity: ringOpacity, transform: [{ scale: ringScale }] }} />
      <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: C.mint }} />
    </View>
  );
}
