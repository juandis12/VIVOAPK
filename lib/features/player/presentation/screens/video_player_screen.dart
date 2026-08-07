import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';
import 'package:vivoweb_flutter/services/session_service.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:go_router/go_router.dart';
import 'package:vivoweb_flutter/services/watch_party_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/features/player/presentation/widgets/social_pulse_overlay.dart';
import 'package:vivoweb_flutter/services/achievements_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String tmdbId;
  final String type;
  final String profileId;
  final int? season;
  final int? episode;
  final int initialSeek;
  final int? runtime; // Nuevo: Duración en minutos

  const VideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.tmdbId,
    required this.type,
    required this.profileId,
    this.season,
    this.episode,
    this.initialSeek = 0,
    this.runtime,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final WebViewController _webController;
  final SupabaseService _supabaseService = SupabaseService();
  final SessionService _sessionService = SessionService();

  Timer? _progressTimer;
  Timer? _nextEpCountdownTimer;
  Timer? _durationCheckTimer;

  // Binge Engine State
  int _introStartTime = 0;
  int _introEndTime = 0;
  double _creditsStartPct = 0.95;
  bool _showSkipIntro = false;
  bool _isBingeLearning = false;


  // Multi-Source State
  List<Map<String, dynamic>> _availableSources = [];
  String? _currentSourceUrl;
  bool _isSwitchingSource = false;

  // Siguiente Episodio State
  Map<String, dynamic>? _nextEpisodeData;
  bool _showNextEpOverlay = false;
  bool _nextEpTriggered = false;
  int _nextEpCountdown = 10;

  // Seek State
  bool _seekApplied = false;

  @override
  void initState() {
    super.initState();
    _currentSourceUrl = widget.streamUrl;
    _loadAvailableSources();

    // Track gamificación (XP)
    AchievementsService().track('play_video', payload: {
      'type': widget.type,
      'tmdb_id': widget.tmdbId,
    });

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WakelockPlus.enable();

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _webController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {
            _applySeek();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('[WebView] Error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentSourceUrl!));

    _checkConcurrency();
    _startProgressTracking();
    _startDurationMonitor();
    _loadBingeMetadata();

    // Pre-cargar el siguiente episodio si es serie
    if (widget.type == 'tv' &&
        widget.season != null &&
        widget.episode != null) {
      _prefetchNextEpisode();
    }

    // ── WATCH PARTY SINC ──
    WatchPartyManager().syncStream.addListener(_onWatchPartySync);
  }



  Future<void> _loadAvailableSources() async {
    final contentService = ContentService();
    try {
      List<Map<String, dynamic>> sources = [];
      if (widget.type == 'movie') {
        sources = await contentService.getMovieSources(int.parse(widget.tmdbId));
      } else if (widget.season != null && widget.episode != null) {
        // Obtener todas las fuentes del episodio desde Supabase
        final response = await _supabaseService.client
            .from('series_episodes')
            .select('stream_url, stream_url_vidsrc, stream_url_2embed, stream_url_superembed')
            .eq('tmdb_id', int.parse(widget.tmdbId))
            .eq('season_number', widget.season!)
            .eq('episode_number', widget.episode!)
            .maybeSingle();

        if (response != null) {
          final candidates = [
            {'name': 'Servidor Principal', 'url': response['stream_url']},
            {'name': 'Servidor VIP 1',     'url': response['stream_url_vidsrc']},
            {'name': 'Servidor VIP 2',     'url': response['stream_url_2embed']},
            {'name': 'Servidor Directo',   'url': response['stream_url_superembed']},
          ];
          sources = candidates
              .where((s) => s['url'] != null && (s['url'] as String).isNotEmpty)
              .toList();
        }
      }

      if (mounted) {
        setState(() => _availableSources = sources);
      }
    } catch (e) {
      debugPrint('[Sources] Error loading servers: $e');
    }
  }

  void _changeSource(String newUrl) async {
    if (newUrl == _currentSourceUrl) return;
    setState(() {
      _isSwitchingSource = true;
      _currentSourceUrl = newUrl;
    });
    try {
      await _webController.loadRequest(Uri.parse(newUrl));
    } catch (e) {
      debugPrint('[Sources] Error switching: $e');
    } finally {
      if (mounted) setState(() => _isSwitchingSource = false);
    }
  }

  Future<void> _loadBingeMetadata() async {
    try {
      final response = await _supabaseService.client
          .from('vivotv_content_metadata')
          .select('*')
          .eq('tmdb_id', widget.tmdbId)
          .eq('content_type', widget.type)
          .maybeSingle();

      if (mounted) {
        if (response != null) {
          setState(() {
            _introStartTime = response['intro_start'] ?? 0;
            _introEndTime = response['intro_end'] ?? 90;
            _creditsStartPct = response['credits_start_pct'] ?? 0.95;
            _isBingeLearning = false;
          });
        } else {
          setState(() {
            _introStartTime = 0;
            _introEndTime = 90;
            _creditsStartPct = 0.95;
            _isBingeLearning = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[Binge] Error loading metadata: $e');
    }
  }

  void _skipIntro() {
    final skipTo = _introEndTime;
    _webController.runJavaScript(
      'if(document.querySelector("video")) document.querySelector("video").currentTime = $skipTo;',
    );
    setState(() => _showSkipIntro = false);
    if (_isBingeLearning) _reportBingeLearning(skipTo);
  }

  Future<void> _reportBingeLearning(int time) async {
    try {
      await _supabaseService.client.from('vivotv_content_metadata').upsert({
        'tmdb_id': widget.tmdbId,
        'content_type': widget.type,
        'intro_start': _introStartTime,
        'intro_end': time,
        'credits_start_pct': _creditsStartPct,
      });
    } catch (e) {
      debugPrint('[Binge] Error reporting learning: $e');
    }
  }

  void _showSourcesMenu() {
    if (_availableSources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay servidores alternativos disponibles.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.navy.withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'SELECCIONAR SERVIDOR',
                    style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _availableSources.length,
                    itemBuilder: (context, index) {
                      final s = _availableSources[index];
                      final bool isCurrent = s['url'] == _currentSourceUrl;
                      return ListTile(
                        leading: Icon(
                          Icons.dns_outlined,
                          color: isCurrent ? AppTheme.accent : Colors.white70,
                        ),
                        title: Text(
                          s['name'],
                          style: TextStyle(
                            color: isCurrent ? AppTheme.accent : Colors.white,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: isCurrent ? const Icon(Icons.check_circle, color: AppTheme.accent) : null,
                        onTap: () {
                          Navigator.pop(context);
                          _changeSource(s['url']);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applySeek() {
    if (widget.initialSeek <= 0 || _seekApplied) return;
    
    final seek = widget.initialSeek;
    debugPrint('[VideoPlayer] Intentando reanudar en segundo: $seek');
    
    // Inyección de JS universal para reproductores basados en HTML5
    _webController.runJavaScript('''
      (function() {
        var v = document.querySelector("video");
        if(v) { 
          v.currentTime = $seek;
          v.play();
        }
        // Soporte para reproductores de terceros comunes (YouTube API / Vimeo)
        if(window.player && typeof window.player.seekTo === "function") window.player.seekTo($seek);
      })();
    ''');
    
    _seekApplied = true;
  }

  // ─── SIGUIENTE EPISODIO ───────────────────────────────────────────────────────

  Future<void> _prefetchNextEpisode() async {
    try {
      final data = await _supabaseService.client
          .from('series_episodes')
          .select('season_number, episode_number, stream_url')
          .eq('tmdb_id', widget.tmdbId)
          .or('and(season_number.eq.${widget.season},episode_number.gt.${widget.episode}),season_number.gt.${widget.season}')
          .order('season_number', ascending: true)
          .order('episode_number', ascending: true)
          .limit(1)
          .maybeSingle();

      if (data != null && data['stream_url'] != null) {
        _nextEpisodeData = data;
        debugPrint(
            '[VideoPlayer] Siguiente episodio listo: T${data['season_number']}E${data['episode_number']}');
      }
    } catch (e) {
      debugPrint('[VideoPlayer] Error prefetch next episode: $e');
    }
  }


  void _showNextEpisodeCountdown() {
    _nextEpCountdown = 10;
    _nextEpCountdownTimer?.cancel();
    _nextEpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _nextEpCountdown--);
      if (_nextEpCountdown <= 0) {
        timer.cancel();
        _playNextEpisode();
      }
    });
  }

  void _cancelNextEpisode() {
    _nextEpCountdownTimer?.cancel();
    _nextEpTriggered = true; // No auto-play
    if (mounted) setState(() => _showNextEpOverlay = false);
  }

  Future<void> _playNextEpisode() async {
    final next = _nextEpisodeData;
    if (next == null || !mounted) return;

    _nextEpCountdownTimer?.cancel();
    if (mounted) setState(() => _showNextEpOverlay = false);

    await _saveProgress();

    final nextSeason = next['season_number'] as int;
    final nextEpisode = next['episode_number'] as int;
    final nextUrl = next['stream_url'] as String;
    final nextTitle = '${widget.title} - T${nextSeason}E$nextEpisode';

    if (!mounted) return;

    // Reemplazar la pantalla actual con el siguiente episodio
    context.pushReplacement('/player', extra: {
      'streamUrl': nextUrl,
      'title': nextTitle,
      'tmdbId': widget.tmdbId,
      'type': widget.type,
      'profileId': widget.profileId,
      'season': nextSeason,
      'episode': nextEpisode,
      'initialSeek': 0,
    });
  }

  /// Monitorea el tiempo transcurrido para mostrar el overlay de siguiente episodio
  void _startDurationMonitor() {
    _durationCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || _nextEpTriggered) return;
      if (_nextEpisodeData == null) return;

      // Al no tener duración total, mostramos el botón después de 20 minutos de reproducción
      if (_secondsWatched >= 1200 && !_showNextEpOverlay) {
        if (mounted) setState(() => _showNextEpOverlay = true);
      }
    });
  }

  // ─── PROGRESO Y TELEMETRÍA ────────────────────────────────────────────────────

  void _onWatchPartySync() {
    // La sincronización precisa de tiempo no es posible en WebView sin inyección de JS específica.
    // Se mantiene el listener para cerrar la sala si el host la cierra.
    final wpState = WatchPartyManager().syncStream.value;
    if (wpState == null || !mounted || WatchPartyManager().isHost) return;

    if (wpState.currentTime == -1 && wpState.timestamp == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El Host ha cerrado la sala.'), backgroundColor: Colors.red),
        );
        Navigator.of(context).pop();
      }
    }
  }

  // ─── PROGRESO Y TELEMETRÍA ────────────────────────────────────────────────────

  int _secondsWatched = 0;

  void _startProgressTracking() {
    _secondsWatched = widget.initialSeek;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _secondsWatched++;
        
        // Control de Skip Intro
        if (_secondsWatched >= _introStartTime && _secondsWatched <= _introEndTime) {
          if (!_showSkipIntro) setState(() => _showSkipIntro = true);
        } else {
          if (_showSkipIntro) setState(() => _showSkipIntro = false);
        }

        if (_secondsWatched % 5 == 0) {
          _saveProgress();
          _updateTelemetry();
        }
      }
    });
  }

  Future<void> _updateTelemetry() async {
    await _sessionService.updateProfileTelemetry({
      'title': widget.title,
      'tmdb_id': widget.tmdbId,
      'type': widget.type,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _saveProgress() async {
    final user = _supabaseService.client.auth.currentUser;
    if (user == null) return;

    // Fase Precision: Marcamos como visto al 85% de la duración estimada
    final int runtimeMin = widget.runtime ?? (widget.type == 'movie' ? 120 : 45);
    final int estimatedTotal = runtimeMin * 60;
    bool isWatched = _secondsWatched >= (estimatedTotal * 0.85); 

    try {
      await _supabaseService.client.from('watch_history').upsert({
        'user_id': user.id,
        'profile_id': widget.profileId,
        'tmdb_id': widget.tmdbId,
        'type': widget.type,
        'season_number': widget.season,
        'episode_number': widget.episode,
        'progress_seconds': _secondsWatched,
        'is_watched': isWatched,
        'last_watched': DateTime.now().toIso8601String(),
      }, onConflict: 'profile_id,tmdb_id,season_number,episode_number');

      // Track gamificación (XP) si se completó el contenido
      if (isWatched) {
        AchievementsService().track('complete_content', payload: {
          'type': widget.type,
          'tmdb_id': widget.tmdbId,
        });
      }
    } catch (e) {
      debugPrint('[Player] Error saving progress: $e');
    }
  }


  // ─── CONCURRENCIA ─────────────────────────────────────────────────────────────

  Future<void> _checkConcurrency() async {
    final allowed = await _sessionService.isSessionAllowed();
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Límite de dispositivos excedido. Cerrando...'),
          backgroundColor: Colors.red,
        ),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) context.pop();
      });
    }
  }

  // ─── DISPOSE ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _progressTimer?.cancel();
    _durationCheckTimer?.cancel();
    _nextEpCountdownTimer?.cancel();
    _saveProgress();
    _sessionService.updateProfileTelemetry(null);
    WakelockPlus.disable();
    WatchPartyManager().syncStream.removeListener(_onWatchPartySync);
    
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _webController.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: RepaintBoundary(
              child: WebViewWidget(controller: _webController),
            ),
          ),

          // Indicador de carga al cambiar de servidor
          if (_isSwitchingSource)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            ),

          // Controles en la parte superior
          Positioned(
            top: 20,
            right: 20,
            child: Row(
              children: [
                _TVPlayerButton(
                  icon: Icons.dns_rounded,
                  onPressed: _showSourcesMenu,
                  label: 'Servidores',
                ),
                const SizedBox(width: 12),
                _TVPlayerButton(
                  icon: Icons.open_in_browser,
                  onPressed: () async {
                    if (_currentSourceUrl != null) {
                      await launchUrl(
                        Uri.parse(_currentSourceUrl!), 
                        mode: Platform.isIOS ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication,
                      );
                    }
                  },
                  label: Platform.isIOS ? 'Navegador Interno' : 'Navegador Externo',
                ),
                const SizedBox(width: 12),
                _TVPlayerButton(
                  icon: Icons.refresh,
                  onPressed: () => _webController.reload(),
                  label: 'Refrescar',
                ),
                const SizedBox(width: 12),
                _TVPlayerButton(
                  icon: Icons.close,
                  onPressed: () => context.pop(),
                  label: 'Salir',
                ),
              ],
            ),
          ),

          // ── OVERLAY: Siguiente Episodio ───────────────────────────────────
          if (_showNextEpOverlay && _nextEpisodeData != null)
            Positioned(
              bottom: 80,
              right: 20,
              child: _NextEpisodeOverlay(
                nextEpData: _nextEpisodeData!,
                countdown: _nextEpCountdown,
                onPlayNow: _playNextEpisode,
                onCancel: _cancelNextEpisode,
                onVisible: _showNextEpisodeCountdown,
              ),
            ),

          // ── OVERLAY: Skip Intro ──────────────────────────────────────────
          if (_showSkipIntro)
            Positioned(
              bottom: 80,
              left: 20,
              child: _GlassButton(
                icon: Icons.fast_forward_rounded,
                label: 'Omitir Intro',
                onPressed: _skipIntro,
                color: Colors.white,
              ),
            ),

          // ── OVERLAY: Social Pulse — Reacciones en Tiempo Real ─────────
          if (widget.profileId.isNotEmpty)
            SocialPulseOverlay(
              tmdbId: widget.tmdbId,
              type: widget.type,
              profileId: widget.profileId,
            ),
        ],
      ),
    );
  }

}

// ─── WIDGET: Overlay de Siguiente Episodio ─────────────────────────────────────

class _NextEpisodeOverlay extends StatefulWidget {
  final Map<String, dynamic> nextEpData;
  final int countdown;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;
  final VoidCallback onVisible;

  const _NextEpisodeOverlay({
    required this.nextEpData,
    required this.countdown,
    required this.onPlayNow,
    required this.onCancel,
    required this.onVisible,
  });

  @override
  State<_NextEpisodeOverlay> createState() => _NextEpisodeOverlayState();
}

class _NextEpisodeOverlayState extends State<_NextEpisodeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    // Iniciar el contador regresivo
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onVisible());
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final season = widget.nextEpData['season_number'];
    final episode = widget.nextEpData['episode_number'];

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SIGUIENTE EPISODIO',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Temporada $season • Episodio $episode',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onPlayNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Reproducir (${widget.countdown}s)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onCancel,
                  icon:
                      const Icon(Icons.close, color: Colors.white60, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget de botón focusable para el reproductor (TV)
class _TVPlayerButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String label;

  const _TVPlayerButton({
    required this.icon,
    required this.onPressed,
    required this.label,
  });

  @override
  State<_TVPlayerButton> createState() => _TVPlayerButtonState();
}

class _TVPlayerButtonState extends State<_TVPlayerButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : Colors.black45,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _isFocused ? AppTheme.accent : Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  color: _isFocused ? Colors.black : Colors.white, size: 18),
              if (_isFocused) ...[
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── WIDGET: Botón Glassmorphism para Skip Intro ──────────────────────────────

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
