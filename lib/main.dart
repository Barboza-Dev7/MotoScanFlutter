import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'config_service.dart';
import 'scan_result_screen.dart';
import 'settings_screen.dart';
import 'udp_sender.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cargamos la configuración guardada (sede, IP, puerto) ANTES de
  // levantar la app, así ya está disponible en ConfigService.instance
  // desde el primer frame, sin tener que volver a seleccionarla.
  await ConfigService.instance.cargarConfiguracion();

  runApp(const MiApp());
}

class MiApp extends StatelessWidget {
  const MiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // mobile_scanner analiza el stream de video EN VIVO (no toma fotos),
  // por eso detecta los códigos mucho más rápido y de forma más
  // confiable que el enfoque anterior de "tomar foto y luego procesarla".
  late final MobileScannerController controller;

  late AnimationController animationController;
  late Animation<double> animation;

  // true mientras ya se detectó un código y se está procesando (enviar
  // por UDP + navegar a la pantalla de resultado). Mientras es true,
  // ignoramos nuevas detecciones para no procesar el mismo código dos
  // veces ni disparar dos navegaciones a la vez.
  bool _procesando = false;

  // Zoom "manual" que se activa al presionar el botón de captura: útil
  // cuando el código está lejos o cuesta enfocarlo. Sube un poco cada
  // vez que se presiona y se mantiene así (no se resetea solo); solo
  // vuelve a 0 cuando se regresa a esta pantalla tras ver el resultado
  // de un escaneo exitoso.
  double _zoomManual = 0.0;
  static const double _zoomPaso = 0.18;
  static const double _zoomMax = 0.65;

  // Cámara actualmente en uso (trasera por defecto). Se actualiza al
  // presionar el botón de voltear cámara.
  CameraFacing _camaraActual = CameraFacing.back;

  // Configuración del recuadro de escaneo
  static const double boxSize = 300;
  static const double boxTop = 140;
  static const double boxRadius = 28;
  static const double lineHeight = 3;
  static const double linePadding = 12; // margen lateral de la línea
  static const double lineVerticalPadding = 16; // espacio arriba/abajo

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    controller = MobileScannerController(
      // Resolución alta -> ayuda a detectar códigos pequeños o algo
      // alejados, sin sacrificar demasiada velocidad de procesamiento.
      cameraResolution: const Size(1920, 1080),
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      // Zoom automático NATIVO: si la cámara tarda en detectar un
      // código (por estar lejos o pequeño), ella misma va acercando el
      // zoom hasta lograr leerlo. Esto es, literalmente, "el pequeño
      // zoom si después de un intento no escanea". (Solo Android.)
      autoZoom: true,
    );

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // La línea recorre todo el alto del recuadro (0 -> boxSize - lineHeight)
    animation = Tween<double>(
      begin: lineVerticalPadding,
      end: boxSize - lineHeight - lineVerticalPadding,
    ).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeInOut,
      ),
    );

    animationController.repeat(reverse: true);
  }

  // Pausa la cámara cuando la app pasa a segundo plano y la reanuda al
  // volver, para no gastar batería/CPU detectando códigos sin sentido.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        unawaited(controller.start());
      case AppLifecycleState.inactive:
        unawaited(controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    animationController.dispose();
    unawaited(controller.dispose());
    super.dispose();
  }

  Future<void> _abrirConfiguracion() async {
    // Pausamos la cámara mientras el usuario está en Configuración: no
    // tiene sentido seguir detectando códigos en una pantalla que no se ve.
    await controller.stop();

    final resultado = await Navigator.of(context).push<ResultadoConfiguracion>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );

    if (resultado != null) {
      debugPrint(
        'Configuración actualizada -> sede: ${resultado.sede.nombre}, '
        'ip: ${resultado.ip}, puerto: ${resultado.puerto}',
      );
    }

    if (mounted) {
      await controller.start();
    }
  }

  /// Se dispara automáticamente cada vez que la cámara detecta un
  /// código en el video (escaneo automático y continuo).
  void _onDetect(BarcodeCapture capture) {
    if (_procesando) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final String codigoEscaneado = barcode.rawValue ?? '';
    if (codigoEscaneado.isEmpty) return;

    setState(() => _procesando = true);

    // Feedback inmediato de escaneo exitoso: vibración + sonido.
    _vibrarYSonarEscaneo();

    unawaited(_procesarYEnviar(codigoEscaneado, barcode));
  }

  /// Alterna entre la cámara trasera y la frontal. Mientras se está
  /// procesando un escaneo no permitimos el cambio, para no interferir
  /// con la navegación/envío en curso.
  Future<void> _voltearCamara() async {
    if (_procesando) return;

    HapticFeedback.selectionClick();

    await controller.switchCamera();

    setState(() {
      _camaraActual = _camaraActual == CameraFacing.back
          ? CameraFacing.front
          : CameraFacing.back;
    });
  }

  /// Se dispara al presionar el botón de captura. El escaneo ya es
  /// automático y continuo, así que este botón funciona como una
  /// "ayuda" manual: da un empujón de zoom (útil si el código está
  /// lejos o cuesta detectarlo) y lo mantiene aplicado hasta que se
  /// resetee (al volver de ver el resultado de un escaneo exitoso).
  Future<void> _intentarEscaneoManual() async {
    if (_procesando) return;

    HapticFeedback.selectionClick();

    _zoomManual = (_zoomManual + _zoomPaso).clamp(0.0, _zoomMax);
    await controller.setZoomScale(_zoomManual);
  }

  /// Pasos 2 a 5 del flujo (misma lógica de negocio de siempre).
  Future<void> _procesarYEnviar(
    String codigoEscaneado,
    Barcode barcode,
  ) async {
    try {
      // Paso 2: consultar la sede seleccionada previamente en Configuración.
      final Sede sedeSeleccionada = ConfigService.instance.sede;

      // Paso 3: procesar el dato según la sede. Cada bloque es
      // independiente para poder ajustar la transformación de cada
      // sede sin afectar a las demás.
      String datoEnviar = "";

      if (sedeSeleccionada == Sede.hero) {
        List<String> partes = codigoEscaneado.split('/');

        if (partes.length > 3) {
          datoEnviar = partes[3].trim();

          if (RegExp(r'^[0-9]').hasMatch(datoEnviar)) {
            String aux = '';
            bool primeraLetraEncontrada = false;
            bool segundoGuionPuesto = false;
            int letrasContadas = 0;

            for (int i = 0; i < datoEnviar.length; i++) {
              String c = datoEnviar[i];
              bool esLetra = RegExp(r'^[A-Za-z]$').hasMatch(c);

              // Primer guion: justo antes de la primera letra
              if (esLetra && !primeraLetraEncontrada) {
                aux += '-';
                primeraLetraEncontrada = true;
              }

              aux += c;

              // Contar letras después del primer guion, hasta la tercera
              if (primeraLetraEncontrada && !segundoGuionPuesto && esLetra) {
                letrasContadas++;
                if (letrasContadas == 3) {
                  aux += '-';
                  segundoGuionPuesto = true;
                }
              }
            }

            datoEnviar = aux;
          }
        } else {
          datoEnviar = codigoEscaneado;
        }
      }

      if (sedeSeleccionada == Sede.uma) {
        List<String> partes = codigoEscaneado.split('-');

        if (partes.length > 1) {
          datoEnviar = partes[0].trim();
        } else {
          datoEnviar = codigoEscaneado;
        }
      }

      if (sedeSeleccionada == Sede.auteco) {
        // TODO: aquí se modificará el dato para Auteco.
        datoEnviar = codigoEscaneado;
      }

      // Paso 4: enviar el dato final por UDP a la IP/puerto configurados.
      final puertoConfigurado = int.tryParse(ConfigService.instance.puerto);
      if (puertoConfigurado == null) {
        _mostrarMensaje('El puerto configurado no es válido.');
        return;
      }

      try {
        await UdpSender.enviar(
          mensaje: datoEnviar,
          ip: ConfigService.instance.ip,
          puerto: puertoConfigurado,
        );
      } catch (e) {
        _mostrarMensaje('No se pudo enviar el dato: $e');
        return;
      }

      if (!mounted) return;

      // Pausamos la cámara mientras se ve el resultado: ahorra batería
      // y evita seguir detectando códigos detrás de esa pantalla.
      await controller.stop();

      // Paso 5: navegar a la pantalla de resultado una vez enviado.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanResultScreen(
            codigo: datoEnviar,
            tipo: _nombreTipo(barcode.format),
            sede: sedeSeleccionada,
            fechaHora: DateTime.now(),
            escaneadoCon: _camaraActual == CameraFacing.front
                ? 'Cámara frontal'
                : 'Cámara trasera',
          ),
        ),
      );

      // "Salir" cierra la app desde dentro de ScanResultScreen, así que
      // si volvemos aquí es porque se eligió "Volver a escanear" (o se
      // usó el botón de atrás). En ambos casos, reanudamos la cámara y
      // quitamos el zoom manual: cada escaneo empieza "limpio".
      if (mounted) {
        await controller.start();
        _zoomManual = 0.0;
        await controller.resetZoomScale();
      }
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
      } else {
        _procesando = false;
      }
    }
  }

  /// Feedback háptico y sonoro al detectar un código válido.
  void _vibrarYSonarEscaneo() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  String _nombreTipo(BarcodeFormat format) {
    switch (format) {
      case BarcodeFormat.qrCode:
        return 'QR';
      case BarcodeFormat.code128:
        return 'CODE 128';
      case BarcodeFormat.code39:
        return 'CODE 39';
      case BarcodeFormat.code93:
        return 'CODE 93';
      case BarcodeFormat.ean8:
        return 'EAN-8';
      case BarcodeFormat.ean13:
        return 'EAN-13';
      case BarcodeFormat.upcA:
        return 'UPC-A';
      case BarcodeFormat.upcE:
        return 'UPC-E';
      case BarcodeFormat.pdf417:
        return 'PDF417';
      case BarcodeFormat.aztec:
        return 'AZTEC';
      case BarcodeFormat.dataMatrix:
        return 'DATA MATRIX';
      case BarcodeFormat.itf:
        return 'ITF';
      case BarcodeFormat.codabar:
        return 'CODABAR';
      default:
        return 'DESCONOCIDO';
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B1B1D),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenWidth = constraints.maxWidth;
          final double boxLeft = (screenWidth - boxSize) / 2;

          final Rect scanRect = Rect.fromLTWH(
            boxLeft,
            boxTop,
            boxSize,
            boxSize,
          );

          return Stack(
            children: [
              // CÁMARA A PANTALLA COMPLETA — CERO BORDES NEGROS.
              // MobileScanner ya se encarga de rellenar la pantalla y de
              // analizar cada frame para detectar códigos en vivo.
              Positioned.fill(
                child: MobileScanner(
                  controller: controller,
                  fit: BoxFit.cover,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) {
                    return Container(
                      color: const Color(0xFF1B1B1D),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No se pudo acceder a la cámara.\n'
                        'Revisa los permisos de la app en Ajustes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // MÁSCARA GRIS TRANSPARENTE CON HUECO EN EL RECUADRO
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: MaskPainter(
                      scanRect: scanRect,
                      radius: boxRadius,
                    ),
                  ),
                ),
              ),

              // BOTÓN DE VOLTEAR CÁMARA (frontal / trasera)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, left: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _voltearCamara,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Icon(
                            Icons.cameraswitch_rounded,
                            color: Colors.white.withValues(alpha: 0.85),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // BOTÓN DE CONFIGURACIÓN (solo ícono, sin fondo circular)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _abrirConfiguracion,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Icon(
                            Icons.settings_rounded,
                            color: Colors.white.withValues(alpha: 0.85),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // RECUADRO DE ESCANEO (borde + línea)
              Positioned(
                left: boxLeft,
                top: boxTop,
                child: SizedBox(
                  width: boxSize,
                  height: boxSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Borde sutil redondeado
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(boxRadius),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                      ),

                      // Línea de escaneo animada (sube y baja completo)
                      AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          return Positioned(
                            top: animation.value,
                            left: linePadding,
                            right: linePadding,
                            child: Container(
                              height: lineHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: .85),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // TEXTO GUÍA DEBAJO DEL RECUADRO
              Positioned(
                top: boxTop + boxSize + 22,
                left: 24,
                right: 24,
                child: Center(
                  child: Text(
                    "Coloca el documento dentro del recuadro",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // BOTÓN DE CAPTURA (ahora es un "ayudante" de zoom manual;
              // el escaneo real ya ocurre solo, de forma automática)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: GestureDetector(
                    onTap: _intentarEscaneoManual,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: _procesando
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.6,
                                ),
                              )
                            : Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pinta una máscara gris semitransparente sobre toda la pantalla,
/// dejando un hueco (recuadro redondeado) donde se ve la cámara nítida.
class MaskPainter extends CustomPainter {
  final Rect scanRect;
  final double radius;

  MaskPainter({required this.scanRect, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = Colors.black.withValues(alpha: 0.5);

    final Path outer = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final Path hole = Path()
      ..addRRect(RRect.fromRectAndRadius(scanRect, Radius.circular(radius)));

    final Path result = Path.combine(PathOperation.difference, outer, hole);

    canvas.drawPath(result, paint);
  }

  @override
  bool shouldRepaint(covariant MaskPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect || oldDelegate.radius != radius;
  }
}