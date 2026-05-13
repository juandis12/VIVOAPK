import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/services/tmdb_service.dart';

class HeroBanner extends StatelessWidget {
  final ContentModel content;
  final VoidCallback onPlay;
  final VoidCallback onInfo;

  const HeroBanner({
    super.key,
    required this.content,
    required this.onPlay,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final tmdbService = TMDBService();

    return SizedBox(
      height: size.height * 0.72,
      width: double.infinity,
      child: Stack(
        children: [
          // Backdrop Image with higher resolution if possible
          CachedNetworkImage(
            imageUrl: tmdbService.getImageUrl(content.backdropPath, size: 'original'),
            imageBuilder: (context, imageProvider) => Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: imageProvider,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            placeholder: (context, url) => Container(color: AppTheme.background),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),

          // Enhanced Gradients (Top for logo readability, Bottom for content blending)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.transparent,
                    Colors.transparent,
                    AppTheme.background.withOpacity(0.9),
                    AppTheme.background,
                  ],
                  stops: const [0.0, 0.25, 0.5, 0.9, 1.0],
                ),
              ),
            ),
          ),

          // Content Info
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag "EL ESTRENO MÁS ESPERADO"
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'EL ESTRENO MÁS ESPERADO',
                    style: TextStyle(
                      color: AppTheme.background,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Title
                Text(
                  content.title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Metadata Row
                Row(
                  children: [
                    Text(
                      content.releaseDate?.split('-')[0] ?? '',
                      style: const TextStyle(
                        color: AppTheme.textSecondary, 
                        fontSize: 14,
                        fontWeight: FontWeight.w600
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '4K ULTRA HD',
                        style: TextStyle(
                          color: AppTheme.textSecondary, 
                          fontSize: 10,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.star, color: AppTheme.accent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      content.voteAverage.toStringAsFixed(1),
                      style: const TextStyle(
                        color: AppTheme.accent, 
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Description
                SizedBox(
                  width: size.width * 0.9,
                  child: Text(
                    content.overview ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                
                // Buttons
                Row(
                  children: [
                    // Primary Play Button
                    Expanded(
                      flex: 5,
                      child: ElevatedButton(
                        onPressed: onPlay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.background,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow, size: 28),
                            SizedBox(width: 8),
                            Text(
                              'Ver Ahora',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Glass Info Button
                    Expanded(
                      flex: 5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: InkWell(
                            onTap: onInfo,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.15)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.info_outline, size: 24, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Información',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

