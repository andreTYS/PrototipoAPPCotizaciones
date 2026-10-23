import { useEffect, useMemo, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { C, card, kicker, t } from "../theme";
import { AvisoSync, CiudadSwitch, Etiqueta } from "../components/caja";
import { Cuerpo, TealGradient } from "../components/ui";
import { ANCHO, useEscritorio } from "../lib/layout";
import { fdateLarga, money, today } from "../lib/format";
import { r2 } from "../lib/caja/calc";
import { apiJson } from "../lib/api";
import { pedirAlertas, type Alerta, type RespuestaAlertas } from "../lib/caja/revision";
import type { Permisos } from "../lib/caja/permisos";
import { saldosDe, sinEnviar, type State } from "../lib/caja/store";
import { CIUDAD_LABEL, type Ciudad, type Hoja, type MovChica } from "../lib/caja/types";
import type { EstadoSync } from "../lib/caja/sync";

type Dia = { fecha: string; hoja?: Hoja; chica: MovChica[] };

/** Historial: los días anteriores de cada ciudad, con el estado del candado. Tocar un día lo abre en Caja diaria. */
export function Historial({ caja, estado, ciudad, setCiudad, permisos, onAbrirDia, topInset, bottomInset }: {
  caja: State;
  estado: EstadoSync;
  ciudad: Ciudad;
  setCiudad: (c: Ciudad) => void;
  permisos: Permisos;
  onAbrirDia: (ciudad: Ciudad, fecha: string) => void;
  topInset: number;
  bottomInset: number;
}) {
  const hoy = today();
  const escritorio = useEscritorio();

  const dias = useMemo(() => {
    const por = new Map<string, Dia>();
    const dia = (fecha: string) => por.get(fecha) ?? (por.set(fecha, { fecha, chica: [] }), por.get(fecha)!);
    for (const h of Object.values(caja.hojas)) {
      const util = h.filas.length > 0 || !!h.cierre;
      if (h.ciudad === ciudad && h.fecha < hoy && util) dia(h.fecha).hoja = h;
    }
    for (const m of caja.chica[ciudad].movs) if (m.fecha < hoy) dia(m.fecha).chica.push(m);
    return [...por.values()].sort((a, b) => (a.fecha < b.fecha ? 1 : -1));
  }, [caja.hojas, caja.chica, ciudad, hoy]);

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }} showsVerticalScrollIndicator={false}>
        <TealGradient ancho={ANCHO.panel} style={{ paddingTop: 18 + topInset, paddingHorizontal: 20, paddingBottom: 26 }}>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
            <Text style={kicker("rgba(255,255,255,.9)", 11)}>HISTORIAL</Text>
            <CiudadSwitch valor={ciudad} onChange={setCiudad} />
          </View>
          <Text style={t(26, 800, C.white, { letterSpacing: -0.5, marginTop: 14 })}>Días anteriores</Text>
          <Text style={t(12, 400, "rgba(255,255,255,.88)", { marginTop: 2 })}>{CIUDAD_LABEL[ciudad]} · últimos 45 días</Text>
        </TealGradient>

        <AvisoSync estado={estado} caja={caja} />

        <Cuerpo ancho={ANCHO.panel} style={{ padding: 16, gap: 18, flexDirection: escritorio ? "row" : "column", alignItems: "flex-start" }}>
          {permisos.revisar ? <View style={{ flex: escritorio ? 2 : undefined, width: escritorio ? undefined : "100%" }}><PanelAlertas ciudad={ciudad} onAbrirDia={onAbrirDia} version={Object.keys(caja.hojas).length} /></View> : null}

          <View style={{ gap: 10, flex: escritorio ? 3 : undefined, width: escritorio ? undefined : "100%" }}>
            <Text style={kicker(C.ink, 11.5)}>DÍAS</Text>
            {dias.length === 0 ? (
              <View style={[card(16), { padding: 26 }]}>
                <Text style={t(12, 400, C.muted, { textAlign: "center", lineHeight: 18 })}>Todavía no hay días anteriores con movimientos.</Text>
              </View>
            ) : (
              <View style={[card(16), { overflow: "hidden" }]}>
                {dias.map((d, i) => (
                  <DiaFila key={d.fecha} d={d} primero={i === 0} caja={caja} onPress={() => onAbrirDia(ciudad, d.fecha)} />
                ))}
              </View>
            )}
            <Text style={t(11, 400, C.muted, { lineHeight: 16 })}>Los egresos de caja chica de cualquier día están en la pestaña Caja chica. Un día cerrado ya no se puede cambiar.</Text>
          </View>
        </Cuerpo>
      </ScrollView>
    </View>
  );
}

function DiaFila({ d, primero, caja, onPress }: { d: Dia; primero: boolean; caja: State; onPress: () => void }) {
  const s = d.hoja ? saldosDe(d.hoja) : null;
  const n = d.hoja?.filas.length ?? 0;
  const gastoChica = r2(d.chica.filter((m) => m.tipo === "EGRESO").reduce((a, m) => a + m.monto, 0));
  const pend = (d.hoja?.filas.some((f) => sinEnviar(caja, f.id)) ?? false) || d.chica.some((m) => sinEnviar(caja, m.id));
  const fotos = (d.hoja?.filas.reduce((a, f) => a + f.adjuntos.length, 0) ?? 0) + d.chica.reduce((a, m) => a + m.adjuntos.length, 0);
  return (
    <Pressable onPress={onPress} accessibilityLabel={`Abrir ${fdateLarga(d.fecha)}`} style={({ pressed }) => ({ padding: 14, gap: 4, borderTopWidth: primero ? 0 : 1, borderTopColor: C.stripeA, backgroundColor: pressed ? C.bg : C.card })}>
      <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
        <Text style={t(13.5, 800)}>{fdateLarga(d.fecha)}</Text>
        {s ? <Text style={t(13, 800, C.ink, { fontVariant: ["tabular-nums"] })}>{money(s.saldo_final_caja)}</Text> : null}
      </View>
      {s ? (
        <Text style={t(11.5, 400, C.muted)} numberOfLines={1}>
          {n} {n === 1 ? "movimiento" : "movimientos"} · +{money(s.totales.caja.ingreso)} · −{money(s.totales.caja.salida)}
        </Text>
      ) : (
        <Text style={t(11.5, 400, C.muted)}>Sin planilla de caja diaria</Text>
      )}
      <View style={{ flexDirection: "row", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        {gastoChica > 0 ? <Text style={t(11.5, 600, C.navy)}>Caja chica −{money(gastoChica)}</Text> : null}
        {fotos > 0 ? <Text style={t(11.5, 600, C.muted)}>{fotos} {fotos === 1 ? "foto" : "fotos"}</Text> : null}
        {d.hoja?.cierre ? <Etiqueta texto={d.hoja.cierre.diferencia === 0 ? "CERRADO · CUADRA" : `CERRADO · ${d.hoja.cierre.diferencia > 0 ? "SOBRA" : "FALTA"} ${money(Math.abs(d.hoja.cierre.diferencia))}`} tono={d.hoja.cierre.diferencia === 0 ? "info" : "error"} /> : d.hoja ? <Etiqueta texto="SIN CERRAR" tono="info" /> : null}
        {pend ? <Etiqueta texto="SIN ENVIAR" tono="info" /> : null}
      </View>
    </Pressable>
  );
}

const NIVEL_COLOR = { alta: C.red, media: "#B7791F", info: C.muted } as const;

/** Alertas de descuadre (cajas en negativo, filas sin comprobante, días sin cerrar…) que calcula el servidor. */
function PanelAlertas({ ciudad, onAbrirDia, version }: { ciudad: Ciudad; onAbrirDia: (c: Ciudad, fecha: string) => void; version: number }) {
  const [r, setR] = useState<RespuestaAlertas | null>(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    let vivo = true;
    pedirAlertas(apiJson, ciudad)
      .then((x) => vivo && (setR(x), setError(false)))
      .catch(() => vivo && setError(true));
    return () => {
      vivo = false;
    };
  }, [ciudad, version]);
  const lista: Alerta[] = r?.alertas ?? [];
  return (
    <View style={{ gap: 10 }}>
      <Text style={kicker(C.ink, 11.5)}>ALERTAS</Text>
      <View style={[card(16), { overflow: "hidden" }]}>
        {error ? <Text style={t(12, 400, C.muted, { padding: 18, textAlign: "center" })}>No se pudieron cargar las alertas.</Text> : null}
        {!error && r && lista.length === 0 ? <Text style={t(12, 600, C.teal, { padding: 18, textAlign: "center" })}>Todo en orden: sin alertas.</Text> : null}
        {lista.map((a, i) => (
          <Pressable
            key={a.id} disabled={!a.fecha} onPress={() => a.fecha && onAbrirDia((a.ciudad ?? ciudad) as Ciudad, a.fecha)}
            accessibilityLabel={`${a.titulo}. ${a.detalle}`} style={({ pressed }) => ({ padding: 14, gap: 3, borderTopWidth: i ? 1 : 0, borderTopColor: C.stripeA, backgroundColor: pressed ? C.bg : C.card })}
          >
            <Text style={t(12.5, 800, NIVEL_COLOR[a.nivel])}>{a.titulo}</Text>
            <Text style={t(11.5, 400, C.muted, { lineHeight: 16 })}>{a.detalle}</Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}
