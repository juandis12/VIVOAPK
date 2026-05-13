import 'package:vivoweb_flutter/services/content_service.dart';

class LiveSyncService {
  static final LiveSyncService _instance = LiveSyncService._internal();
  factory LiveSyncService() => _instance;
  LiveSyncService._internal();

  final ContentService _contentService = ContentService();

  // Mapeo de géneros según TMDB para cada canal
  static const Map<String, int> genreMap = {
    'Acción': 28,
    'Terror': 27,
    'Risa': 35, // Comedia
    'Anime': 16,
    'Familiar': 10751,
  };

  /// Obtiene el contenido que debería estar reproduciéndose ahora para un canal dado.
  /// Devuelve un mapa con el contenido y el segundo exacto de inicio.
  Future<Map<String, dynamic>> getCurrentLiveContent(String channelName) async {
    final genreId = genreMap[channelName];
    if (genreId == null) throw Exception('Canal no válido');

    // ⚠️ FIX: Garantizar que ContentService esté inicializado antes de filtrar.
    // Sin esto, _availableIds está vacío y todos los resultados se descartan.
    if (!_contentService.isInitialized) {
      await _contentService.initialize();
    }

    // Obtenemos los contenidos de ese género desde la base de datos
    final contents = await _contentService.getCategoryWithGenre(genreId);
    
    if (contents.isEmpty) return {};

    // Sincronización determinista basada en el tiempo actual
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Usamos una duración estimada de 2 horas (7200s) por película para el ciclo
    const movieDuration = 7200; 
    final totalCycleDuration = contents.length * movieDuration;
    
    final currentCycleTime = now % totalCycleDuration;
    final contentIndex = currentCycleTime ~/ movieDuration;
    final seekSeconds = currentCycleTime % movieDuration;

    // Simulador de EPG (Inspirado en MXL TV): Obtener los próximos programas
    final nextContentIndex1 = (contentIndex + 1) % contents.length;
    final nextContentIndex2 = (contentIndex + 2) % contents.length;

    return {
      'content': contents[contentIndex],
      'seekSeconds': seekSeconds,
      'upcoming': [
        contents[nextContentIndex1],
        contents[nextContentIndex2],
      ]
    };
  }
}
