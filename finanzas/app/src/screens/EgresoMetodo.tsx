import { CONTENIDO_FORMULARIO } from "../lib/layout";
import { Pressable, ScrollView, Text, View } from "react-native";
import type { ReactNode } from "react";
import { C, t } from "../theme";
import { Header, Screen } from "../components/ui";

export function EgresoMetodo({ onBack, onManual, onCaptura, topInset, bottomInset }: {
  onBack: () => void;
  onManual: () => void;
  onCaptura: () => void;
  topInset: number;
  bottomInset: number;
}) {
  return (
    <Screen>
      <Header kicker="NUEVO REGISTRO" title="Registrar egreso" sub="¿Cómo quieres registrarlo?" onBack={onBack} topInset={topInset} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ ...CONTENIDO_FORMULARIO, paddingVertical: 22, paddingHorizontal: 20, paddingBottom: 22 + bottomInset, gap: 14 }}>
        <MethodCard
          icon={<Text style={t(12, 800, C.white, { letterSpacing: 0.72 })}>ABC</Text>}
          iconBg={C.teal}
          title="REGISTRO MANUAL"
          sub="Completa el formulario con los datos del gasto"
          onPress={onManual}
        />
        <MethodCard
          icon={
            <View style={{ width: 22, height: 18, borderWidth: 2.5, borderColor: "#fff", borderRadius: 5, alignItems: "center", justifyContent: "center" }}>
              <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: "#fff" }} />
            </View>
          }
          iconBg={C.navy}
          title="CON CAPTURA"
          sub="Sube una foto del comprobante y llenamos el formulario por ti"
          onPress={onCaptura}
        />
        <Text style={t(11.5, 400, C.muted, { textAlign: "center", marginTop: 6 })}>En ambos casos podrás revisar y confirmar antes de registrar.</Text>
      </ScrollView>
    </Screen>
  );
}

function MethodCard({ icon, iconBg, title, sub, onPress }: { icon: ReactNode; iconBg: string; title: string; sub: string; onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => ({
        flexDirection: "row",
        alignItems: "center",
        gap: 14,
        borderRadius: 18,
        padding: 18,
        backgroundColor: pressed ? C.tintPressed : C.tint,
      })}
    >
      <View style={{ width: 52, height: 52, borderRadius: 14, backgroundColor: iconBg, alignItems: "center", justifyContent: "center" }}>{icon}</View>
      <View style={{ flex: 1 }}>
        <Text style={t(14, 800, C.ink, { letterSpacing: 0.42 })}>{title}</Text>
        <Text style={t(12, 400, C.soft, { marginTop: 3 })}>{sub}</Text>
      </View>
      <Text style={t(16, 800, C.teal)}>›</Text>
    </Pressable>
  );
}
