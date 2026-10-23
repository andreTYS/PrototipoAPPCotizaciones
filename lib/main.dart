import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'services/api_cliente.dart';
import 'services/db_helper.dart';
import 'services/notificaciones_service.dart';
import 'state/almacen_state.dart';
import 'state/auth_state.dart';
import 'state/checklist_state.dart';
import 'state/cotizacion_state.dart';
import 'state/navegacion_state.dart';
import 'screens/main_tabs_screen.dart';
import 'theme/brand_colors.dart';
import 'utils/avisos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cuando el servidor rechaza un cambio ("otra persona modificó esto...",
  // "tu rol no permite..."), se le muestra el motivo a la persona.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is ApiError && !error.sesionVencida) avisar(error.mensaje);
    return error is ApiError;
  };
  await NotificacionesService.inicializar();
  runApp(const CotizadorApp());
}

/// Para volver a la pantalla de ingreso desde cualquier parte (la sesión venció).
final navegadorKey = GlobalKey<NavigatorState>();

class CotizadorApp extends StatelessWidget {
  const CotizadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: BrandColors.cian,
      primary: BrandColors.cian,
      onPrimary: Colors.white,
      secondary: BrandColors.menta,
      onSecondary: BrandColors.azulMarino,
      tertiary: BrandColors.azulOscuro,
      onTertiary: Colors.white,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CotizacionState()),
        Provider(create: (_) => BorradoresChecklist()),
        ChangeNotifierProvider(create: (_) => AlmacenState()),
        ChangeNotifierProvider(create: (_) => NavegacionState()),
        ChangeNotifierProvider(create: (_) => AuthState()),
      ],
      child: MaterialApp(
        title: 'ICR Energy',
        navigatorKey: navegadorKey,
        scaffoldMessengerKey: mensajeroKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Manrope',
          colorScheme: colorScheme,
          appBarTheme: const AppBarTheme(
            backgroundColor: BrandColors.azulMarino,
            foregroundColor: Colors.white,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: BrandColors.cian,
            foregroundColor: Colors.white,
          ),
          navigationBarTheme: NavigationBarThemeData(
            indicatorColor: BrandColors.cian,
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? const IconThemeData(color: Colors.white) : null,
            ),
          ),
        ),
        home: const _Splash(),
      ),
    );
  }
}

class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // Primer arranque: si el celular no tiene datos guardados aún, los toma
  // del catálogo que viene empaquetado dentro de la propia app
  // (assets/productos_seed.json) — así funciona sin red desde el día 1.
  // También se ejecuta en arranques posteriores, por si el catálogo
  // empaquetado se actualizó desde la última vez que se abrió la app.
  // Además deja cargado Almacén, para que el Inicio ya muestre lo pendiente.
  Future<void> _cargar() async {
    try {
      final auth = context.read<AuthState>();
      await auth.iniciar();
      if (!mounted) return;
      // Con servidor, si la sesión venció se vuelve a la pantalla de ingreso.
      ApiCliente.instancia.alVencerSesion = () {
        auth.olvidarSesion();
        context.read<AlmacenState>().detenerActualizacionAutomatica();
        navegadorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginScreen(alEntrar: _entrarALaApp)),
          (_) => false,
        );
      };
      if (auth.requiereIngreso) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginScreen(alEntrar: _entrarALaApp)));
        return;
      }
      await _abrirApp();
    } catch (error) {
      // Sin esto, un catálogo semilla corrupto deja la app en este
      // spinner para siempre, sin ninguna pista de qué falló.
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  /// Después de ingresar: se carga todo y se abre la app.
  void _entrarALaApp() {
    navegadorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const _Splash()),
      (_) => false,
    );
  }

  Future<void> _abrirApp() async {
    await DbHelper.instance.actualizarCatalogoBase();
    if (!mounted) return;
    final almacen = context.read<AlmacenState>();
    await almacen.cargar();
    almacen.iniciarActualizacionAutomatica();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainTabsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudo cargar la app.\n\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: BrandColors.cian),
            SizedBox(height: 16),
            Text('Cargando catálogo...', style: TextStyle(color: BrandColors.azulMarino)),
          ],
        ),
      ),
    );
  }
}
