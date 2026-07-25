import 'dart:convert';
import 'dart:io';

/// Envía datos por UDP a un PC en la misma red (mismo wifi) sin esperar
/// ninguna respuesta del servidor. Abre un socket efímero, manda el
/// datagrama y lo cierra de inmediato ("fire and forget").
class UdpSender {
  UdpSender._();

  static Future<void> enviar({
    required String mensaje,
    required String ip,
    required int puerto,
  }) async {
    RawDatagramSocket? socket;
    try {
      // Puerto 0 -> el sistema operativo asigna un puerto local libre
      // para este socket de salida; no es el puerto del servidor.
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final data = utf8.encode(mensaje);
      socket.send(data, InternetAddress(ip), puerto);
    } finally {
      socket?.close();
    }
  }
}