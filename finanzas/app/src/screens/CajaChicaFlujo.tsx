import { useRef, useState } from "react";
import { View } from "react-native";
import { usePuerta } from "../components/Puerta";
import { diaCerrado, type Permisos } from "../lib/caja/permisos";
import { today } from "../lib/format";
import { EgresoMetodo } from "./EgresoMetodo";
import { Captura, type CapState } from "./Captura";
import { EgresoForm } from "./EgresoForm";
import { CajaChica } from "./CajaChica";
import { leerComprobante } from "../lib/ocr";
import { elegirFoto, FotoError, type Origen } from "../lib/caja/foto";
import { saldoCajaChica, type State } from "../lib/caja/store";
import type { Egreso } from "../lib/data";
import type { FotoGuardada } from "../lib/caja/fotos";
import type { EstadoSync } from "../lib/caja/sync";
import type { Ciudad, MovChica } from "../lib/caja/types";

type Paso = "lista" | "metodo" | "captura" | "egreso";
const IDLE: CapState = { status: "idle", uri: null, step: 0, error: null };
const MIN_SCAN_MS = 1800; // el OCR casi no tarda; se deja ver el avance para que se lea qué está pasando

/** Caja chica: la lista y, desde ahí, registrar un egreso a mano o leyendo la foto del recibo. */
export function CajaChicaFlujo({ caja, estado, ciudad, setCiudad, permisos, onOcultarTabs, topInset, bottomInset }: {
  caja: State;
  estado: EstadoSync;
  ciudad: Ciudad;
  setCiudad: (c: Ciudad) => void;
  permisos: Permisos;
  /** La barra de pestañas se esconde mientras se llena un formulario. */
  onOcultarTabs: (oculto: boolean) => void;
  topInset: number;
  bottomInset: number;
}) {
  const [paso, setPasoRaw] = useState<Paso>("lista");
  const [editar, setEditar] = useState<MovChica | undefined>();
  const [cap, setCap] = useState<CapState>(IDLE);
  const [inicial, setInicial] = useState<Egreso | undefined>();
  const [foto, setFoto] = useState<FotoGuardada | null>(null);
  const [desdeCaptura, setDesdeCaptura] = useState(false);
  const trabajo = useRef<symbol | null>(null);
  const puerta = usePuerta(permisos, bottomInset);

  const setPaso = (p: Paso) => {
    setPasoRaw(p);
    onOcultarTabs(p !== "lista");
  };
  const volverALista = () => {
    setEditar(undefined);
    setInicial(undefined);
    setFoto(null);
    setDesdeCaptura(false);
    setCap(IDLE);
    setPaso("lista");
  };
  const cancelarCaptura = () => {
    trabajo.current = null;
    setCap(IDLE);
  };

  /** Elige la foto, la lee con OCR (animación mínima de 1.8 s) y abre el formulario con lo detectado. */
  const capturar = async (origen: Origen) => {
    let elegida;
    try {
      elegida = await elegirFoto(origen, { maxLado: 2000, calidad: 0.9 });
    } catch (e) {
      return setCap({ ...IDLE, error: e instanceof FotoError ? e.message : "No se pudo leer la imagen." });
    }
    if (!elegida) return;
    const mio = Symbol("lectura");
    trabajo.current = mio;
    setCap({ status: "busy", uri: elegida.uri, step: 0, error: null });
    let paso = 0;
    const tick = setInterval(() => paso < 3 && setCap((c) => (c.status === "busy" ? { ...c, step: ++paso } : c)), 650);
    try {
      const [datos] = await Promise.all([leerComprobante(elegida.uri), new Promise((r) => setTimeout(r, MIN_SCAN_MS))]);
      if (trabajo.current !== mio) return; // la persona canceló
      clearInterval(tick);
      setCap((c) => ({ ...c, step: 4 }));
      await new Promise((r) => setTimeout(r, 400));
      if (trabajo.current !== mio) return;
      setInicial(datos);
      setFoto(elegida.guardada);
      setDesdeCaptura(true);
      setPaso("egreso");
    } catch (e) {
      if (trabajo.current === mio) setCap({ ...IDLE, error: e instanceof Error ? e.message : "No se pudo analizar el comprobante." });
    } finally {
      clearInterval(tick);
    }
  };

  const inset = { topInset, bottomInset };
  if (paso === "metodo")
    return <EgresoMetodo onBack={volverALista} onManual={() => (setDesdeCaptura(false), setPaso("egreso"))} onCaptura={() => setPaso("captura")} {...inset} />;
  if (paso === "captura")
    return <Captura cap={cap} onBack={() => (cancelarCaptura(), setPaso("metodo"))} onGallery={() => void capturar("galeria")} onCamera={() => void capturar("camara")} onCancel={cancelarCaptura} {...inset} />;
  if (paso === "egreso")
    return (
      <EgresoForm
        ciudad={ciudad} mov={editar} inicial={inicial} fotoCaptura={foto} desdeCaptura={desdeCaptura} saldoChica={saldoCajaChica(caja, ciudad)}
        responsables={caja.responsables} permisos={permisos} cerrado={editar ? diaCerrado(caja.hojas, ciudad, editar.fecha) : false} onClose={volverALista} {...inset}
      />
    );
  return (
    <View style={{ flex: 1 }}>
      <CajaChica
        caja={caja} estado={estado} ciudad={ciudad} setCiudad={setCiudad} onNuevo={() => setPaso("metodo")}
        onEditar={(m) => puerta.pedir(m.fecha < today(), () => (setEditar(m), setPaso("egreso")), diaCerrado(caja.hojas, ciudad, m.fecha))}
        pedir={(m, accion) => puerta.pedir(m.fecha < today(), accion, diaCerrado(caja.hojas, ciudad, m.fecha))} {...inset}
      />
      {puerta.modal}
    </View>
  );
}
