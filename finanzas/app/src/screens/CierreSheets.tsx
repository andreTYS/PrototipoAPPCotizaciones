import { useEffect, useState } from "react";
import { ScrollView, Text, View } from "react-native";
import { Sheet } from "../components/Overlays";
import { AmountField, ErrorText, PrimaryButton, SecondaryButton, TextField } from "../components/ui";
import { C, kicker, t } from "../theme";
import { cleanAmt, fdateLarga, money, num } from "../lib/format";
import { apiJson } from "../lib/api";
import { sync } from "../lib/caja/runtime";
import { describirCambio, pedirCambios, type Cambio } from "../lib/caja/revision";
import { CIUDAD_LABEL, type Ciudad } from "../lib/caja/types";

const r2 = (n: number) => Math.round(n * 100) / 100;
const mensaje = (e: unknown) => (e instanceof Error && e.message ? e.message : "No se pudo completar. Revisa tu conexión e inténtalo otra vez.");

/** Cierre del día (arqueo): se escribe el efectivo contado, se ve la diferencia con el saldo calculado y el día queda bloqueado. */
export function CierreSheet({ ciudad, fecha, saldoCalculado, onClose, bottomInset }: { ciudad: Ciudad; fecha: string; saldoCalculado: number; onClose: () => void; bottomInset: number }) {
  const [contado, setContado] = useState("");
  const [nota, setNota] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const escrito = contado.trim() !== "";
  const dif = r2(num(contado) - saldoCalculado);
  const cuadra = escrito && dif === 0;

  const cerrar = async () => {
    if (!escrito) return setError("Escribe el efectivo que contaste en caja.");
    if (dif !== 0 && !nota.trim()) return setError("Hay diferencia: explica en la nota a qué se debe.");
    setOcupado(true);
    setError(null);
    try {
      await sync.cerrarHoja(ciudad, fecha, num(contado), nota.trim());
      onClose();
    } catch (e) {
      setError(mensaje(e));
    } finally {
      setOcupado(false);
    }
  };

  return (
    <Sheet onClose={ocupado ? () => {} : onClose} bottomInset={bottomInset}>
      <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
        <Text style={kicker(C.muted, 10.5)}>CERRAR EL DÍA · {CIUDAD_LABEL[ciudad].toUpperCase()}</Text>
        <Text style={t(20, 800, C.ink, { marginTop: 6 })}>{fdateLarga(fecha)}</Text>
        <View style={{ flexDirection: "row", justifyContent: "space-between", backgroundColor: C.bg, borderRadius: 12, padding: 14, marginTop: 14 }}>
          <Text style={t(12.5, 400, C.muted)}>Saldo calculado de caja</Text>
          <Text style={t(14, 800, C.ink, { fontVariant: ["tabular-nums"] })}>{money(saldoCalculado)}</Text>
        </View>
        <Text style={kicker(C.muted, 10.5)}>
          {"\n"}EFECTIVO CONTADO
        </Text>
        <View style={{ marginTop: 6 }}>
          <AmountField value={contado} onChangeText={(v) => (setContado(cleanAmt(v)), setError(null))} accent={C.navy} />
        </View>
        {escrito ? (
          <View style={{ marginTop: 12, borderRadius: 12, padding: 12, backgroundColor: cuadra ? C.tint : "#FBE9E9" }} accessibilityRole="alert">
            <Text style={t(13, 800, cuadra ? C.teal : C.red)}>{cuadra ? "La caja cuadra." : dif > 0 ? `Sobran ${money(dif)}` : `Faltan ${money(-dif)}`}</Text>
          </View>
        ) : null}
        <Text style={kicker(C.muted, 10.5)}>
          {"\n"}NOTA {dif !== 0 && escrito ? "(OBLIGATORIA)" : "(OPCIONAL)"}
        </Text>
        <View style={{ marginTop: 6 }}>
          <TextField value={nota} onChangeText={(v) => (setNota(v), setError(null))} placeholder="Ej. faltó registrar un vuelto" multiline accessibilityLabel="Nota del cierre" />
        </View>
        <Text style={t(11.5, 400, C.muted, { marginTop: 12, lineHeight: 16 })}>Al cerrar, el día queda bloqueado: ya no se podrán agregar ni corregir movimientos. Solo un administrador puede reabrirlo.</Text>
        <ErrorText>{error}</ErrorText>
        <View style={{ gap: 10, marginTop: 16 }}>
          <PrimaryButton label={ocupado ? "CERRANDO…" : "CERRAR EL DÍA"} onPress={() => void (ocupado ? undefined : cerrar())} />
          <SecondaryButton label="Cancelar" onPress={onClose} />
        </View>
      </ScrollView>
    </Sheet>
  );
}

/** Reabrir un día cerrado (solo administrador): el motivo queda en el historial de cambios. */
export function ReabrirSheet({ ciudad, fecha, onClose, bottomInset }: { ciudad: Ciudad; fecha: string; onClose: () => void; bottomInset: number }) {
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const reabrir = async () => {
    if (!motivo.trim()) return setError("Escribe el motivo de la reapertura.");
    setOcupado(true);
    try {
      await sync.reabrirHoja(ciudad, fecha, motivo.trim());
      onClose();
    } catch (e) {
      setError(mensaje(e));
    } finally {
      setOcupado(false);
    }
  };
  return (
    <Sheet onClose={onClose} bottomInset={bottomInset}>
      <Text style={kicker(C.muted, 10.5)}>REABRIR EL DÍA</Text>
      <Text style={t(20, 800, C.ink, { marginTop: 6 })}>{fdateLarga(fecha)}</Text>
      <Text style={t(12.5, 400, C.muted, { marginTop: 4, marginBottom: 14, lineHeight: 18 })}>El día volverá a poder corregirse. Quedan anotados quién lo reabrió y por qué.</Text>
      <TextField value={motivo} onChangeText={(v) => (setMotivo(v), setError(null))} placeholder="Motivo" multiline autoFocus accessibilityLabel="Motivo de la reapertura" />
      <ErrorText>{error}</ErrorText>
      <View style={{ gap: 10, marginTop: 16 }}>
        <PrimaryButton label={ocupado ? "REABRIENDO…" : "REABRIR"} onPress={() => void (ocupado ? undefined : reabrir())} />
        <SecondaryButton label="Cancelar" onPress={onClose} />
      </View>
    </Sheet>
  );
}

const hora = (iso: string) => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString("es-PE", { timeZone: "America/Lima", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
};

/** Historial de cambios: quién tocó qué, cuándo y cómo estaba antes. Sin fecha muestra lo más reciente de la ciudad. */
export function CambiosSheet({ ciudad, fecha, onClose, bottomInset }: { ciudad: Ciudad; fecha?: string; onClose: () => void; bottomInset: number }) {
  const [cambios, setCambios] = useState<Cambio[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    pedirCambios(apiJson, { ciudad, fecha, limite: 100 })
      .then((c) => vivo && setCambios(c))
      .catch((e) => vivo && setError(mensaje(e)));
    return () => {
      vivo = false;
    };
  }, [ciudad, fecha]);

  return (
    <Sheet onClose={onClose} bottomInset={bottomInset}>
      <Text style={kicker(C.muted, 10.5)}>HISTORIAL DE CAMBIOS · {CIUDAD_LABEL[ciudad].toUpperCase()}</Text>
      <Text style={t(20, 800, C.ink, { marginTop: 6, marginBottom: 12 })}>{fecha ? fdateLarga(fecha) : "Lo más reciente"}</Text>
      <ScrollView style={{ maxHeight: 440 }} showsVerticalScrollIndicator={false}>
        {error ? <ErrorText>{error}</ErrorText> : null}
        {!cambios && !error ? <Text style={t(12.5, 400, C.muted)}>Cargando…</Text> : null}
        {cambios && cambios.length === 0 ? <Text style={t(12.5, 400, C.muted)}>No hay cambios registrados.</Text> : null}
        {cambios?.map((c) => {
          const d = describirCambio(c);
          return (
            <View key={c.id} style={{ paddingVertical: 10, borderTopWidth: 1, borderTopColor: C.stripeA, gap: 3 }}>
              <Text style={t(12.5, 700, C.ink, { lineHeight: 17 })}>{d.titulo}</Text>
              <Text style={t(11, 400, C.muted)}>
                {c.usuario ?? "—"}
                {c.rol ? ` (${c.rol})` : ""} · {hora(c.creado_en)}
                {!fecha && c.fecha_dia ? ` · día ${c.fecha_dia}` : ""}
              </Text>
              {d.detalle.map((l, i) => (
                <Text key={i} style={t(11.5, 400, C.ink, { lineHeight: 16 })}>• {l}</Text>
              ))}
            </View>
          );
        })}
      </ScrollView>
      <View style={{ marginTop: 14 }}>
        <SecondaryButton label="Cerrar" onPress={onClose} />
      </View>
    </Sheet>
  );
}
