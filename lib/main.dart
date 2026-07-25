import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'config_service.dart';
import 'scan_result_screen.dart';
import 'settings_screen.dart';
import 'udp_sender.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  cameras = await availableCameras();

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
    with SingleTickerProviderStateMixin {
  late CameraController controller;
  late Future<void> initializeControllerFuture;

  late AnimationController animationController;
  late Animation<double> animation;

  // Escáner de ML Kit: detecta tanto QR como códigos de barras (VIN, etc.)
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  bool _escaneando = false;

  // Configuración del recuadro de escaneo
  static const double boxSize = 300;
  static const double boxTop = 140;
  static const double boxRadius = 28;
  static const double lineHeight = 3;
  static const double linePadding = 12; // margen lateral de la línea
  static const double lineVerticalPadding = 16; // espacio que deja arriba/abajo

  @override
  void initState() {
    super.initState();

    controller = CameraController(
      cameras.first,
      ResolutionPreset.max,
    );

    initializeControllerFuture = controller.initialize();

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Ahora la línea recorre TODO el alto del recuadro (0 -> boxSize - lineHeight)
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

  @override
  void dispose() {
    animationController.dispose();
    controller.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _abrirConfiguracion() async {
    final resultado = await Navigator.of(context).push<ResultadoConfiguracion>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );

    if (resultado == null) return;

    debugPrint(
      'Configuración actualizada -> sede: ${resultado.sede.nombre}, '
      'ip: ${resultado.ip}, puerto: ${resultado.puerto}',
    );
  }

  /// Se dispara al presionar el botón de captura.
  /// Toma una foto, la pasa por ML Kit y, si detecta un código,
  /// arranca el flujo descrito (pasos 1 a 5).
  Future<void> _capturarYEscanear() async {
    if (_escaneando) return;
    setState(() => _escaneando = true);

    try {
      final XFile foto = await controller.takePicture();
      final inputImage = InputImage.fromFilePath(foto.path);
      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isEmpty) {
        _mostrarMensaje('No se detectó ningún código. Intenta de nuevo.');
        return;
      }

      final barcode = barcodes.first;

      // Paso 1: obtener el valor escaneado.
      final String codigoEscaneado = barcode.rawValue ?? '';
      if (codigoEscaneado.isEmpty) {
        _mostrarMensaje('El código detectado no tiene datos legibles.');
        return;
      }

      // Feedback inmediato de escaneo exitoso: vibración + sonido.
      _vibrarYSonarEscaneo();

      await _procesarYEnviar(codigoEscaneado, barcode);
    } catch (e) {
      _mostrarMensaje('Error al escanear: $e');
    } finally {
      if (mounted) setState(() => _escaneando = false);
    }
  }

  /// Pasos 2 a 5 del flujo.
  Future<void> _procesarYEnviar(
    String codigoEscaneado,
    Barcode barcode,
  ) async {
    // Paso 2: consultar la sede seleccionada previamente en Configuración.
    final Sede sedeSeleccionada = ConfigService.instance.sede;

    // Paso 3: procesar el dato según la sede. Cada bloque es independiente
    // para que más adelante puedas agregar la transformación específica
    // de cada sede sin afectar a las demás.
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

    // Paso 5: navegar a la pantalla de resultado una vez enviado.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanResultScreen(
          codigo: datoEnviar,
          tipo: _nombreTipo(barcode.format),
          sede: sedeSeleccionada,
          fechaHora: DateTime.now(),
          escaneadoCon: cameras.first.lensDirection == CameraLensDirection.back
              ? 'Cámara trasera'
              : 'Cámara frontal',
        ),
      ),
    );

    // Al volver de la pantalla de resultado (ya sea "Volver a escanear"
    // o "Salir"), simplemente quedamos listos para un nuevo escaneo.
  }

  /// Feedback háptico y sonoro al detectar un código válido.
  /// Usa APIs nativas de Flutter (sin dependencias extra):
  /// - HapticFeedback.mediumImpact(): vibración corta y perceptible.
  /// - SystemSound.play(SystemSoundType.click): sonido corto del
  ///   sistema (el mismo "click" que usan apps nativas de escaneo).
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
      case BarcodeFormat.upca:
        return 'UPC-A';
      case BarcodeFormat.upce:
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
      body: FutureBuilder(
        future: initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          return LayoutBuilder(
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
                  // CÁMARA A PANTALLA COMPLETA — CERO BORDES NEGROS
                  Positioned.fill(
                    child: _CameraFill(controller: controller),
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

                  // RECUADRO DE ESCANEO (borde + línea + esquinas)
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

                          // Línea de escaneo animada (ahora sube y baja completo)
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

                  // BOTÓN DE CAPTURA
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: GestureDetector(
                        onTap: _capturarYEscanear,
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
                            child: _escaneando
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
          );
        },
      ),
    );
  }
}

/// Cubre el 100% de la pantalla con la cámara, sin bordes negros.
/// Usa el aspect ratio corregido para retrato (1 / aspectRatio, ya que
/// el plugin lo reporta en la orientación nativa del sensor) y aplica
/// la escala UNIFORME mínima necesaria (mismo factor en X e Y, por eso
/// no hay distorsión) para tapar cualquier hueco restante.
class _CameraFill extends StatelessWidget {
  final CameraController controller;

  const _CameraFill({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        final double previewAspectRatio = 1 / controller.value.aspectRatio;
        final double screenAspectRatio = screenSize.width / screenSize.height;

        double scale = previewAspectRatio / screenAspectRatio;
        if (scale < 1) scale = 1 / scale;

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: AspectRatio(
                aspectRatio: previewAspectRatio,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
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