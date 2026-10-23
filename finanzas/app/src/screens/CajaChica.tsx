import { useMemo, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { C, card, kicker, t } from "../theme";
import { AvisoSync, CiudadSwitch, Etiqueta, FotosSoloLectura } from "../components/caja";
import { Sheet } from "../components/Overlays";
import { Cuerpo, PrimaryButton, SecondaryButton, TealGradient } from "../components/ui";
import { ANCHO } from "../lib/layout";
import { catLabel } from "../lib/data";
import { fdate, fdateLarga, money } from "../lib/format";
import { conSaldoAcumulado } from "../lib/caja/calc";
import { errorDe, saldoCajaChica, sinEnviar, type State } from "../lib/caja/store";
import { store } from "../lib/caja/runtime";
import { CIUDAD_LABEL, type Ciudad, type MovChica } from "../lib/caja/types";
import type { EstadoSync } from "../lib/caja/sync";

/** Caja chica: saldo, botón para registrar un egreso, y el historial con su saldo acumulado. */
export function CajaChica({ caja, estado, ciudad, setCiudad, onNuevo, onEditar, pedir, topInset, bottomInset }: {
  caja: State;
  estado: EstadoSync;
  ciudad: Ciudad;
  setCiudad: (c: Ciudad) => void;
  onNuevo: () => void;
  onEditar: (m: MovChica) => void;
  /** Ejecuta la acción sobre un movimiento; si es de un día anterior, antes pide el código. */
  pedir: (m: MovChica, accion: () => void) => void;
  topInset: number;
  bottomInset: number;
}) {
  const [ver, setVer] = useState<MovChica | null>(null);
  const [anulando, setAnulando] = useState(false);
  const saldo = saldoCajaChica(caja, ciudad);
  const { saldoBase, movs } = caja.chica[ciudad];

  // del más nuevo al más viejo, cada uno con el saldo que quedó después de ese movimiento
  const filas = useMemo(() => {
    const orden = [...movs].sort((a, b) => (a.fecha === b.fecha ? (a.updated_at < b.updated_at ? -1 : 1) : a.fecha < b.fecha ? -1 : 1));
    return conSaldoAcumulado(saldoBase, orden).reverse();
  }, [movs, saldoBase]);
  const grupos = useMemo(() => {
    const out: { fecha: string; items: typeof filas }[] = [];
    for (const f of filas) {
      const g = out[out.length - 1];
      if (g && g.fecha === f.fecha) g.items.push(f);
      else out.push({ fecha: f.fecha, items: [f] });
    }
    return out;
  }, [filas]);
  const recibido = movs.filter((m) => m.tipo === "TRANSFERENCIA").reduce((a, m) => a + m.monto, 0);
  const gastado = movs.filter((m) => m.tipo === "EGRESO").reduce((a, m) => a + m.monto, 0);

  const cerrar = () => (setVer(null), setAnulando(false));
  const anular = () => {
    if (!ver?.transferencia_id) return cerrar();
    const m = ver;
    pedir(m, () => (store.anularTransferencia(ciudad, m.fecha, m.transferencia_id!), cerrar()));
  };

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }} showsVerticalScrollIndicator={false}>
        <TealGradient ancho={ANCHO.lista} style={{ paddingTop: 18 + topInset, paddingHorizontal: 20, paddingBottom: 70 }}>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
            <Text style={kicker("rgba(255,255,255,.9)", 11)}>CAJA CHICA</Text>
            <CiudadSwitch valor={ciudad} onChange={setCiudad} />
          </View>
          <Text style={kicker("rgba(255,255,255,.9)", 10.5)}>SALDO DE CAJA CHICA</Text>
          <Text style={t(36, 800, C.white, { letterSpacing: -0.72, marginTop: 4, fontVariant: ["tabular-nums"] })} numberOfLines={1} accessibilityLabel={`Saldo de caja chica ${money(saldo)}`}>
            {money(saldo)}
          </Text>
          <Text style={t(12, 400, "rgba(255,255,255,.88)", { marginTop: 2 })}>{CIUDAD_LABEL[ciudad]} · se llena con envíos desde la caja diaria</Text>
        </TealGradient>

        <AvisoSync estado={estado} caja={caja} />

        <Cuerpo ancho={ANCHO.lista}>
        <View style={{ flexDirection: "row", gap: 12, paddingHorizontal: 18, marginTop: -44 }}>
          <View style={[card(16), { flex: 1, padding: 14, borderWidth: 0, elevation: 4, shadowColor: "#0D2233" }]}>
            <Text style={kicker(C.teal, 10)}>RECIBIDO</Text>
            <Text style={t(17, 800, C.teal, { marginTop: 4, fontVariant: ["tabular-nums"] })} numberOfLines={1}>{money(recibido)}</Text>
          </View>
          <View style={[card(16), { flex: 1, padding: 14, borderWidth: 0, elevation: 4, shadowColor: "#0D2233" }]}>
            <Text style={kicker(C.muted, 10)}>GASTADO</Text>
            <Text style={t(17, 800, C.red, { marginTop: 4, fontVariant: ["tabular-nums"] })} numberOfLines={1}>{money(gastado)}</Text>
          </View>
        </View>
        <Text style={t(10.5, 400, C.muted, { paddingHorizontal: 20, paddingTop: 6 })}>Últimos 45 días</Text>

        <View style={{ paddingHorizontal: 18, paddingTop: 14 }}>
          <PrimaryButton label="+ REGISTRAR EGRESO" onPress={onNuevo} />
        </View>

        <View style={{ paddingHorizontal: 18, paddingTop: 22, gap: 16 }}>
          <Text style={kicker(C.ink, 11.5)}>MOVIMIENTOS</Text>
          {grupos.map((g) => (
            <View key={g.fecha} style={{ gap: 8 }}>
              <Text style={t(11.5, 700, C.muted)}>{fdateLarga(g.fecha)}</Text>
              <View style={[card(16), { overflow: "hidden" }]}>
                {g.items.map((m, i) => {
                  const entra = m.tipo === "TRANSFERENCIA";
                  const error = errorDe(caja, m.id);
                  return (
                    <Pressable key={m.id} onPress={() => setVer(m)} accessibilityLabel={`${m.descripcion}, ${money(m.monto)}`} style={({ pressed }) => ({ flexDirection: "row", gap: 12, padding: 13, paddingHorizontal: 14, borderTopWidth: i ? 1 : 0, borderTopColor: C.stripeA, backgroundColor: error ? "#FDF3F3" : pressed ? C.bg : C.card })}>
                      <View style={{ width: 38, height: 38, borderRadius: 11, alignItems: "center", justifyContent: "center", backgroundColor: entra ? C.tint : C.outIcon }}>
                        <Text style={t(18, 800, entra ? C.teal : C.navy)}>{entra ? "+" : "−"}</Text>
                      </View>
                      <View style={{ flex: 1, minWidth: 0, gap: 4 }}>
                        <Text numberOfLines={2} style={t(13, 700)}>{m.descripcion}</Text>
                        <Text numberOfLines={1} style={t(11.5, 400, C.muted)}>
                          {[entra ? "Envío desde caja diaria" : catLabel(m.categoria, m.subcategoria), m.persona, m.adjuntos.length ? `${m.adjuntos.length} ${m.adjuntos.length === 1 ? "foto" : "fotos"}` : null].filter(Boolean).join(" · ")}
                        </Text>
                        {error ? <Etiqueta texto="NO SE GUARDÓ" tono="error" /> : sinEnviar(caja, m.id) ? <Etiqueta texto="SIN ENVIAR" tono="info" /> : null}
                        {error ? <Text style={t(11, 600, C.red, { lineHeight: 15 })}>{error}</Text> : null}
                      </View>
                      <View style={{ alignItems: "flex-end", gap: 2 }}>
                        <Text style={t(13.5, 800, entra ? C.teal : C.red, { fontVariant: ["tabular-nums"] })}>{entra ? "+" : "−"}{money(m.monto)}</Text>
                        <Text style={t(10.5, 600, C.muted, { fontVariant: ["tabular-nums"] })}>Saldo {money(m.saldo)}</Text>
                      </View>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          ))}
          {grupos.length === 0 ? (
            <View style={[card(16), { padding: 26 }]}>
              <Text style={t(12, 400, C.muted, { textAlign: "center", lineHeight: 18 })}>Aún no hay movimientos. Envía dinero desde la Caja diaria y registra aquí los gastos menores.</Text>
            </View>
          ) : null}
        </View>
        </Cuerpo>
      </ScrollView>

      {ver ? (
        <Sheet onClose={cerrar} bottomInset={bottomInset}>
          <Text style={kicker(C.muted, 10.5)}>{ver.tipo === "TRANSFERENCIA" ? "ENVÍO DESDE CAJA DIARIA" : "EGRESO DE CAJA CHICA"}</Text>
          <Text style={t(28, 800, ver.tipo === "TRANSFERENCIA" ? C.teal : C.red, { marginTop: 6, marginBottom: 14, fontVariant: ["tabular-nums"] })}>{ver.tipo === "TRANSFERENCIA" ? "+" : "−"}{money(ver.monto)}</Text>
          <ScrollView style={{ flexGrow: 0 }} contentContainerStyle={{ gap: 14 }}>
            <View style={[card(14), { overflow: "hidden" }]}>
              {([["Descripción", ver.descripcion], ["Fecha", fdate(ver.fecha)], ["Persona", ver.persona || "—"], ...(ver.tipo === "EGRESO" ? ([["Categoría", catLabel(ver.categoria, ver.subcategoria)]] as [string, string][]) : [])] as [string, string][]).map(([k, v], i) => (
                <View key={k} style={{ flexDirection: "row", justifyContent: "space-between", gap: 12, padding: 11, paddingHorizontal: 14, borderTopWidth: i ? 1 : 0, borderTopColor: C.stripeA }}>
                  <Text style={t(12.5, 400, C.muted)}>{k}</Text>
                  <Text style={t(12.5, 700, C.ink, { textAlign: "right", flexShrink: 1 })}>{v}</Text>
                </View>
              ))}
            </View>
            <FotosSoloLectura adjuntos={ver.adjuntos} />
          </ScrollView>
          <View style={{ gap: 10, marginTop: 16 }}>
            {ver.tipo === "EGRESO" ? (
              <PrimaryButton label="EDITAR O ELIMINAR" onPress={() => (onEditar(ver), cerrar())} />
            ) : anulando ? (
              <>
                <Text style={t(12.5, 600, C.ink, { lineHeight: 18 })}>¿Anular este envío? El dinero vuelve a la caja diaria. Solo se puede si la caja chica no lo gastó ya.</Text>
                <SecondaryButton label="Sí, anular el envío" onPress={anular} danger />
              </>
            ) : (
              <SecondaryButton label="Anular envío" onPress={() => setAnulando(true)} danger />
            )}
            <SecondaryButton label="Cerrar" onPress={cerrar} />
          </View>
        </Sheet>
      ) : null}
    </View>
  );
}
