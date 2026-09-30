import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/requerimiento.dart';
import '../theme/brand_colors.dart';

/// Notificaciones del propio celular (sin servidor): hoy solo el aviso de
/// que hay un requerimiento esperando la aprobación del jefe de obra. Si
/// algo de esto falla (permiso negado, plugin no disponible), la app sigue
/// funcionando igual — el requerimiento ya quedó guardado y se ve en Inicio.
class NotificacionesService {
  NotificacionesService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _listo = false;

  /// Requerimiento que se debe abrir porque se tocó su notificación (con la
  /// app abierta o recién lanzada por ella). MainTabsScreen lo escucha y lo
  /// vuelve a null después de abrirlo.
  static final ValueNotifier<int?> requerimientoTocado = ValueNotifier(null);

  static const _prefijoPayload = 'requerimiento:';

  static const _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      'requerimientos_pendientes',
      'Requerimientos pendientes',
      channelDescription: 'Aviso cuando un requerimiento espera la aprobación del jefe de obra',
      importance: Importance.high,
      priority: Priority.high,
      color: BrandColors.cian,
    ),
  );

  static Future<void> inicializar() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notificacion'),
        ),
        onDidReceiveNotificationResponse: (respuesta) => _alTocar(respuesta.payload),
      );
      _listo = true;

      final lanzamiento = await _plugin.getNotificationAppLaunchDetails();
      if (lanzamiento?.didNotificationLaunchApp ?? false) {
        _alTocar(lanzamiento!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
  }

  static void _alTocar(String? payload) {
    if (payload == null || !payload.startsWith(_prefijoPayload)) return;
    final id = int.tryParse(payload.substring(_prefijoPayload.length));
    if (id != null) requerimientoTocado.value = id;
  }

  static Future<void> avisarRequerimientoPendiente(Requerimiento r) async {
    if (!_listo || r.id == null) return;
    try {
      // Android 13+ pide permiso para notificar; se pregunta recién acá, la
      // primera vez que hay algo que avisar, en vez de al abrir la app.
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      final items = r.totalItems == 1 ? '1 ítem' : '${r.totalItems} ítems';
      await _plugin.show(
        id: r.id!,
        title: r.urgente ? 'Requerimiento URGENTE por aprobar' : 'Requerimiento pendiente de aprobación',
        body: '${r.numero} · ${r.obra} · $items. Toca para revisarlo.',
        notificationDetails: _detalles,
        payload: '$_prefijoPayload${r.id}',
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación: $e');
    }
  }

  /// Una vez aprobado, el aviso de "pendiente" ya no aplica.
  static Future<void> quitarAviso(Requerimiento r) async {
    if (!_listo || r.id == null) return;
    try {
      await _plugin.cancel(id: r.id!);
    } catch (_) {
      // Si ya no estaba, no pasa nada.
    }
  }
}
