import { useEffect, useMemo, useRef, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { C, card, kicker, t } from "../theme";
import { AvisoSync, FilaSwitch, Seccion } from "../components/caja";
import { Chip, Cuerpo, DateField, PrimaryButton, SecondaryButton, TealGradient } from "../components/ui";
import { ANCHO } from "../lib/layout";
import { apiJson, logout, type Session } from "../lib/api";
import { fdate, isoDate, money, pad, today } from "../lib/format";
import { pendientes, type State } from "../lib/caja/store";
import { store } from "../lib/caja/runtime";
import type { EstadoSync } from "../lib/caja/sync";
import { CIUDADES, CIUDAD_LABEL, type Ciudad, type Hoja, type MovChica } from "../lib/caja/types";
import { cargarReporte, nombreArchivo, nombreCiudades, periodoTexto, totalesReporte, type FuenteDatos, type Reporte, type ReporteOpciones } from "../lib/reportes/model";
import { PRESETS, errorDeRango, rangoPreset, type Preset } from "../lib/reportes/periodo";
import { descargar } from "../lib/reportes/descarga";

type Formato = "xlsx" | "csv";
type Ambito = Ciudad | "ambas";

const MIME: Record<Formato, string> = {
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  csv: "text/csv;charset=utf-8",
};

/** Pide al servidor lo que el reporte necesita (las mismas rutas que usa la sincronización). */
const servidor: FuenteDatos = {
  hojas: async (ciudad, desde, hasta) => (await apiJson<{ hojas: Hoja[] }>("GET", `/caja/hojas?ciudad=${ciudad}&desde=${desde}&hasta=${hasta}`)).hojas,
  chica: (ciudad, desde, hasta) => apiJson<{ saldo_anterior: number; movimientos: MovChica[] }>("GET", `/caja-chica/movimientos?ciudad=${ciudad}&desde=${desde}&hasta=${hasta}`),
};

/** Reportes: elegir ciudad, período y contenido, ver un resumen y exportar a Excel o CSV. Más la cuenta. */
export function Reportes({ caja, estado, session, onSalio, topInset, bottomInset }: { caja: State; estado: EstadoSync; session: Session; onSalio: () => void; topInset: number; bottomInset: number }) {
  const [ambito, setAmbito] = useState<Ambito>(caja.ciudad);
  const [preset, setPreset] = useState<Preset>("hoy");
  const [otro, setOtro] = useState(() => ({ desde: today(), hasta: today() }));
  const [diaria, setDiaria] = useState(true);
  const [chica, setChica] = useState(true);
  const [ocupado, setOcupado] = useState<Formato | null>(null);
  const [error, setError] = useState("");
  const [hecho, setHecho] = useState("");
  const [saliendo, setSaliendo] = useState(false);

  const { desde, hasta } = preset === "otro" ? otro : rangoPreset(preset, today());
  const errRango = errorDeRango(desde, hasta);
  const sinContenido = !diaria && !chica;
  const opciones = useMemo<ReporteOpciones>(() => ({ ciudades: ambito === "ambas" ? [...CIUDADES] : [ambito], desde, hasta, diaria, chica }), [ambito, desde, hasta, diaria, chica]);
  const usuario = session.nombre || session.email;

  // Vista previa: se rearma sola al cambiar las opciones (con una pausa corta; las respuestas viejas se descartan).
  const [vista, setVista] = useState<{ cargando: boolean; reporte?: Reporte; error?: string }>({ cargando: false });
  const ultima = useRef(0);
  useEffect(() => {
    setHecho("");
    if (errRango || sinContenido) return setVista({ cargando: false });
    const n = ++ultima.current;
    setVista((v) => ({ ...v, cargando: true, error: undefined }));
    const espera = setTimeout(() => {
      cargarReporte({ ...opciones, usuario }, servidor, store.get())
        .then((reporte) => n === ultima.current && setVista({ cargando: false, reporte }))
        .catch((e) => n === ultima.current && setVista({ cargando: false, error: e?.message || "No se pudo consultar los datos." }));
    }, 350);
    return () => clearTimeout(espera);
  }, [opciones, errRango, sinContenido, usuario]);

  const exportar = async (formato: Formato) => {
    setError("");
    setHecho("");
    setOcupado(formato);
    try {
      // siempre con datos frescos, no con la vista previa de hace un rato
      const r = await cargarReporte({ ...opciones, usuario }, servidor, store.get());
      let bytes: Uint8Array;
      if (formato === "xlsx") {
        bytes = await (await import("../lib/reportes/xlsx")).generarXlsx(r);
      } else {
        bytes = (await import("../lib/reportes/csv")).generarCsv(r);
      }
      const nombre = `${nombreArchivo(r)}.${formato}`;
      descargar(bytes, nombre, MIME[formato]);
      setHecho(r.desdeLocal ? `${nombre} descargado, pero sin conexión: solo incluye lo guardado en este dispositivo.` : `${nombre} descargado.`);
    } catch (e) {
      setError((e as Error)?.message || "No se pudo generar el archivo.");
    } finally {
      setOcupado(null);
    }
  };

  const pend = pendientes(caja);
  const salir = async () => {
    await logout();
    await store.reiniciar();
    onSalio();
  };

  const r = vista.reporte;
  const tot = r ? totalesReporte(r) : null;
  const bloqueado = !!errRango || sinContenido || !!ocupado;

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }} showsVerticalScrollIndicator={false}>
        <TealGradient ancho={ANCHO.lista} style={{ paddingTop: 18 + topInset, paddingHorizontal: 20, paddingBottom: 26 }}>
          <Text style={kicker("rgba(255,255,255,.9)", 11)}>REPORTES</Text>
          <Text style={t(26, 800, C.white, { letterSpacing: -0.5, marginTop: 6 })}>Exportar caja</Text>
          <Text style={t(12, 400, "rgba(255,255,255,.88)", { marginTop: 2 })}>Por día o por fechas, en Excel o CSV</Text>
        </TealGradient>

        <AvisoSync estado={estado} caja={caja} />

        <Cuerpo ancho={ANCHO.lista} style={{ padding: 16, gap: 22 }}>
          <Seccion titulo="CIUDAD">
            <View style={{ flexDirection: "row", gap: 8, flexWrap: "wrap" }}>
              {CIUDADES.map((c) => (
                <Chip key={c} label={CIUDAD_LABEL[c]} active={ambito === c} onPress={() => setAmbito(c)} />
              ))}
              <Chip label="Ambas" active={ambito === "ambas"} onPress={() => setAmbito("ambas")} />
            </View>
          </Seccion>

          <Seccion titulo="PERÍODO" derecha={<Text style={t(11.5, 600, C.muted)}>{errRango ? "" : periodoTexto(desde, hasta)}</Text>}>
            <View style={{ flexDirection: "row", gap: 8, flexWrap: "wrap" }}>
              {PRESETS.map((p) => (
                <Chip key={p.id} label={p.label} active={preset === p.id} onPress={() => setPreset(p.id)} />
              ))}
            </View>
            {preset === "otro" ? (
              <View style={{ flexDirection: "row", gap: 10 }}>
                <View style={{ flex: 1 }}>
                  <Text style={kicker(C.muted, 10)}>DESDE</Text>
                  <View style={{ marginTop: 6 }}>
                    <DateField value={otro.desde} onChange={(v) => setOtro((o) => ({ ...o, desde: v }))} />
                  </View>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={kicker(C.muted, 10)}>HASTA</Text>
                  <View style={{ marginTop: 6 }}>
                    <DateField value={otro.hasta} onChange={(v) => setOtro((o) => ({ ...o, hasta: v }))} />
                  </View>
                </View>
              </View>
            ) : null}
            {errRango ? <Text style={t(12, 600, C.red)}>{errRango}</Text> : null}
          </Seccion>

          <Seccion titulo="CONTENIDO">
            <FilaSwitch titulo="Caja diaria" detalle="Una planilla por día y ciudad, como la hoja de papel" value={diaria} onValueChange={setDiaria} />
            <FilaSwitch titulo="Caja chica" detalle="Movimientos y saldo acumulado del período" value={chica} onValueChange={setChica} />
            {sinContenido ? <Text style={t(12, 600, C.red)}>Activa al menos Caja diaria o Caja chica.</Text> : null}
          </Seccion>

          <Seccion titulo="RESUMEN">
            <View style={[card(14), { padding: 14, gap: 8, minHeight: 92 }]}>
              {errRango || sinContenido ? (
                <Text style={t(12.5, 400, C.muted)}>Completa las opciones para ver el resumen.</Text>
              ) : vista.error ? (
                <Text style={t(12.5, 600, C.red)}>{vista.error}</Text>
              ) : !r || tot === null ? (
                <Text style={t(12.5, 400, C.muted)}>Consultando…</Text>
              ) : (
                <>
                  <Text style={t(12, 600, C.muted)}>
                    {nombreCiudades(r.ciudades)} · {periodoTexto(r.desde, r.hasta)}
                    {vista.cargando ? " · actualizando…" : ""}
                  </Text>
                  {r.diaria ? (
                    <>
                      <Linea k={`Caja diaria · ${r.hojas.length} ${r.hojas.length === 1 ? "planilla" : "planillas"}, ${tot.movimientos} mov.`} v="" />
                      <Linea k="Ingresos de caja" v={money(tot.ingresos)} color={C.teal} />
                      <Linea k="Salidas de caja" v={money(tot.salidas)} color={C.red} />
                    </>
                  ) : null}
                  {r.chica ? <Linea k="Caja chica · gastado" v={money(tot.gastadoChica)} color={C.red} /> : null}
                  {r.diaria && !r.hojas.length ? <Text style={t(12, 600, C.muted)}>No hay planillas en este período.</Text> : null}
                  {r.desdeLocal ? <Text style={t(12, 600, C.red)}>Sin conexión: se usa lo guardado en este dispositivo; puede faltar lo que registró otra persona.</Text> : null}
                </>
              )}
            </View>
          </Seccion>

          <View style={{ gap: 10 }}>
            <PrimaryButton label={ocupado === "xlsx" ? "GENERANDO EXCEL…" : "DESCARGAR EXCEL (.XLSX)"} onPress={() => !bloqueado && void exportar("xlsx")} />
            <SecondaryButton label={ocupado === "csv" ? "Generando CSV…" : "Descargar CSV"} onPress={() => !bloqueado && void exportar("csv")} />
            {error ? <Text style={t(12.5, 600, C.red)} accessibilityRole="alert">{error}</Text> : null}
            {hecho ? <Text style={t(12.5, 600, C.teal)} accessibilityRole="alert">{hecho}</Text> : null}
          </View>

          <Seccion titulo="CUENTA">
            <View style={[card(14), { padding: 14, gap: 4 }]}>
              <Text style={t(14, 800)}>{session.nombre || session.email}</Text>
              {session.nombre ? <Text style={t(12, 400, C.muted)}>{session.email}</Text> : null}
              <Text style={t(12, 400, C.muted, { marginTop: 4 })}>{estadoTexto(estado)}</Text>
            </View>
            {saliendo ? (
              <View style={[card(14), { padding: 14, gap: 10, borderColor: C.red }]}>
                <Text style={t(13, 700, C.red)}>
                  {pend ? `Tienes ${pend} ${pend === 1 ? "cambio" : "cambios"} sin enviar. Si sales ahora se pierden.` : "Tus datos siguen en el servidor; solo se cierra tu sesión."}
                </Text>
                <SecondaryButton label="Salir" danger onPress={() => void salir()} />
                <Pressable onPress={() => setSaliendo(false)} hitSlop={8} style={{ alignItems: "center", paddingVertical: 4 }}>
                  <Text style={t(13, 700, C.teal)}>Cancelar</Text>
                </Pressable>
              </View>
            ) : (
              <SecondaryButton label="Cerrar sesión" danger onPress={() => setSaliendo(true)} />
            )}
          </Seccion>
          <View style={{ height: bottomInset }} />
        </Cuerpo>
      </ScrollView>
    </View>
  );
}

/** ISO (UTC) -> "22 oct 2026 14:05" en la hora del dispositivo. */
const horaLocal = (iso: string) => {
  const d = new Date(iso);
  return `${fdate(isoDate(d))} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const estadoTexto = (e: EstadoSync) =>
  e.fase === "sin-conexion" ? "Sin conexión" : e.fase === "sesion-vencida" ? "Sesión vencida" : e.fase === "sincronizando" ? "Sincronizando…" : e.ultimoOk ? `Sincronizado ${horaLocal(e.ultimoOk)}` : "Sin sincronizar todavía";

function Linea({ k, v, color = C.ink }: { k: string; v: string; color?: string }) {
  return (
    <View style={{ flexDirection: "row", justifyContent: "space-between", gap: 10 }}>
      <Text style={t(12.5, 600, C.soft, { flex: 1 })}>{k}</Text>
      {v ? <Text style={t(13, 800, color, { fontVariant: ["tabular-nums"] })}>{v}</Text> : null}
    </View>
  );
}
