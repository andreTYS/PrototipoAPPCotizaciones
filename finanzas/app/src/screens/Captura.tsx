import { CONTENIDO_FORMULARIO } from "../lib/layout";
import { useEffect, useRef, useState } from "react";
import { Animated, Easing, Image, Pressable, ScrollView, Text, View } from "react-native";
import { C, card, kicker, t } from "../theme";
import { ErrorText, Header, Screen, SecondaryButton } from "../components/ui";

export type CapState = { status: "idle" | "busy"; uri: string | null; step: number; error: string | null };

const STEPS = ["Leyendo imagen", "Detectando monto y fecha", "Identificando proveedor", "Sugiriendo categoría"];

export function Captura({ cap, onBack, onGallery, onCamera, onCancel, topInset, bottomInset }: {
  cap: CapState;
  onBack: () => void;
  onGallery: () => void;
  onCamera: () => void;
  onCancel: () => void;
  topInset: number;
  bottomInset: number;
}) {
  return (
    <Screen>
      <Header kicker="EGRESO · CAPTURA" title="Sube tu comprobante" sub="Boleta, factura, voucher o captura de transferencia" onBack={onBack} topInset={topInset} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ ...CONTENIDO_FORMULARIO, paddingVertical: 22, paddingHorizontal: 20, paddingBottom: 22 + bottomInset, gap: 16 }}>
        {cap.status === "idle" ? (
          <>
            <Pressable
              onPress={onGallery}
              style={({ pressed }) => ({
                height: 340,
                borderRadius: 18,
                borderWidth: 1.5,
                borderStyle: "dashed",
                borderColor: C.placeholder,
                backgroundColor: pressed ? C.stripeB : C.stripeA,
                alignItems: "center",
                justifyContent: "center",
                gap: 12,
              })}
            >
              <View style={{ width: 56, height: 56, borderRadius: 16, backgroundColor: C.navy, alignItems: "center", justifyContent: "center" }}>
                <Text style={t(26, 700, C.white)}>↑</Text>
              </View>
              <Text style={t(14, 800, C.ink)}>Toca para subir una foto</Text>
              <Text style={t(11.5, 400, C.muted, { maxWidth: 220, textAlign: "center" })}>JPG o PNG. Asegúrate de que el monto y la fecha se lean bien.</Text>
            </Pressable>
            <ErrorText>{cap.error}</ErrorText>
            <SecondaryButton label="Tomar foto con la cámara" onPress={onCamera} />
          </>
        ) : (
          <>
            <View style={{ height: 340, borderRadius: 18, overflow: "hidden", backgroundColor: C.ink }}>
              {cap.uri ? (
                <Image source={{ uri: cap.uri }} resizeMode="contain" style={{ width: "100%", height: "100%", opacity: 0.85 }} accessibilityLabel="Comprobante" />
              ) : null}
              <ScanLine />
            </View>
            <View style={[card(16), { paddingVertical: 14, paddingHorizontal: 16, gap: 10 }]}>
              <Text style={kicker(C.ink, 12)}>ANALIZANDO COMPROBANTE…</Text>
              {STEPS.map((label, i) => {
                const done = cap.step > i;
                const cur = cap.step === i;
                return (
                  <View key={label} style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
                    <View
                      style={{
                        width: 18,
                        height: 18,
                        borderRadius: 6,
                        alignItems: "center",
                        justifyContent: "center",
                        backgroundColor: done ? C.teal : cur ? C.cyan : C.border,
                      }}
                    >
                      {done ? <Text style={t(11, 800, C.white)}>✓</Text> : null}
                    </View>
                    <Text style={t(12.5, 600, done || cur ? C.ink : C.placeholder)}>{label}</Text>
                  </View>
                );
              })}
            </View>
            <SecondaryButton label="Cancelar" onPress={onCancel} danger />
          </>
        )}
      </ScrollView>
    </Screen>
  );
}

/** Mint scan line sweeping up and down the preview (design: `scanLine 2s ease-in-out infinite`). */
function ScanLine() {
  const [h, setH] = useState(0);
  const y = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!h) return;
    const ease = Easing.inOut(Easing.ease);
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(y, { toValue: h - 3, duration: 1000, easing: ease, useNativeDriver: true }),
        Animated.timing(y, { toValue: 0, duration: 1000, easing: ease, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [h, y]);
  return (
    <View pointerEvents="none" onLayout={(e) => setH(e.nativeEvent.layout.height)} style={{ position: "absolute", top: 0, bottom: 0, left: 0, right: 0 }}>
      <Animated.View
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          height: 3,
          backgroundColor: C.mint,
          transform: [{ translateY: y }],
        }}
      />
    </View>
  );
}
