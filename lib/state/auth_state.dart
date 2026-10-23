import 'package:flutter/foundation.dart';
import '../services/api_cliente.dart';
import '../services/db_helper.dart';

/// Quién está usando la app (solo con servidor) y qué puede hacer.
class Usuario {
  final int id;
  final String usuario;
  final String nombre;
  final String rol;

  const Usuario({required this.id, required this.usuario, required this.nombre, required this.rol});

  factory Usuario.fromApi(Map<String, dynamic> m) => Usuario(
        id: (m['id'] as num).toInt(),
        usuario: (m['usuario'] ?? '').toString(),
        nombre: (m['nombre'] ?? '').toString(),
        rol: (m['rol'] ?? 'empleado').toString(),
      );

  String get rolEtiqueta => rolesUsuario[rol] ?? rol;
}

const rolesUsuario = {
  'admin': 'Administrador',
  'empleado': 'Empleado',
  'encargado': 'Encargado',
  'almacen': 'Almacén',
  'vendedor': 'Vendedor',
  'finanzas': 'Finanzas',
};

/// Sesión de la persona que usa la app. Sin servidor no hay usuarios: todo
/// está permitido, como siempre. Con servidor, el rol decide qué botones se
/// pueden usar (el servidor también lo comprueba): cualquiera envía un
/// requerimiento, el encargado lo aprueba, el almacenero lo alista y quien
/// lo pidió confirma que lo recibió.
class AuthState extends ChangeNotifier {
  Usuario? _usuario;
  bool _cargando = true;

  Usuario? get usuario => _usuario;
  bool get cargando => _cargando;

  bool get _servidor => DbHelper.instance.esServidor;

  /// Con servidor, hay que ingresar antes de usar la app.
  bool get requiereIngreso => _servidor && _usuario == null;

  bool _es(List<String> roles) => !_servidor || (_usuario != null && (_usuario!.rol == 'admin' || roles.contains(_usuario!.rol)));

  bool get puedeAprobar => _es(['encargado']);
  bool get puedeAlistar => _es(['almacen']);
  bool get puedeConfirmarSalida => _es(['almacen']);
  bool get puedeConfirmarDevolucion => _es(['almacen', 'encargado']);
  bool get puedeGestionarListas => _es(['encargado', 'almacen']);
  bool get puedeEditarProductos => _es(['encargado', 'vendedor']);
  bool get esAdmin => !_servidor || _usuario?.rol == 'admin';

  /// Recupera la sesión guardada (si sigue vigente).
  Future<void> iniciar() async {
    if (!_servidor) {
      _cargando = false;
      notifyListeners();
      return;
    }
    try {
      await ApiCliente.instancia.cargar();
      if (ApiCliente.instancia.tieneSesion) {
        _usuario = Usuario.fromApi(Map<String, dynamic>.from(await ApiCliente.instancia.get('yo') as Map));
      }
    } on ApiError {
      _usuario = null;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<void> entrar(String usuario, String clave) async {
    final datos = await ApiCliente.instancia.post('login', {'usuario': usuario.trim(), 'clave': clave}) as Map;
    await ApiCliente.instancia.guardarToken(datos['token'] as String);
    _usuario = Usuario.fromApi(Map<String, dynamic>.from(datos['usuario'] as Map));
    notifyListeners();
  }

  Future<void> salir() async {
    try {
      await ApiCliente.instancia.post('logout');
    } catch (_) {
      // Aunque el servidor no responda, en este dispositivo la sesión se cierra.
    }
    await olvidarSesion();
  }

  /// La sesión venció o se cerró: se vuelve a pedir el ingreso.
  Future<void> olvidarSesion() async {
    await ApiCliente.instancia.guardarToken(null);
    _usuario = null;
    notifyListeners();
  }

  Future<void> cambiarMiClave(String actual, String nueva) async {
    await ApiCliente.instancia.post('yo/clave', {'actual': actual, 'nueva': nueva});
  }
}
