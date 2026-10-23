import { useEffect, useRef, useState } from "react";
import { Text, View } from "react-native";
import { CajaDiaria } from "./CajaDiaria";
import { FilaForm } from "./FilaForm";
import { EnviarCajaChica } from "./EnviarCajaChica";
import { SaldosIniciales } from "./SaldosIniciales";
import { Sheet } from "../components/Overlays";
import { PrimaryButton, SecondaryButton } from "../components/ui";
import { C, kicker, t } from "../theme";
import { fdateLarga, money, today } from "../lib/format";
import { usePuerta } from "../components/Puerta";
import { CambiosSheet, CierreSheet, ReabrirSheet } from "./CierreSheets";
import { store } from "../lib/caja/runtime";
import { diaCerrado, motivoSoloLectura, type Permisos } from "../lib/caja/permisos";
import { hojaKey, type Ciudad, type Fila } from "../lib/caja/types";
import { saldosDe, type State } from "../lib/caja/store";
import type { EstadoSync } from "../lib/caja/sync";

type Paso = "hoja" | "fila" | "enviar" | "saldos";
type Hoja2 = "cerrar" | "reabrir" | "cambios" | null;

/** Caja diaria: la hoja del día y, desde ahí, nuevo movimiento, enviar a caja chica y saldos iniciales. */
export function CajaDiariaFlujo({ caja, estado, ciudad, setCiudad, permisos, irA, onOcultarTabs, topInset, bottomInset }: {
  caja: State;
  estado: EstadoSync;
  ciudad: Ciudad;
  setCiudad: (c: Ciudad) => void;
  permisos: Permisos;
  /** Pedido desde Historial: abrir este día (n cambia en cada pedido para que se repita aunque sea la misma fecha). */
  irA?: { fecha: string; n: number };
  onOcultarTabs: (oculto: boolean) => void;
  topInset: number;
  bottomInset: number;
}) {
  const [paso, setPasoRaw] = useState<Paso>("hoja");
  const [fecha, setFecha] = useState(today());
  const [hoy, setHoy] = useState(today());
  const [editar, setEditar] = useState<Fila | undefined>();
  const [envio, setEnvio] = useState<Fila | null>(null);
  const [anulando, setAnulando] = useState(false);
  const [sheet, setSheet] = useState<Hoja2>(null);
  const puerta = usePuerta(permisos, bottomInset);

  const setPaso = (p: Paso) => {
    setPasoRaw(p);
    onOcultarTabs(p !== "hoja");
  };

  // Pasa la medianoche con la app abierta: el día nuevo se abre solo, limpio y con el cierre de ayer.
  const hoyPrevio = useRef(hoy);
  useEffect(() => {
    const id = setInterval(() => setHoy(today()), 30_000);
    return () => clearInterval(id);
  }, []);
  useEffect(() => {
    if (hoy !== hoyPrevio.current) {
      setFecha((f) => (f === hoyPrevio.current ? hoy : f));
      hoyPrevio.current = hoy;
    }
  }, [hoy]);
  useEffect(() => {
    if (!irA) return;
    setFecha(irA.fecha);
    setPasoRaw("hoja");
    onOcultarTabs(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [irA?.n]);
  // La hoja de hoy existe desde que se abre la app (así el saldo anterior ya está calculado).
  useEffect(() => {
    if (permisos.acceso && !caja.hojas[hojaKey(ciudad, hoy)]) store.abrirHoja(ciudad, hoy);
  }, [ciudad, hoy, caja.hojas, permisos.acceso]);

  const hoja = caja.hojas[hojaKey(ciudad, fecha)];
  const inset = { topInset, bottomInset };
  const cerrar = () => (setEditar(undefined), setPaso("hoja"));
  const pasado = fecha < hoy;
  const cerrado = diaCerrado(caja.hojas, ciudad, fecha);
  const motivo = motivoSoloLectura(permisos, fecha, hoy, cerrado);

  if (paso === "fila") return <FilaForm ciudad={ciudad} fecha={fecha} fila={editar} responsables={caja.responsables} onClose={cerrar} {...inset} />;
  if (paso === "enviar") return <EnviarCajaChica caja={caja} ciudad={ciudad} fecha={fecha} responsable={hoja?.responsable_caja || caja.responsables[0] || ""} onClose={cerrar} {...inset} />;
  if (paso === "saldos") return <SaldosIniciales ciudad={ciudad} config={caja.config[ciudad]} onClose={cerrar} {...inset} />;

  const cerrarEnvio = () => (setEnvio(null), setAnulando(false));
  return (
    <View style={{ flex: 1 }}>
      <CajaDiaria
        caja={caja} estado={estado} ciudad={ciudad} setCiudad={setCiudad} fecha={fecha} setFecha={setFecha} hoy={hoy}
        permisos={permisos} motivoSoloLectura={motivo}
        onNueva={() => puerta.pedir(pasado, () => (setEditar(undefined), setPaso("fila")), cerrado)}
        onEditar={(f) => puerta.pedir(pasado, () => (setEditar(f), setPaso("fila")), cerrado)}
        onEnvio={setEnvio}
        onEnviarChica={() => puerta.pedir(pasado, () => setPaso("enviar"), cerrado)}
        onSaldos={() => setPaso("saldos")}
        onCerrarDia={() => setSheet("cerrar")} onReabrir={() => setSheet("reabrir")} onCambios={() => setSheet("cambios")} {...inset}
      />
      {puerta.modal}
      {sheet === "cerrar" && hoja ? <CierreSheet ciudad={ciudad} fecha={fecha} saldoCalculado={saldosDe(hoja).saldo_final_caja} onClose={() => setSheet(null)} bottomInset={bottomInset} /> : null}
      {sheet === "reabrir" ? <ReabrirSheet ciudad={ciudad} fecha={fecha} onClose={() => setSheet(null)} bottomInset={bottomInset} /> : null}
      {sheet === "cambios" ? <CambiosSheet ciudad={ciudad} fecha={fecha} onClose={() => setSheet(null)} bottomInset={bottomInset} /> : null}
      {envio ? (
        <Sheet onClose={cerrarEnvio} bottomInset={bottomInset}>
          <Text style={kicker(C.muted, 10.5)}>ENVÍO A CAJA CHICA</Text>
          <Text style={t(28, 800, C.red, { marginTop: 6, marginBottom: 6 })}>−{money(envio.caja_salida_efectivo)}</Text>
          <Text style={t(12.5, 400, C.muted, { marginBottom: 14, lineHeight: 18 })}>{fdateLarga(fecha)} · {envio.descripcion}</Text>
          {anulando ? (
            <View style={{ gap: 10 }}>
              <Text style={t(12.5, 600, C.ink, { lineHeight: 18 })}>¿Anular este envío? El dinero vuelve a la caja diaria y sale de la caja chica. Solo se puede si la caja chica no lo gastó ya.</Text>
              <SecondaryButton label="Sí, anular el envío" onPress={() => puerta.pedir(pasado, () => (store.anularTransferencia(ciudad, fecha, envio.transferencia_id!), cerrarEnvio()), cerrado)} danger />
              <SecondaryButton label="No, conservar" onPress={cerrarEnvio} />
            </View>
          ) : (
            <View style={{ gap: 10 }}>
              <SecondaryButton label="Anular envío" onPress={() => setAnulando(true)} danger />
              <PrimaryButton label="CERRAR" onPress={cerrarEnvio} />
            </View>
          )}
        </Sheet>
      ) : null}
    </View>
  );
}
