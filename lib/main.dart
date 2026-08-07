import 'package:flutter/material.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';
import 'package:vivoweb_flutter/features/auth/presentation/screens/auth_screen.dart';
import 'package:vivoweb_flutter/features/auth/presentation/screens/register_screen.dart';
import 'package:vivoweb_flutter/features/profiles/presentation/screens/profile_selection_screen.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/screens/dashboard_screen.dart';
import 'package:vivoweb_flutter/services/session_service.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/screens/content_detail_screen.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/screens/search_screen.dart';
import 'package:vivoweb_flutter/features/player/presentation/screens/video_player_screen.dart';
import 'package:vivoweb_flutter/features/player/presentation/screens/embed_player_screen.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/screens/vibe_engine_screen.dart';
import 'package:vivoweb_flutter/services/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:vivoweb_flutter/services/download_service.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/screens/downloads_screen.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/screens/performance_settings_screen.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Registrar handler de segundo plano
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 2. Inicialización de servicios con captura de errores fatal
  try {
    final supabaseService = SupabaseService();
    await supabaseService.initialize();
    await SessionService().initialize();
    
    // Iniciar notificaciones (requiere google-services.json)
    await PushNotificationService().initialize();
  } catch (e) {
    debugPrint('Fatal initialization error: $e');
  }

  runApp(const VivoTVApp());
}

final GoRouter _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/profiles',
      builder: (context, state) => ProfileSelectionScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/detail/:type/:id',
      builder: (context, state) => ContentDetailScreen(
        type: state.pathParameters['type']!,
        id: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/player',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return VideoPlayerScreen(
          streamUrl: extra['streamUrl']!,
          title: extra['title'] ?? '',
          tmdbId: extra['tmdbId'] ?? '',
          type: extra['type'] ?? 'movie',
          profileId: extra['profileId'] ?? '',
          season: extra['season'] as int?,
          episode: extra['episode'] as int?,
          initialSeek: extra['initialSeek'] ?? 0,
        );
      },
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/downloads',
      builder: (context, state) => const DownloadsScreen(),
    ),
    GoRoute(
      path: '/vibe-engine',
      builder: (context, state) => const VibeEngineScreen(),
    ),
    GoRoute(
      path: '/embed-player',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return EmbedPlayerScreen(
          url: extra['streamUrl']!,
          title: extra['title'] ?? '',
          tmdbId: extra['tmdbId'] ?? '',
          type: extra['type'] ?? 'movie',
          profileId: extra['profileId'] ?? '',
          season: extra['season'] as int?,
          episode: extra['episode'] as int?,
          initialSeek: extra['initialSeek'] ?? 0,
        );
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const PerformanceSettingsScreen(),
    ),
  ],
);

class VivoTVApp extends StatelessWidget {
  const VivoTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DownloadService()),
      ],
      child: MaterialApp.router(
        title: 'VivoTv',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          physics: const BouncingScrollPhysics(),
          scrollbars: false,
        ),
        routerConfig: _router,
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Future.microtask(() async {
      final supabase = SupabaseService().client;
      final session = supabase.auth.currentSession;
      if (session != null) {
        context.go('/profiles');
      } else {
        context.go('/auth');
      }
    });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill, size: 80, color: AppTheme.accent),
            const SizedBox(height: 20),
            Text(
              'VivoTv',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
