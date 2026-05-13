import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/services/live_service.dart';
import 'package:vivoweb_flutter/services/live_auto_update_service.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/services/tmdb_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class LiveChannelsScreen extends StatefulWidget {
  const LiveChannelsScreen({super.key});

  @override
  State<LiveChannelsScreen> createState() => _LiveChannelsScreenState();
}

class _LiveChannelsScreenState extends State<LiveChannelsScreen>
    with SingleTickerProviderStateMixin {
  final LiveService _liveService = LiveService();
  final ContentService _contentService = ContentService();

  late final WebViewController _controller;
  late final AnimationController _livePulse;

  bool _isPlayerLoading = true;
  String? _currentTitle;
  int _selectedChannelIndex = -1;

  // Auto-update: servicio y suscripción actuales
  LiveAutoUpdateService? _autoUpdateService;
  StreamSubscription? _showChangeSub;

  final Map<String, ContentModel?> _channelShows = {};
  int? _loadedTmdbId;
  
  final List<Map<String, dynamic>> _channels = [
    {'name': 'Risa', 'icon': '😄', 'color': Colors.yellowAccent, 'id': 'risa'},
    {'name': 'Acción', 'icon': '🥊', 'color': Colors.redAccent, 'id': 'action'},
    {'name': 'Terror', 'icon': '👻', 'color': Colors.purpleAccent, 'id': 'horror'},
    {'name': 'Anime', 'icon': '🏮', 'color': Colors.orangeAccent, 'id': 'anime'},
    {'name': 'Familiar', 'icon': '👨‍👩‍👧‍👦', 'color': Colors.blueAccent, 'id': 'family'},
  ];

  @override
  void initState() {
    super.initState();
    _initWebViewController();
    _initLivePulseAnimation();
    _loadInitialShows();
    _autoSelectFirstChannel();
  }

  Future<void> _loadInitialShows() async {
    // Asegurar que el catálogo esté construido
    if (_contentService.dbCatalog.isNotEmpty) {
      _liveService.buildLiveCatalog(_contentService.dbCatalog);
    } else {
      await _contentService.initialize();
      _liveService.buildLiveCatalog(_contentService.dbCatalog);
    }

    for (var channel in _channels) {
      final showResult = _liveService.getCurrentShow(channel['id']);
      if (showResult != null && mounted) {
        // Obtener el modelo completo del contenido para el UI
        final content = _contentService.dbCatalog.firstWhere(
          (c) => c.id == showResult.currentShow.tmdbId,
          orElse: () => ContentModel(
            id: showResult.currentShow.tmdbId,
            title: showResult.currentShow.title,
            type: showResult.currentShow.type,
            posterPath: '',
            backdropPath: '',
            voteAverage: 0.0,
          ),
        );
        setState(() {
          _channelShows[channel['id']] = content;
        });
      }
    }
  }

  // ─── Animación del badge "● EN VIVO" ───────────────────────
  void _initLivePulseAnimation() {
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  // ─── WebView ────────────────────────────────────────────────
  void _initWebViewController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true);
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params);
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isPlayerLoading = true),
          onPageFinished: (_) {
            setState(() => _isPlayerLoading = false);
            // Intento inmediato
            _controller.runJavaScript(
              "document.querySelector('video')?.play();",
            );
            // Segundo intento retrasado — el player interno puede tardar en iniciar
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                _controller.runJavaScript(
                  "document.querySelector('video')?.play();",
                );
              }
            });
          },
        ),
      );

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
  }

  /// Determina si la URL es un video directo (.mp4 / .m3u8) y lo envuelve
  /// en una página HTML con un <video> autoplay. Esto es necesario porque
  /// el WebView no puede reproducir una URL de video directa sin HTML.
  String _buildLoadUrl(String streamUrl) {
    final lower = streamUrl.toLowerCase();
    final isDirectVideo = lower.contains('.mp4') ||
        lower.contains('.m3u8') ||
        lower.contains('.mkv') ||
        lower.contains('.webm');

    if (!isDirectVideo) return streamUrl; // Es una página embed → cargar directo

    // Envuelve el video directo en una página HTML5 minimalista
    return Uri.dataFromString(
      '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin:0; padding:0; background:#000; }
    video { width:100vw; height:100vh; object-fit:contain; }
  </style>
</head>
<body>
  <video autoplay controls playsinline src="$streamUrl"></video>
  <script>document.querySelector('video').play();</script>
</body>
</html>
''',
      mimeType: 'text/html',
      encoding: Encoding.getByName('utf-8'),
    ).toString();
  }

  // ─── Selección automática del primer canal ──────────────────
  Future<void> _autoSelectFirstChannel() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) _selectChannel(0);
  }

  // ─── Seleccionar canal + iniciar auto-update ─────────────────
  Future<void> _selectChannel(int index) async {
    if (_selectedChannelIndex == index) return;

    // Cancelar el auto-update del canal anterior
    _cancelCurrentAutoUpdate();

    setState(() {
      _selectedChannelIndex = index;
      _isPlayerLoading = true;
      _loadedTmdbId = null;
    });

    await _loadChannelContent(index);

    // Iniciar auto-update para el nuevo canal
    _startAutoUpdate(index);
  }

  // ─── Carga del contenido para un canal ─────────────────────
  Future<void> _loadChannelContent(int index, {String? expectedTmdbId}) async {
    final channel = _channels[index];
    final showResult = _liveService.getCurrentShow(channel['id']);
    final content = showResult?.currentShow;

    if (!mounted) return;

    if (content == null) {
      setState(() {
        _isPlayerLoading = false;
        _currentTitle = 'Sin programación disponible';
      });
      return;
    }

    // Si el programa no cambió respecto al cargado, no recargar el player
    if (expectedTmdbId != null && content.tmdbId.toString() == _loadedTmdbId.toString()) return;

    final streamUrl =
        await _contentService.getStreamUrl(content.tmdbId, content.type);

    if (!mounted) return;

    if (streamUrl != null) {
      setState(() {
        _currentTitle = "${channel['name']} — ${content.title}";
        _loadedTmdbId = content.tmdbId;
      });
      _controller.loadRequest(Uri.parse(_buildLoadUrl(streamUrl)));
    } else {
      setState(() {
        _isPlayerLoading = false;
        _currentTitle = 'Enlace no disponible';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace de streaming no encontrado')),
      );
    }
  }

  // ─── Iniciar el servicio de auto-actualización del canal ─────
  void _startAutoUpdate(int index) {
    final channelId = _channels[index]['id'] as String;
    _autoUpdateService = LiveAutoUpdateService(channelId);

    _showChangeSub = _autoUpdateService!.onShowChanged.listen((result) {
      // El programa cambió → recargar el contenido automáticamente
      if (mounted) {
        debugPrint('[LiveAutoUpdate] Cambio detectado en canal $channelId: '
            '${result.currentShow.title}');
        _loadChannelContent(index, expectedTmdbId: result.currentShow.tmdbId.toString());
      }
    });

    _autoUpdateService!.start();
  }

  // ─── Cancelar auto-update anterior ──────────────────────────
  void _cancelCurrentAutoUpdate() {
    _showChangeSub?.cancel();
    _showChangeSub = null;
    _autoUpdateService?.dispose();
    _autoUpdateService = null;
  }

  @override
  void dispose() {
    _cancelCurrentAutoUpdate();
    _livePulse.dispose();
    super.dispose();
  }

  // ─── BUILD ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // 📺 REPRODUCTOR SUPERIOR (MODO TV)
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            color: Colors.black,
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      WebViewWidget(controller: _controller),
                      if (_isPlayerLoading)
                        const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.accent)),
                      if (_selectedChannelIndex == -1)
                        const Center(
                          child: Text(
                            'SELECCIONA UN CANAL',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                // Barra de título con badge ● EN VIVO animado
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  width: double.infinity,
                  color: AppTheme.navy,
                  child: Row(
                    children: [
                      // Badge ● EN VIVO (pulsa cuando hay canal seleccionado)
                      if (_selectedChannelIndex >= 0) ...[
                        AnimatedBuilder(
                          animation: _livePulse,
                          builder: (_, __) => Icon(
                            Icons.circle,
                            size: 10,
                            color: Colors.redAccent
                                .withOpacity(0.4 + _livePulse.value * 0.6),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'EN VIVO',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          _currentTitle ?? 'VivoTv Live',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white, size: 20),
                        onPressed: () => context.push('/search'),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 🎞️ LISTA DE CANALES
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: _channels.length,
              itemBuilder: (context, index) {
                final channel = _channels[index];
                final isSelected = _selectedChannelIndex == index;
                final currentShow = _channelShows[channel['id']];

                return _TVChannelItem(
                  channelName: channel['name'],
                  currentShow: currentShow,
                  color: channel['color'],
                  isSelected: isSelected,
                  onTap: () => _selectChannel(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TVChannelItem extends StatelessWidget {
  final String channelName;
  final ContentModel? currentShow;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _TVChannelItem({
    required this.channelName,
    this.currentShow,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tmdbService = TMDBService();

    return Focus(
      onFocusChange: (focused) {}, // Triggered for D-pad focus
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
           (event.logicalKey == LogicalKeyboardKey.select || 
            event.logicalKey == LogicalKeyboardKey.enter)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return AnimatedScale(
            scale: isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.15)
                    : isFocused ? Colors.white.withOpacity(0.1) : AppTheme.navy.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? color : isFocused ? Colors.white54 : Colors.white.withOpacity(0.05),
                  width: isFocused || isSelected ? 1.5 : 0.8,
                ),
                boxShadow: isFocused ? [
                  BoxShadow(color: color.withOpacity(0.2), blurRadius: 15, spreadRadius: -2)
                ] : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Miniatura del programa actual
                      SizedBox(
                        width: 100,
                        child: currentShow != null
                            ? CachedNetworkImage(
                                imageUrl: tmdbService.getImageUrl(currentShow!.backdropPath ?? currentShow!.posterPath),
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(color: Colors.black26),
                                errorWidget: (context, url, err) => Container(color: Colors.black26),
                              )
                            : Container(
                                color: Colors.black26,
                                child: const Icon(Icons.tv, color: Colors.white12),
                              ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Información
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Canal $channelName'.toUpperCase(),
                                style: TextStyle(
                                  color: isSelected ? color : isFocused ? Colors.white70 : AppTheme.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentShow?.title ?? 'Cargando programación...',
                                style: TextStyle(
                                  color: isFocused ? Colors.white : Colors.white,
                                  fontSize: 14,
                                  fontWeight: isFocused ? FontWeight.w900 : FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
        
                      if (isSelected || isFocused)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Center(
                            child: Icon(
                              isSelected ? Icons.play_circle_fill : Icons.radio_button_checked, 
                              color: isSelected ? color : Colors.white70, 
                              size: 24
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }
}
