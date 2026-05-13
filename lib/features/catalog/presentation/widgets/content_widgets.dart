import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/services/tmdb_service.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/skeleton_widgets.dart';

class ContentCard extends StatefulWidget {
  final ContentModel content;
  final VoidCallback onTap;
  final int? rank;

  const ContentCard({
    super.key,
    required this.content,
    required this.onTap,
    this.rank,
  });

  @override
  State<ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<ContentCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final tmdbService = TMDBService();
    final bool isAvailable = ContentService().isAvailable(widget.content.id.toString());

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
           (event.logicalKey == LogicalKeyboardKey.select || 
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.2 : 1.0, // Aumentado para mayor impacto visual
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.rank != null)
                Positioned(
                  left: -50,
                  bottom: -35,
                  child: Text(
                    widget.rank.toString(),
                    style: TextStyle(
                      fontSize: 220, // Más grande para mayor impacto
                      fontWeight: FontWeight.w900,
                      letterSpacing: -15,
                      fontFamily: 'Inter', // Si está disponible, o sans-serif
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 6
                        ..color = Colors.grey[800]!.withOpacity(_isFocused ? 0.9 : 0.7),
                    ),
                  ),
                ),
              AspectRatio(
                aspectRatio: 2 / 3,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4), // Bordes más cuadrados estilo Netflix
                color: _isFocused ? Colors.white10 : Colors.transparent,
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.white.withOpacity(0.05),
                  width: _isFocused ? 3 : 0.8,
                ),
                boxShadow: [
                  if (_isFocused)
                    BoxShadow(
                      color: const Color(0xFFBB86FC).withOpacity(0.5),
                      blurRadius: 35,
                      spreadRadius: 2,
                    ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Hero(
                tag: 'poster-${widget.content.id}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                    imageUrl: tmdbService.getImageUrl(widget.content.posterPath),
                    fit: BoxFit.cover,
                    color: isAvailable ? null : Colors.black.withOpacity(0.4),
                    colorBlendMode: isAvailable ? null : BlendMode.darken,
                    placeholder: (context, url) => const CustomShimmer(),
                    errorWidget: (context, url, error) {
                      ContentService().reportMaintenance(widget.content.id.toString());
                      return Container(
                        color: AppTheme.navy,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.build_circle_outlined, color: AppTheme.accent.withOpacity(0.5), size: 30),
                              const SizedBox(height: 4),
                              const Text(
                                'MANTENIMIENTO',
                                style: TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  
                  // Premium Status Badge (XPTV Style) - Disponible vs Próximamente
                  Positioned(
                    top: widget.rank != null ? null : 10,
                    bottom: widget.rank != null ? 8 : null,
                    left: widget.rank != null ? 0 : 10,
                    right: widget.rank != null ? 0 : null,
                    child: Center(
                      child: AppTheme.glassEffect(
                        blur: 10,
                        opacity: 0.1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: widget.rank != null 
                                  ? Colors.red.withOpacity(0.8)
                                  : (isAvailable 
                                      ? AppTheme.accent.withOpacity(0.4) 
                                      : Colors.white.withOpacity(0.05))
                            ),
                            borderRadius: BorderRadius.circular(2), // Más rectangular estilo Netflix
                            color: widget.rank != null ? Colors.red : Colors.transparent,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.rank == null) ...[
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: isAvailable ? AppTheme.accent : Colors.white38,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                widget.rank != null 
                                    ? 'RECIÉN AGREGADO' 
                                    : (isAvailable ? 'DISPONIBLE' : 'PRÓXIMAMENTE'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Barra de Progreso e indicador "VISTO"
                  if (widget.content.progressSeconds > 10)
                    (() {
                      final totalSecs = widget.content.runtime * 60;
                      final isWatched = totalSecs > 0 && (widget.content.progressSeconds > totalSecs * 0.9);
                      final progressPct = totalSecs > 0 ? (widget.content.progressSeconds / totalSecs) : 0.0;

                      if (isWatched) {
                        return Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check, size: 10, color: AppTheme.background),
                                SizedBox(width: 2),
                                Text('VISTO', style: TextStyle(color: AppTheme.background, fontSize: 8, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      }

                      return Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 4,
                          color: Colors.black26,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progressPct.clamp(0.0, 1.0),
                            child: Container(color: AppTheme.accent),
                          ),
                        ),
                      );
                    })(),
                  
                  // Info Overlay (Netflix Style)
                  if (_isFocused)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.9),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.content.title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '${widget.content.voteAverage.toStringAsFixed(1)} Match',
                                  style: const TextStyle(color: Color(0xFF46D369), fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white24, width: 0.5),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: const Text('HD', style: TextStyle(color: Colors.white70, fontSize: 8)),
                                ),

                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}


class ContentCarousel extends StatelessWidget {
  final String title;
  final List<ContentModel> items;
  final Function(ContentModel) onContentTap;
  final bool isLoading;
  final bool isRanked;

  const ContentCarousel({
    super.key,
    this.title = '',
    required this.items,
    required this.onContentTap,
    this.isLoading = false,
    this.isRanked = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildSkeleton(context);
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 12, 4),
            child: Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {},
                  child: const Text(
                    'VER TODO',
                    style: TextStyle(
                      color: AppTheme.textSecondary, 
                      fontSize: 11, 
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        SizedBox(
          height: isRanked ? 340 : 320, 
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(
              left: isRanked ? 60 : 14, // Espacio para el primer número
              right: 14,
            ),
            clipBehavior: Clip.none, // IMPORTANTE para que el número no se corte
            itemCount: items.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(
                  left: isRanked ? 35 : 0, // Espacio entre items ranked
                ),
                child: ContentCard(
                  content: items[index],
                  onTap: () => onContentTap(items[index]),
                  rank: isRanked ? index + 1 : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 8, top: 20),
          child: Container(
            width: 120,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Container(
                width: 120,
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withOpacity(0.03),
                  border: Border.all(color: Colors.white.withOpacity(0.03)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

