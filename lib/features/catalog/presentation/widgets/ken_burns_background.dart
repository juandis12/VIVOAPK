import 'package:flutter/material.dart';

class KenBurnsBackground extends StatefulWidget {
  final String imageUrl;
  final Widget? child;

  const KenBurnsBackground({
    super.key,
    required this.imageUrl,
    this.child,
  });

  @override
  State<KenBurnsBackground> createState() => _KenBurnsBackgroundState();
}

class _KenBurnsBackgroundState extends State<KenBurnsBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _moveAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _moveAnimation = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(-0.02, -0.02),
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(
                MediaQuery.of(context).size.width * _moveAnimation.value.dx,
                MediaQuery.of(context).size.height * _moveAnimation.value.dy,
              ),
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => Container(color: Colors.black),
          ),
        ),
        // Overlay degradado para legibilidad (Estilo XPTV)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.7),
                const Color(0xFF060912), // AppTheme.background
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}
