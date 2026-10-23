import { Component, useEffect, useState, type ErrorInfo, type ReactNode } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider, useSafeAreaInsets } from "react-native-safe-area-context";
import { useFonts, Manrope_400Regular, Manrope_500Medium, Manrope_600SemiBold, Manrope_700Bold, Manrope_800ExtraBold } from "@expo-google-fonts/manrope";

import { C, t } from "./src/theme";
import { loadSession, logout, refrescarPermisos, setUnauthorizedHandler, type Session } from "./src/lib/api";
import { ROL_LABEL } from "./src/lib/caja/permisos";
import { sync, store, useCaja, useEstadoSync, useSyncAutomatica } from "./src/lib/caja/runtime";
import type { Ciudad } from "./src/lib/caja/types";
import { Login } from "./src/screens/Login";
import { CajaDiariaFlujo } from "./src/screens/CajaDiariaFlujo";
import { CajaChicaFlujo } from "./src/screens/CajaChicaFlujo";
import { Historial } from "./src/screens/Historial";
import { Reportes } from "./src/screens/Reportes";
import { MenuLateral, TabBar, type Pestana } from "./src/components/caja";
import { ANCHO, useEscritorio } from "./src/lib/layout";
import { Avisos } from "./src/components/Overlays";

export default function App() {
  const [fontsLoaded] = useFonts({ Manrope_400Regular, Manrope_500Medium, Manrope_600SemiBold, Manrope_700Bold, Manrope_800ExtraBold });
  return (
    <SafeAreaProvider>
      <View style={{ flex: 1, backgroundColor: C.stripeB }}>
        <StatusBar style="light" />
        {fontsLoaded ? (
          <ErrorBoundary>
            <Shell />
          </ErrorBoundary>
        ) : null}
      </View>
    </SafeAreaProvider>
  );
}

/** Sesión, pestañas y avisos. Cada pestaña maneja sus propias pantallas. */
function Shell() {
  const insets = useSafeAreaInsets();
  const caja = useCaja();
  const estado = useEstadoSync();
  const escritorio = useEscritorio();
  const [listo, setListo] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [tab, setTab] = useState<Pestana>("diaria");
  const [sinTabs, setSinTabs] = useState(false);
  const [irA, setIrA] = useState<{ fecha: string; n: number } | undefined>();

  useEffect(() => {
    setUnauthorizedHandler(() => setSession(null));
    void Promise.all([store.init(), loadSession()]).then(async ([, s]) => {
      setSession(s);
      setListo(true);
      if (s) setSession((await refrescarPermisos()) ?? s); // por si cambiaron el rol desde la última vez
    });
    return () => setUnauthorizedHandler(null);
  }, []);
  useSyncAutomatica(!!session);

  // el rol puede cambiar mientras la app está abierta: se vuelve a preguntar cada tanto
  useEffect(() => {
    if (!session) return;
    const id = setInterval(() => void refrescarPermisos().then((s) => s && setSession(s)), 60_000);
    return () => clearInterval(id);
  }, [!!session]);

  if (!listo) return null;
  const inset = { topInset: insets.top, bottomInset: insets.bottom };
  const ciudad: Ciudad = caja.ciudad;
  const cambiarCiudad = (c: Ciudad) => store.setCiudad(c);
  const verTabs = (oculto: boolean) => setSinTabs(oculto);

  const salir = () => void logout().then(() => store.reiniciar()).then(() => setSession(null));
  const conSesion = !!session && session.permisos.acceso;

  return (
    // Teléfono (y tableta): una columna. Computadora: menú lateral a la izquierda y el contenido en un panel centrado.
    <View style={{ flex: 1, width: "100%", flexDirection: escritorio && conSesion ? "row" : "column", maxWidth: escritorio ? undefined : 640, alignSelf: "center", backgroundColor: escritorio && conSesion ? C.stripeB : C.bg }}>
      {!session ? (
        <Login onLoggedIn={() => void loadSession().then((s) => (setSession(s), sync.sincronizar()))} {...inset} />
      ) : !session.permisos.acceso ? (
        <SinAcceso session={session} onSalir={salir} {...inset} />
      ) : (
        <>
          {escritorio ? <MenuLateral activa={tab} onPick={setTab} nombre={session.nombre} rol={ROL_LABEL[session.rolCodigo] ?? session.rolCodigo} onSalir={salir} /> : null}
          <View style={{ flex: 1, alignItems: "center" }}>
          <View style={{ flex: 1, width: "100%", ...(escritorio ? { maxWidth: ANCHO.panel + 40, backgroundColor: C.bg, borderLeftWidth: 1, borderRightWidth: 1, borderColor: C.line } : {}) }}>
            <View style={{ flex: 1 }}>
            <View style={{ flex: 1, display: tab === "diaria" ? "flex" : "none" }}>
              <CajaDiariaFlujo caja={caja} estado={estado} ciudad={ciudad} setCiudad={cambiarCiudad} permisos={session.permisos} irA={irA} onOcultarTabs={verTabs} {...inset} />
            </View>
            <View style={{ flex: 1, display: tab === "chica" ? "flex" : "none" }}>
              <CajaChicaFlujo caja={caja} estado={estado} ciudad={ciudad} setCiudad={cambiarCiudad} permisos={session.permisos} onOcultarTabs={verTabs} {...inset} />
            </View>
            {tab === "historial" ? (
              <Historial caja={caja} estado={estado} ciudad={ciudad} setCiudad={cambiarCiudad} permisos={session.permisos} onAbrirDia={(c, fecha) => (store.setCiudad(c), setIrA({ fecha, n: Date.now() }), setTab("diaria"))} {...inset} />
            ) : null}
            {tab === "reportes" ? <Reportes caja={caja} estado={estado} session={session} onSalio={() => setSession(null)} {...inset} /> : null}
            </View>
            {!escritorio && (!sinTabs || tab === "reportes" || tab === "historial") ? <TabBar activa={tab} onPick={setTab} bottomInset={insets.bottom} /> : null}
            <Avisos avisos={caja.avisos} onCerrar={store.quitarAviso} topInset={insets.top} />
          </View>
          </View>
        </>
      )}
    </View>
  );
}

/** Cuenta válida pero sin permiso para Finanzas (p. ej. almacén o vendedor). */
function SinAcceso({ session, onSalir, topInset }: { session: Session; onSalir: () => void; topInset: number; bottomInset: number }) {
  return (
    <View style={{ flex: 1, backgroundColor: C.bg, padding: 24, paddingTop: 64 + topInset, gap: 10 }}>
      <Text style={t(24, 800)}>Sin acceso a Finanzas</Text>
      <Text style={t(13, 400, C.muted, { lineHeight: 19 })}>
        Tu cuenta ({session.nombre}) tiene el rol «{ROL_LABEL[session.rolCodigo] ?? session.rolCodigo}», que no puede usar Finanzas. Pídele a un administrador que te asigne el rol Finanzas o Encargado.
      </Text>
      <Pressable onPress={onSalir} style={{ height: 54, borderRadius: 14, backgroundColor: C.teal, alignItems: "center", justifyContent: "center", marginTop: 14 }}>
        <Text style={t(14, 800, C.white)}>SALIR</Text>
      </Pressable>
    </View>
  );
}

/**
 * If a screen throws while rendering, show what happened (and let the user retry) instead of the
 * app silently closing. The message is what we need to fix the problem.
 */
class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };
  static getDerivedStateFromError(error: Error) {
    return { error };
  }
  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("ICR Finanzas crash:", error, info.componentStack);
  }
  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <View style={{ flex: 1, backgroundColor: C.bg, padding: 24, paddingTop: 64 }}>
        <Text style={t(24, 800)}>Algo salió mal</Text>
        <Text style={t(13, 600, C.muted, { marginTop: 8 })}>Toma una captura de esta pantalla y envíala para corregirlo.</Text>
        <ScrollView style={{ flex: 1, marginVertical: 16, backgroundColor: C.card, borderRadius: 12, borderWidth: 1, borderColor: C.line }} contentContainerStyle={{ padding: 14 }}>
          <Text style={t(12, 700, C.red)}>{String(error.message)}</Text>
          <Text style={t(10.5, 400, C.muted, { marginTop: 8 })}>{String(error.stack ?? "").slice(0, 1500)}</Text>
        </ScrollView>
        <Pressable onPress={() => this.setState({ error: null })} style={{ height: 54, borderRadius: 14, backgroundColor: C.teal, alignItems: "center", justifyContent: "center" }}>
          <Text style={t(14, 800, C.white)}>REINTENTAR</Text>
        </Pressable>
      </View>
    );
  }
}
