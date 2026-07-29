import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'config_service.dart';

/// Lo que el usuario eligió hacer al salir de la pantalla de resultado.
enum ScanResultAction { reescanear, salir }

class ScanResultScreen extends StatefulWidget {
  final String codigo;
  final String tipo;
  final Sede sede;
  final DateTime fechaHora;
  final String escaneadoCon;

  const ScanResultScreen({
    super.key,
    required this.codigo,
    required this.tipo,
    required this.sede,
    required this.fechaHora,
    required this.escaneadoCon,
  });

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  static const Color _bg = Color(0xFF1B1B1D);
  static const Color _card = Color(0xFF232326);
  static const Color _border = Color(0xFF34343A);
  static const Color _green = Color(0xFF2FD1B0);
  static const Color _red = Color(0xFFE0303A);

  Color get _colorSede {
    switch (widget.sede) {
      case Sede.hero:
        return _red;
      case Sede.uma:
        return const Color(0xFF3B82F6);
      case Sede.auteco:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaFormateada =
        DateFormat('dd/MM/yyyy hh:mm a').format(widget.fechaHora);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildIconoExito(),
              const SizedBox(height: 20),
              const Text(
                'Escaneo exitoso',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'El código ha sido leído correctamente',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildResultadoCard(context, fechaFormateada),
                ),
              ),
              _buildBoton(
                context: context,
                texto: 'Volver a escanear',
                icono: Icons.refresh_rounded,
                relleno: true,
                onTap: () {
                  Navigator.of(context).pop(ScanResultAction.reescanear);
                },
              ),
              const SizedBox(height: 12),
              _buildBoton(
                context: context,
                texto: 'Salir',
                icono: Icons.logout_rounded,
                relleno: false,
                // "Salir" cierra la app por completo, no vuelve a la
                // cámara (para eso está el botón "Volver a escanear").
                onTap: () {
                  SystemNavigator.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconoExito() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _green, width: 2),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: 0.35),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, color: _green, size: 52),
    );
  }

  Widget _buildResultadoCard(BuildContext context, String fechaFormateada) {
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
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_2_rounded,
                    color: _green, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'RESULTADO ESCANEADO',
                style: TextStyle(
                  color: _green,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'CÓDIGO',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.codigo,
                  style: const TextStyle(
                    color: _green,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.codigo));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código copiado'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.copy_rounded, color: _green, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 14),
          _buildFila(
              Icons.view_week_rounded, 'TIPO', widget.tipo, Colors.white),
          const SizedBox(height: 16),
          _buildFila(Icons.calendar_today_rounded, 'FECHA Y HORA',
              fechaFormateada, Colors.white),
          const SizedBox(height: 16),
          _buildFila(Icons.sell_outlined, 'SEDE', widget.sede.nombre,
              _colorSede),
          const SizedBox(height: 16),
          _buildFila(Icons.wifi_tethering_rounded, 'ESCANEADO CON',
              widget.escaneadoCon, Colors.white),
        ],
      ),
    );
  }

  Widget _buildFila(IconData icon, String label, String valor, Color color) {
    return Row(
      children: [
        Icon(icon, color: _green, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
        const Spacer(),
        Text(
          valor,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildBoton({
    required BuildContext context,
    required String texto,
    required IconData icono,
    required bool relleno,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: relleno
              ? const LinearGradient(
                  colors: [Color(0xFF2FD1B0), Color(0xFF1E9E85)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          border: relleno ? null : Border.all(color: _red, width: 1.3),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, color: relleno ? Colors.white : _red, size: 20),
            const SizedBox(width: 10),
            Text(
              texto,
              style: TextStyle(
                color: relleno ? Colors.white : _red,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}