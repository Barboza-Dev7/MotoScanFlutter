import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Sede _sedeSeleccionada;
  late final TextEditingController _ipController;
  late final TextEditingController _puertoController;

  final _formKey = GlobalKey<FormState>();
  bool _guardando = false;

  static const Color _bg = Color(0xFF1B1B1D);
  static const Color _card = Color(0xFF232326);
  static const Color _border = Color(0xFF34343A);
  static const Color _accentRed = Color(0xFFE0303A);
  static const Color _accentTeal = Color(0xFF2FD1B0);

  @override
  void initState() {
    super.initState();
    // Precargamos con lo que ya haya guardado en el ConfigService
    // (que a su vez fue cargado desde SharedPreferences al iniciar la app).
    final config = ConfigService.instance;
    _sedeSeleccionada = config.sede;
    _ipController = TextEditingController(text: config.ip);
    _puertoController = TextEditingController(text: config.puerto);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _puertoController.dispose();
    super.dispose();
  }

  String? _validarIp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa la IP del servidor';
    }
    final regex = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    );
    final match = regex.firstMatch(value.trim());
    if (match == null) return 'Formato de IP inválido';
    for (int i = 1; i <= 4; i++) {
      final octeto = int.parse(match.group(i)!);
      if (octeto > 255) return 'Formato de IP inválido';
    }
    return null;
  }

  String? _validarPuerto(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa el puerto';
    }
    final puerto = int.tryParse(value.trim());
    if (puerto == null || puerto < 1 || puerto > 65535) {
      return 'Puerto inválido (1-65535)';
    }
    return null;
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    await ConfigService.instance.guardarConfiguracion(
      sede: _sedeSeleccionada,
      ip: _ipController.text.trim(),
      puerto: _puertoController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2FD1B0),
      ),
    );

    // Devolvemos la configuración al widget que abrió esta pantalla,
    // por si necesita reaccionar de inmediato (ej. reconectar el socket).
    Navigator.of(context).pop(
      ResultadoConfiguracion(
        sede: _sedeSeleccionada,
        ip: _ipController.text.trim(),
        puerto: _puertoController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildSedeCard(),
              const SizedBox(height: 20),
              _buildConexionCard(),
              const SizedBox(height: 28),
              _buildGuardarButton(),
              const SizedBox(height: 14),
              _buildFooterNota(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 14),
            const Text(
              'Configuración',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Ajusta las preferencias de envío y conexión',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String titulo,
    required String subtitulo,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildSedeCard() {
    return _buildSectionCard(
      icon: Icons.location_on_rounded,
      iconColor: _accentRed,
      titulo: 'SELECCIONE LA SEDE',
      subtitulo: 'Seleccione la sede a la que se enviará la información',
      child: Column(
        children: [
          _buildSedeOption(
            sede: Sede.hero,
            badgeColor: const Color(0xFFE0303A),
            badgeText: 'Hero',
          ),
          const SizedBox(height: 12),
          _buildSedeOption(
            sede: Sede.uma,
            badgeColor: const Color(0xFF2B5FE0),
            badgeText: 'UMA',
          ),
          const SizedBox(height: 12),
          _buildSedeOption(
            sede: Sede.auteco,
            badgeColor: Colors.black,
            badgeText: 'Auteco',
          ),
        ],
      ),
    );
  }

  Widget _buildSedeOption({
    required Sede sede,
    required Color badgeColor,
    required String badgeText,
  }) {
    final bool seleccionada = _sedeSeleccionada == sede;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _sedeSeleccionada = sede),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: seleccionada
              ? _accentRed.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: seleccionada ? _accentRed : _border,
            width: seleccionada ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badgeText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sede.nombre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Enviar a sede ${sede.nombre}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            _buildRadio(seleccionada),
          ],
        ),
      ),
    );
  }

  Widget _buildRadio(bool seleccionada) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: seleccionada ? _accentRed : Colors.white.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: seleccionada
          ? Center(
              child: Container(
                width: 11,
                height: 11,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accentRed,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildConexionCard() {
    return _buildSectionCard(
      icon: Icons.link_rounded,
      iconColor: _accentTeal,
      titulo: 'CONEXIÓN',
      subtitulo: 'Ingresa la IP y el puerto del servidor',
      child: Column(
        children: [
          _buildTextField(
            controller: _ipController,
            label: 'IP DEL SERVIDOR',
            hint: '192.168.1.100',
            icon: Icons.dns_rounded,
            keyboardType: TextInputType.number,
            validator: _validarIp,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _puertoController,
            label: 'PUERTO',
            hint: '8080',
            icon: Icons.settings_ethernet_rounded,
            keyboardType: TextInputType.number,
            validator: _validarPuerto,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
    required String? Function(String?) validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _accentTeal,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                TextFormField(
                  controller: controller,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  validator: validator,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    errorStyle: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: _accentTeal, size: 20),
        ],
      ),
    );
  }

  Widget _buildGuardarButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _guardando ? null : _guardar,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF3B9CFF), Color(0xFF7B4CFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        alignment: Alignment.center,
        child: _guardando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.4,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Guardar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFooterNota() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user_outlined,
            color: Colors.white.withValues(alpha: 0.4), size: 15),
        const SizedBox(width: 6),
        Text(
          'La configuración se guardará de forma segura',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

/// Lo que devuelve la pantalla al hacer pop, por si quien la abrió
/// necesita reaccionar inmediatamente (ej. reconectar un socket).
class ResultadoConfiguracion {
  final Sede sede;
  final String ip;
  final String puerto;

  ResultadoConfiguracion({
    required this.sede,
    required this.ip,
    required this.puerto,
  });
}