import 'package:shared_preferences/shared_preferences.dart';

/// Sedes disponibles para el envío de información.
enum Sede { hero, uma, auteco }

extension SedeExtension on Sede {
  String get nombre {
    switch (this) {
      case Sede.hero:
        return 'Hero';
      case Sede.uma:
        return 'Uma';
      case Sede.auteco:
        return 'Auteco';
    }
  }
}

/// Guarda y expone la configuración de la app (sede seleccionada, IP y
/// puerto del servidor). Usa SharedPreferences para persistir los datos
/// en el dispositivo, así el usuario no tiene que volver a configurarlos
/// cada vez que abre la app.
class ConfigService {
  ConfigService._privateConstructor();
  static final ConfigService instance = ConfigService._privateConstructor();

  static const _keySede = 'config_sede';
  static const _keyIp = 'config_ip';
  static const _keyPuerto = 'config_puerto';

  // Valores por defecto (se sobreescriben al cargar si hay algo guardado).
  Sede sede = Sede.hero;
  String ip = '192.168.1.100';
  String puerto = '8080';

  bool _cargado = false;
  bool get estaCargado => _cargado;

  /// Carga la configuración guardada. Llamar una vez al iniciar la app
  /// (antes de runApp) para que la UI ya tenga los valores correctos.
  Future<void> cargarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();

    final sedeGuardada = prefs.getString(_keySede);
    if (sedeGuardada != null) {
      sede = Sede.values.firstWhere(
        (s) => s.name == sedeGuardada,
        orElse: () => Sede.hero,
      );
    }

    ip = prefs.getString(_keyIp) ?? ip;
    puerto = prefs.getString(_keyPuerto) ?? puerto;
    _cargado = true;
  }

  /// Guarda una nueva configuración tanto en memoria (para uso inmediato)
  /// como en disco (para que persista entre aperturas de la app).
  Future<void> guardarConfiguracion({
    required Sede sede,
    required String ip,
    required String puerto,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySede, sede.name);
    await prefs.setString(_keyIp, ip);
    await prefs.setString(_keyPuerto, puerto);

    this.sede = sede;
    this.ip = ip;
    this.puerto = puerto;
  }
}