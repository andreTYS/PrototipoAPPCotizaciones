import { useEffect, useRef } from "react";
import { Animated, Easing, Pressable, StyleSheet, Text, View } from "react-native";
import { useEscritorio } from "../lib/layout";
import { C, kicker, t } from "../theme";
import { PrimaryButton, SecondaryButton } from "./ui";

export type SheetData = {
  kicker: string;
  amount: string;
  amountColor: string;
  rows: [string, string][];
  newBalance: string;
  /** Texto de la franja de saldo; por defecto "Saldo después del registro". */
  newBalanceLabel?: string;
  cta: string;
};

/** Bottom sheet: "CONFIRMA TU INGRESO/EGRESO" with the summary and the final register button. */
export function ConfirmSheet({ data, onConfirm, onClose, bottomInset }: { data: SheetData; onConfirm: () => void; onClose: () => void; bottomInset: number }) {
  const fade = useRef(new Animated.Value(0)).current;
  const slide = useRef(new Animated.Value(600)).current;
  const escritorio = useEscritorio();
  useEffect(() => {
    Animated.timing(fade, { toValue: 1, duration: 200, useNativeDriver: true }).start();
    Animated.timing(slide, { toValue: 0, duration: 280, easing: Easing.bezier(0.2, 0.8, 0.2, 1), useNativeDriver: true }).start();
  }, [fade, slide]);

  return (
    <Animated.View style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, zIndex: 5, backgroundColor: "rgba(13,34,51,.5)", opacity: fade, justifyContent: escritorio ? "center" : "flex-end", alignItems: "center", padding: escritorio ? 24 : 0 }}>
      <Pressable style={StyleSheet.absoluteFill} onPress={onClose} accessibilityLabel="Cerrar" />
      <Animated.View
        style={{
          width: "100%",
          maxWidth: 540,
          backgroundColor: C.card,
          borderTopLeftRadius: 26,
          borderTopRightRadius: 26,
          borderBottomLeftRadius: escritorio ? 26 : 0,
          borderBottomRightRadius: escritorio ? 26 : 0,
          paddingTop: 10,
          paddingHorizontal: 22,
          paddingBottom: 24 + bottomInset,
          transform: [{ translateY: slide }],
        }}
      >
        <View style={{ width: 40, height: 4, borderRadius: 4, backgroundColor: C.border, alignSelf: "center", marginBottom: 18 }} />
        <Text style={kicker(C.muted)}>{data.kicker}</Text>
        <Text style={t(30, 800, data.amountColor, { marginTop: 6, marginBottom: 16, fontVariant: ["tabular-nums"] })}>{data.amount}</Text>
        <View style={{ borderWidth: 1, borderColor: C.line, borderRadius: 14, overflow: "hidden", marginBottom: 14 }}>
          {data.rows.map(([k, v], i) => (
            <View
              key={k}
              style={{ flexDirection: "row", justifyContent: "space-between", gap: 12, paddingVertical: 11, paddingHorizontal: 14, borderTopWidth: i ? 1 : 0, borderTopColor: C.stripeA }}
            >
              <Text style={t(12.5, 400, C.muted)}>{k}</Text>
              <Text style={t(12.5, 700, C.ink, { textAlign: "right", flexShrink: 1 })}>{v}</Text>
            </View>
          ))}
        </View>
        <View
          style={{
            flexDirection: "row",
            justifyContent: "space-between",
            alignItems: "center",
            backgroundColor: C.bg,
            borderRadius: 12,
            paddingVertical: 12,
            paddingHorizontal: 14,
            marginBottom: 18,
          }}
        >
          <Text style={t(12, 400, C.muted)}>{data.newBalanceLabel ?? "Saldo después del registro"}</Text>
          <Text style={t(14, 800, C.ink)}>{data.newBalance}</Text>
        </View>
        <View style={{ gap: 10 }}>
          <PrimaryButton label={data.cta} onPress={onConfirm} />
          <SecondaryButton label="Volver a editar" onPress={onClose} />
        </View>
      </Animated.View>
    </Animated.View>
  );
}

export function SuccessToast({ title, sub, topInset }: { title: string; sub: string; topInset: number }) {
  const a = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(a, { toValue: 1, duration: 300, useNativeDriver: true }).start();
  }, [a]);
  return (
    <Animated.View
      pointerEvents="none"
      style={{
        position: "absolute",
        left: 18,
        right: 18,
        top: 18 + topInset,
        zIndex: 6,
        backgroundColor: C.ink,
        borderRadius: 16,
        paddingVertical: 14,
        paddingHorizontal: 16,
        flexDirection: "row",
        alignItems: "center",
        gap: 12,
        elevation: 8,
        opacity: a,
        transform: [{ translateY: a.interpolate({ inputRange: [0, 1], outputRange: [10, 0] }) }],
      }}
    >
      <View style={{ width: 34, height: 34, borderRadius: 17, backgroundColor: C.mint, alignItems: "center", justifyContent: "center" }}>
        <Text style={t(15, 800, C.ink)}>✓</Text>
      </View>
      <View style={{ flex: 1 }}>
        <Text style={t(13, 800, C.white)}>{title}</Text>
        <Text style={t(11.5, 400, "rgba(255,255,255,.8)", { marginTop: 2 })}>{sub}</Text>
      </View>
    </Animated.View>
  );
}

/** Hoja inferior genérica (detalle de un movimiento, confirmar una anulación…). Se cierra tocando fuera. */
export function Sheet({ onClose, bottomInset, children }: { onClose: () => void; bottomInset: number; children: React.ReactNode }) {
  const fade = useRef(new Animated.Value(0)).current;
  const slide = useRef(new Animated.Value(500)).current;
  const escritorio = useEscritorio();
  useEffect(() => {
    Animated.timing(fade, { toValue: 1, duration: 200, useNativeDriver: true }).start();
    Animated.timing(slide, { toValue: 0, duration: 260, easing: Easing.bezier(0.2, 0.8, 0.2, 1), useNativeDriver: true }).start();
  }, [fade, slide]);
  return (
    <Animated.View style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, zIndex: 5, backgroundColor: "rgba(13,34,51,.5)", opacity: fade, justifyContent: escritorio ? "center" : "flex-end", alignItems: "center", padding: escritorio ? 24 : 0 }}>
      <Pressable style={StyleSheet.absoluteFill} onPress={onClose} accessibilityLabel="Cerrar" />
      <Animated.View style={{ width: "100%", maxWidth: 540, backgroundColor: C.card, borderTopLeftRadius: 26, borderTopRightRadius: 26, borderBottomLeftRadius: escritorio ? 26 : 0, borderBottomRightRadius: escritorio ? 26 : 0, paddingTop: 10, paddingHorizontal: 22, paddingBottom: 24 + bottomInset, maxHeight: "88%", transform: [{ translateY: slide }] }}>
        <View style={{ width: 40, height: 4, borderRadius: 4, backgroundColor: C.border, alignSelf: "center", marginBottom: 16 }} />
        {children}
      </Animated.View>
    </Animated.View>
  );
}

/** Avisos para la persona ("no se pudo anular…"): se quedan hasta que los cierra. */
export function Avisos({ avisos, onCerrar, topInset }: { avisos: { id: string; texto: string }[]; onCerrar: (id: string) => void; topInset: number }) {
  if (!avisos.length) return null;
  return (
    <View style={{ position: "absolute", left: 14, right: 14, top: 14 + topInset, zIndex: 7, gap: 8, alignItems: "center" }} pointerEvents="box-none">
      {avisos.map((a) => (
        <Pressable key={a.id} onPress={() => onCerrar(a.id)} accessibilityRole="alert" style={{ width: "100%", maxWidth: 520, backgroundColor: C.ink, borderRadius: 14, paddingVertical: 12, paddingHorizontal: 14, flexDirection: "row", gap: 10, alignItems: "center", elevation: 8 }}>
          <Text style={t(12.5, 600, C.white, { flex: 1, lineHeight: 17 })}>{a.texto}</Text>
          <Text style={t(11, 800, C.mint)}>OK</Text>
        </Pressable>
      ))}
    </View>
  );
}
