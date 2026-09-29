import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'services/db_helper.dart';
import 'state/cotizacion_state.dart';
import 'screens/main_tabs_screen.dart';
import 'theme/brand_colors.dart';

void main() {
  // sqflite no tiene implementación nativa en navegador — en la build web
  // (PWA) se guarda igual en el propio navegador (IndexedDB vía sqlite3
  // compilado a WebAssembly), así que el catálogo sincronizado y el
  // historial de cotizaciones siguen persistiendo entre sesiones ahí
  // también, sin tocar ninguna pantalla ni el resto de DbHelper.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  runApp(const CotizadorApp());
}

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

    return ChangeNotifierProvider(
      create: (_) => CotizacionState(),
      child: MaterialApp(
        title: 'Cotizador ICR',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: colorScheme,
          // Roboto empaquetada localmente (ver pubspec.yaml) en vez de la
          // que Flutter Material pide por defecto a fonts.gstatic.com — la
          // build web/PWA no debe depender de esa red para poder leer texto.
          fontFamily: 'Roboto',
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
              (states) => states.contains(WidgetState.selected)
                  ? const IconThemeData(color: Colors.white)
                  : null,
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Primer arranque: si el celular no tiene datos guardados aún, los
    // toma del catálogo que viene empaquetado dentro de la propia app
    // (assets/productos_seed.json) — así funciona sin red desde el día 1.
    try {
      await DbHelper.instance.seedFromAssetsIfEmpty();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainTabsScreen()),
      );
    } catch (e) {
      // Sin este catch, un catálogo semilla corrupto deja la app girando
      // en este spinner para siempre, sin ninguna pista de qué falló.
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el catálogo inicial.\n\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
