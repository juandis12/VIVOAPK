import 'dart:math';
import 'package:vivoweb_flutter/models/content_model.dart';

class LiveChannel {
  final String id;
  final String name;
  final String icon;
  final String color;
  final List<int> genreIds;
  List<LiveScheduleItem> schedule = [];

  LiveChannel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.genreIds,
  });
}

class LiveScheduleItem {
  final String time; // HH:mm
  final int tmdbId;
  final String title;
  final String type;
  final int duration; // en segundos

  LiveScheduleItem({
    required this.time,
    required this.tmdbId,
    required this.title,
    required this.type,
    required this.duration,
  });
}

class LiveShowResult {
  final LiveScheduleItem currentShow;
  final LiveScheduleItem nextShow;
  final int offsetSeconds;
  final double progress;

  LiveShowResult({
    required this.currentShow,
    required this.nextShow,
    required this.offsetSeconds,
    required this.progress,
  });
}

class LiveService {
  static final LiveService _instance = LiveService._internal();
  factory LiveService() => _instance;
  LiveService._internal();

  final List<LiveChannel> channels = [
    LiveChannel(id: 'risa', name: 'Vivo Risa', icon: '😄', color: '#facc15', genreIds: [35]),
    LiveChannel(id: 'action', name: 'Vivo Acción', icon: '💥', color: '#ef4444', genreIds: [28, 12]),
    LiveChannel(id: 'horror', name: 'Vivo Terror', icon: '👻', color: '#7c3aed', genreIds: [27, 53, 9648]),
    LiveChannel(id: 'anime', name: 'Anime 24/7', icon: '🍥', color: '#f97316', genreIds: [16]),
    LiveChannel(id: 'family', name: 'Vivo Familiar', icon: '🌈', color: '#22c55e', genreIds: [10751, 10762, 16]),
  ];

  /// Inicializa el catálogo y genera la programación del día de forma determinista
  void buildLiveCatalog(List<ContentModel> dbCatalog) {
    if (dbCatalog.isEmpty) return;

    final now = DateTime.now().toUtc();
    final dateStr = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    final dateSeed = int.parse(dateStr);

    for (var channel in channels) {
      // Filtrar por género
      var matching = dbCatalog.where((item) {
        final itemGenres = item.genreIds;
        return channel.genreIds.any((id) => itemGenres.contains(id));
      }).toList();

      if (matching.isEmpty) {
        matching = dbCatalog.take(20).toList();
      }

      // Hash del ID del canal para seed único
      final channelHash = channel.id.runes.reduce((a, b) => a + b);
      final seed = dateSeed + channelHash;
      
      channel.schedule = _generateDailySchedule(matching, seed);
    }
  }

  List<LiveScheduleItem> _generateDailySchedule(List<ContentModel> pool, int seed) {
    final random = _Mulberry32(seed);
    final shuffled = List<ContentModel>.from(pool)..shuffle(random);
    
    List<LiveScheduleItem> schedule = [];
    int currentSeconds = 0;
    const int secondsInDay = 24 * 3600;
    int i = 0;

    while (currentSeconds < secondsInDay) {
      final item = shuffled[i % shuffled.length];
      // Asumimos 2h por defecto si no hay runtime
      final int duration = 7200; 
      
      final h = currentSeconds ~/ 3600;
      final m = (currentSeconds % 3600) ~/ 60;
      final timeStr = "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";

      schedule.add(LiveScheduleItem(
        time: timeStr,
        tmdbId: item.id,
        title: item.title,
        type: item.type,
        duration: duration,
      ));

      currentSeconds += duration;
      i++;
    }
    return schedule;
  }

  LiveShowResult? getCurrentShow(String channelId) {
    try {
      final channel = channels.firstWhere((c) => c.id == channelId);
      if (channel.schedule.isEmpty) return null;

      final now = DateTime.now().toUtc();
      final currentTimeInSeconds = (now.hour * 3600) + (now.minute * 60) + now.second;

      LiveScheduleItem? currentShow;
      LiveScheduleItem? nextShow;

      for (int i = 0; i < channel.schedule.length; i++) {
        final item = channel.schedule[i];
        final parts = item.time.split(':').map(int.parse).toList();
        final showTimeSeconds = (parts[0] * 3600) + (parts[1] * 60);

        if (showTimeSeconds <= currentTimeInSeconds) {
          currentShow = item;
          nextShow = (i + 1 < channel.schedule.length) ? channel.schedule[i+1] : channel.schedule[0];
        } else {
          break;
        }
      }

      // Fallback si no se encontró (fin del día)
      currentShow ??= channel.schedule.last;
      nextShow ??= channel.schedule.first;

      final parts = currentShow.time.split(':').map(int.parse).toList();
      final int showTimeSeconds = (parts[0] * 3600) + (parts[1] * 60);
      int offset = currentTimeInSeconds - showTimeSeconds;
      if (offset < 0) offset += (24 * 3600); // Salto de día

      return LiveShowResult(
        currentShow: currentShow,
        nextShow: nextShow,
        offsetSeconds: offset,
        progress: (offset / currentShow.duration).clamp(0.0, 1.0),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Implementación de PRNG Mulberry32 para paridad con JS
class _Mulberry32 implements Random {
  int seed;
  _Mulberry32(this.seed);

  @override
  int nextInt(int max) {
    seed = (seed + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = seed;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= t + _imul(t ^ (t >> 7), t | 61);
    int res = ((t ^ (t >> 14)) >> 0) & 0xFFFFFFFF;
    return (res % max).abs();
  }

  int _imul(int a, int b) {
    return (a * b) & 0xFFFFFFFF;
  }
  
  @override
  double nextDouble() => (nextInt(0x7FFFFFFF) / 0x7FFFFFFF);

  @override
  bool nextBool() => nextInt(2) == 0;
}
