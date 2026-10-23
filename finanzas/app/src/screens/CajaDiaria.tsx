import { useEffect, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { C, card, kicker, raisedCard, t } from "../theme";
import { Etiqueta, FechaNav, Seccion, AvisoSync, CiudadSwitch } from "../components/caja";
import { Cuerpo, PrimaryButton, SecondaryButton, TealGradient, TextField } from "../components/ui";
import { ANCHO, useEscritorio } from "../lib/layout";
import { fdateLarga, money } from "../lib/format";
import { aperturaEstimada } from "../lib/caja/calc";
import { errorDe, saldosDe, sinEnviar, type State } from "../lib/caja/store";
import { store } from "../lib/caja/runtime";
import { COMPROBANTE_LABEL, TIPO_FILA_LABEL, hojaKey, type Cierre, type Ciudad, type Fila, type Hoja } from "../lib/caja/types";
import type { Permisos } from "../lib/caja/permisos";
import type { EstadoSync } from "../lib/caja/sync";

/** Hoja del día que se ve aunque todavía no exista (día pasado sin movimientos). */
function hojaVisible(caja: State, ciudad: Ciudad, fecha: string): Hoja {
  const h = caja.hojas[hojaKey(ciudad, fecha)];
  if (h) return h;
  const cfg = caja.config[ciudad] ?? { saldo_inicial_caja: 0, saldo_inicial_cta_cte: 0, saldo_inicial_caja_chica: 0 };
  const deLaCiudad = Object.values(caja.hojas).filter((x) => x.ciudad === ciudad);
  return { ciudad, fecha, responsable_caja: "", obras_realizadas: "", maletas: "", escaleras: "", encargado_obra: "", ...aperturaEstimada(deLaCiudad, fecha, cfg), estimado: true, filas: [], updated_at: "" };
}

export function CajaDiaria({ caja, estado, ciudad, setCiudad, fecha, setFecha, hoy, permisos, motivoSoloLectura, onNueva, onEditar, onEnvio, onEnviarChica, onSaldos, onCerrarDia, onReabrir, onCambios, topInset, bottomInset }: {
  caja: State;
  estado: EstadoSync;
  ciudad: Ciudad;
  setCiudad: (c: Ciudad) => void;
  fecha: string;
  setFecha: (f: string) => void;
  hoy: string;
  permisos: Permisos;
  /** Si el día no se puede cambiar (cerrado, o anterior sin permiso), por qué; si se puede, null. */
  motivoSoloLectura: string | null;
  onNueva: () => void;
  onEditar: (f: Fila) => void;
  onEnvio: (f: Fila) => void;
  onEnviarChica: () => void;
  onSaldos: () => void;
  onCerrarDia: () => void;
  onReabrir: () => void;
  onCambios: () => void;
  topInset: number;
  bottomInset: number;
}) {
  const escritorio = useEscritorio();
  const hoja = hojaVisible(caja, ciudad, fecha);
  const s = saldosDe(hoja);
  const t_ = s.totales;
  const pasado = fecha < hoy;
  const soloLectura = motivoSoloLectura !== null;
  const cierre = hoja.cierre ?? null;
  const puedeCerrar = permisos.cerrar && !cierre && !hoja.estimado && fecha <= hoy && !soloLectura;

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        <TealGradient ancho={ANCHO.panel} style={{ paddingTop: 18 + topInset, paddingHorizontal: 20, paddingBottom: 70 }}>
          <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: 18 }}>
            <Text style={kicker("rgba(255,255,255,.9)", 11)}>CAJA DIARIA</Text>
            <CiudadSwitch valor={ciudad} onChange={setCiudad} />
          </View>
          <FechaNav fecha={fecha} hoy={hoy} onChange={setFecha} textoFecha={fdateLarga(fecha)} />
          <View style={{ marginTop: 14 }}>
            <Text style={kicker("rgba(255,255,255,.9)", 10.5)}>SALDO DE CAJA</Text>
            <Text style={t(36, 800, C.white, { letterSpacing: -0.72, marginTop: 4, fontVariant: ["tabular-nums"] })} numberOfLines={1} accessibilityLabel={`Saldo de caja ${money(s.saldo_final_caja)}`}>
              {money(s.saldo_final_caja)}
            </Text>
            <Text style={t(12, 400, "rgba(255,255,255,.88)", { marginTop: 2 })}>
              Saldo anterior {money(hoja.saldo_anterior_caja)}
              {hoja.estimado ? " (estimado)" : ""} · Cta. cte. {money(s.saldo_final_cta_cte)}
            </Text>
          </View>
        </TealGradient>

        <AvisoSync estado={estado} caja={caja} />

        <Cuerpo ancho={ANCHO.panel}>
          <View style={{ flexDirection: "row", gap: 12, paddingHorizontal: 18, marginTop: -44 }}>
            <View style={[raisedCard(16), { flex: 1, padding: 14 }]}>
              <Text style={kicker(C.teal, 10)}>INGRESOS</Text>
              <Text style={t(17, 800, C.teal, { marginTop: 4, fontVariant: ["tabular-nums"] })} numberOfLines={1}>{money(t_.caja.ingreso)}</Text>
            </View>
            <View style={[raisedCard(16), { flex: 1, padding: 14 }]}>
              <Text style={kicker(C.muted, 10)}>SALIDAS</Text>
              <Text style={t(17, 800, C.red, { marginTop: 4, fontVariant: ["tabular-nums"] })} numberOfLines={1}>{money(t_.caja.salida)}</Text>
            </View>
          </View>

          <View style={{ paddingHorizontal: 18, paddingTop: 16, gap: 10 }}>
            {cierre ? <CierreResumen cierre={cierre} puedeReabrir={permisos.reabrir} onReabrir={onReabrir} /> : null}
            {soloLectura && !cierre ? (
              <View style={{ backgroundColor: C.tint, borderRadius: 12, padding: 12, gap: 8 }}>
                <Text style={t(12, 700, C.ink, { lineHeight: 17 })}>{motivoSoloLectura}</Text>
                <Pressable onPress={() => setFecha(hoy)} accessibilityRole="button">
                  <Text style={t(12, 800, C.teal)}>Volver a hoy ›</Text>
                </Pressable>
              </View>
            ) : null}
            {/* teléfono: los botones uno debajo del otro; computadora: en una fila */}
            <View style={{ flexDirection: escritorio ? "row" : "column", gap: 10, flexWrap: escritorio ? "wrap" : "nowrap" }}>
              {!soloLectura ? (
                <>
                  <View style={{ flex: escritorio ? 1 : undefined, minWidth: escritorio ? 200 : undefined }}><PrimaryButton label="+ NUEVO MOVIMIENTO" onPress={onNueva} /></View>
                  <View style={{ flex: escritorio ? 1 : undefined, minWidth: escritorio ? 200 : undefined }}><SecondaryButton label="Enviar dinero a caja chica" onPress={onEnviarChica} /></View>
                </>
              ) : null}
              {puedeCerrar ? <View style={{ flex: escritorio ? 1 : undefined, minWidth: escritorio ? 200 : undefined }}><SecondaryButton label="Cerrar el día" onPress={onCerrarDia} /></View> : null}
            </View>
            {permisos.revisar ? (
              <Pressable onPress={onCambios} accessibilityRole="button" style={{ alignSelf: "center", paddingVertical: 4 }}>
                <Text style={t(12, 800, C.teal)}>Ver cambios del día ›</Text>
              </Pressable>
            ) : null}
          </View>

          {/* teléfono: todo en una columna; computadora: movimientos a la izquierda, resumen y responsable a la derecha */}
          <View style={{ flexDirection: escritorio ? "row" : "column", alignItems: "flex-start" }}>
            <View style={{ flex: escritorio ? 3 : undefined, width: escritorio ? undefined : "100%", paddingHorizontal: 18, paddingTop: 22 }}>
              <Seccion titulo="MOVIMIENTOS DEL DÍA" derecha={<Text style={t(11.5, 400, C.muted)}>{hoja.filas.length} {hoja.filas.length === 1 ? "registro" : "registros"}</Text>}>
                <View style={[card(16), { overflow: "hidden" }]}>
                  {hoja.filas.map((f, i) => (
                    <FilaCard key={f.id} f={f} primero={i === 0} caja={caja} onPress={() => (f.transferencia_id ? onEnvio(f) : onEditar(f))} />
                  ))}
                  {hoja.filas.length === 0 ? <Text style={t(12, 400, C.muted, { padding: 26, textAlign: "center" })}>{pasado ? "No hubo movimientos ese día." : "Aún no hay movimientos hoy. Toca “Nuevo movimiento”."}</Text> : null}
                </View>
              </Seccion>
            </View>

            <View style={{ flex: escritorio ? 2 : undefined, width: escritorio ? undefined : "100%" }}>
              <View style={{ paddingHorizontal: 18, paddingTop: 22 }}>
                <Seccion titulo="RESUMEN DEL DÍA">
                  <View style={[card(16), { overflow: "hidden" }]}>
                    <FilaResumen cab c1="INGRESO" c2="SALIDA" c3="TOTAL" />
                    <FilaResumen titulo="Efectivo" p={t_.efectivo} />
                    <FilaResumen titulo="Yape / Transf." p={t_.transf} />
                    <FilaResumen titulo="Caja" p={t_.caja} fuerte />
                    <FilaResumen titulo="Cta. cte." p={t_.cta_cte} />
                  </View>
                </Seccion>
              </View>
              <ResponsableCaja key={hojaKey(ciudad, fecha)} hoja={hoja} ciudad={ciudad} fecha={fecha} sugerencias={caja.responsables} soloLectura={soloLectura} />
            </View>
          </View>

          {permisos.configurar ? (
            <Pressable onPress={onSaldos} style={{ alignSelf: "center", paddingVertical: 20 }} accessibilityRole="button">
              <Text style={t(12, 700, C.teal)}>Saldos iniciales de {ciudad === "AQP" ? "Arequipa" : "Moquegua"} ›</Text>
            </Pressable>
          ) : null}
        </Cuerpo>
      </ScrollView>
    </View>
  );
}

function FilaResumen({ titulo, p, cab, c1, c2, c3, fuerte }: { titulo?: string; p?: { ingreso: number; salida: number; total: number }; cab?: boolean; c1?: string; c2?: string; c3?: string; fuerte?: boolean }) {
  const celda = (txt: string, color: string = C.ink, peso: 400 | 700 | 800 = 700) => <Text style={t(cab ? 9.5 : 12, cab ? 800 : peso, cab ? C.muted : color, { width: 78, textAlign: "right", fontVariant: ["tabular-nums"], letterSpacing: cab ? 0.8 : 0 })}>{txt}</Text>;
  return (
    <View style={{ flexDirection: "row", alignItems: "center", paddingVertical: cab ? 9 : 11, paddingHorizontal: 14, backgroundColor: cab ? C.bg : fuerte ? C.tint : C.card, borderTopWidth: cab ? 0 : 1, borderTopColor: C.stripeA }}>
      <Text style={t(12, fuerte ? 800 : 600, C.ink, { flex: 1 })}>{titulo ?? ""}</Text>
      {cab ? (
        <>
          {celda(c1!)}
          {celda(c2!)}
          {celda(c3!)}
        </>
      ) : (
        <>
          {celda(money(p!.ingreso).replace("S/ ", ""), C.teal)}
          {celda(money(p!.salida).replace("S/ ", ""), C.red)}
          {celda(money(p!.total).replace("S/ ", ""), p!.total < 0 ? C.red : C.ink, 800)}
        </>
      )}
    </View>
  );
}

function FilaCard({ f, primero, caja, onPress }: { f: Fila; primero: boolean; caja: State; onPress: () => void }) {
  const ing = f.caja_ingreso_efectivo + f.caja_ingreso_transf;
  const sal = f.caja_salida_efectivo + f.caja_salida_transf;
  const signo = ing > 0 && sal > 0 ? "±" : ing > 0 ? "+" : sal > 0 ? "−" : "·";
  const error = errorDe(caja, f.id);
  const detalle = [TIPO_FILA_LABEL[f.tipo], f.responsable, f.comprobante !== "NINGUNO" ? COMPROBANTE_LABEL[f.comprobante] : null, f.adjuntos.length ? `${f.adjuntos.length} ${f.adjuntos.length === 1 ? "foto" : "fotos"}` : null].filter(Boolean).join(" · ");
  return (
    <Pressable onPress={onPress} accessibilityLabel={`${f.descripcion}, ${detalle}`} style={({ pressed }) => ({ flexDirection: "row", gap: 12, padding: 13, paddingHorizontal: 14, borderTopWidth: primero ? 0 : 1, borderTopColor: C.stripeA, backgroundColor: error ? "#FDF3F3" : pressed ? C.bg : C.card })}>
      <View style={{ width: 38, height: 38, borderRadius: 11, alignItems: "center", justifyContent: "center", backgroundColor: f.interno ? C.stripeB : ing > 0 ? C.tint : C.outIcon }}>
        <Text style={t(17, 800, f.interno ? C.muted : ing > 0 && sal === 0 ? C.teal : C.navy)}>{f.interno ? "⇄" : signo}</Text>
      </View>
      <View style={{ flex: 1, minWidth: 0, gap: 4 }}>
        <Text numberOfLines={2} style={t(13, 700)}>{f.descripcion}</Text>
        <Text numberOfLines={1} style={t(11.5, 400, C.muted)}>{detalle}</Text>
        <View style={{ flexDirection: "row", gap: 6, flexWrap: "wrap" }}>
          {f.interno ? <Etiqueta texto="MOVIMIENTO INTERNO" tono="info" /> : null}
          {error ? <Etiqueta texto="NO SE GUARDÓ" tono="error" /> : sinEnviar(caja, f.id) ? <Etiqueta texto="SIN ENVIAR" tono="info" /> : null}
        </View>
        {error ? <Text style={t(11, 600, C.red, { lineHeight: 15 })}>{error}</Text> : null}
      </View>
      <View style={{ alignItems: "flex-end", gap: 2 }}>
        {ing > 0 ? <Text style={t(13, 800, C.teal, { fontVariant: ["tabular-nums"] })}>+{money(ing)}</Text> : null}
        {sal > 0 ? <Text style={t(13, 800, C.red, { fontVariant: ["tabular-nums"] })}>−{money(sal)}</Text> : null}
        {f.cta_cte_ingreso > 0 ? <Text style={t(10.5, 700, C.navy)}>Cta. cte. +{money(f.cta_cte_ingreso)}</Text> : null}
        {f.cta_cte_salida > 0 ? <Text style={t(10.5, 700, C.navy)}>Cta. cte. −{money(f.cta_cte_salida)}</Text> : null}
      </View>
    </Pressable>
  );
}

/** Responsable de caja del día: se guarda al salir del campo. */
function ResponsableCaja({ hoja, ciudad, fecha, sugerencias, soloLectura }: { hoja: Hoja; ciudad: Ciudad; fecha: string; sugerencias: string[]; soloLectura: boolean }) {
  const [v, setV] = useState(hoja.responsable_caja);
  // si cambia desde afuera (lo puso otra persona) se actualiza
  useEffect(() => setV(hoja.responsable_caja), [hoja.responsable_caja]);
  const guardar = () => {
    const nuevo = v.trim();
    if (nuevo !== hoja.responsable_caja) store.patchHoja(ciudad, fecha, { responsable_caja: nuevo });
  };
  return (
    <View style={{ paddingHorizontal: 18, paddingTop: 22 }}>
      <Seccion titulo="RESPONSABLE DE CAJA">
        <View style={[card(16), { padding: 14 }]}>
          <TextField value={v} onChangeText={setV} onBlur={guardar} placeholder={soloLectura ? "" : "¿Quién lleva la caja hoy?"} accessibilityLabel="Responsable de caja" editable={!soloLectura} style={soloLectura ? { backgroundColor: C.bg } : undefined} />
          {!v && !soloLectura && sugerencias.length ? (
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 8 }}>
              {sugerencias.slice(0, 4).map((n) => (
                <Pressable key={n} onPress={() => store.patchHoja(ciudad, fecha, { responsable_caja: n })} style={{ paddingVertical: 5, paddingHorizontal: 11, borderRadius: 999, borderWidth: 1, borderColor: C.border }}>
                  <Text style={t(11.5, 700)}>{n}</Text>
                </Pressable>
              ))}
            </View>
          ) : null}
        </View>
      </Seccion>
    </View>
  );
}

/** Resultado del cierre del día: quién cerró, lo contado y la diferencia. */
function CierreResumen({ cierre, puedeReabrir, onReabrir }: { cierre: Cierre; puedeReabrir: boolean; onReabrir: () => void }) {
  const cuadra = cierre.diferencia === 0;
  return (
    <View style={{ backgroundColor: cuadra ? C.tint : "#FFF4D6", borderRadius: 12, padding: 12, gap: 6 }}>
      <Text style={t(12.5, 800, C.ink)}>Día cerrado · {cuadra ? "la caja cuadra" : cierre.diferencia > 0 ? `sobran ${money(cierre.diferencia)}` : `faltan ${money(-cierre.diferencia)}`}</Text>
      <Text style={t(11.5, 400, C.ink, { lineHeight: 16 })}>
        Contado {money(cierre.efectivo_contado)} · calculado {money(cierre.saldo_calculado)} · por {cierre.cerrada_por || "—"}
      </Text>
      {cierre.nota ? <Text style={t(11.5, 400, C.muted, { lineHeight: 16 })}>Nota: {cierre.nota}</Text> : null}
      <Text style={t(11, 400, C.muted, { lineHeight: 15 })}>Ya no se puede cambiar este día.</Text>
      {puedeReabrir ? (
        <Pressable onPress={onReabrir} accessibilityRole="button">
          <Text style={t(12, 800, C.teal)}>Reabrir el día ›</Text>
        </Pressable>
      ) : null}
    </View>
  );
}
