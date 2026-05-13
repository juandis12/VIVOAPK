import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';

class AchievementsService {
  static final AchievementsService _instance = AchievementsService._internal();
  factory AchievementsService() => _instance;
  AchievementsService._internal();

  final _supabase = SupabaseService().client;
  String? _profileId;
  
  int xp = 0;
  List<String> unlockedIds = [];
  Map<String, dynamic> stats = {};

  Future<void> init(String profileId) async {
    _profileId = profileId;
    await loadState();
    debugPrint('[Achievements] 🏆 Engine inicializado para perfil: $profileId | XP: $xp');
  }

  Future<void> loadState() async {
    if (_profileId == null) return;
    try {
      final data = await _supabase
          .from('user_achievements')
          .select('xp, unlocked_ids, stats')
          .eq('profile_id', _profileId!)
          .maybeSingle();

      if (data != null) {
        xp = data['xp'] ?? 0;
        unlockedIds = List<String>.from(data['unlocked_ids'] ?? []);
        stats = Map<String, dynamic>.from(data['stats'] ?? {});
      }
    } catch (e) {
      debugPrint('[Achievements] Error cargando estado: $e');
    }
  }

  Future<void> saveState() async {
    if (_profileId == null) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('user_achievements').upsert({
        'user_id': user.id,
        'profile_id': _profileId,
        'xp': xp,
        'unlocked_ids': unlockedIds,
        'stats': stats,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'profile_id');
      debugPrint('[Achievements] ☁️ Sincronización exitosa: $xp XP');
    } catch (e) {
      debugPrint('[Achievements] Error guardando estado: $e');
    }
  }

  Future<void> track(String event, {Map<String, dynamic>? payload}) async {
    if (_profileId == null) return;

    switch (event) {
      case 'play_video':
        stats['plays'] = (stats['plays'] ?? 0) + 1;
        List<int> genres = List<int>.from(stats['genres'] ?? []);
        int? genre = payload?['genre'];
        if (genre != null && !genres.contains(genre)) {
          genres.add(genre);
          stats['genres'] = genres;
        }

        if (stats['plays'] == 1) _unlock('first_play', 50);
        if (genres.length >= 5) _unlock('genre_hopper', 150);

        if (payload?['type'] == 'tv') {
          stats['episode_streak'] = (stats['episode_streak'] ?? 0) + 1;
          if (stats['episode_streak'] >= 3) _unlock('binge_3', 100);
          if (stats['episode_streak'] >= 10) _unlock('binge_10', 300);
        } else {
          stats['episode_streak'] = 0;
        }

        // Búho nocturno
        final hour = DateTime.now().hour;
        if (hour >= 0 && hour < 5) _unlock('night_owl', 75);
        break;

      case 'complete_content':
        stats['completed'] = (stats['completed'] ?? 0) + 1;
        if (payload?['type'] == 'anime') {
          stats['anime_completed'] = (stats['anime_completed'] ?? 0) + 1;
          if (stats['anime_completed'] >= 5) _unlock('anime_fan', 200);
        }
        if (payload?['type'] == 'movie') {
          stats['movies_watched'] = (stats['movies_watched'] ?? 0) + 1;
          if (stats['movies_watched'] >= 50) _unlock('cinephile_50', 500);
        }
        if (stats['completed'] >= 20) _unlock('completionist', 400);
        break;
        
      case 'vibe_engine_used':
        _unlock('explorer', 100);
        break;

      case 'watch_party_created':
        _unlock('party_host', 150);
        break;
    }

    if (xp >= 2000) _unlock('legend', 0);
    await saveState();
  }

  void _unlock(String id, int xpReward) {
    if (unlockedIds.contains(id)) return;
    unlockedIds.add(id);
    xp += xpReward;
    debugPrint('[Achievements] 🏆 Desbloqueado: $id (+ $xpReward XP)');
    // Aquí se podría disparar una notificación local si se desea
  }
}
