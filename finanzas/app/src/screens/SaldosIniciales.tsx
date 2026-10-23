import { CONTENIDO_FORMULARIO } from "../lib/layout";
import { useState } from "react";
import { KeyboardAvoidingView, ScrollView, Text, View } from "react-native";
import { C, t } from "../theme";
import { AmountField, BottomBar, ErrorText, FieldLabel, Header, PrimaryButton, Screen } from "../components/ui";
import { cleanAmt, money, num } from "../lib/format";
import { store } from "../lib/caja/runtime";
import { CIUDAD_LABEL, type Ciudad, type Config } from "../lib/caja/types";

/** Con cuánto dinero arranca cada caja. Todo lo demás (saldo anterior de cada día, saldo actual) se calcula a partir de esto. */
export function SaldosIniciales({ ciudad, config, onClose, topInset, bottomInset }: { ciudad: Ciudad; config?: Config; onClose: () => void; topInset: number; bottomInset: number }) {
  const [v, setV] = useState({ caja: String(config?.saldo_inicial_caja ?? ""), cta: String(config?.saldo_inicial_cta_cte ?? ""), chica: String(config?.saldo_inicial_caja_chica ?? "") });
  const [error, setError] = useState<string | null>(null);
  const campo = (k: keyof typeof v) => (x: string) => (setV((p) => ({ ...p, [k]: cleanAmt(x) })), setError(null));

  const guardar = () => {
    if ([v.caja, v.cta, v.chica].some((x) => x.trim() === "")) return setError("Completa los tres saldos (pon 0 si no hay).");
    store.setConfig(ciudad, { saldo_inicial_caja: num(v.caja), saldo_inicial_cta_cte: num(v.cta), saldo_inicial_caja_chica: num(v.chica) });
    if (store.puedeEscribir()) onClose();
  };
  return (
    <Screen>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior="height">
        <Header kicker="CONFIGURACIÓN" title={`Saldos iniciales · ${CIUDAD_LABEL[ciudad]}`} sub="Con cuánto arranca cada caja" onBack={onClose} topInset={topInset} />
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ ...CONTENIDO_FORMULARIO, paddingTop: 20, paddingHorizontal: 20, paddingBottom: 24, gap: 18 }} keyboardShouldPersistTaps="handled">
          <View>
            <FieldLabel>CAJA DIARIA</FieldLabel>
            <AmountField value={v.caja} onChangeText={campo("caja")} accent={C.teal} />
          </View>
          <View>
            <FieldLabel>CUENTA CORRIENTE</FieldLabel>
            <AmountField value={v.cta} onChangeText={campo("cta")} accent={C.navy} />
          </View>
          <View>
            <FieldLabel>CAJA CHICA</FieldLabel>
            <AmountField value={v.chica} onChangeText={campo("chica")} accent={C.teal} />
          </View>
          <ErrorText>{error}</ErrorText>
          <Text style={t(11.5, 400, C.muted, { lineHeight: 17 })}>
            Es el dinero que había ANTES del primer movimiento registrado en esta app (por ejemplo, el saldo de la planilla de papel del último día). Cada día nuevo abre con el cierre del día anterior; no hace falta volver a escribirlo.
            {config ? `\n\nAhora: caja ${money(config.saldo_inicial_caja)} · cuenta corriente ${money(config.saldo_inicial_cta_cte)} · caja chica ${money(config.saldo_inicial_caja_chica)}.` : ""}
          </Text>
          <Text style={t(11.5, 700, C.red, { lineHeight: 17 })}>Cambiarlo mueve todos los saldos de {CIUDAD_LABEL[ciudad]} (también los de días ya cerrados).</Text>
        </ScrollView>
        <BottomBar bottomInset={bottomInset}>
          <PrimaryButton label="GUARDAR SALDOS" onPress={guardar} />
        </BottomBar>
      </KeyboardAvoidingView>
    </Screen>
  );
}
