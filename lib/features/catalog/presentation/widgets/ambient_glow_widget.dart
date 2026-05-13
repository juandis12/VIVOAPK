import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// AmbientGlowWidget
/// Extrae el color dominante de un póster y aplica un glow ambiental
/// alrededor del contenido, igual al AmbientGlow de la Web.
///
/// Uso:
/// ```dart
/// AmbientGlowWidget(
///   posterUrl: content.posterUrl,
///   child: MyContentWidget(),
/// )
/// ```
class AmbientGlowWidget extends StatefulWidget {
  final String? posterUrl;
  final Widget child;
  final double glowRadius;
  final double glowOpacity;

  const AmbientGlowWidget({
    super.key,
    required this.posterUrl,
    required this.child,
    this.glowRadius = 280,
    this.glowOpacity = 0.45,
  });

  @override
  State<AmbientGlowWidget> createState() => _AmbientGlowWidgetState();
}

class _AmbientGlowWidgetState extends State<AmbientGlowWidget>
    with SingleTickerProviderStateMixin {
  Color _glowColor = Colors.transparent;
  Color _targetColor = Colors.transparent;
  late AnimationController _colorAnimCtrl;
  late Animation<Color?> _colorAnim;

  @override
  void initState() {
    super.initState();
    _colorAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _colorAnim = ColorTween(begin: Colors.transparent, end: Colors.transparent)
        .animate(CurvedAnimation(parent: _colorAnimCtrl, curve: Curves.easeInOut));

    if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty) {
      _extractColor(widget.posterUrl!);
    }
  }

  @override
  void didUpdateWidget(AmbientGlowWidget old) {
    super.didUpdateWidget(old);
    if (old.posterUrl != widget.posterUrl && widget.posterUrl != null) {
      _extractColor(widget.posterUrl!);
    }
  }

  @override
  void dispose() {
    _colorAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _extractColor(String url) async {
    try {
      final imageProvider = CachedNetworkImageProvider(url);
      final config = ImageConfiguration.empty;

      final ImageStream stream = imageProvider.resolve(config);
      final completer = Completer<ImageInfo>();
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        completer.complete(info);
        stream.removeListener(listener);
      }, onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      });
      stream.addListener(listener);

      final imageInfo = await completer.future;
      final byteData = await imageInfo.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null || !mounted) return;

      final color = _dominantColor(byteData, imageInfo.image.width, imageInfo.image.height);
      _animateTo(color);
    } catch (e) {
      debugPrint('[AmbientGlow] Error extrayendo color: $e');
    }
  }

  Color _dominantColor(ByteData data, int w, int h) {
    // Muestrear 12 puntos estratégicos (esquinas + bordes + centro)
    final samples = [
      [0.1, 0.1], [0.5, 0.1], [0.9, 0.1],
      [0.1, 0.5], [0.5, 0.5], [0.9, 0.5],
      [0.1, 0.9], [0.5, 0.9], [0.9, 0.9],
      [0.3, 0.3], [0.7, 0.3], [0.5, 0.7],
    ];

    double r = 0, g = 0, b = 0;
    int count = 0;

    for (final s in samples) {
      final px = (s[0] * w).floor().clamp(0, w - 1);
      final py = (s[1] * h).floor().clamp(0, h - 1);
      final idx = (py * w + px) * 4;
      if (idx + 2 >= data.lengthInBytes) continue;

      final pr = data.getUint8(idx);
      final pg = data.getUint8(idx + 1);
      final pb = data.getUint8(idx + 2);
      final brightness = (pr + pg + pb) / 3;

      // Ignorar píxeles muy oscuros o muy claros (fondo/blanco)
      if (brightness > 25 && brightness < 230) {
        r += pr; g += pg; b += pb;
        count++;
      }
    }

    if (count == 0) return const Color(0xFF7B2FBE);

    // Saturar para efecto más cinemático
    final avgR = (r / count).round();
    final avgG = (g / count).round();
    final avgB = (b / count).round();

    final hslColor = HSLColor.fromColor(Color.fromARGB(255, avgR, avgG, avgB));
    return hslColor
        .withSaturation((hslColor.saturation * 1.6).clamp(0.0, 1.0))
        .withLightness(0.4)
        .toColor();
  }

  void _animateTo(Color color) {
    if (!mounted) return;
    _colorAnim = ColorTween(begin: _glowColor, end: color)
        .animate(CurvedAnimation(parent: _colorAnimCtrl, curve: Curves.easeInOut));
    _colorAnimCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() => _glowColor = color);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnim,
      builder: (context, child) {
        final c = _colorAnim.value ?? _glowColor;
        return Stack(
          children: [
            // Glow ambiental (capa de fondo)
            Positioned(
              top: -60,
              left: 0,
              right: 0,
              child: Container(
                height: widget.glowRadius,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.5),
                    radius: 1.2,
                    colors: [
                      c.withOpacity(widget.glowOpacity),
                      c.withOpacity(widget.glowOpacity * 0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            // Glow secundario esquina derecha (profundidad)
            Positioned(
              top: 0,
              right: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      c.withOpacity(widget.glowOpacity * 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Contenido encima
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
