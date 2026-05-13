import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:vivoweb_flutter/services/tmdb_service.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/content_widgets.dart';

// ── Mapa de Vibras — idéntico al de la Web ──────────────────────────────────
class VibeOption {
  final String id;
  final String emoji;
  final String label;
  final String desc;
  final Color color;
  final List<int> genres;

  const VibeOption({
    required this.id,
    required this.emoji,
    required this.label,
    required this.desc,
    required this.color,
    required this.genres,
  });
}

const _vibes = [
  VibeOption(id: 'adrenalina', emoji: '⚡', label: 'Adrenalina Total',       desc: 'Acción explosiva y héroes invencibles',    color: Color(0xFFFF4136), genres: [28, 53, 10752]),
  VibeOption(id: 'melancolico', emoji: '🌧', label: 'Noches de Lluvia',      desc: 'Drama profundo, emociones a flor de piel',  color: Color(0xFF5856D6), genres: [18, 10749]),
  VibeOption(id: 'reir',        emoji: '😂', label: 'Modo Carcajadas',        desc: 'Comedias que te harán llorar de risa',      color: Color(0xFFFF9F0A), genres: [35, 10751]),
  VibeOption(id: 'misterio',    emoji: '🔍', label: 'Mente Detectivesca',    desc: 'Thrillers y giros de guion impactantes',    color: Color(0xFF00B4D8), genres: [9648, 80, 53]),
  VibeOption(id: 'terror',      emoji: '👻', label: 'No Puedo Mirar',        desc: 'Terror que te hará dormir con la luz puesta', color: Color(0xFF8B0000), genres: [27]),
  VibeOption(id: 'epico',       emoji: '⚔️', label: 'Épica Cinematográfica', desc: 'Mundos épicos y fantasía pura',             color: Color(0xFFFFD700), genres: [14, 12, 878]),
  VibeOption(id: 'anime',       emoji: '🌸', label: 'Modo Otaku',            desc: 'Los mejores animes del mundo',              color: Color(0xFFFF6B9D), genres: [16]),
  VibeOption(id: 'chill',       emoji: '☁️', label: 'Chill & Relax',         desc: 'Para ver tranquilo sin drama',              color: Color(0xFF34D399), genres: [35, 10751, 10770]),
];

// ── Screen ──────────────────────────────────────────────────────────────────

class VibeEngineScreen extends StatefulWidget {
  const VibeEngineScreen({super.key});

  @override
  State<VibeEngineScreen> createState() => _VibeEngineScreenState();
}

class _VibeEngineScreenState extends State<VibeEngineScreen>
    with TickerProviderStateMixin {
  final ContentService _contentService = ContentService();
  final TMDBService _tmdbService = TMDBService();

  VibeOption? _selectedVibe;
  List<ContentModel> _results = [];
  bool _isLoading = false;

  late AnimationController _titleAnim;
  late AnimationController _cardEntryAnim;

  @override
  void initState() {
    super.initState();
    _titleAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _cardEntryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _titleAnim.dispose();
    _cardEntryAnim.dispose();
    super.dispose();
  }

  Future<void> _selectVibe(VibeOption vibe) async {
    setState(() {
      _selectedVibe = vibe;
      _isLoading = true;
      _results = [];
    });
    _cardEntryAnim.reset();

    try {
      // Buscar por géneros en TMDB (igual que la web)
      final List<ContentModel> all = [];
      for (final genreId in vibe.genres.take(2)) {
        final data = await _tmdbService.fetchFromTMDB('/discover/movie', {
          'with_genres': genreId.toString(),
          'sort_by': 'popularity.desc',
          'page': '1',
        });
        final items = (data['results'] as List? ?? []);
        for (final item in items.take(10)) {
          final model = ContentModel.fromJson(
              Map<String, dynamic>.from(item as Map), 'movie');
          if (!all.any((e) => e.id == model.id)) all.add(model);
        }
        // También buscar series si el género aplica
        if (vibe.id != 'anime') {
          final tvData = await _tmdbService.fetchFromTMDB('/discover/tv', {
            'with_genres': genreId.toString(),
            'sort_by': 'popularity.desc',
            'page': '1',
          });
          final tvItems = (tvData['results'] as List? ?? []);
          for (final item in tvItems.take(6)) {
            final model = ContentModel.fromJson(
                Map<String, dynamic>.from(item as Map), 'tv');
            if (!all.any((e) => e.id == model.id)) all.add(model);
          }
        }
      }

      // Para anime buscar específicamente en TV con género 16
      if (vibe.id == 'anime') {
        final animeData = await _tmdbService.fetchFromTMDB('/discover/tv', {
          'with_genres': '16',
          'sort_by': 'popularity.desc',
          'page': '1',
        });
        final animeItems = (animeData['results'] as List? ?? []);
        for (final item in animeItems.take(15)) {
          final model = ContentModel.fromJson(
              Map<String, dynamic>.from(item as Map), 'tv');
          if (!all.any((e) => e.id == model.id)) all.add(model);
        }
      }

      all.shuffle();
      if (mounted) {
        setState(() {
          _results = all.take(20).toList();
          _isLoading = false;
        });
        _cardEntryAnim.forward();
      }
    } catch (e) {
      debugPrint('[VibeEngine] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Fondo con glow del color de la vibe seleccionada
          if (_selectedVibe != null)
            Positioned(
              top: -100,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                height: 400,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.5),
                    radius: 1.0,
                    colors: [
                      _selectedVibe!.color.withOpacity(0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 8),
                      SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.3),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: _titleAnim, curve: Curves.easeOut)),
                        child: FadeTransition(
                          opacity: _titleAnim,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '🎭 VIBE ENGINE',
                                style: TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                              Text(
                                _selectedVibe == null
                                    ? '¿Cómo te sientes hoy?'
                                    : _selectedVibe!.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_selectedVibe != null) ...[
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedVibe = null;
                            _results = [];
                          }),
                          child: const Text('← Cambiar', style: TextStyle(color: AppTheme.accent)),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Grilla de Vibras (cuando no hay selección)
                if (_selectedVibe == null)
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.4,
                      ),
                      itemCount: _vibes.length,
                      itemBuilder: (context, i) => _VibeCard(
                        vibe: _vibes[i],
                        onTap: () => _selectVibe(_vibes[i]),
                      ),
                    ),
                  ),

                // Resultados
                if (_selectedVibe != null)
                  Expanded(
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  color: _selectedVibe!.color,
                                  strokeWidth: 2,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Buscando la playlist perfecta...',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.65,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final item = _results[i];
                              return AnimatedBuilder(
                                animation: _cardEntryAnim,
                                builder: (context, child) {
                                  final delay = (i * 0.05).clamp(0.0, 0.8);
                                  final progress = (((_cardEntryAnim.value - delay) / (1 - delay)).clamp(0.0, 1.0));
                                  return Opacity(
                                    opacity: progress,
                                    child: Transform.translate(
                                      offset: Offset(0, 20 * (1 - progress)),
                                      child: child,
                                    ),
                                  );
                                },
                                child: GestureDetector(
                                  onTap: () => context.push('/detail/${item.type}/${item.id}'),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          _tmdbService.getImageUrl(item.posterPath),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(color: AppTheme.navy),
                                        ),
                                        // Overlay gradiente con título
                                        Positioned(
                                          bottom: 0, left: 0, right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                                              ),
                                            ),
                                            child: Text(
                                              item.title,
                                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vibe Card Widget ─────────────────────────────────────────────────────────

class _VibeCard extends StatefulWidget {
  final VibeOption vibe;
  final VoidCallback onTap;

  const _VibeCard({required this.vibe, required this.onTap});

  @override
  State<_VibeCard> createState() => _VibeCardState();
}

class _VibeCardState extends State<_VibeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapCancel: () => setState(() => _hovered = false),
      onTapUp: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_hovered ? 0.96 : 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.vibe.color.withOpacity(_hovered ? 0.25 : 0.12),
              Colors.white.withOpacity(0.03),
            ],
          ),
          border: Border.all(
            color: _hovered
                ? widget.vibe.color.withOpacity(0.7)
                : Colors.white.withOpacity(0.08),
            width: _hovered ? 1.5 : 1,
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: widget.vibe.color.withOpacity(0.35), blurRadius: 24, spreadRadius: 2)]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.vibe.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                widget.vibe.label,
                style: TextStyle(
                  color: widget.vibe.color,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.vibe.desc,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 10,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
