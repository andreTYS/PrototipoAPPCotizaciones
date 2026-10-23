/** Piezas visuales propias de Caja diaria, Caja chica y Reportes (el resto vive en ui.tsx). */
import { useEffect, useState, type ReactNode } from "react";
import { Image, Modal, Pressable, Switch, Text, TextInput, View } from "react-native";
import { C, card, kicker, t } from "../theme";
import { PrimaryButton } from "./ui";
import { CIUDADES, CIUDAD_LABEL, type Adjunto, type Ciudad } from "../lib/caja/types";
import { conError, pendientes, type State } from "../lib/caja/store";
import { sync, urlAdjunto } from "../lib/caja/runtime";
import { sumarDias } from "../lib/format";
import { urlFoto } from "../lib/caja/fotos";
import type { EstadoSync } from "../lib/caja/sync";
import type { FotoGuardada } from "../lib/caja/fotos";

// ---- barra de pestañas -------------------------------------------------------------------------

export type Pestana = "diaria" | "chica" | "historial" | "reportes";

function Icono({ tipo, color }: { tipo: Pestana; color: string }) {
  const borde = { borderWidth: 2, borderColor: color };
  if (tipo === "diaria")
    return (
      <View style={[{ width: 24, height: 24, borderRadius: 6, paddingHorizontal: 4, justifyContent: "center", gap: 3 }, borde]}>
        <View style={{ height: 2, backgroundColor: color, borderRadius: 1 }} />
        <View style={{ height: 2, width: "60%", backgroundColor: color, borderRadius: 1 }} />
      </View>
    );
  if (tipo === "chica")
    return (
      <View style={[{ width: 24, height: 24, borderRadius: 12, alignItems: "center", justifyContent: "center" }, borde]}>
        <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: color }} />
      </View>
    );
  if (tipo === "historial")
    return (
      <View style={[{ width: 24, height: 24, borderRadius: 12, alignItems: "center", justifyContent: "center" }, borde]}>
        <View style={{ position: "absolute", width: 2, height: 7, top: 4, backgroundColor: color, borderRadius: 1 }} />
        <View style={{ position: "absolute", width: 6, height: 2, left: 10, top: 10, backgroundColor: color, borderRadius: 1 }} />
      </View>
    );
  return (
    <View style={{ width: 24, height: 24, flexDirection: "row", alignItems: "flex-end", justifyContent: "space-between", paddingHorizontal: 2 }}>
      {[10, 18, 14].map((h, i) => (
        <View key={i} style={{ width: 5, height: h, borderRadius: 1.5, backgroundColor: color }} />
      ))}
    </View>
  );
}

const PESTANAS: { id: Pestana; label: string }[] = [
  { id: "diaria", label: "Caja diaria" },
  { id: "chica", label: "Caja chica" },
  { id: "historial", label: "Historial" },
  { id: "reportes", label: "Reportes" },
];

export function TabBar({ activa, onPick, bottomInset }: { activa: Pestana; onPick: (p: Pestana) => void; bottomInset: number }) {
  return (
    <View style={{ flexDirection: "row", backgroundColor: C.card, borderTopWidth: 1, borderTopColor: C.line, paddingBottom: bottomInset }} accessibilityRole="tablist">
      {PESTANAS.map((p) => {
        const on = p.id === activa;
        const color = on ? C.teal : C.placeholder;
        return (
          <Pressable key={p.id} onPress={() => onPick(p.id)} accessibilityRole="tab" accessibilityState={{ selected: on }} style={{ flex: 1, alignItems: "center", paddingTop: 0, paddingBottom: 9 }}>
            <View style={{ width: 30, height: 3, borderRadius: 2, backgroundColor: on ? C.teal : "transparent", marginBottom: 9 }} />
            <Icono tipo={p.id} color={color} />
            <Text style={t(10.5, on ? 800 : 600, color, { marginTop: 5 })}>{p.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

/** Menú lateral para pantallas grandes (computadora): el mismo contenido que la barra de abajo del teléfono. */
export function MenuLateral({ activa, onPick, nombre, rol, onSalir }: { activa: Pestana; onPick: (p: Pestana) => void; nombre: string; rol: string; onSalir: () => void }) {
  return (
    <View style={{ width: 240, backgroundColor: C.card, borderRightWidth: 1, borderRightColor: C.line, paddingVertical: 22, paddingHorizontal: 14 }} accessibilityRole="tablist">
      <View style={{ flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 8, marginBottom: 26 }}>
        <Image source={require("../../assets/icon.png")} style={{ width: 38, height: 38, borderRadius: 10 }} accessibilityLabel="ICR" />
        <View>
          <Text style={t(15, 800, C.ink)}>ICR Finanzas</Text>
          <Text style={t(11, 400, C.muted)}>Caja diaria y caja chica</Text>
        </View>
      </View>
      <View style={{ gap: 4 }}>
        {PESTANAS.map((p) => {
          const on = p.id === activa;
          const color = on ? C.teal : C.muted;
          return (
            <Pressable
              key={p.id} onPress={() => onPick(p.id)} accessibilityRole="tab" accessibilityState={{ selected: on }}
              style={({ pressed, hovered }: { pressed: boolean; hovered?: boolean }) => ({ flexDirection: "row", alignItems: "center", gap: 12, paddingVertical: 11, paddingHorizontal: 12, borderRadius: 12, backgroundColor: on ? C.tint : pressed || hovered ? C.bg : "transparent" })}
            >
              <Icono tipo={p.id} color={color} />
              <Text style={t(13.5, on ? 800 : 600, on ? C.teal : C.ink)}>{p.label}</Text>
            </Pressable>
          );
        })}
      </View>
      <View style={{ flex: 1 }} />
      <View style={{ borderTopWidth: 1, borderTopColor: C.line, paddingTop: 14, paddingHorizontal: 8, gap: 2 }}>
        <Text style={t(13, 800, C.ink)} numberOfLines={1}>{nombre}</Text>
        <Text style={t(11.5, 400, C.muted)}>{rol}</Text>
        <Pressable onPress={onSalir} accessibilityRole="button" style={{ marginTop: 8, alignSelf: "flex-start" }}>
          <Text style={t(12, 800, C.teal)}>Cerrar sesión</Text>
        </Pressable>
      </View>
    </View>
  );
}

// ---- selector de ciudad ------------------------------------------------------------------------

/** Dos botones, Arequipa / Moquegua. `claro` = sobre fondo blanco; si no, sobre el degradado. */
export function CiudadSwitch({ valor, onChange, claro = false }: { valor: Ciudad; onChange: (c: Ciudad) => void; claro?: boolean }) {
  return (
    <View style={{ flexDirection: "row", borderRadius: 999, padding: 3, backgroundColor: claro ? C.bg : "rgba(13,34,51,.22)" }} accessibilityRole="radiogroup">
      {CIUDADES.map((c) => {
        const on = c === valor;
        return (
          <Pressable key={c} onPress={() => onChange(c)} accessibilityRole="radio" accessibilityState={{ selected: on }} style={{ paddingVertical: 6, paddingHorizontal: 12, borderRadius: 999, backgroundColor: on ? (claro ? C.teal : C.card) : "transparent" }}>
            <Text style={t(11.5, 800, on ? (claro ? C.white : C.teal) : claro ? C.muted : "rgba(255,255,255,.85)")}>{CIUDAD_LABEL[c]}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

// ---- aviso de sincronización -------------------------------------------------------------------

/** Barra bajo el encabezado: dice si hay cambios por enviar, si falta conexión o si el servidor rechazó algo. */
export function AvisoSync({ estado, caja }: { estado: EstadoSync; caja: State }) {
  const pend = pendientes(caja);
  const errores = conError(caja).length;
  if (estado.fase === "sesion-vencida") return <Franja color={C.red} fondo="#FBE9E9" texto="Tu sesión venció. Vuelve a iniciar sesión para enviar lo pendiente." />;
  if (errores > 0)
    return <Franja color={C.red} fondo="#FBE9E9" texto={`${errores} ${errores === 1 ? "cambio no se pudo guardar" : "cambios no se pudieron guardar"}. Revisa los marcados en rojo.`} accion="Reintentar" onAccion={() => void sync.reintentarTodo()} />;
  if (estado.fase === "sin-conexion") return <Franja color={C.red} fondo="#FBE9E9" texto={pend ? `Sin conexión · ${pend} ${pend === 1 ? "cambio" : "cambios"} sin enviar. No cierres esta pantalla hasta que vuelva internet.` : "Sin conexión. Mientras tanto no se puede guardar nada."} accion="Reintentar" onAccion={() => void sync.sincronizar()} />;
  if (estado.fase === "sincronizando" && pend) return <Franja color={C.ink} fondo={C.tint} texto={`Enviando ${pend} ${pend === 1 ? "cambio" : "cambios"}…`} />;
  if (pend) return <Franja color={C.ink} fondo={C.tint} texto={`${pend} ${pend === 1 ? "cambio" : "cambios"} por enviar`} accion="Enviar ahora" onAccion={() => void sync.sincronizar()} />;
  return null;
}

function Franja({ texto, fondo, color, accion, onAccion }: { texto: string; fondo: string; color: string; accion?: string; onAccion?: () => void }) {
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: fondo, paddingVertical: 9, paddingHorizontal: 16 }} accessibilityRole="alert">
      <Text style={t(12, 600, color, { flex: 1, lineHeight: 16 })}>{texto}</Text>
      {accion ? (
        <Pressable onPress={onAccion} hitSlop={8}>
          <Text style={t(12, 800, C.teal)}>{accion}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

/** Etiqueta chica dentro de una fila: "Sin enviar", error, etc. */
export function Etiqueta({ texto, tono }: { texto: string; tono: "info" | "error" }) {
  const e = tono === "error";
  return (
    <View style={{ alignSelf: "flex-start", paddingVertical: 2, paddingHorizontal: 7, borderRadius: 5, backgroundColor: e ? "#FBE9E9" : C.tint }}>
      <Text style={t(9.5, 800, e ? C.red : C.teal, { letterSpacing: 0.4 })}>{texto}</Text>
    </View>
  );
}

// ---- campos ------------------------------------------------------------------------------------

/** Importe compacto con su etiqueta (para las seis columnas de la planilla). */
export function MontoCampo({ label, value, onChangeText, color = C.ink }: { label: string; value: string; onChangeText: (v: string) => void; color?: string }) {
  const [foco, setFoco] = useState(false);
  return (
    <View style={{ flex: 1, minWidth: 0 }}>
      <Text style={kicker(C.muted, 9.5)} numberOfLines={1}>{label}</Text>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 6, marginTop: 6, height: 46, paddingHorizontal: 10, borderRadius: 12, borderWidth: 1, backgroundColor: C.card, borderColor: foco ? C.teal : C.border }}>
        <Text style={t(13, 800, color)}>S/</Text>
        <TextInput
          value={value}
          onChangeText={onChangeText}
          onFocus={() => setFoco(true)}
          onBlur={() => setFoco(false)}
          keyboardType="decimal-pad"
          placeholder="0.00"
          placeholderTextColor={C.placeholder}
          selectionColor={C.teal}
          cursorColor={C.teal}
          accessibilityLabel={label}
          style={[t(16, 800), { flex: 1, minWidth: 0, padding: 0, height: 44, outlineWidth: 0 }]}
        />
      </View>
    </View>
  );
}

export function FilaSwitch({ titulo, detalle, value, onValueChange }: { titulo: string; detalle: string; value: boolean; onValueChange: (v: boolean) => void }) {
  return (
    <View style={[card(14), { flexDirection: "row", alignItems: "center", gap: 12, padding: 14 }]}>
      <View style={{ flex: 1 }}>
        <Text style={t(13, 700)}>{titulo}</Text>
        <Text style={t(11.5, 400, C.muted, { marginTop: 3, lineHeight: 16 })}>{detalle}</Text>
      </View>
      <Switch value={value} onValueChange={onValueChange} trackColor={{ false: C.border, true: C.teal }} thumbColor={C.white} accessibilityLabel={titulo} />
    </View>
  );
}

/** Navegación de fecha: ‹ jue 22 oct 2026 ›. No deja pasar de hoy. */
export function FechaNav({ fecha, hoy, onChange, textoFecha }: { fecha: string; hoy: string; onChange: (f: string) => void; textoFecha: string }) {
  const flecha = (signo: "‹" | "›", dir: -1 | 1, off: boolean, etiqueta: string) => (
    <Pressable onPress={() => !off && onChange(sumarDias(fecha, dir))} disabled={off} accessibilityLabel={etiqueta} hitSlop={8} style={{ width: 34, height: 34, borderRadius: 17, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(255,255,255,.2)", opacity: off ? 0.35 : 1 }}>
      <Text style={t(20, 600, C.white, { marginTop: -3 })}>{signo}</Text>
    </Pressable>
  );
  return (
    <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
      {flecha("‹", -1, false, "Día anterior")}
      <View style={{ alignItems: "center" }}>
        <Text style={t(13.5, 800, C.white)}>{textoFecha}</Text>
        {fecha === hoy ? <Text style={t(10.5, 700, C.mint, { letterSpacing: 0.6, marginTop: 1 })}>HOY</Text> : null}
      </View>
      {flecha("›", 1, fecha >= hoy, "Día siguiente")}
    </View>
  );
}
// ---- fotos de recibos --------------------------------------------------------------------------

/** Una foto en el formulario: ya guardada en el servidor/dispositivo (`adj`) o recién tomada (`nueva`). */
export type FotoItem = { id: string; adj?: Adjunto; nueva?: FotoGuardada };

function useUrl(item: FotoItem) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    const p = item.nueva ? urlFoto(item.nueva.key) : item.adj ? urlAdjunto(item.adj) : Promise.resolve(null);
    void p.then((u) => vivo && setUrl(u));
    return () => {
      vivo = false;
    };
  }, [item.id, item.nueva?.key, item.adj?.id, item.adj?.localKey]);
  return url;
}

function Miniatura({ item, onVer, onQuitar }: { item: FotoItem; onVer: (url: string) => void; onQuitar?: () => void }) {
  const url = useUrl(item);
  return (
    <View style={{ width: 72, height: 72 }}>
      <Pressable onPress={() => url && onVer(url)} accessibilityLabel="Ver foto del recibo" style={{ width: 72, height: 72, borderRadius: 12, overflow: "hidden", backgroundColor: C.stripeB, borderWidth: 1, borderColor: C.line, alignItems: "center", justifyContent: "center" }}>
        {url ? <Image source={{ uri: url }} style={{ width: "100%", height: "100%" }} resizeMode="cover" /> : <Text style={t(10, 700, C.muted)}>foto</Text>}
      </Pressable>
      {onQuitar ? (
        <Pressable onPress={onQuitar} accessibilityLabel="Quitar foto" hitSlop={6} style={{ position: "absolute", top: -6, right: -6, width: 22, height: 22, borderRadius: 11, backgroundColor: C.ink, alignItems: "center", justifyContent: "center" }}>
          <Text style={t(13, 800, C.white, { marginTop: -1 })}>×</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

/** Fotos de recibos: miniaturas, botones para tomar/elegir otra, y vista ampliada al tocar. */
export function FotosBloque({ items, onAgregar, onQuitar, error, ocupado }: { items: FotoItem[]; onAgregar: (o: "camara" | "galeria") => void; onQuitar: (id: string) => void; error?: string | null; ocupado?: boolean }) {
  const [grande, setGrande] = useState<string | null>(null);
  return (
    <View style={{ gap: 12 }}>
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 12 }}>
        {items.map((it) => (
          <Miniatura key={it.id} item={it} onVer={setGrande} onQuitar={() => onQuitar(it.id)} />
        ))}
        {items.length === 0 ? <Text style={t(12, 400, C.muted, { alignSelf: "center" })}>Aún no hay fotos de recibos.</Text> : null}
      </View>
      <View style={{ flexDirection: "row", gap: 10 }}>
        {(["camara", "galeria"] as const).map((o) => (
          <Pressable key={o} onPress={() => onAgregar(o)} disabled={ocupado} style={({ pressed }) => ({ flex: 1, height: 44, borderRadius: 12, borderWidth: 1.5, borderColor: C.navy, backgroundColor: pressed ? C.bg : C.card, alignItems: "center", justifyContent: "center", opacity: ocupado ? 0.5 : 1 })}>
            <Text style={t(12.5, 800, C.navy)}>{o === "camara" ? "Tomar foto" : "Elegir de la galería"}</Text>
          </Pressable>
        ))}
      </View>
      {error ? <Text style={t(11.5, 400, C.red)}>{error}</Text> : null}
      <Modal visible={!!grande} transparent animationType="fade" onRequestClose={() => setGrande(null)}>
        <Pressable onPress={() => setGrande(null)} accessibilityLabel="Cerrar foto" style={{ flex: 1, backgroundColor: "rgba(13,34,51,.92)", alignItems: "center", justifyContent: "center", padding: 16 }}>
          {grande ? <Image source={{ uri: grande }} style={{ width: "100%", height: "88%" }} resizeMode="contain" /> : null}
          <Text style={t(12, 700, C.white, { marginTop: 10 })}>Toca para cerrar</Text>
        </Pressable>
      </Modal>
    </View>
  );
}

/** Miniaturas de solo lectura (detalle de un movimiento). */
export function FotosSoloLectura({ adjuntos }: { adjuntos: Adjunto[] }) {
  const [grande, setGrande] = useState<string | null>(null);
  if (!adjuntos.length) return null;
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 10 }}>
      {adjuntos.map((a) => (
        <Miniatura key={a.id} item={{ id: a.id, adj: a }} onVer={setGrande} />
      ))}
      <Modal visible={!!grande} transparent animationType="fade" onRequestClose={() => setGrande(null)}>
        <Pressable onPress={() => setGrande(null)} style={{ flex: 1, backgroundColor: "rgba(13,34,51,.92)", alignItems: "center", justifyContent: "center", padding: 16 }}>
          {grande ? <Image source={{ uri: grande }} style={{ width: "100%", height: "88%" }} resizeMode="contain" /> : null}
          <Text style={t(12, 700, C.white, { marginTop: 10 })}>Toca para cerrar</Text>
        </Pressable>
      </Modal>
    </View>
  );
}

export function Seccion({ titulo, children, derecha }: { titulo: string; children: ReactNode; derecha?: ReactNode }) {
  return (
    <View style={{ gap: 10 }}>
      <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
        <Text style={kicker(C.ink, 11.5)}>{titulo}</Text>
        {derecha}
      </View>
      {children}
    </View>
  );
}

export { PrimaryButton };
