import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_categoria.dart';
import '../models/checklist_herramientas.dart';
import '../models/requerimiento.dart';
import '../theme/app_text_styles.dart';
import '../theme/brand_colors.dart';
import '../utils/checklist_estilo.dart';
import '../utils/formato.dart';
import 'animated_pressable.dart';
import 'imagen_ruta.dart';

/// Colores de estado de Almacén — aparte de los de marca, porque tienen que
/// leerse de un vistazo: ámbar = falta algo, azul = aprobado / registrado,
/// violeta = listo para entrega, verde = terminado, rojo = urgente.
class ColoresEstado {
  ColoresEstado._();

  static const pendiente = Color(0xFFB45309);
  static const pendienteFondo = Color(0xFFFEF3C7);
  static const aprobado = BrandColors.azulOscuro;
  static const aprobadoFondo = Color(0xFFDBEAFE);
  static const preparado = Color(0xFF6D28D9);
  static const preparadoFondo = Color(0xFFEDE9FE);
  static const listo = Color(0xFF047857);
  static const listoFondo = Color(0xFFD1FAE5);
  static const urgente = Color(0xFFB91C1C);
  static const urgenteFondo = Color(0xFFFEE2E2);

  static (Color, Color) deRequerimiento(EstadoRequerimiento estado) => switch (estado) {
        EstadoRequerimiento.pendiente => (pendiente, pendienteFondo),
        EstadoRequerimiento.aprobado => (aprobado, aprobadoFondo),
        EstadoRequerimiento.listo => (preparado, preparadoFondo),
        EstadoRequerimiento.entregado => (listo, listoFondo),
      };

  static (Color, Color) deHerramientas(EstadoHerramientas estado) => switch (estado) {
        EstadoHerramientas.registrado => (aprobado, aprobadoFondo),
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

  /// Recordatorio para el almacenero mientras un requerimiento aprobado no
  /// se ha alistado.
  factory PildoraEstado.porAlistar([String texto = 'Pendiente de alistar']) => PildoraEstado(
        texto: texto,
        color: ColoresEstado.pendiente,
        fondo: ColoresEstado.pendienteFondo,
        icono: Icons.inventory_2_outlined,
      );

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
          '${r.numero} · ${cantidadConPalabra(r.totalItems, 'ítem', 'ítems')}${r.conPrecios ? ' · ${soles(r.totalPrecio)}' : ''} · ${fechaCorta(r.fechaCreacion)} · ${r.solicitante}',
      pildoras: [
        PildoraEstado.requerimiento(r.estado),
        if (r.pendienteDeAlistar)
          PildoraEstado.porAlistar(
            r.totalAlistados == 0 ? 'Pendiente de alistar' : 'Alistando ${r.totalAlistados}/${r.totalItems}',
          ),
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
          '${h.numero}${h.maleta == null ? '' : ' · ${h.maleta}'} · ${cantidadConPalabra(h.totalItems, 'herramienta', 'herramientas')} · ${fechaCorta(h.fechaSalida)} · ${h.responsable}',
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

  /// Salidas de herramientas: cada ítem muestra su recorrido (no salió,
  /// en obra, devuelta, no volvió) según lo que se marcó al confirmar.
  final bool recorridoHerramientas;

  /// Requerimientos aprobados: cada material muestra si ya se alistó, quién
  /// lo hizo y cuándo.
  final bool mostrarAlistado;

  const ListaItemsPorCategoria({
    super.key,
    required this.categorias,
    this.completado = false,
    this.recorridoHerramientas = false,
    this.mostrarAlistado = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Las salidas por maleta traen foto de cada herramienta; los
    // requerimientos, el precio de cada material.
    final conFotos = categorias.any((c) => c.items.any((i) => i.imagen != null));
    final conPrecios = categoriasConPrecios(categorias);
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
                        if (conFotos) ...[
                          FotoHerramienta(ruta: item.imagen, titulo: item.texto, tamano: 40),
                          const SizedBox(width: 10),
                        ],
                        if (recorridoHerramientas)
                          _IconoRecorrido(item: item)
                        else
                          Icon(
                            completado || (mostrarAlistado && item.alistado == true)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: completado || (mostrarAlistado && item.alistado == true)
                                ? (mostrarAlistado && !completado ? ColoresEstado.preparado : BrandColors.cian)
                                : colorScheme.outline,
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.texto, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                              if (mostrarAlistado && item.alistado == true)
                                Text(
                                  'Alistado${(item.alistadoPor ?? '').isEmpty ? '' : ' por ${item.alistadoPor}'}'
                                  '${item.fechaAlistado == null ? '' : ' · ${fechaCortaConHora(item.fechaAlistado!)}'}',
                                  style: AppTextStyles.apoyo,
                                ),
                              if (item.agregadoDespues)
                                const Text('Agregado después', style: AppTextStyles.apoyo),
                              if (conPrecios)
                                Text(
                                  item.precio == null
                                      ? 'Sin precio'
                                      : '${soles(item.precio!)} c/u · ${soles(item.subtotal)}',
                                  style: AppTextStyles.apoyo,
                                ),
                            ],
                          ),
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

/// En lugar de un botón, cuando el rol de la persona no permite esa acción
/// (por ejemplo, aprobar es del encargado): le dice quién la hace.
class AvisoRol extends StatelessWidget {
  final String texto;

  const AvisoRol(this.texto, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// La foto es un asset de la app (las que vienen con ella) o un archivo del
/// celular (las que se toman desde Configuración).
Widget _imagenHerramienta(
  String ruta, {
  double? height,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return imagenDeRuta(ruta, fit: BoxFit.contain, height: height, errorBuilder: errorBuilder);
}

/// Dónde va una herramienta de una salida, según lo marcado al confirmar
/// la salida y la devolución.
class _IconoRecorrido extends StatelessWidget {
  final ChecklistItemEntry item;

  const _IconoRecorrido({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icono, color, texto) = switch ((item.salio, item.volvio)) {
      (false, _) => (Icons.cancel_outlined, ColoresEstado.urgente, 'No salió'),
      (true, true) => (Icons.check_circle, ColoresEstado.listo, 'Devuelta'),
      (true, false) => (Icons.error_outline, ColoresEstado.urgente, 'No volvió'),
      (true, null) => (Icons.outbox_outlined, ColoresEstado.pendiente, 'En obra'),
      _ => (Icons.radio_button_unchecked, Theme.of(context).colorScheme.outline, 'Por salir'),
    };
    return Tooltip(
      message: texto,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 20, color: color),
          Text(texto, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Foto de una herramienta (las de las maletas vienen en los assets). Sin
/// foto muestra un ícono; con foto, tocarla la abre en grande.
class FotoHerramienta extends StatelessWidget {
  final String? ruta;
  final double tamano;
  final String titulo;

  const FotoHerramienta({super.key, required this.ruta, required this.titulo, this.tamano = 48});

  void _ampliar(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _imagenHerramienta(ruta!, height: 280),
              ),
              const SizedBox(height: 12),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: BrandColors.azulMarino),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sinFoto = Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.handyman_outlined, size: tamano * 0.45, color: colorScheme.outline),
    );
    if (ruta == null) return sinFoto;
    return GestureDetector(
      onTap: () => _ampliar(context),
      child: Container(
        width: tamano,
        height: tamano,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: _imagenHerramienta(ruta!, errorBuilder: (_, __, ___) => sinFoto),
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

/// Confirmación de un paso de Almacén que solo pide el nombre de quien lo
/// hace (Listo para entrega, Confirmar salida). Recuerda el último nombre
/// escrito en [clavePreferencia] para no tipearlo cada vez. El nombre es
/// obligatorio. Devuelve el nombre, o null si se canceló.
class HojaConfirmacionNombre extends StatefulWidget {
  final String titulo;
  final String texto;
  final String etiquetaNombre;
  final String textoBoton;
  final Color color;
  final String clavePreferencia;

  const HojaConfirmacionNombre({
    super.key,
    required this.titulo,
    required this.texto,
    required this.etiquetaNombre,
    required this.textoBoton,
    required this.color,
    required this.clavePreferencia,
  });

  @override
  State<HojaConfirmacionNombre> createState() => _HojaConfirmacionNombreState();
}

class _HojaConfirmacionNombreState extends State<HojaConfirmacionNombre> {
  final _nombreController = TextEditingController();
  bool _faltaNombre = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted && _nombreController.text.isEmpty) {
        _nombreController.text = prefs.getString(widget.clavePreferencia) ?? '';
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _faltaNombre = true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(widget.clavePreferencia, nombre);
    if (mounted) Navigator.of(context).pop(nombre);
  }

  @override
  Widget build(BuildContext context) {
    return HojaAlmacen(
      titulo: widget.titulo,
      texto: widget.texto,
      children: [
        TextField(
          controller: _nombreController,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) {
            if (_faltaNombre) setState(() => _faltaNombre = false);
          },
          decoration: decoracionCampoHoja('${widget.etiquetaNombre} *', icono: Icons.person_outline)
              .copyWith(errorText: _faltaNombre ? 'El nombre es obligatorio' : null),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: estiloBotonSecundario,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _confirmar,
                style: FilledButton.styleFrom(
                  backgroundColor: widget.color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(widget.textoBoton, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
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
