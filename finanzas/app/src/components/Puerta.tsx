import { useState, type ReactNode } from "react";
import { Text } from "react-native";
import { C, kicker, t } from "../theme";
import { Sheet } from "./Overlays";
import { PrimaryButton } from "./ui";
import type { Permisos } from "../lib/caja/permisos";

/** Aviso de por qué no se puede hacer algo (día cerrado, falta de permiso, sin conexión). */
export function AvisoSheet({ titulo, texto, onClose, bottomInset }: { titulo: string; texto: string; onClose: () => void; bottomInset: number }) {
  return (
    <Sheet onClose={onClose} bottomInset={bottomInset}>
      <Text style={kicker(C.muted, 10.5)}>NO SE PUEDE</Text>
      <Text style={t(20, 800, C.ink, { marginTop: 6 })}>{titulo}</Text>
      <Text style={t(12.5, 400, C.muted, { marginTop: 6, marginBottom: 16, lineHeight: 18 })}>{texto}</Text>
      <PrimaryButton label="ENTENDIDO" onPress={onClose} />
    </Sheet>
  );
}

/**
 * Puerta de los cambios que reescriben el pasado. El servidor es quien decide de verdad (rol de la cuenta); aquí solo se
 * avisa antes, para no dejar llenar un formulario que va a ser rechazado.
 * `pedir(pasado, accion, cerrado)`: si el día está cerrado o es anterior a hoy y el rol no puede corregirlo, explica por qué.
 */
export function usePuerta(permisos: Permisos, bottomInset: number) {
  const [aviso, setAviso] = useState<{ titulo: string; texto: string } | null>(null);
  const pedir = (pasado: boolean, accion: () => void, cerrado = false) => {
    if (cerrado) return setAviso({ titulo: "Día cerrado", texto: "Este día ya se cerró y no se puede cambiar. Si hay un error, un administrador puede reabrirlo." });
    if (pasado && !permisos.corregir_pasado) return setAviso({ titulo: "Día anterior", texto: "Solo Finanzas o un administrador pueden corregir días anteriores. Pídeselo a ellos." });
    accion();
  };
  const modal: ReactNode = aviso ? <AvisoSheet {...aviso} bottomInset={bottomInset} onClose={() => setAviso(null)} /> : null;
  return { pedir, modal, avisar: (titulo: string, texto: string) => setAviso({ titulo, texto }) };
}
