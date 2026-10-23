import { CONTENIDO_FORMULARIO } from "../lib/layout";
import { useMemo, useState } from "react";
import { KeyboardAvoidingView, Pressable, ScrollView, Text, View } from "react-native";
import { C, t } from "../theme";
import { BottomBar, ErrorText, FieldLabel, Header, OptionGrid, PrimaryButton, Screen, SecondaryButton, TextField } from "../components/ui";
import { FilaSwitch, FotosBloque, MontoCampo, Seccion, type FotoItem } from "../components/caja";
import { cleanAmt, num } from "../lib/format";
import { validarFila, montosParaErp } from "../lib/caja/calc";
import { CATS, SUBCATS } from "../lib/data";
import { elegirFoto, FotoError } from "../lib/caja/foto";
import { borrarFoto } from "../lib/caja/fotos";
import { nuevoId } from "../lib/caja/ids";
import { store } from "../lib/caja/runtime";
import { COMPROBANTES, COMPROBANTE_LABEL, TIPOS_FILA, TIPO_FILA_LABEL, CIUDAD_LABEL, type Ciudad, type Comprobante, type Fila, type TipoFila } from "../lib/caja/types";

const monto = (n: number) => (n ? String(n) : "");

type Sentido = "ingreso" | "egreso";
const SENTIDOS = ["ingreso", "egreso"] as const;
const SENTIDO_LABEL: Record<Sentido, string> = { ingreso: "Ingreso", egreso: "Egreso" };
/** Un movimiento es un ingreso o un egreso, no los dos a la vez: una fila antigua con salidas y sin ingresos es un egreso. */
const sentidoDe = (f?: Fila): Sentido => (f && f.caja_ingreso_efectivo + f.caja_ingreso_transf + f.cta_cte_ingreso === 0 && f.caja_salida_efectivo + f.caja_salida_transf + f.cta_cte_salida > 0 ? "egreso" : "ingreso");

/** Una línea de la planilla "CAJA DIARIO": nueva o editando una existente. */
export function FilaForm({ ciudad, fecha, fila, responsables, onClose, topInset, bottomInset }: { ciudad: Ciudad; fecha: string; fila?: Fila; responsables: string[]; onClose: () => void; topInset: number; bottomInset: number }) {
  const [sentido, setSentidoRaw] = useState<Sentido>(sentidoDe(fila));
  const [tipo, setTipo] = useState<TipoFila>(fila?.tipo ?? "VTA");
  const [descripcion, setDescripcion] = useState(fila?.descripcion ?? "");
  const [responsable, setResponsable] = useState(fila?.responsable ?? "");
  const [comprobante, setComprobante] = useState<Comprobante>(fila?.comprobante ?? "NINGUNO");
  const [m, setM] = useState({
    ie: monto(fila?.caja_ingreso_efectivo ?? 0), it: monto(fila?.caja_ingreso_transf ?? 0), se: monto(fila?.caja_salida_efectivo ?? 0),
    st: monto(fila?.caja_salida_transf ?? 0), ci: monto(fila?.cta_cte_ingreso ?? 0), cs: monto(fila?.cta_cte_salida ?? 0),
  });
  const [categoria, setCategoria] = useState<Fila["categoria"]>(fila?.categoria ?? "");
  const [subcategoria, setSubcategoria] = useState<Fila["subcategoria"]>(fila?.subcategoria ?? "");
  const [interno, setInterno] = useState(fila?.interno ?? false);
  const [fotos, setFotos] = useState<FotoItem[]>((fila?.adjuntos ?? []).map((a) => ({ id: a.id, adj: a })));
  const [errFoto, setErrFoto] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [intento, setIntento] = useState(false);
  const [borrando, setBorrando] = useState(false);

  // al cambiar entre ingreso y egreso se borran los importes del otro lado (y la categoría del gasto, que solo aplica a egresos)
  const setSentido = (v: Sentido) => {
    if (v === sentido) return;
    setSentidoRaw(v);
    setM((p) => (v === "ingreso" ? { ...p, se: "", st: "", cs: "" } : { ...p, ie: "", it: "", ci: "" }));
    if (v === "ingreso") (setCategoria(""), setSubcategoria(""));
  };
  const setMonto = (k: keyof typeof m) => (v: string) => setM((p) => ({ ...p, [k]: cleanAmt(v) }));
  const armada = (): Fila => ({
    id: fila?.id ?? "nueva", orden: fila?.orden ?? 0, tipo, descripcion: descripcion.trim(), responsable: responsable.trim(), comprobante,
    caja_ingreso_efectivo: num(m.ie), caja_ingreso_transf: num(m.it), caja_salida_efectivo: num(m.se), caja_salida_transf: num(m.st), cta_cte_ingreso: num(m.ci), cta_cte_salida: num(m.cs),
    categoria, subcategoria, interno, adjuntos: [], updated_at: "",
  });
  const actual = armada();
  const errores = useMemo(() => validarFila(actual), [tipo, descripcion, responsable, comprobante, m, categoria, subcategoria, interno]); // eslint-disable-line react-hooks/exhaustive-deps
  const gastoReal = montosParaErp(actual).salida > 0;
  const mostrar = (k: keyof typeof errores) => (intento ? errores[k] : undefined);
  const sugerencias = responsables.filter((n) => n.toLowerCase().includes(responsable.trim().toLowerCase()) && n !== responsable.trim()).slice(0, 5);

  const agregar = async (origen: "camara" | "galeria") => {
    setErrFoto(null);
    setOcupado(true);
    try {
      const r = await elegirFoto(origen);
      if (r) setFotos((p) => [...p, { id: nuevoId(), nueva: r.guardada }]);
    } catch (e) {
      setErrFoto(e instanceof FotoError ? e.message : "No se pudo agregar la foto.");
    } finally {
      setOcupado(false);
    }
  };
  const quitar = (id: string) => setFotos((p) => p.filter((x) => x.id !== id));

  const cancelar = () => {
    for (const f of fotos) if (f.nueva) void borrarFoto(f.nueva.key); // fotos tomadas y no guardadas
    onClose();
  };

  const guardar = () => {
    setIntento(true);
    if (Object.keys(errores).length) return;
    const id = fila?.id ?? nuevoId();
    store.guardarFila(ciudad, fecha, { ...actual, id, categoria: gastoReal ? categoria : "", subcategoria: gastoReal && categoria === "Gastos fijos" ? subcategoria : "", transferencia_id: fila?.transferencia_id });
    const quedan = new Set(fotos.filter((f) => f.adj).map((f) => f.adj!.id));
    for (const a of fila?.adjuntos ?? []) if (!quedan.has(a.id)) store.quitarAdjunto("fila", id, a.id);
    for (const f of fotos) if (f.nueva) store.agregarAdjunto("fila", id, f.nueva);
    if (store.puedeEscribir()) onClose(); // sin conexión no se guardó nada: el aviso ya salió y se queda el formulario

  };

  const borrar = () => {
    if (!fila) return;
    store.borrarFila(ciudad, fecha, fila.id);
    if (store.puedeEscribir()) onClose();
  };

  return (
    <Screen>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior="height">
        <Header kicker={`CAJA DIARIA · ${CIUDAD_LABEL[ciudad].toUpperCase()}`} title={fila ? "Editar movimiento" : "Nuevo movimiento"} sub="Como en la planilla de caja diaria" onBack={cancelar} topInset={topInset} tone="teal" />
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ ...CONTENIDO_FORMULARIO, paddingTop: 20, paddingHorizontal: 20, paddingBottom: 28, gap: 20 }} keyboardShouldPersistTaps="handled">
          <View>
            <FieldLabel>MOVIMIENTO</FieldLabel>
            <OptionGrid options={SENTIDOS} value={sentido} onPick={setSentido} columns={2} height={46} fontSize={13.5} labels={SENTIDO_LABEL} />
          </View>
          <View>
            <FieldLabel>TIPO</FieldLabel>
            <OptionGrid options={TIPOS_FILA} value={tipo} onPick={setTipo} columns={3} height={44} fontSize={12.5} labels={TIPO_FILA_LABEL} />
          </View>
          <View>
            <FieldLabel>DESCRIPCIÓN</FieldLabel>
            <TextField value={descripcion} onChangeText={setDescripcion} placeholder="Ej. Compra de plumón indeleble" accessibilityLabel="Descripción" />
            <ErrorText>{mostrar("descripcion")}</ErrorText>
          </View>
          <View>
            <FieldLabel>RESPONSABLE</FieldLabel>
            <TextField value={responsable} onChangeText={setResponsable} placeholder="¿Quién hizo el movimiento?" accessibilityLabel="Responsable" />
            {sugerencias.length ? (
              <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 8 }}>
                {sugerencias.map((n) => (
                  <Pressable key={n} onPress={() => setResponsable(n)} style={{ paddingVertical: 5, paddingHorizontal: 11, borderRadius: 999, borderWidth: 1, borderColor: C.border, backgroundColor: C.card }}>
                    <Text style={t(11.5, 700)}>{n}</Text>
                  </Pressable>
                ))}
              </View>
            ) : null}
            <ErrorText>{mostrar("responsable")}</ErrorText>
          </View>
          <View>
            <FieldLabel>COMPROBANTE A REGISTRAR</FieldLabel>
            <OptionGrid options={COMPROBANTES} value={comprobante} onPick={setComprobante} columns={2} height={42} fontSize={12} labels={COMPROBANTE_LABEL} />
          </View>

          <Seccion titulo="CAJA">
            {sentido === "ingreso" ? (
              <View style={{ flexDirection: "row", gap: 10 }}>
                <MontoCampo label="INGRESO · EFECTIVO" value={m.ie} onChangeText={setMonto("ie")} color={C.teal} />
                <MontoCampo label="INGRESO · YAPE/TRANSF." value={m.it} onChangeText={setMonto("it")} color={C.teal} />
              </View>
            ) : (
              <View style={{ flexDirection: "row", gap: 10 }}>
                <MontoCampo label="SALIDA · EFECTIVO" value={m.se} onChangeText={setMonto("se")} color={C.red} />
                <MontoCampo label="SALIDA · YAPE/TRANSF." value={m.st} onChangeText={setMonto("st")} color={C.red} />
              </View>
            )}
          </Seccion>
          <Seccion titulo="CUENTA CORRIENTE">
            <View style={{ flexDirection: "row", gap: 10 }}>
              {sentido === "ingreso" ? (
                <MontoCampo label="INGRESO" value={m.ci} onChangeText={setMonto("ci")} color={C.navy} />
              ) : (
                <MontoCampo label="SALIDA" value={m.cs} onChangeText={setMonto("cs")} color={C.navy} />
              )}
              <View style={{ flex: 1 }} />
            </View>
            <ErrorText>{mostrar("montos")}</ErrorText>
          </Seccion>

          <FilaSwitch
            titulo="Movimiento interno"
            detalle="Depósito al banco, retiro o traspaso entre cajas. Mueve dinero pero NO es un ingreso ni un gasto, por eso no se refleja en Contabilidad."
            value={interno}
            onValueChange={setInterno}
          />

          {gastoReal ? (
            <View>
              <FieldLabel>CATEGORÍA DEL GASTO</FieldLabel>
              <OptionGrid options={CATS} value={categoria} onPick={(c) => { setCategoria(c); if (c !== "Gastos fijos") setSubcategoria(""); }} columns={3} height={42} fontSize={12} />
              <ErrorText>{mostrar("categoria")}</ErrorText>
              {categoria === "Gastos fijos" ? (
                <View style={{ marginTop: 14 }}>
                  <FieldLabel>TIPO DE GASTO FIJO</FieldLabel>
                  <OptionGrid options={SUBCATS["Gastos fijos"]} value={subcategoria} onPick={setSubcategoria} columns={3} height={42} fontSize={12} />
                  <ErrorText>{mostrar("subcategoria")}</ErrorText>
                </View>
              ) : null}
              <Text style={t(11, 400, C.muted, { marginTop: 8, lineHeight: 15 })}>Se pide porque es un gasto real: se registra en Contabilidad con esta categoría.</Text>
            </View>
          ) : null}

          <Seccion titulo="FOTOS DE RECIBOS">
            <FotosBloque items={fotos} onAgregar={agregar} onQuitar={quitar} error={errFoto} ocupado={ocupado} />
          </Seccion>

          {fila ? (
            borrando ? (
              <View style={{ gap: 10 }}>
                <Text style={t(12.5, 600, C.ink, { lineHeight: 18 })}>¿Eliminar este movimiento? Se quita de la hoja del día y del ERP.</Text>
                <SecondaryButton label="Sí, eliminar" onPress={borrar} danger />
                <SecondaryButton label="No, conservar" onPress={() => setBorrando(false)} />
              </View>
            ) : (
              <SecondaryButton label="Eliminar movimiento" onPress={() => setBorrando(true)} danger />
            )
          ) : null}
        </ScrollView>
        <BottomBar bottomInset={bottomInset}>
          <PrimaryButton label={fila ? "GUARDAR CAMBIOS" : "GUARDAR MOVIMIENTO"} onPress={guardar} />
        </BottomBar>
      </KeyboardAvoidingView>
    </Screen>
  );
}
