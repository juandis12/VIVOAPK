import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/models/episode_model.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';
import 'package:vivoweb_flutter/services/tmdb_service.dart';
import 'package:http/http.dart' as http;

class ContentService {
  static final ContentService _instance = ContentService._internal();
  factory ContentService() => _instance;
  ContentService._internal();

  final SupabaseService _supabaseService = SupabaseService();
  final TMDBService _tmdbService = TMDBService();
  
  static const _vimeusApiKey = 'ak_dhYuCU8aswKclnexhYTtbf3tHqgzQTkF';
  static const _vimeusViewKey = 'X_FK-_jYlGUUrM9cgLrkDdOJSe7EB-cXlrU7GFdd_Rk';
  
  final Set<String> _availableMovies = {};
  final Set<String> _availableSeries = {};
  final Set<String> _availableIds = {};
  
  // Cache en memoria para listados (datos ligeros: poster, title, genres)
  final Map<String, ContentModel> _detailCache = {};
  static const String _cacheKey = 'vivoweb_content_cache_v3';

  // TTL: el caché en disco se considera válido por 6 horas
  static const Duration _cacheTTL = Duration(hours: 6);
  static const String _cacheTimestampKey = 'vivoweb_cache_timestamp_v3';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Realtime Listeners
  RealtimeChannel? _favsChannel;
  RealtimeChannel? _historyChannel;
  
  final _contentUpdateController = StreamController<String>.broadcast();
  Stream<String> get onContentUpdate => _contentUpdateController.stream;

  // Acceso al catálogo completo en memoria
  List<ContentModel> get dbCatalog => _detailCache.values.toList();

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Carga rápida del caché desde el disco (indispensable para el Dashboard)
    await _loadCacheFromDisk();
    
    // Marcamos como inicializado para que el Dashboard pueda mostrar el caché
    _isInitialized = true;

    // Disparamos la carga de disponibilidad en segundo plano para NO BLOQUEAR el Dashboard
    _loadAvailabilityInBackground();
  }

  Future<void> _loadAvailabilityInBackground() async {
    try {
      debugPrint('[ContentService] 📡 Iniciando carga de disponibilidad masiva en segundo plano...');
      
      // PERF-04: Usar consultas más ligeras (solo ids) y con límite si es necesario
      // pero para el set necesitamos todos. Supabase tiene un límite por defecto,
      // así que para miles de registros lo ideal es una función RPC o paginación.
      // Por ahora, aumentamos el tiempo de espera y cargamos en paralelo.
      
      final results = await Future.wait([
        _supabaseService.client.from('video_sources').select('tmdb_id').timeout(const Duration(seconds: 30)),
        _supabaseService.client.from('series_episodes').select('tmdb_id').timeout(const Duration(seconds: 30)),
      ]);

      final Set<String> newMovies = {};
      final Set<String> newSeries = {};
      final Set<String> newAll = {};

      final movies = results[0] as List;
      final series = results[1] as List;

      for (var m in movies) {
        final id = m['tmdb_id']?.toString();
        if (id != null) {
          newMovies.add(id);
          newAll.add(id);
        }
      }

      for (var s in series) {
        final id = s['tmdb_id']?.toString();
        if (id != null) {
          newSeries.add(id);
          newAll.add(id);
        }
      }

      if (newAll.isNotEmpty) {
        _availableMovies.clear();
        _availableSeries.clear();
        _availableIds.clear();
        _availableMovies.addAll(newMovies);
        _availableSeries.addAll(newSeries);
        _availableIds.addAll(newAll);
        
        debugPrint('[ContentService] ✅ Disponibilidad cargada: ${newAll.length} items totales.');
        
        // Notificamos al Dashboard que ya tenemos los datos de disponibilidad
        _contentUpdateController.add('availability');
      }

      _setupRealtimeSync();
    } catch (e) {
      debugPrint('[ContentService] ❌ Error cargando disponibilidad en segundo plano: $e');
      // Reintento silencioso en 10 segundos si falló por red
      Future.delayed(const Duration(seconds: 10), () => _loadAvailabilityInBackground());
    }
  }

  void _setupRealtimeSync() {
    final userId = _supabaseService.client.auth.currentUser?.id;
    
    // CANCELAR suscripciones previas
    _favsChannel?.unsubscribe();
    _historyChannel?.unsubscribe();

    debugPrint('[Sync] 📡 Iniciando suscripciones Realtime');

    // 1. Suscripción a Disponibilidad (Global)
    _supabaseService.client
        .channel('public:availability_sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'video_sources',
          callback: (payload) {
            debugPrint('[Sync] ⚡ Cambio en Disponibilidad (Movies)');
            _refreshAvailabilityAndNotify();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'series_episodes',
          callback: (payload) {
            debugPrint('[Sync] ⚡ Cambio en Disponibilidad (Series)');
            _refreshAvailabilityAndNotify();
          },
        )
        .subscribe();

    if (userId == null) return;

    // 2. Suscripción a Favoritos
    _favsChannel = _supabaseService.client
        .channel('public:user_favorites:sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_favorites',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) {
            debugPrint('[Sync] ⚡ Cambio detectado en Favoritos');
            _contentUpdateController.add('favorites');
          },
        )
        .subscribe();

    // 3. Suscripción a Historial
    _historyChannel = _supabaseService.client
        .channel('public:watch_history:sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'watch_history',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) {
            debugPrint('[Sync] ⚡ Cambio detectado en Historial');
            _contentUpdateController.add('history');
          },
        )
        .subscribe();
  }

  Future<void> _refreshAvailabilityAndNotify() async {
    try {
      final results = await Future.wait([
        _supabaseService.client.from('video_sources').select('tmdb_id'),
        _supabaseService.client.from('series_episodes').select('tmdb_id'),
      ]);

      _availableMovies.clear();
      _availableSeries.clear();
      _availableIds.clear();

      for (var m in (results[0] as List)) {
        final id = m['tmdb_id']?.toString();
        if (id != null) {
          _availableMovies.add(id);
          _availableIds.add(id);
        }
      }

      for (var s in (results[1] as List)) {
        final id = s['tmdb_id']?.toString();
        if (id != null) {
          _availableSeries.add(id);
          _availableIds.add(id);
        }
      }

      debugPrint('[Sync] 🔄 Disponibilidad actualizada Realtime');
      _contentUpdateController.add('availability');
    } catch (e) {
      debugPrint('[Sync] ❌ Error refreshing availability: $e');
    }
  }

  void dispose() {
    _favsChannel?.unsubscribe();
    _historyChannel?.unsubscribe();
    _contentUpdateController.close();
  }

  Future<void> _loadCacheFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Verificar si el caché ha expirado (TTL de 6 horas)
      final timestampRaw = prefs.getInt(_cacheTimestampKey);
      if (timestampRaw != null) {
        final savedAt = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
        final age = DateTime.now().difference(savedAt);
        if (age > _cacheTTL) {
          debugPrint('[Cache] Caché expirado (${age.inHours}h). Se refrescará en background.');
          // No cargamos el caché viejo — dejamos que se reconstruya
          await prefs.remove(_cacheKey);
          await prefs.remove(_cacheTimestampKey);
          return;
        }
      }

      final cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        final Map<String, dynamic> decoded = json.decode(cachedData);
        decoded.forEach((key, value) {
          _detailCache[key] = ContentModel.fromCache(Map<String, dynamic>.from(value));
        });
        debugPrint('[Cache] ✅ Cargados ${_detailCache.length} ítems desde el disco.');
      }
    } catch (e) {
      debugPrint('[Cache] Error cargando caché: $e');
    }
  }

  Future<void> _saveCacheToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Solo guardamos los primeros 400 para no saturar SharedPreferences
      final limitedCache = Map.fromEntries(
        _detailCache.entries.take(400)
      );
      final encoded = json.encode(limitedCache);
      await prefs.setString(_cacheKey, encoded);
      // Registrar timestamp para el TTL
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('[Cache] 💾 Guardados ${limitedCache.length} ítems en disco.');
    } catch (e) {
      debugPrint('[Cache] Error guardando caché: $e');
    }
  }

  Future<ContentModel> getFullDetails(String type, int id) async {
    final details = await _tmdbService.getContentDetails(type, id);
    return ContentModel.fromJson(details, type);
  }

  Future<String?> getStreamUrl(int tmdbId, String type) async {
    if (type == 'movie') {
      return getMovieStreamUrl(tmdbId);
    } else {
      // Para series en canales en vivo, buscamos el primer episodio disponible
      final res = await _supabaseService.client
          .from('series_episodes')
          .select('stream_url')
          .eq('tmdb_id', tmdbId)
          .limit(1)
          .maybeSingle();
      return res?['stream_url'];
    }
  }

  Future<List<ContentModel>> getTrendingContent() async {
    final trending = await _tmdbService.getTrending('movie');
    final movies = await _filterAndFetchDetails(trending, 'movie');
    
    // Si hay muy pocos resultados en tendencias, rellenamos con lo más reciente de la DB
    if (movies.length < 5) {
      final recentlyAdded = await getRecentlyAdded();
      return {...movies, ...recentlyAdded}.toList();
    }
    
    return movies;
  }

  Future<List<ContentModel>> getRecentlyAdded() async {
    try {
      final movieRes = await _supabaseService.client
          .from('video_sources')
          .select('tmdb_id')
          .order('created_at', ascending: false)
          .limit(20);
          
      final seriesRes = await _supabaseService.client
          .from('series_episodes')
          .select('tmdb_id')
          .order('created_at', ascending: false)
          .limit(20);
          
      final movieIds = (movieRes as List).map((m) => m['tmdb_id']?.toString()).whereType<String>().toList();
      final seriesIds = (seriesRes as List).map((s) => s['tmdb_id']?.toString()).whereType<String>().toSet().toList();
      
      final movies = await _fetchMissingDetails(movieIds, 'movie');
      final series = await _fetchMissingDetails(seriesIds, 'tv');
      
      return [...movies, ...series];
    } catch (e) {
      debugPrint('[ContentService] Error fetching recently added: $e');
      return [];
    }
  }

  // Nuevo método para traer todo el contenido de la base de datos (Optimizado)
  Future<List<ContentModel>> getDatabaseContent(String type) async {
    // CAMBIO: Ahora en lugar de solo lo de Supabase, traemos lo más popular de TMDB 
    // para que la lista "TODAS" se vea realmente completa como pide el usuario.
    final effectiveType = type == 'movie' ? 'movie' : 'tv';
    
    if (type == 'anime') {
      final results = await _tmdbService.fetchFromTMDB('/discover/tv', {
        'with_genres': '16',
        'sort_by': 'popularity.desc',
        'page': '1'
      });
      final items = results['results'] as List? ?? [];
      return _filterAndFetchDetails(items, 'tv');
    }

    final results = await _tmdbService.fetchFromTMDB(
      effectiveType == 'movie' ? '/movie/popular' : '/tv/popular', 
      {'page': '1'}
    );
    final items = results['results'] as List? ?? [];
    return _filterAndFetchDetails(items, effectiveType);
  }

  // Filtrar por género cruzando con la DB local
  Future<List<ContentModel>> getDatabaseContentByGenre(String type, int genreId) async {
    final effectiveType = type == 'movie' ? 'movie' : 'tv';
    final searchType = type == 'anime' ? 'tv' : effectiveType;
    final searchGenre = type == 'anime' ? 16 : genreId;

    final results = await _tmdbService.fetchFromTMDB(searchType == 'movie' ? '/discover/movie' : '/discover/tv', {
      'with_genres': searchGenre.toString(),
      'sort_by': 'popularity.desc',
    });
    final items = results['results'] as List? ?? [];
    return _filterAndFetchDetails(items, searchType);
  }

  // Filtrar populares cruzando con la DB local
  Future<List<ContentModel>> getPopularDatabase(String type) async {
    final searchType = type == 'movie' ? 'movie' : 'tv';
    final results = await _tmdbService.fetchFromTMDB(searchType == 'movie' ? '/movie/popular' : '/tv/popular', {});
    
    // Si es anime, agregamos el filtro de género por TV
    if (type == 'anime') {
      final animeResults = await _tmdbService.fetchFromTMDB('/discover/tv', {
        'with_genres': '16',
        'sort_by': 'popularity.desc',
      });
      final items = animeResults['results'] as List? ?? [];
      return _filterAndFetchDetails(items, 'tv');
    }

    final items = results['results'] as List? ?? [];
    return _filterAndFetchDetails(items, searchType);
  }

  // Filtrar mejores valoradas cruzando con la DB local
  Future<List<ContentModel>> getTopRatedDatabase(String type) async {
    final searchType = type == 'movie' ? 'movie' : 'tv';
    
    if (type == 'anime') {
      final animeResults = await _tmdbService.fetchFromTMDB('/discover/tv', {
        'with_genres': '16',
        'sort_by': 'vote_average.desc',
      });
      final items = animeResults['results'] as List? ?? [];
      return _filterAndFetchDetails(items, 'tv');
    }

    final results = await _tmdbService.fetchFromTMDB(searchType == 'movie' ? '/movie/top_rated' : '/tv/top_rated', {});
    final items = results['results'] as List? ?? [];
    return _filterAndFetchDetails(items, searchType);
  }

  // ─── FETCH PARA LISTADOS (Usa endpoint LIGERO) ────────────────────────────────
  // Usa getContentSummary() en lugar de getContentDetails() para ahorrar ~70% de
  // ancho de banda. Videos, créditos y recomendaciones NO se descargan aquí.
  // El caché en disco se guarda UNA sola vez al finalizar todos los lotes.
  Future<List<ContentModel>> _fetchMissingDetails(List<String> ids, String tmdbType) async {
    List<ContentModel> results = [];
    List<String> idsToFetch = [];

    for (var id in ids) {
      if (_detailCache.containsKey(id)) {
        results.add(_detailCache[id]!);
      } else {
        idsToFetch.add(id);
      }
    }

    if (idsToFetch.isEmpty) return results;

    debugPrint('[ContentService] 📡 Fetching ${idsToFetch.length} ítems nuevos (ligero)...');

    // Lotes de 20 peticiones paralelas (endpoint ligero aguanta más concurrencia)
    const int batchSize = 20;
    bool hasNewData = false;

    for (int i = 0; i < idsToFetch.length; i += batchSize) {
      final batch = idsToFetch.sublist(
        i,
        (i + batchSize) > idsToFetch.length ? idsToFetch.length : (i + batchSize),
      );
      
      final batchResults = await Future.wait(batch.map((id) async {
        try {
          // ✅ CLAVE: Usamos el endpoint LIGERO aquí, no el completo
          final summary = await _tmdbService.getContentSummary(tmdbType, int.parse(id));
          final model = ContentModel.fromJson(summary, tmdbType);
          _detailCache[id] = model;
          hasNewData = true;
          return model;
        } catch (e) {
          debugPrint('[ContentService] Error fetching summary for $id: $e');
          return null;
        }
      }));

      results.addAll(batchResults.whereType<ContentModel>());
    }

    // ✅ CLAVE: Guardar en disco UNA sola vez al terminar todos los lotes
    // (no dentro del loop para evitar I/O innecesario)
    if (hasNewData) {
      _saveCacheToDisk(); // Fire-and-forget: no bloquea la UI
    }

    return results;
  }

  Future<List<ContentModel>> getCategoryContent(String type, {int? excludeGenre}) async {
    // Si queremos el catálogo completo, usamos getDatabaseContent
    // pero para las filas del inicio combinamos con TMDB
    final items = type == 'movie' 
        ? await _tmdbService.getTrending('movie') 
        : await _tmdbService.getTrending('tv');
    
    return _filterAndFetchDetails(items, type == 'movie' ? 'movie' : 'tv');
  }

  // ─── MI LISTA ─────────────────────────────────────────────────────────────
  // CORRECIÓN: Se usa Future.wait (paralelo) en lugar de for-await (secuencial).
  // Para 20 favoritos pasa de ~14 segundos a ~700ms.
  // Filtro unificado con la web: profile_id únicamente (igual que app.js).
  Future<List<ContentModel>> getMyList(String profileId) async {
    final response = await _supabaseService.client
        .from('user_favorites')
        .select('tmdb_id, type')
        .eq('profile_id', profileId)
        .order('created_at', ascending: false)
        .limit(50);
    
    final favs = response as List;
    if (favs.isEmpty) return [];

    // Paralelo: todas las peticiones al mismo tiempo
    final results = await Future.wait(
      favs.map((fav) async {
        try {
          final tmdbId = int.tryParse(fav['tmdb_id'].toString());
          if (tmdbId == null) return null;
          // Endpoint ligero: no descarga videos/créditos para el listado
          final summary = await _tmdbService.getContentSummary(
            fav['type'] ?? 'movie',
            tmdbId,
          );
          final model = ContentModel.fromJson(summary, fav['type'] ?? 'movie');
          _detailCache[tmdbId.toString()] = model; // Guardar en caché
          return model;
        } catch (e) {
          return null;
        }
      }),
    );
    return results.whereType<ContentModel>().toList();
  }

  // ─── HISTORIAL DE REPRODUCCIÓN ────────────────────────────────────────────
  // CORRECIÓN: Future.wait paralelo + endpoint ligero.
  // Filtro unificado con la web: solo profile_id (campo que siempre existe).
  Future<List<ContentModel>> getWatchHistory(String profileId) async {
    final response = await _supabaseService.client
        .from('watch_history')
        .select('tmdb_id, type, progress_seconds')
        .eq('profile_id', profileId)
        .order('last_watched', ascending: false)
        .limit(20);
    
    final history = response as List;
    if (history.isEmpty) return [];
 
    final seen = <String>{};
    final unique = history.where((h) {
      final id = h['tmdb_id'].toString();
      if (seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();
 
    final results = await Future.wait(
      unique.map((hist) async {
        try {
          final tmdbId = int.tryParse(hist['tmdb_id'].toString());
          if (tmdbId == null) return null;
          final summary = await _tmdbService.getContentSummary(hist['type'] ?? 'movie', tmdbId);
          final model = ContentModel.fromJson(summary, hist['type'] ?? 'movie');
          
          final runtime = summary['runtime'] ?? (summary['episode_run_time'] != null && (summary['episode_run_time'] as List).isNotEmpty ? summary['episode_run_time'][0] : 45);
          
          return model.copyWith(
            progressSeconds: hist['progress_seconds'] ?? 0,
            runtime: runtime,
          );
        } catch (e) {
          return null;
        }
      }),
    );
    return results.whereType<ContentModel>().toList();
  }

  Future<List<ContentModel>> searchContent(String query) async {
    final results = await _tmdbService.searchContent(query);
    
    // Mapeamos cada resultado a su tipo correcto detectado por TMDB
    final List<ContentModel> searchResults = [];
    
    for (var item in results) {
      final mediaType = item['media_type'] ?? 'movie';
      if (mediaType == 'person') continue; // Ignorar personas en la búsqueda de contenido
      
      final model = ContentModel.fromJson(item, mediaType);
      searchResults.add(model);
    }
    
    return searchResults;
  }

  // ─── FAVORITOS CRUD ─────────────────────────────────────────────────────────────
  // CORRECIÓN: insert ahora incluye user_id para que la consulta de la web
  // (que filtra por user_id + profile_id) pueda encontrar los favoritos
  // agregados desde la app móvil. La web agrega ambos campos, la app también.
  Future<void> toggleFavorite(String profileId, ContentModel content) async {
    final isFav = await isFavorite(profileId, content.id.toString());
    final userId = _supabaseService.client.auth.currentUser?.id;
    
    if (isFav) {
      await _supabaseService.client
          .from('user_favorites')
          .delete()
          .eq('profile_id', profileId)
          .eq('tmdb_id', content.id.toString());
    } else {
      await _supabaseService.client.from('user_favorites').insert({
        'profile_id': profileId,
        if (userId != null) 'user_id': userId, // Agrega user_id para sync con web
        'tmdb_id': content.id.toString(),
        'type': content.type,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<bool> isFavorite(String profileId, String tmdbId) async {
    final res = await _supabaseService.client
        .from('user_favorites')
        .select()
        .eq('profile_id', profileId)
        .eq('tmdb_id', tmdbId)
        .maybeSingle();
    return res != null;
  }

  Future<int> getSavedProgress(String profileId, String tmdbId, {int? season, int? episode}) async {
    // BUG-01 FIX: Los métodos .eq() retornan un NUEVO builder — se debe reasignar.
    // Sin esto, los filtros de season/episode nunca se aplicaban.
    var query = _supabaseService.client
        .from('watch_history')
        .select('progress_seconds')
        .eq('profile_id', profileId)
        .eq('tmdb_id', tmdbId);
    
    if (season != null) query = query.eq('season_number', season);
    if (episode != null) query = query.eq('episode_number', episode);

    final res = await query.maybeSingle();
    return res?['progress_seconds'] ?? 0;
  }

  bool isAvailable(String tmdbId) => _availableIds.contains(tmdbId);

  Future<List<ContentModel>> getCategoryWithGenre(int genreId) async {
    // Para canales en vivo, buscamos tanto en Películas como en Series
    final movieResults = await _tmdbService.fetchFromTMDB('/discover/movie', {
      'with_genres': genreId.toString(),
      'sort_by': 'popularity.desc',
    });
    
    final tvResults = await _tmdbService.fetchFromTMDB('/discover/tv', {
      'with_genres': genreId.toString(),
      'sort_by': 'popularity.desc',
    });

    final movieItems = movieResults['results'] as List? ?? [];
    final tvItems = tvResults['results'] as List? ?? [];

    final movies = await _filterAndFetchDetails(movieItems, 'movie');
    final series = await _filterAndFetchDetails(tvItems, 'tv');

    return [...movies, ...series];
  }

  Future<List<ContentModel>> _filterAndFetchDetails(List<dynamic> items, String defaultType) async {
    // YA NO FILTRAMOS: Mostramos todo lo que viene de TMDB para que el catálogo se vea lleno
    final allIds = items
        .map((item) => item['id'].toString())
        .toList();
    
    return _fetchMissingDetails(allIds, defaultType);
  }

  /// Reporta un contenido como fallido (póster roto o link caído) para ponerlo en mantenimiento
  Future<void> reportMaintenance(String tmdbId) async {
    try {
      debugPrint('[Maintenance] 🔧 Reportando ID $tmdbId para mantenimiento...');
      await _supabaseService.client.from('vivotv_maintenance_reports').upsert({
        'tmdb_id': tmdbId,
        'reported_at': DateTime.now().toIso8601String(),
        'platform': 'flutter_mobile'
      });
    } catch (e) {
      debugPrint('[Maintenance] Error reportando: $e');
    }
  }

  // ─── EPISODIOS DE TEMPORADA ───────────────────────────────────────────────────
  Future<List<EpisodeModel>> getSeasonEpisodes(
    dynamic tmdbId,
    int seasonNumber, {
    required String profileId,
  }) async {
    try {
      final id = int.tryParse(tmdbId.toString()) ?? 0;
      if (id == 0) return [];

      debugPrint('[ContentService] 📺 Cargando T$seasonNumber de $id para perfil $profileId');

      // 1. TMDB: Metadata
      final tmdbData = await _tmdbService.fetchFromTMDB(
        '/tv/$id/season/$seasonNumber',
        <String, String>{},
      );
      
      if (tmdbData == null || tmdbData['episodes'] == null) return [];
      final tmdbEpisodes = (tmdbData['episodes'] as List);

      // 1. Consultar API de Vimeus para esta temporada completa
      final Map<int, String> vimeusStreams = {};
      try {
        final vimeusRes = await http.get(
          Uri.parse('https://vimeus.com/api/listing/episodes?tmdb_id=$id&season=$seasonNumber'),
          headers: {'X-API-Key': _vimeusApiKey},
        ).timeout(const Duration(seconds: 5));
        
        if (vimeusRes.statusCode == 200) {
          final vimeusData = json.decode(vimeusRes.body);
          if (vimeusData['error'] == false && vimeusData['data'] != null) {
            final resultList = vimeusData['data']['result'] ?? vimeusData['data']['episodes'];
            if (resultList != null && resultList is List) {
              for (var ep in resultList) {
                final epNum = int.tryParse(ep['episode'].toString());
                if (epNum != null && ep['embed_url'] != null) {
                  vimeusStreams[epNum] = ep['embed_url'];
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Vimeus] Error obteniendo episodios de la API: $e');
      }

      // 2. Supabase Fallback (para episodios faltantes en Vimeus)
      final dbResponse = await _supabaseService.client
          .from('series_episodes')
          .select('episode_number, stream_url, stream_url_vidsrc, stream_url_2embed, stream_url_superembed')
          .eq('tmdb_id', id)
          .eq('season_number', seasonNumber);
      
      final dbEpisodes = (dbResponse as List? ?? []);
      final dbMap = {for (var ep in dbEpisodes) (ep['episode_number'] as int): ep};

      // 3. Watch History
      final historyResponse = await _supabaseService.client
          .from('watch_history')
          .select('episode_number, progress_seconds, is_watched')
          .eq('profile_id', profileId)
          .eq('tmdb_id', id)
          .eq('season_number', seasonNumber);
      
      final historyList = (historyResponse as List? ?? []);
      final historyMap = {for (var h in historyList) (h['episode_number'] as int): h};

      // 4. Merge
      return tmdbEpisodes.map((epData) {
        final epNum = epData['episode_number'] as int;
        final dbEp = dbMap[epNum];
        final hist = historyMap[epNum];
        
        final streamUrl = vimeusStreams[epNum] ?? dbEp?['stream_url'] ?? dbEp?['stream_url_vidsrc'];

        return EpisodeModel.fromJson(
          epData,
          id,
          seasonNumber,
          streamUrl: streamUrl,
          progressSeconds: hist?['progress_seconds'] ?? 0,
          isWatched: hist?['is_watched'] ?? false,
        );
      }).toList();
    } catch (e) {
      debugPrint('[ContentService] ❌ Error getSeasonEpisodes: $e');
      return [];
    }
  }

  // ─── URLS DE PELÍCULAS ────────────────────────────────────────────────────────
  Future<String?> getMovieStreamUrl(dynamic tmdbId) async {
    final sources = await getMovieSources(tmdbId);
    return sources.isNotEmpty ? sources.first['url'] as String? : null;
  }

  Future<List<Map<String, dynamic>>> getMovieSources(dynamic tmdbId) async {
    try {
      final id = int.tryParse(tmdbId.toString()) ?? 0;
      if (id == 0) return [];
      
      final List<Map<String, dynamic>> sources = [];

      // 1. Consultar Vimeus directo usando HTTP HEAD en la URL de embed
      final vimeusUrl = 'https://vimeus.com/e/movie?tmdb=$id&view_key=$_vimeusViewKey';
      try {
        final headRes = await http.head(Uri.parse(vimeusUrl)).timeout(const Duration(seconds: 4));
        if (headRes.statusCode == 200) {
          sources.add({'name': 'Vimeus (VIP Principal)', 'url': vimeusUrl});
        }
      } catch (e) {
        debugPrint('[Vimeus] Error verificando película: $e');
      }

      // 2. Si no está en Vimeus, usar Supabase como fallback
      if (sources.isEmpty) {
        final response = await _supabaseService.client
            .from('video_sources')
            .select('stream_url, stream_url_vidsrc, stream_url_2embed, stream_url_superembed')
            .eq('tmdb_id', id)
            .maybeSingle();

        if (response != null) {
          final data = response as Map<String, dynamic>;
          if (data['stream_url'] != null) {
            sources.add({'name': 'Servidor Alternativo 1', 'url': data['stream_url']});
          }
          if (data['stream_url_vidsrc'] != null) {
            sources.add({'name': 'VIP Mirror 1', 'url': data['stream_url_vidsrc']});
          }
          if (data['stream_url_2embed'] != null) {
            sources.add({'name': 'VIP Mirror 2', 'url': data['stream_url_2embed']});
          }
          if (data['stream_url_superembed'] != null) {
            sources.add({'name': 'Servidor Directo', 'url': data['stream_url_superembed']});
          }
        }
      }

      return sources.where((s) => (s['url'] as String).trim().isNotEmpty).toList();
    } catch (e) {
      debugPrint('[ContentService] ❌ Error obteniendo fuentes de película $tmdbId: $e');
      return [];
    }
  }
}
