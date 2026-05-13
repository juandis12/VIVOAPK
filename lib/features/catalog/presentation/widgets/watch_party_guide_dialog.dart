import 'package:flutter/material.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';

class WatchPartyGuideDialog extends StatefulWidget {
  const WatchPartyGuideDialog({super.key});

  @override
  State<WatchPartyGuideDialog> createState() => _WatchPartyGuideDialogState();
}

class _WatchPartyGuideDialogState extends State<WatchPartyGuideDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _steps = [
    {
      'title': '¡Bienvenido a Watch Party!',
      'text': 'Ahora puedes disfrutar de tus películas favoritas con amigos en tiempo real, sin importar dónde estén.',
      'image': 'assets/images/info-help-btn.png',
    },
    {
      'title': '1. Crea tu Sala',
      'text': 'Haz clic en el botón de Watch Party en cualquier película. Tú serás el anfitrión y controlarás la reproducción.',
      'image': 'assets/images/info-help-btn.png',
    },
    {
      'title': '2. Comparte el Enlace',
      'text': 'Copia el enlace generado y envíalo a tus amigos. Solo necesitan tener una cuenta activa para unirse.',
      'image': 'assets/images/info-help-btn.png',
    },
    {
      'title': '3. ¡Listos para la Acción!',
      'text': 'Cuando tus amigos se unan, la reproducción se sincronizará automáticamente. ¡Disfruten la función!',
      'image': 'assets/images/info-help-btn.png',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppTheme.navy,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.navy.withOpacity(0.9),
              const Color(0xFF131A33),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withOpacity(0.2),
              blurRadius: 40,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header / Close button
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ),
            ),

            // Content (Carousel)
            SizedBox(
              height: 380,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withOpacity(0.2),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            step['image']!,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          step['title']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          step['text']!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentPage == index ? 24 : 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index ? AppTheme.accent : Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 30),

            // Footer Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 40),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (_currentPage > 0)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ElevatedButton(
                              onPressed: () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Anterior'),
                            ),
                          ),
                        ),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_currentPage < _steps.length - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 8,
                            shadowColor: AppTheme.accent.withOpacity(0.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(_currentPage == _steps.length - 1 ? '¡Entendido!' : 'Siguiente'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Saltar tour',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
