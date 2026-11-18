import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Bridge to the bundled LunaTV server that the Android shell runs.
///
/// The native side (MainActivity / LunaGateway) owns the port, the generated
/// password and process lifetime; Dart only asks for the connection details and
/// waits for the port to answer, so the user never types a server address.
class LocalServerService {
  static const MethodChannel _channel = MethodChannel('lunatv/server');

  /// Only the Android build carries a server; desktop builds keep the normal
  /// login screen.
  static bool get isBundled => Platform.isAndroid;

  static Future<Map<String, dynamic>> info() async {
    final raw = await _channel.invokeMethod<Map>('getInfo');
    return Map<String, dynamic>.from(raw ?? const {});
  }

  /// Polls the local server until it answers. A 401 from /api/health still
  /// proves the server is up (that route sits behind the auth cookie).
  static Future<bool> waitReady(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 240),
    void Function(int seconds)? onTick,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var elapsed = 0;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final res = await http
            .get(Uri.parse('$baseUrl/api/health'))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode < 500) {
          return true;
        }
      } catch (_) {
        // not listening yet — the first launch is still unpacking ~18k files
      }
      onTick?.call(elapsed);
      elapsed += 2;
      await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  static Future<int?> setPort(int port) =>
      _channel.invokeMethod<int>('setPort', {'port': port});

  /// What the native side is doing right now: the unpacking text and whether
  /// the port already answers. The splash screen polls this so the first
  /// launch (~18k files) is never a silent spinner.
  static Future<Map<String, dynamic>> progress() async {
    final raw = await _channel.invokeMethod<Map>('getProgress');
    return Map<String, dynamic>.from(raw ?? const {});
  }

  static Future<String?> lanAddress() =>
      _channel.invokeMethod<String>('lanAddress');

  static Future<String?> openAdmin() =>
      _channel.invokeMethod<String>('openAdmin');
}