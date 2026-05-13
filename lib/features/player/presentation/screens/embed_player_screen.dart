import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';
import 'package:vivoweb_flutter/services/session_service.dart';
import 'package:vivoweb_flutter/services/achievements_service.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class EmbedPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String tmdbId;
  final String type;
  final String profileId;
  final int? season;
  final int? episode;
  final int initialSeek;
  final int? runtime;

  const EmbedPlayerScreen({
    super.key,
    required this.url,
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
  State<EmbedPlayerScreen> createState() => _EmbedPlayerScreenState();
}

class _EmbedPlayerScreenState extends State<EmbedPlayerScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isMiniPlayer = false;
  bool _forceReset = false; // Hack para Video Beam/TV Box
  OverlayEntry? _overlayEntry;

  // Progreso basado en tiempo real de visualización (cronómetro)
  Timer? _progressTimer;
  Timer? _nextEpCountdownTimer;
  int _elapsedSeconds = 0;

  // Siguiente episodio
  bool _showNextEpOverlay = false;
  bool _nextEpTriggered = false;
  int _nextEpCountdown = 10;
  Map<String, dynamic>? _nextEpisodeData;


  final SupabaseService _supabaseService = SupabaseService();
  final SessionService _sessionService = SessionService();

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Track gamificación (XP)
    AchievementsService().track('play_video', payload: {
      'type': widget.type,
      'tmdb_id': widget.tmdbId,
    });
    
    WakelockPlus.enable();

    // Iniciar desde el progreso guardado (cronómetro interno)
    _elapsedSeconds = widget.initialSeek;

    _initController();
    _startProgressTracking();
    _sessionService.updateProfileTelemetry({
      'tmdb_id': widget.tmdbId,
      'title': widget.title,
      'last_seen': DateTime.now().toIso8601String(),
    });

    if (widget.type == 'tv' &&
        widget.season != null &&
        widget.episode != null) {
      _prefetchNextEpisode();
    }
  }



  // ─── WEBVIEW ────────────────────────────────────────────────────────────────

  void _initController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params);

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            // Intentar forzar autoplay, silenciar y ocultar overlays de carga/poster
            _controller.runJavaScript(
              """
              (function() {
                const videos = document.querySelectorAll('video');
                videos.forEach(v => {
                  v.play().catch(e => console.log('Autoplay blocked'));
                  v.muted = false;
                  v.style.display = 'block';
                  v.style.opacity = '1';
                });
                
                // Intentar detectar y remover el 'poster' o overlays que bloquean la imagen
                const commonOverlays = [
                  '.vjs-poster', '.vjs-big-play-button', '.ytp-cued-thumbnail-overlay',
                  '[class*="poster"]', '[class*="overlay"]', '[class*="play-button"]',
                  '.jw-preview', '.jw-display-icon-container'
                ];
                commonOverlays.forEach(selector => {
                  document.querySelectorAll(selector).forEach(el => el.style.display = 'none');
                });
              })();
              """
            );
          },
          onWebResourceError: (e) {
            // Solo marcar error fatal si es el recurso principal (falla de carga de la web)
            // Ignoramos errores de recursos secundarios como anuncios bloqueados o scripts.
            // Si isForMainFrame no está disponible, usamos una validación por URL.
            final bool isMainError = e.isForMainFrame ?? (e.url == widget.url);

            if (isMainError) {
              debugPrint(
                  '[EmbedPlayer] Critical WebView error: ${e.description}');
              if (mounted) setState(() => _hasError = true);
            } else {
              debugPrint(
                  '[EmbedPlayer] Non-critical resource error: ${e.description}');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_buildSeekUrl(widget.url, widget.initialSeek)));

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    // Forzar User-Agent de escritorio para evitar que los proveedores bloqueen 
    // o muestren placeholders estáticos en pantallas grandes/projectores.
    _controller.setUserAgent(
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
    );
  }

  // Lógica para reiniciar la superficie (útil en Video Beam/TV Boxes)
  void _resetWebView() {
    if (mounted) {
      setState(() => _forceReset = true);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _forceReset = false);
      });
    }
  }

  void _toggleMiniPlayer() {
    setState(() => _isMiniPlayer = !_isMiniPlayer);

    if (_isMiniPlayer) {
      // Entrar en modo mini
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      _showFloatingPlayer();
      context.pop(); // Salir de la pantalla completa
    }
  }

  void _showFloatingPlayer() {
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 50,
        right: 20,
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 200,
            height: 120,
            color: Colors.black,
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                Positioned(
                  top: 5,
                  right: 5,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () {
                      _overlayEntry?.remove();
                      _overlayEntry = null;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Inyecta seek time en la URL según el proveedor detectado.
  String _buildSeekUrl(String url, int seekSeconds) {
    if (seekSeconds <= 0) return url;
    final cleanUrl = url.trim();

    // Vimeo oficial
    if (cleanUrl.contains('vimeo.com') && !cleanUrl.contains('vimeos.net')) {
      return cleanUrl.contains('#') ? cleanUrl : '$cleanUrl#t=${seekSeconds}s';
    }

    // YouTube embed
    if (cleanUrl.contains('youtube.com/embed') ||
        cleanUrl.contains('youtu.be')) {
      final sep = cleanUrl.contains('?') ? '&' : '?';
      return '$cleanUrl${sep}start=$seekSeconds&autoplay=1';
    }

    // .html embeds (vimeos.net, vimeus.com, goodstream, etc.) — best-effort
    if (cleanUrl.contains('.html') ||
        cleanUrl.contains('embed') ||
        cleanUrl.contains('vimeus.com') ||
        cleanUrl.contains('/e/')) {
      final sep = cleanUrl.contains('?') ? '&' : '?';
      return '$cleanUrl${sep}t=$seekSeconds&start=$seekSeconds';
    }

    // Fallback
    final sep = cleanUrl.contains('?') ? '&' : '?';
    return '$cleanUrl${sep}t=$seekSeconds';
  }

  // ─── PROGRESO (CRONÓMETRO) ────────────────────────────────────────────────────
  // Para embeds no podemos leer currentTime del iframe por CORS.
  // Usamos un cronómetro interno que cuenta desde initialSeek.

  void _startProgressTracking() {
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      _elapsedSeconds += 5;
      _saveProgress(_elapsedSeconds);

      // Detectar "casi terminado" para siguiente episodio e isWatched
      final int runtimeMin = widget.runtime ?? (widget.type == 'movie' ? 120 : 45);
      final int estimatedTotal = runtimeMin * 60;
      
      if (_nextEpisodeData != null && !_nextEpTriggered) {
        final remaining = estimatedTotal - _elapsedSeconds;
        if (remaining <= 120 && !_showNextEpOverlay) {
          setState(() => _showNextEpOverlay = true);
        }
        if (remaining <= 0) {
          _nextEpTriggered = true;
          _playNextEpisode();
        }
      }
    });
  }

  Future<void> _saveProgress(int seconds) async {
    if (!mounted) return;

    // Fase Precision: Marcar como visto al 85%
    final int runtimeMin = widget.runtime ?? (widget.type == 'movie' ? 120 : 45);
    final int estimatedTotal = runtimeMin * 60;
    final bool isWatched = seconds >= (estimatedTotal * 0.85);

    try {
      final user = _supabaseService.client.auth.currentUser;
      if (user == null) return;

      await _supabaseService.client.from('watch_history').upsert({
        'user_id': user.id,
        'profile_id': widget.profileId,
        'tmdb_id': widget.tmdbId,
        'type': widget.type,
        'season_number': widget.season ?? 0,
        'episode_number': widget.episode ?? 0,
        'progress_seconds': seconds,
        'is_watched': isWatched,
        'last_watched': DateTime.now().toIso8601String(),
      }, onConflict: 'profile_id, tmdb_id, season_number, episode_number');

      // Track gamificación (XP) si se completó el contenido
      if (isWatched) {
        AchievementsService().track('complete_content', payload: {
          'type': widget.type,
          'tmdb_id': widget.tmdbId,
        });
      }
    } catch (e) {
      debugPrint('[EmbedPlayer] Error guardando progreso: $e');
    }
  }

  // ─── SIGUIENTE EPISODIO ────────────────────────────────────────────────────────

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
            '[EmbedPlayer] Siguiente ep: T${data['season_number']}E${data['episode_number']}');
      }
    } catch (e) {
      debugPrint('[EmbedPlayer] Error prefetch next: $e');
    }
  }

  void _startNextEpCountdown() {
    _nextEpCountdown = 10;
    _nextEpCountdownTimer?.cancel();
    _nextEpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _nextEpCountdown--);
      if (_nextEpCountdown <= 0) {
        t.cancel();
        _playNextEpisode();
      }
    });
  }

  void _cancelNextEpisode() {
    _nextEpCountdownTimer?.cancel();
    _nextEpTriggered = true;
    if (mounted) setState(() => _showNextEpOverlay = false);
  }

  Future<void> _playNextEpisode() async {
    final next = _nextEpisodeData;
    if (next == null || !mounted) return;

    _nextEpCountdownTimer?.cancel();
    await _saveProgress(_elapsedSeconds);
    if (mounted) setState(() => _showNextEpOverlay = false);

    final nextSeason = next['season_number'] as int;
    final nextEpisode = next['episode_number'] as int;
    final nextUrl = next['stream_url'] as String;
    final isEmbed = nextUrl.contains('.html') ||
        nextUrl.contains('embed') ||
        nextUrl.contains('vimeo') ||
        nextUrl.contains('youtube');

    if (!mounted) return;

    final route = isEmbed ? '/embed-player' : '/player';
    context.pushReplacement(route, extra: {
      'streamUrl': nextUrl,
      'title':
          '${widget.title.split(' - ').first} - T${nextSeason}E$nextEpisode',
      'tmdbId': widget.tmdbId,
      'type': widget.type,
      'profileId': widget.profileId,
      'season': nextSeason,
      'episode': nextEpisode,
      'initialSeek': 0,
      if (isEmbed) 'url': nextUrl,
    });
  }

  // ─── DISPOSE ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _progressTimer?.cancel();
    _nextEpCountdownTimer?.cancel();
    _saveProgress(_elapsedSeconds);
    _sessionService.updateProfileTelemetry(null);
    WakelockPlus.disable();
    _overlayEntry?.remove();
    _overlayEntry = null;
    
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!_forceReset)
            RepaintBoundary(
              child: WebViewWidget(controller: _controller),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),

          // Loader
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),

          // Botón volver
          Positioned(
            top: 40,
            left: 16,
            child: SafeArea(
              child: IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: () => context.pop(),
              ),
            ),
          ),

          // Botón de Refresco (Hack para Video Beam / TV Box)
          Positioned(
            top: 40,
            right: 20,
            child: SafeArea(
              child: _TVPlayerButton(
                icon: Icons.refresh,
                onPressed: _resetWebView,
                label: 'Refrescar Imagen',
              ),
            ),
          ),

          // Overlay de Error de Contenido (Estamos solucionando...)
          if (_hasError)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(30),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const Icon(Icons.movie_filter_outlined,
                              color: AppTheme.accent, size: 40),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'CONTENIDO NO DISPONIBLE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Lo sentimos, este servidor externo no está respondiendo correctamente. Intentaremos habilitar fuentes alternativas pronto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => context.pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                              ),
                              child: const Text('VOLVER'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _hasError = false;
                                  _isLoading = true;
                                });
                                _controller.reload();
                              },
                              child: const Text('REINTENTAR'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Overlay "Siguiente Episodio"
          if (!_hasError && _showNextEpOverlay && _nextEpisodeData != null)
            Positioned(
              bottom: 70,
              right: 16,
              child: _NextEpisodeCard(
                nextEpData: _nextEpisodeData!,
                countdown: _nextEpCountdown,
                onPlayNow: _playNextEpisode,
                onCancel: _cancelNextEpisode,
                onVisible: _startNextEpCountdown,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── WIDGET compartido: Tarjeta de Siguiente Episodio ───────────────────────────

class _NextEpisodeCard extends StatefulWidget {
  final Map<String, dynamic> nextEpData;
  final int countdown;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;
  final VoidCallback onVisible;

  const _NextEpisodeCard({
    required this.nextEpData,
    required this.countdown,
    required this.onPlayNow,
    required this.onCancel,
    required this.onVisible,
  });

  @override
  State<_NextEpisodeCard> createState() => _NextEpisodeCardState();
}

class _NextEpisodeCardState extends State<_NextEpisodeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
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
      opacity: _fade,
      child: Container(
        width: 270,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.90),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SIGUIENTE EPISODIO',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Temporada $season • Episodio $episode',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
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
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: Text(
                      'Reproducir (${widget.countdown}s)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: widget.onCancel,
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 18),
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

// ─── WIDGET: Botón focusable para TV/Control Remoto ───────────────────────────

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : Colors.black45,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _isFocused ? AppTheme.accent : Colors.white24),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                        color: AppTheme.accent.withOpacity(0.4), blurRadius: 10)
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  color: _isFocused ? Colors.black : Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
