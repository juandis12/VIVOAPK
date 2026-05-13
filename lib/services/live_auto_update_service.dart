import 'dart:async';
import 'package:vivoweb_flutter/services/live_service.dart';

/// Servicio que monitorea cambios de programa en un canal Live.
/// Usa un [Timer.periodic] cada 30 segundos para detectar si el
/// programa actual cambió y notificar a los listeners.
class LiveAutoUpdateService {
  Timer? _timer;
  final _controller = StreamController<LiveShowResult>.broadcast();
  
  int? _lastTmdbId;
  final String channelId;
  final LiveService _liveService = LiveService();

  LiveAutoUpdateService(this.channelId);

  /// Stream de eventos: emite un [LiveShowResult] cada vez que
  /// el programa del canal cambia (no en cada tick del timer).
  Stream<LiveShowResult> get onShowChanged => _controller.stream;

  /// Inicia el monitoreo periódico. Emite el estado actual inmediatamente
  /// y luego comprueba cada 30 segundos.
  void start() {
    _checkAndEmit(); // Emitir estado inicial
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkAndEmit();
    });
  }

  void _checkAndEmit() {
    if (_controller.isClosed) return;

    final result = _liveService.getCurrentShow(channelId);
    if (result == null) return;

    final currentTmdbId = result.currentShow.tmdbId;

    // Solo emite si el programa cambió desde la última comprobación
    if (currentTmdbId != _lastTmdbId) {
      _lastTmdbId = currentTmdbId;
      _controller.add(result);
    }
  }

  /// Detiene el timer y cierra el stream. Llamar en [dispose()] del widget.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }
}
