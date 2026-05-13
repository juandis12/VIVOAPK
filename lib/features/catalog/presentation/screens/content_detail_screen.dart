import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/models/episode_model.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:vivoweb_flutter/services/tmdb_service.dart';
import 'package:vivoweb_flutter/services/session_service.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/watch_party_guide_dialog.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/ambient_glow_widget.dart';
import 'package:go_router/go_router.dart';
import 'package:vivoweb_flutter/services/watch_party_manager.dart';
import 'package:vivoweb_flutter/services/download_service.dart';


class ContentDetailScreen extends StatefulWidget {
  final String type;
  final String id;

  const ContentDetailScreen({
    super.key,
    required this.type,
    required this.id,
  });

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> with SingleTickerProviderStateMixin {
  late AnimationController _kenBurnsController;
  final ContentService _contentService = ContentService();
  final TMDBService _tmdbService = TMDBService();
  final DownloadService _downloadService = DownloadService();

  ContentModel? _content;
  List<EpisodeModel> _episodes = [];
  int _selectedSeason = 1;
  bool _isLoading = true;
  bool _isLoadingEpisodes = false;
  bool _isFavorite = false;
  
  String get _profileId => SessionService().currentProfile?.id ?? "invitado";

  @override
  void initState() {
    super.initState();
    _kenBurnsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);
    _loadDetails();
  }

  @override
  void dispose() {
    _kenBurnsController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    // ---- WATCH PARTY INTERCEPTOR ----
    if (widget.id == 'party_redirect') {
      await _joinWatchParty();
      return;
    }
    // ---------------------------------

    setState(() => _isLoading = true);
    try {
      final content = await _contentService.getFullDetails(widget.type, int.parse(widget.id));
      final isFav = await _contentService.isFavorite(_profileId, widget.id);
      
      setState(() {
        _content = content;
        _isFavorite = isFav;
        _isLoading = false;
      });

      if (widget.type == 'tv') {
        _loadSeason(1);
      }
    } catch (e) {
      debugPrint('Error loading details: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_content == null) return;
    
    final oldStatus = _isFavorite;
    setState(() => _isFavorite = !oldStatus); 
    
    try {
      await _contentService.toggleFavorite(_profileId, _content!);
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      setState(() => _isFavorite = oldStatus); 
    }
  }



  Future<void> _joinWatchParty() async {
    try {
      setState(() => _isLoading = true);
      // Extraemos partyId desde el GoRouter state (extra cacheado o singleton).
      // Pero como no tenemos extra fácil en initState sin context.read,
      // usaremos un delay para GoRouter o podemos pasarlo por el servicio.
      // FIX TEMPORAL: GoRouter _route extra:
      final extraParams = GoRouterState.of(context).extra as Map<String, dynamic>?;
      final partyId = extraParams?['partyId'] as String?;
      
      if (partyId == null || partyId.isEmpty) throw Exception('No party ID');
      
      final cleanIdString = partyId.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
      String finalId = cleanIdString;
      if (cleanIdString.length == 32 && !cleanIdString.contains('-')) {
        finalId = '${cleanIdString.substring(0,8)}-${cleanIdString.substring(8,12)}-${cleanIdString.substring(12,16)}-${cleanIdString.substring(16,20)}-${cleanIdString.substring(20)}';
      }

      final partyData = await WatchPartyManager().joinParty(finalId, SessionService().currentProfile?.name ?? 'Invitado');
      if (partyData == null) throw Exception('Sala no existe o RLS bloquea acceso');

      // Obtenemos los detalles reales del tmdbId que nos dio la base de datos
      final realTmdbId = partyData['tmdb_id'].toString();
      final content = await _contentService.getFullDetails(partyData['media_type'], int.parse(realTmdbId));
      
      setState(() {
        _content = content;
        _isLoading = false;
      });

      // Show toast
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🎉 Unido a sala Watch Party de ${partyData['creator_name']}!')));
      }

    } catch (e) {
      debugPrint('[WatchParty] Error ingresando a sala: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error: La sala no existe o está cerrada.')));
        context.pop();
      }
    }
  }

  Future<void> _handlePlayClick({EpisodeModel? episode}) async {
    if (_content == null) return;
    
    try {
      debugPrint('[Detail] Iniciando búsqueda de fuentes para: ${widget.id} (${widget.type})');
      
      if (widget.type == 'movie') {
        final tmdbId = int.tryParse(widget.id);
        if (tmdbId == null) throw Exception('ID de TMDB no válido: ${widget.id}');

        // PRIORIDAD 1: Descarga Local
        final localPath = _downloadService.getLocalPath(widget.id);
        if (localPath != null) {
          debugPrint('[Detail] Reproduciendo descarga local segura: $localPath');
          _playContent(localPath);
          return;
        }

        final sources = await _contentService.getMovieSources(tmdbId);
        debugPrint('[Detail] Fuentes encontradas: ${sources.length}');
        
        if (!mounted) return;
        
        if (sources.length > 1) {
          _showSourceSelector(sources);
        } else if (sources.isNotEmpty) {
          final url = sources.first['url'];
          debugPrint('[Detail] Reproduciendo fuente única: $url');
          _playContent(url);
        } else {
          debugPrint('[Detail] No hay fuentes en la DB para esta película.');
          _playContent(null);
        }
      } else {
        debugPrint('[Detail] Reproduciendo episodio: ${episode?.name} - URL: ${episode?.streamUrl}');
        _playContent(episode?.streamUrl, episode: episode);
      }
    } catch (e) {
      debugPrint('[Detail] Error en _handlePlayClick: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar reproducción: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showSourceSelector(List<Map<String, dynamic>> sources) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text('SELECCIONAR SERVIDOR', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
            ),
            ...sources.map((s) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.dns_rounded, color: AppTheme.accent, size: 20),
              ),
              title: Text(s['name'].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(s['url'].contains('vimeus') ? 'Fuente Optimizada' : 'Fuente Alternativa', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: const Icon(Icons.play_arrow_rounded, color: Colors.white24),
              onTap: () {
                Navigator.pop(context);
                _playContent(s['url']);
              },
            )),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Future<void> _playContent(String? streamUrl, {EpisodeModel? episode}) async {
    if (streamUrl == null || _content == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este contenido no está disponible para reproducción')),
      );
      return;
    }

    // Fetch progress before playing
    final progress = await _contentService.getSavedProgress(
      _profileId, 
      widget.id,
      season: episode?.seasonNumber,
      episode: episode?.episodeNumber,
    );
    
    if (!mounted) return;

    if (!mounted) return;

    // Detectar si es un enlace de tipo embed (HTML)
    final isEmbed = streamUrl.contains('embed') || 
                   streamUrl.contains('.html') || 
                   streamUrl.contains('vimeo') || 
                   streamUrl.contains('vimeus') ||
                   streamUrl.contains('/e/');

    if (isEmbed) {
      context.push('/embed-player', extra: {
        'streamUrl': streamUrl,
        'title': episode != null ? '${_content!.title} - E${episode.episodeNumber}' : _content!.title,
        'tmdbId': widget.id,
        'type': widget.type,
        'profileId': _profileId,
        'season': episode?.seasonNumber,
        'episode': episode?.episodeNumber,
        'initialSeek': progress, 
        'runtime': episode?.runtime ?? _content!.runtime, // Pasar duración
      });
    } else {
      context.push('/player', extra: {
        'streamUrl': streamUrl,
        'title': episode != null ? '${_content!.title} - E${episode.episodeNumber}' : _content!.title,
        'tmdbId': widget.id,
        'type': widget.type,
        'season': episode?.seasonNumber,
        'episode': episode?.episodeNumber,
        'profileId': _profileId,
        'initialSeek': progress,
        'runtime': episode?.runtime ?? _content!.runtime, // Pasar duración
      });
    }

  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    if (_content == null) return const Scaffold(body: Center(child: Text('No se pudo cargar el contenido')));

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AmbientGlowWidget(
        posterUrl: _content!.posterPath != null
            ? _tmdbService.getImageUrl(_content!.posterPath)
            : null,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildMainInfo(),
                    const SizedBox(height: 30),
                    _buildActions(),
                    const SizedBox(height: 40),
                    _buildCast(),
                    const SizedBox(height: 40),
                    if (widget.type == 'tv') _buildSeriesSection(),
                    _buildSimilar(),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 350,
      backgroundColor: AppTheme.background,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Ken Burns Effect Image
            AnimatedBuilder(
              animation: _kenBurnsController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_kenBurnsController.value * 0.15),
                  child: CachedNetworkImage(
                    imageUrl: _tmdbService.getImageUrl(_content!.backdropPath),
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
            
            // Adaptive Overlay Layers
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                    AppTheme.background.withOpacity(0.8),
                    AppTheme.background,
                  ],
                  stops: const [0.0, 0.4, 0.8, 1.0],
                ),
              ),
            ),
            
            // XPTV Blur Bottom Transition
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 80,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ColorFilter.mode(
                    AppTheme.background.withOpacity(0.5),
                    BlendMode.darken,
                  ),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _content!.title.toUpperCase(),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
            ),
            if (widget.type == 'movie' && _content!.progressSeconds > (_content!.runtime * 60 * 0.85) && _content!.runtime > 0)
               Container(
                  margin: const EdgeInsets.only(left: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(6)),
                  child: const Text('VISTO', style: TextStyle(color: AppTheme.background, fontSize: 10, fontWeight: FontWeight.bold)),
               ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(_content!.releaseDate?.split('-')[0] ?? '', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(width: 15),
            Text('★ ${_content!.voteAverage.toStringAsFixed(1)}', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
            const SizedBox(width: 15),
            if (_content!.genres.isNotEmpty)
              Text(_content!.genres.first, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          _content!.overview ?? '',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        // Botón Principal: Reproducir (Optimizado)
        Expanded(
          flex: 4,
          child: Material(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(16),
            elevation: 8,
            shadowColor: AppTheme.accent.withOpacity(0.4),
            child: InkWell(
              onTap: () {
                debugPrint('[Detail] Botón Reproducir presionado para ${widget.id}');
                _handlePlayClick(episode: _episodes.isNotEmpty ? _episodes.first : null);
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: AppTheme.background, size: 30),
                    SizedBox(width: 10),
                    Text(
                      'REPRODUCIR',
                      style: TextStyle(
                        color: AppTheme.background,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        
        // Botón: Mi Lista
        _buildCircularBtn(
          icon: _isFavorite ? Icons.check_rounded : Icons.add_rounded,
          color: _isFavorite ? AppTheme.accent : Colors.white,
          onTap: _toggleFavorite,
          tooltip: 'Mi Lista',
        ),
        const SizedBox(width: 12),
        
        // Botón: Compartir
        _buildCircularBtn(
          icon: Icons.share_rounded,
          onTap: () {
            Clipboard.setData(ClipboardData(
                text: 'https://vivoweb-liar.vercel.app/${widget.type}.html?id=${widget.id}'
            ));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Enlace copiado al portapapeles'), backgroundColor: Colors.blue),
            );
          },
          tooltip: 'Compartir',
        ),
        const SizedBox(width: 12),

        // Botón: Descargar (Nuevo)
        if (widget.type == 'movie')
          ListenableBuilder(
            listenable: _downloadService,
            builder: (context, _) {
              final bool downloaded = _downloadService.isDownloaded(widget.id);
              return _buildCircularBtn(
                icon: downloaded ? Icons.download_done_rounded : Icons.download_rounded,
                color: downloaded ? AppTheme.accent : Colors.white,
                onTap: () async {
                  if (downloaded) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Este video ya está descargado.')),
                    );
                  } else {
                    final url = await _contentService.getMovieStreamUrl(int.parse(widget.id));
                    if (url != null) {
                      _downloadService.startDownload(
                        tmdbId: widget.id,
                        title: _content!.title,
                        type: widget.type,
                        url: url,
                        posterPath: _content!.posterPath,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Descarga iniciada...')),
                      );
                    }
                  }
                },
                tooltip: 'Descargar',
              );
            },
          ),
        
        const Spacer(),
        
        // Botón: Info/Ayuda
        _buildCircularBtn(
          icon: Icons.help_outline_rounded,
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => const WatchPartyGuideDialog(),
            );
          },
          tooltip: 'Ayuda',
        ),
      ],
    );
  }

  Widget _buildCircularBtn({
    required IconData icon, 
    required VoidCallback onTap, 
    Color color = Colors.white,
    String? tooltip,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 56,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
      ),
    );
  }

  Widget _buildCast() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('REPARTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _content!.cast.length,
            itemBuilder: (context, index) {
              final actor = _content!.cast[index];
              return Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: actor['profile_path'] != null 
                          ? NetworkImage(_tmdbService.getImageUrl(actor['profile_path']))
                          : null,
                      child: actor['profile_path'] == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 70,
                      child: Text(
                        actor['name'] ?? '',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _loadSeason(int seasonNumber) async {
    setState(() {
      _selectedSeason = seasonNumber;
      _isLoadingEpisodes = true;
    });
    try {
      final episodes = await _contentService.getSeasonEpisodes(
        int.parse(widget.id), 
        seasonNumber,
        profileId: _profileId,
      );
      setState(() {
        _episodes = episodes;
        _isLoadingEpisodes = false;
      });
    } catch (e) {
      debugPrint('Error loading episodes: $e');
      setState(() => _isLoadingEpisodes = false);
    }
  }

  Widget _buildSeriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('EPISODIOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            // FIX: _content!.seasons puede ser 0 si la API ligera no devolvió number_of_seasons
            // En ese caso se muestra mínimo la T1
            children: List.generate((_content!.seasons > 0 ? _content!.seasons : 1), (index) {
              final sn = index + 1;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text('T$sn'),
                  selected: _selectedSeason == sn,
                  onSelected: (val) => _loadSeason(sn),
                  selectedColor: AppTheme.accent,
                  backgroundColor: AppTheme.navy,
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 20),
        if (_isLoadingEpisodes)
          const Center(child: CircularProgressIndicator(color: AppTheme.accent))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _episodes.length,
            itemBuilder: (context, index) {
              final ep = _episodes[index];
              final totalSecs = (ep.runtime ?? 45) * 60;
              final progressPct = totalSecs > 0 ? (ep.progressSeconds / totalSecs) : 0.0;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 70,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                        image: ep.stillPath != null 
                            ? DecorationImage(image: NetworkImage(_tmdbService.getImageUrl(ep.stillPath)), fit: BoxFit.cover)
                            : null,
                      ),
                      child: ep.streamUrl != null 
                        ? Center(child: Icon(Icons.play_circle_fill, color: Colors.white.withOpacity(0.8), size: 30))
                        : null,
                    ),
                    // Badge "VISTO"
                    if (ep.isWatched)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, color: AppTheme.background, size: 10),
                              SizedBox(width: 2),
                              Text('VISTO', style: TextStyle(color: AppTheme.background, fontSize: 8, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    // Barra de Progreso
                    if (!ep.isWatched && ep.progressSeconds > 10)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progressPct.clamp(0.0, 1.0),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: AppTheme.accent,
                                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text('E${ep.episodeNumber}. ${ep.name}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ep.overview ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('${ep.runtime ?? "?"} min', style: TextStyle(color: AppTheme.accent.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                enabled: ep.streamUrl != null,
                trailing: ep.streamUrl != null 
                  ? ListenableBuilder(
                      listenable: _downloadService,
                      builder: (context, _) {
                        final downloaded = _downloadService.isDownloaded(
                          widget.id, 
                          season: ep.seasonNumber, 
                          episode: ep.episodeNumber
                        );
                        return IconButton(
                          icon: Icon(
                            downloaded ? Icons.download_done_rounded : Icons.download_for_offline_outlined,
                            color: downloaded ? AppTheme.accent : Colors.white24,
                            size: 20,
                          ),
                          onPressed: downloaded ? null : () {
                             _downloadService.startDownload(
                               tmdbId: widget.id,
                               title: '${_content!.title} T${ep.seasonNumber} E${ep.episodeNumber}',
                               type: widget.type,
                               url: ep.streamUrl!,
                               posterPath: ep.stillPath ?? _content!.posterPath,
                             );
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text('Descarga iniciada...')),
                             );
                          },
                        );
                      }
                    )
                  : null,
                onTap: () => _handlePlayClick(episode: ep),
              );
            },
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSimilar() {
    final availableSimilar = _content!.similar
        .where((item) => _contentService.isAvailable(item.id.toString()))
        .toList();

    if (availableSimilar.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SIMILARES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.7,
          ),
          itemCount: availableSimilar.length,
          itemBuilder: (context, index) {
            final item = availableSimilar[index];
            return InkWell(
              onTap: () {
                context.pushReplacement('/detail/${widget.type}/${item.id}');
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: _tmdbService.getImageUrl(item.posterPath),
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: AppTheme.navy),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
