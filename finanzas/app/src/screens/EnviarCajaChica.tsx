import { CONTENIDO_FORMULARIO } from "../lib/layout";
import { useState } from "react";
import { KeyboardAvoidingView, ScrollView, Text, View } from "react-native";
import { C, card, t } from "../theme";
import { AmountField, BottomBar, ErrorText, FieldLabel, Header, PrimaryButton, Screen, TextField } from "../components/ui";
import { ConfirmSheet } from "../components/Overlays";
import { cleanAmt, fdateLarga, money, num } from "../lib/format";
import { saldosDe, saldoCajaChica, type State } from "../lib/caja/store";
import { store } from "../lib/caja/runtime";
import { CIUDAD_LABEL, hojaKey, type Ciudad } from "../lib/caja/types";

/** Mueve dinero de la caja diaria a la caja chica: baja una y sube la otra, en un solo paso. */
export function EnviarCajaChica({ caja, ciudad, fecha, responsable, onClose, topInset, bottomInset }: { caja: State; ciudad: Ciudad; fecha: string; responsable: string; onClose: () => void; topInset: number; bottomInset: number }) {
  const [valor, setValor] = useState("");
  const [nota, setNota] = useState("");
  const [intento, setIntento] = useState(false);
  const [confirmar, setConfirmar] = useState(false);

  const hoja = caja.hojas[hojaKey(ciudad, fecha)];
  const disponible = hoja ? saldosDe(hoja).saldo_final_caja : (caja.config[ciudad]?.saldo_inicial_caja ?? 0);
  const chica = saldoCajaChica(caja, ciudad);
  const monto = num(valor);
  const error = !(monto > 0) ? "Ingresa el monto a enviar" : monto > disponible + 0.001 ? `La caja diaria solo tiene ${money(disponible)}` : null;

  const enviar = () => {
    store.enviarACajaChica({ ciudad, fecha, monto, nota: nota.trim(), responsable });
    if (store.puedeEscribir()) onClose();
  };

  return (
    <Screen>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior="height">
        <Header kicker={`CAJA DIARIA · ${CIUDAD_LABEL[ciudad].toUpperCase()}`} title="Enviar a caja chica" sub={fdateLarga(fecha)} onBack={onClose} topInset={topInset} tone="teal" />
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ ...CONTENIDO_FORMULARIO, paddingTop: 20, paddingHorizontal: 20, paddingBottom: 24, gap: 18 }} keyboardShouldPersistTaps="handled">
          <View style={{ flexDirection: "row", gap: 12 }}>
            <View style={[card(14), { flex: 1, padding: 14 }]}>
              <Text style={t(10, 800, C.muted, { letterSpacing: 1 })}>CAJA DIARIA</Text>
              <Text style={t(17, 800, C.ink, { marginTop: 4 })} numberOfLines={1}>{money(disponible)}</Text>
            </View>
            <View style={[card(14), { flex: 1, padding: 14 }]}>
              <Text style={t(10, 800, C.muted, { letterSpacing: 1 })}>CAJA CHICA</Text>
              <Text style={t(17, 800, C.ink, { marginTop: 4 })} numberOfLines={1}>{money(chica)}</Text>
            </View>
          </View>
          <View>
            <FieldLabel>MONTO A ENVIAR</FieldLabel>
            <AmountField value={valor} onChangeText={(v) => setValor(cleanAmt(v))} accent={C.teal} />
            <ErrorText>{intento ? error : null}</ErrorText>
          </View>
          <View>
            <FieldLabel optional>NOTA</FieldLabel>
            <TextField value={nota} onChangeText={setNota} placeholder="Ej. Para movilidad de la semana" accessibilityLabel="Nota" />
          </View>
          {monto > 0 ? (
            <View style={[card(14), { padding: 14, gap: 8 }]}>
              <Text style={t(12, 700)}>Después del envío</Text>
              <Fila k="Caja diaria" v={money(disponible - monto)} malo={disponible - monto < 0} />
              <Fila k="Caja chica" v={money(chica + monto)} />
            </View>
          ) : null}
          <Text style={t(11.5, 400, C.muted, { lineHeight: 16 })}>El envío aparece como una salida en la hoja del día y como un ingreso en la caja chica. No cuenta como gasto en Contabilidad.</Text>
        </ScrollView>
        <BottomBar bottomInset={bottomInset}>
          <PrimaryButton label="REVISAR ENVÍO" onPress={() => (setIntento(true), !error && setConfirmar(true))} />
        </BottomBar>
      </KeyboardAvoidingView>
      {confirmar ? (
        <ConfirmSheet
          data={{
            kicker: "CONFIRMA EL ENVÍO A CAJA CHICA",
            amount: money(monto),
            amountColor: C.teal,
            rows: [["Ciudad", CIUDAD_LABEL[ciudad]], ["Fecha", fdateLarga(fecha)], ["Caja diaria quedará en", money(disponible - monto)], ...(nota.trim() ? ([["Nota", nota.trim()]] as [string, string][]) : [])],
            newBalance: money(chica + monto),
            newBalanceLabel: "Caja chica quedará en",
            cta: "ENVIAR A CAJA CHICA",
          }}
          onConfirm={enviar}
          onClose={() => setConfirmar(false)}
          bottomInset={bottomInset}
        />
      ) : null}
    </Screen>
  );
}

const Fila = ({ k, v, malo }: { k: string; v: string; malo?: boolean }) => (
  <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
    <Text style={t(12.5, 400, C.muted)}>{k}</Text>
    <Text style={t(12.5, 800, malo ? C.red : C.ink)}>{v}</Text>
  </View>
);
