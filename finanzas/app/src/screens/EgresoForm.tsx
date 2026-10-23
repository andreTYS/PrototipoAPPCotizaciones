import { CONTENIDO_FORMULARIO } from "../lib/layout";
import { useState } from "react";
import { Image, KeyboardAvoidingView, ScrollView, Text, View } from "react-native";
import { C, t } from "../theme";
import { AmountField, BottomBar, DateField, ErrorText, FieldLabel, Header, OptionGrid, PrimaryButton, Screen, SecondaryButton, TextField } from "../components/ui";
import { FotosBloque, Seccion, type FotoItem } from "../components/caja";
import { usePuerta } from "../components/Puerta";
import { ConfirmSheet } from "../components/Overlays";
import { cleanAmt, fdate, money, num, today } from "../lib/format";
import { type Permisos } from "../lib/caja/permisos";
import { CATS, SUBCATS, catLabel, type Egreso } from "../lib/data";
import { elegirFoto, FotoError } from "../lib/caja/foto";
import { borrarFoto, urlFoto } from "../lib/caja/fotos";
import { nuevoId } from "../lib/caja/ids";
import { store } from "../lib/caja/runtime";
import { CIUDAD_LABEL, type Ciudad, type MovChica } from "../lib/caja/types";
import type { FotoGuardada } from "../lib/caja/fotos";

type Errores = Partial<Record<"fecha" | "persona" | "desc" | "categoria" | "subcategoria" | "monto", string>>;

/**
 * Egreso de la caja chica: manual, o con los datos que leyó el OCR de la foto del recibo (marcados AUTO).
 * También sirve para corregir un egreso ya registrado (`mov`).
 */
export function EgresoForm({ ciudad, mov, inicial, fotoCaptura, saldoChica, responsables, desdeCaptura, permisos, cerrado, onClose, topInset, bottomInset }: {
  ciudad: Ciudad;
  mov?: MovChica;
  inicial?: Egreso;
  fotoCaptura?: FotoGuardada | null;
  saldoChica: number;
  responsables: string[];
  desdeCaptura: boolean;
  permisos: Permisos;
  /** El día del egreso ya está cerrado (o hay uno posterior cerrado): solo se puede ver. */
  cerrado: boolean;
  onClose: () => void;
  topInset: number;
  bottomInset: number;
}) {
  const base: Egreso = mov
    ? { fecha: mov.fecha, persona: mov.persona, desc: mov.descripcion, ciudad: "", categoria: mov.categoria, subcategoria: mov.subcategoria, monto: String(mov.monto) }
    : inicial ?? { fecha: today(), persona: "", desc: "", ciudad: "", categoria: "", subcategoria: "", monto: "" };
  const [e, setE] = useState<Egreso>(base);
  const [fotos, setFotos] = useState<FotoItem[]>(mov ? mov.adjuntos.map((a) => ({ id: a.id, adj: a })) : fotoCaptura ? [{ id: nuevoId(), nueva: fotoCaptura }] : []);
  const [errFoto, setErrFoto] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [err, setErr] = useState<Errores>({});
  const [confirmar, setConfirmar] = useState(false);
  const puerta = usePuerta(permisos, bottomInset);
  const [borrando, setBorrando] = useState(false);

  const set = <K extends keyof Egreso>(k: K, v: Egreso[K]) => (setE((p) => ({ ...p, [k]: v })), setErr((p) => ({ ...p, [k === "desc" ? "desc" : k]: undefined })));
  // Un campo conserva su marca AUTO mientras siga valiendo lo que leyó la foto.
  const auto = (k: keyof Egreso) => desdeCaptura && !mov && inicial?.[k] !== undefined && inicial[k] !== "" && inicial[k] === e[k];
  const monto = num(e.monto);
  const efecto = mov ? monto - mov.monto : monto; // al editar, solo cuenta la diferencia
  const sugerencias = responsables.filter((n) => n.toLowerCase().includes(e.persona.trim().toLowerCase()) && n !== e.persona.trim()).slice(0, 4);

  const validar = (): Errores => {
    const x: Errores = {};
    if (!e.fecha) x.fecha = "Selecciona la fecha";
    if (!e.persona.trim()) x.persona = "Indica la persona";
    if (!e.desc.trim()) x.desc = "Agrega una descripción";
    if (!e.categoria) x.categoria = "Elige una categoría";
    else if (e.categoria === "Gastos fijos" && !e.subcategoria) x.subcategoria = "Elige el tipo de gasto fijo";
    if (!(monto > 0)) x.monto = "Ingresa un monto mayor a 0";
    return x;
  };
  const revisar = () => {
    const x = validar();
    setErr(x);
    if (!Object.keys(x).length) setConfirmar(true);
  };

  const agregar = async (origen: "camara" | "galeria") => {
    setErrFoto(null);
    setOcupado(true);
    try {
      const r = await elegirFoto(origen);
      if (r) setFotos((p) => [...p, { id: nuevoId(), nueva: r.guardada }]);
    } catch (x) {
      setErrFoto(x instanceof FotoError ? x.message : "No se pudo agregar la foto.");
    } finally {
      setOcupado(false);
    }
  };

  const cancelar = () => {
    for (const f of fotos) if (f.nueva) void borrarFoto(f.nueva.key);
    onClose();
  };

  // un egreso con fecha anterior a hoy (nuevo o ya registrado) reescribe un día cerrado: pide el código
  const pasado = e.fecha < today() || (!!mov && mov.fecha < today());
  const registrar = () => puerta.pedir(pasado, guardar, cerrado);
  const guardar = () => {
    const id = mov?.id ?? nuevoId();
    store.guardarMov({
      id, ciudad, fecha: e.fecha, descripcion: e.desc.trim(), persona: e.persona.trim(), categoria: e.categoria, subcategoria: e.categoria === "Gastos fijos" ? e.subcategoria : "",
      monto, origen: mov ? (mov.origen === "TRANSFERENCIA" ? "MANUAL" : mov.origen) : desdeCaptura ? "CAPTURA" : "MANUAL",
    });
    const quedan = new Set(fotos.filter((f) => f.adj).map((f) => f.adj!.id));
    for (const a of mov?.adjuntos ?? []) if (!quedan.has(a.id)) store.quitarAdjunto("mov", id, a.id);
    for (const f of fotos) if (f.nueva) store.agregarAdjunto("mov", id, f.nueva);
    if (store.puedeEscribir()) onClose();
  };

  const eliminar = () => {
    if (!mov) return;
    puerta.pedir(pasado, () => (store.borrarMov(ciudad, mov.id), store.puedeEscribir() && onClose()), cerrado);
  };

  return (
    <Screen>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior="height">
        <Header
          kicker={mov ? "CAJA CHICA · EDITAR" : desdeCaptura ? "CAJA CHICA · DESDE CAPTURA" : "CAJA CHICA · MANUAL"}
          title="Datos del egreso"
          sub={`${CIUDAD_LABEL[ciudad]} · caja chica ${money(saldoChica)}`}
          onBack={cancelar}
          topInset={topInset}
        />
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ ...CONTENIDO_FORMULARIO, paddingTop: 18, paddingHorizontal: 20, paddingBottom: 24, gap: 18 }} keyboardShouldPersistTaps="handled">
          {desdeCaptura && !mov ? (
            <View style={{ flexDirection: "row", gap: 12, alignItems: "center", backgroundColor: C.tint, borderRadius: 14, padding: 12 }}>
              <MiniaturaCaptura foto={fotoCaptura} />
              <Text style={t(12, 400, C.ink, { flex: 1, lineHeight: 17 })}>
                <Text style={t(12, 800, C.ink)}>Datos detectados automáticamente.</Text> Revisa y corrige lo que sea necesario. La foto queda guardada con el egreso.
              </Text>
            </View>
          ) : null}

          <View>
            <FieldLabel auto={auto("fecha")}>FECHA</FieldLabel>
            <DateField value={e.fecha} onChange={(v) => set("fecha", v)} />
            <ErrorText>{err.fecha}</ErrorText>
          </View>
          <View>
            <FieldLabel auto={auto("persona")}>PERSONA</FieldLabel>
            <TextField value={e.persona} onChangeText={(v) => set("persona", v)} placeholder="¿A quién se pagó?" accessibilityLabel="Persona" />
            {sugerencias.length ? (
              <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 8 }}>
                {sugerencias.map((n) => (
                  <Text key={n} onPress={() => set("persona", n)} style={[t(11.5, 700), { paddingVertical: 5, paddingHorizontal: 11, borderRadius: 999, borderWidth: 1, borderColor: C.border, backgroundColor: C.card, overflow: "hidden" }]}>{n}</Text>
                ))}
              </View>
            ) : null}
            <ErrorText>{err.persona}</ErrorText>
          </View>
          <View>
            <FieldLabel auto={auto("desc")}>DESCRIPCIÓN</FieldLabel>
            <TextField value={e.desc} onChangeText={(v) => set("desc", v)} placeholder="Ej. Compra de cemento para losa" accessibilityLabel="Descripción" />
            <ErrorText>{err.desc}</ErrorText>
          </View>
          <View>
            <FieldLabel auto={auto("categoria")}>CATEGORÍA</FieldLabel>
            <OptionGrid options={CATS} value={e.categoria} onPick={(c) => { set("categoria", c); if (c !== "Gastos fijos") set("subcategoria", ""); }} columns={3} height={42} fontSize={12} />
            <ErrorText>{err.categoria}</ErrorText>
          </View>
          {e.categoria === "Gastos fijos" ? (
            <View>
              <FieldLabel auto={auto("subcategoria")}>TIPO DE GASTO FIJO</FieldLabel>
              <OptionGrid options={SUBCATS["Gastos fijos"]} value={e.subcategoria} onPick={(v) => set("subcategoria", v)} columns={3} height={42} fontSize={12} />
              <ErrorText>{err.subcategoria}</ErrorText>
            </View>
          ) : null}
          <View>
            <FieldLabel auto={auto("monto")}>MONTO</FieldLabel>
            <AmountField value={e.monto} onChangeText={(v) => set("monto", cleanAmt(v))} accent={C.navy} />
            <ErrorText>{err.monto}</ErrorText>
            {monto > 0 ? <Text style={t(12, 700, saldoChica - efecto < 0 ? C.red : C.navy, { marginTop: 8 })}>Caja chica quedará en {money(saldoChica - efecto)}{saldoChica - efecto < 0 ? " · saldo negativo" : ""}</Text> : null}
          </View>

          <Seccion titulo="FOTOS DE RECIBOS">
            <FotosBloque items={fotos} onAgregar={agregar} onQuitar={(id) => setFotos((p) => p.filter((x) => x.id !== id))} error={errFoto} ocupado={ocupado} />
          </Seccion>

          {mov ? (
            borrando ? (
              <View style={{ gap: 10 }}>
                <Text style={t(12.5, 600, C.ink, { lineHeight: 18 })}>¿Eliminar este egreso? La caja chica recupera el monto y se quita del ERP.</Text>
                <SecondaryButton label="Sí, eliminar" onPress={eliminar} danger />
                <SecondaryButton label="No, conservar" onPress={() => setBorrando(false)} />
              </View>
            ) : (
              <SecondaryButton label="Eliminar egreso" onPress={() => setBorrando(true)} danger />
            )
          ) : null}
        </ScrollView>
        <BottomBar bottomInset={bottomInset}>
          <PrimaryButton label="CONFIRMAR EGRESO" onPress={revisar} />
        </BottomBar>
      </KeyboardAvoidingView>
      {confirmar ? (
        <ConfirmSheet
          data={{
            kicker: "CONFIRMA TU EGRESO",
            amount: `−${money(monto)}`,
            amountColor: C.red,
            rows: [["Ciudad", CIUDAD_LABEL[ciudad]], ["Fecha", fdate(e.fecha)], ["Persona", e.persona], ["Descripción", e.desc], ["Categoría", catLabel(e.categoria, e.subcategoria)], ["Fotos", String(fotos.length)], ["Origen", desdeCaptura ? "Captura de recibo" : "Manual"]],
            newBalance: money(saldoChica - efecto),
            newBalanceLabel: "Caja chica después del registro",
            cta: mov ? "GUARDAR CAMBIOS" : "REGISTRAR EGRESO",
          }}
          onConfirm={registrar}
          onClose={() => setConfirmar(false)}
          bottomInset={bottomInset}
        />
      ) : null}
      {puerta.modal}
    </Screen>
  );
}

function MiniaturaCaptura({ foto }: { foto?: FotoGuardada | null }) {
  const [url, setUrl] = useState<string | null>(null);
  useState(() => void (foto && urlFoto(foto.key).then(setUrl)));
  return (
    <View style={{ width: 46, height: 56, borderRadius: 8, overflow: "hidden", backgroundColor: C.stripeB }}>
      {url ? <Image source={{ uri: url }} style={{ width: "100%", height: "100%" }} resizeMode="cover" /> : null}
    </View>
  );
}
