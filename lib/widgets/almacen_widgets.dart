import 'package:flutter/material.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../models/requerimiento.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../utils/formato.dart';
import 'animated_pressable.dart';

/// Colores de estado de Almacén — aparte de los de marca, porque tienen que
/// leerse de un vistazo: ámbar = falta algo, azul = aprobado, verde = listo,
/// rojo = urgente.
class ColoresEstado {
  ColoresEstado._();

  static const pendiente = Color(0xFFB45309);
  static const pendienteFondo = Color(0xFFFEF3C7);
  static const aprobado = BrandColors.azulOscuro;
  static const aprobadoFondo = Color(0xFFDBEAFE);
  static const listo = Color(0xFF047857);
  static const listoFondo = Color(0xFFD1FAE5);
  static const urgente = Color(0xFFB91C1C);
  static const urgenteFondo = Color(0xFFFEE2E2);

  static (Color, Color) deRequerimiento(EstadoRequerimiento estado) => switch (estado) {
        EstadoRequerimiento.pendiente => (pendiente, pendienteFondo),
        EstadoRequerimiento.aprobado => (aprobado, aprobadoFondo),
        EstadoRequerimiento.entregado => (listo, listoFondo),
      };

  static (Color, Color) deHerramientas(EstadoHerramientas estado) => switch (estado) {
        EstadoHerramientas.pendiente => (pendiente, pendienteFondo),
        EstadoHerramientas.conforme => (listo, listoFondo),
      };
}

/// Pastilla de estado ("Pendiente aprobación", "Urgente", "Conforme"...).
class PildoraEstado extends StatelessWidget {
  final String texto;
  final Color color;
  final Color fondo;
  final IconData? icono;

  const PildoraEstado({super.key, required this.texto, required this.color, required this.fondo, this.icono});

  factory PildoraEstado.requerimiento(EstadoRequerimiento estado) {
    final (color, fondo) = ColoresEstado.deRequerimiento(estado);
    return PildoraEstado(texto: estado.etiqueta, color: color, fondo: fondo);
  }

  factory PildoraEstado.herramientas(EstadoHerramientas estado) {
    final (color, fondo) = ColoresEstado.deHerramientas(estado);
    return PildoraEstado(texto: estado.etiqueta, color: color, fondo: fondo);
  }

  factory PildoraEstado.urgente() => const PildoraEstado(
        texto: 'Urgente',
        color: ColoresEstado.urgente,
        fondo: ColoresEstado.urgenteFondo,
        icono: Icons.priority_high_rounded,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 12, color: color),
            const SizedBox(width: 2),
          ],
          Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

/// Tarjeta base de las listas de Almacén: mismo formato que las tarjetas del
/// historial de cotizaciones (ícono en caja de color, título, subtítulo) con
/// las pastillas de estado debajo.
class _TarjetaAlmacen extends StatelessWidget {
  final IconData icono;
  final Color colorIcono;
  final String titulo;
  final String subtitulo;
  final List<Widget> pildoras;
  final VoidCallback onTap;

  const _TarjetaAlmacen({
    required this.icono,
    required this.colorIcono,
    required this.titulo,
    required this.subtitulo,
    required this.pildoras,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorIcono.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: colorIcono, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: BrandColors.azulMarino),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: pildoras),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class TarjetaRequerimiento extends StatelessWidget {
  final Requerimiento requerimiento;
  final VoidCallback onTap;

  const TarjetaRequerimiento({super.key, required this.requerimiento, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = requerimiento;
    final urgenteActivo = r.urgente && !r.entregado;
    final (colorEstado, _) = ColoresEstado.deRequerimiento(r.estado);
    return _TarjetaAlmacen(
      icono: Icons.assignment_outlined,
      colorIcono: urgenteActivo ? ColoresEstado.urgente : colorEstado,
      titulo: r.obra.isEmpty ? 'Obra sin nombre' : r.obra,
      subtitulo:
          '${r.numero} · ${cantidadConPalabra(r.totalItems, 'ítem', 'ítems')} · ${fechaCorta(r.fechaCreacion)} · ${r.solicitante}',
      pildoras: [
        PildoraEstado.requerimiento(r.estado),
        if (urgenteActivo) PildoraEstado.urgente(),
      ],
      onTap: onTap,
    );
  }
}

class TarjetaHerramientas extends StatelessWidget {
  final ChecklistHerramientas checklist;
  final VoidCallback onTap;

  const TarjetaHerramientas({super.key, required this.checklist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = checklist;
    final (colorEstado, _) = ColoresEstado.deHerramientas(h.estado);
    return _TarjetaAlmacen(
      icono: Icons.handyman_outlined,
      colorIcono: colorEstado,
      titulo: h.obra.isEmpty ? 'Obra sin nombre' : h.obra,
      subtitulo:
          '${h.numero} · ${cantidadConPalabra(h.totalItems, 'herramienta', 'herramientas')} · ${fechaCorta(h.fechaSalida)} · ${h.responsable}',
      pildoras: [PildoraEstado.herramientas(h.estado)],
      onTap: onTap,
    );
  }
}

/// Un paso del recorrido de estados en el detalle (ej. "Aprobado por jefe
/// de obra · 29/09 10:15 · Ing. Pérez").
class PasoEstado {
  final String titulo;
  final String detalle;
  final bool hecho;

  const PasoEstado({required this.titulo, required this.detalle, required this.hecho});
}

/// Línea de tiempo vertical de estados: los pasos hechos con check cian,
/// el siguiente pendiente resaltado en ámbar, y los que faltan en gris.
class LineaTiempoEstados extends StatelessWidget {
  final List<PasoEstado> pasos;

  const LineaTiempoEstados({super.key, required this.pasos});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final siguiente = pasos.indexWhere((p) => !p.hecho);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < pasos.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      _circulo(pasos[i].hecho, i == siguiente, colorScheme),
                      if (i < pasos.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: pasos[i].hecho ? BrandColors.cian : colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pasos[i].titulo,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: pasos[i].hecho || i == siguiente ? BrandColors.azulMarino : colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pasos[i].detalle,
                            style: TextStyle(
                              fontSize: 12,
                              color: i == siguiente ? ColoresEstado.pendiente : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _circulo(bool hecho, bool esSiguiente, ColorScheme colorScheme) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hecho ? BrandColors.cian : Colors.white,
        border: Border.all(
          color: hecho
              ? BrandColors.cian
              : esSiguiente
                  ? ColoresEstado.pendiente
                  : colorScheme.outlineVariant,
          width: 2,
        ),
      ),
      child: hecho ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    );
  }
}

/// Lo que se pidió o salió, agrupado por categoría (con el ícono de cada
/// una), con su cantidad — el cuerpo de los detalles de Almacén.
class ListaItemsPorCategoria extends StatelessWidget {
  final List<ChecklistCategoriaState> categorias;

  /// Si ya se entregó/devolvió: cada ítem se ve con su check cian.
  final bool completado;

  const ListaItemsPorCategoria({super.key, required this.categorias, this.completado = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final categoria in categorias)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 8),
                  child: Row(
                    children: [
                      _iconoCategoria(categoria.nombre),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          quitarNumeroCategoria(categoria.nombre),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13.5, color: BrandColors.azulMarino),
                        ),
                      ),
                      Text(
                        cantidadConPalabra(categoria.items.length, 'ítem', 'ítems'),
                        style: AppTextStyles.apoyo.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                for (final item in categoria.items)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          completado ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 18,
                          color: completado ? BrandColors.cian : colorScheme.outline,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(item.texto, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                        ),
                        if (item.esExtra) ...[
                          Icon(
                            item.esProducto ? Icons.inventory_2_outlined : Icons.edit_note_outlined,
                            size: 16,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          item.cantidadTexto,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BrandColors.cian),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
              ],
            ),
          ),
      ],
    );
  }

  Widget _iconoCategoria(String nombre) {
    final estilo = estiloDeCategoriaChecklist(nombre);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: estilo.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(estilo.icono, color: estilo.color, size: 18),
    );
  }
}

/// Etiqueta chica + valor en negrita (como en el detalle de cotización).
class ParDato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final bool alinearDerecha;

  const ParDato({super.key, required this.etiqueta, required this.valor, this.alinearDerecha = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alinearDerecha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: AppTextStyles.etiqueta),
        const SizedBox(height: 4),
        Text(
          valor.trim().isEmpty ? '-' : valor.trim(),
          textAlign: alinearDerecha ? TextAlign.right : TextAlign.left,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: BrandColors.azulMarino),
        ),
      ],
    );
  }
}

/// Título de sección en mayúsculas chicas (ej. "REQUERIMIENTOS PENDIENTES").
class TituloSeccion extends StatelessWidget {
  final String texto;
  final Widget? accion;

  const TituloSeccion(this.texto, {super.key, this.accion});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Row(
        children: [
          Expanded(child: Text(texto, style: AppTextStyles.etiqueta.copyWith(color: BrandColors.azulMarino))),
          if (accion != null) accion!,
        ],
      ),
    );
  }
}

/// Botón secundario de contorno (Ver PDF, Compartir, Cancelar).
final estiloBotonSecundario = OutlinedButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: 14),
  foregroundColor: BrandColors.azulMarino,
  side: const BorderSide(color: BrandColors.azulMarino),
  shape: const StadiumBorder(),
);

/// Acción principal a lo ancho, en forma de píldora (Aprobar, Confirmar...).
class BotonPrincipal extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Color color;
  final VoidCallback onPressed;

  const BotonPrincipal(
      {super.key, required this.texto, required this.icono, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icono, size: 20),
        label: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

/// Acción principal de una lista (Nuevo requerimiento, Registrar salida):
/// fija abajo de la pantalla, siempre a la vista aunque se desplace la
/// lista. Va en el bottomNavigationBar del Scaffold.
class BotonInferiorFijo extends StatelessWidget {
  final String texto;
  final IconData icono;
  final VoidCallback onPressed;

  const BotonInferiorFijo({super.key, required this.texto, required this.icono, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: BotonPrincipal(texto: texto, icono: icono, color: BrandColors.cian, onPressed: onPressed),
      ),
    );
  }
}

/// Hoja base de las confirmaciones de Almacén (misma forma que la de
/// "¿Qué quieres crear?" del historial): blanca, esquinas de arriba
/// redondeadas, y se sube con el teclado.
class HojaAlmacen extends StatelessWidget {
  final String titulo;
  final String texto;
  final List<Widget> children;

  const HojaAlmacen({super.key, required this.titulo, required this.texto, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titulo,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: BrandColors.azulMarino),
              ),
              const SizedBox(height: 6),
              Text(texto,
                  style: TextStyle(fontSize: 13, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration decoracionCampoHoja(String label, {IconData? icono}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: icono == null ? null : Icon(icono, size: 20),
    filled: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
