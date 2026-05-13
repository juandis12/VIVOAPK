import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/hero_banner.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/content_widgets.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/screens/live_channels_screen.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/category_grid_page.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/glass_nav_bar.dart';
import 'package:vivoweb_flutter/services/session_service.dart';
import 'package:vivoweb_flutter/core/utils/avatar_resolver.dart';
import 'package:vivoweb_flutter/services/app_update_service.dart';
import 'package:go_router/go_router.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/skeleton_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ContentService _contentService = ContentService();
  bool _isLoading = true;
  bool _isRefreshing = false;
  ContentModel? _heroContent;
  int _currentIndex = 0;
  final List<Map<String, dynamic>> _dynamicSections = [];
  StreamSubscription? _updateSubscription;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    // Iniciar heartbeat periódico (equivalente al de la web, cada 15s)
    // Esto mantiene la sesión registrada y detecta límites de concurrencia
    SessionService().startPeriodicHeartbeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService().checkForUpdate(context);
      _syncProfileFromCloud();
    });
    
    // Escuchar actualizaciones de contenido (Realtime)
    _updateSubscription = _contentService.onContentUpdate.listen(_handleRealtimeEvent);
  }

  @override
  void dispose() {
    // Detener el heartbeat cuando el usuario sale del dashboard
    SessionService().stopPeriodicHeartbeat();
    _updateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _syncProfileFromCloud() async {
    final currentProfile = SessionService().currentProfile;
    if (currentProfile == null) return;

    try {
      final updated = await SessionService().getLatestProfileData(currentProfile.id);
      if (updated != null && mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[Sync] Error sincronizando perfil: $e');
    }
  }

  void _handleRealtimeEvent(String event) {
    if (event == 'favorites' || event == 'history' || event == 'availability') {
      _refreshDashboard();
    } else if (event.startsWith('handover:')) {
      final parts = event.split(':');
      if (parts.length >= 3) {
        final tmdbId = parts[1];
        final progress = int.parse(parts[2]);
        _showHandoverNotification(tmdbId, progress);
      }
    }
  }

  void _showHandoverNotification(String tmdbId, int progress) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.devices, color: AppTheme.accent),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '¿Continuar viendo en este dispositivo?',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.navy.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'REANUDAR',
          textColor: AppTheme.accent,
          onPressed: () {
            // UX-01 FIX: El seek se pasa como `extra` en GoRouter, no como
            // query param. La pantalla de detalle lo recibe y lo reenvió al player.
            context.push('/detail/movie/$tmdbId', extra: {'seek': progress});
          },
        ),
      ),
    );
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    await _contentService.initialize();
    
    // 1. Cargar secciones instantáneas desde el caché si existen
    await _prepareDynamicSections();
    
    if (mounted) {
      setState(() => _isLoading = false);
    }

    // 2. Refrescar en segundo plano con datos nuevos y aleatorios
    _refreshDashboard();
  }

  Future<void> _refreshDashboard() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    
    try {
      await _prepareDynamicSections();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _prepareDynamicSections() async {
    // Definimos qué secciones queremos mostrar
    final genres = [
      {'id': 28, 'name': 'Acción y Adrenalina', 'emoji': '💥'},
      {'id': 35, 'name': 'Para Morirse de Risa', 'emoji': '😂'},
      {'id': 27, 'name': 'Noches de Terror', 'emoji': '👻'},
      {'id': 878, 'name': 'Ciencia Ficción', 'emoji': '🚀'},
      {'id': 16, 'name': 'Anime y Animación', 'emoji': '🏮'},
      {'id': 10749, 'name': 'Historias de Amor', 'emoji': '❤️'},
      {'id': 53, 'name': 'Suspenso e Intriga', 'emoji': '🕵️'},
    ];

    // Mezclamos y tomamos 4 géneros aleatorios para el dashboard
    genres.shuffle();
    final selectedGenres = genres.take(4).toList();

    // ── RENDERIZADO PROGRESIVO ───────────────────────────────────────────────
    if (mounted) {
      setState(() => _dynamicSections.clear());
    }

    final profileId = SessionService().currentProfile?.id ?? "";

    // PERF-01/02: Ejecutar consultas base en paralelo para reducir latencia inicial
    final results = await Future.wait([
      _contentService.getTrendingContent(),
      if (profileId.isNotEmpty) _contentService.getWatchHistory(profileId) else Future.value(<ContentModel>[]),
      if (profileId.isNotEmpty) _contentService.getMyList(profileId) else Future.value(<ContentModel>[]),
    ]);

    final trending = results[0];
    final history = (results.length > 1) ? results[1] : <ContentModel>[];
    final myList = (results.length > 2) ? results[2] : <ContentModel>[];

    if (mounted) {
      setState(() {
        if (trending.isNotEmpty) {
          _heroContent = trending[0];
          _dynamicSections.add({
            'title': 'Las 10 series más populares en Colombia hoy', 
            'items': trending.take(10).toList(),
            'isRanked': true
          });
        }
        
        if (history.isNotEmpty) {
          _dynamicSections.add({'title': '⏰ Continuar Viendo', 'items': history});
        }
        if (myList.isNotEmpty) {
          _dynamicSections.add({'title': '❤️ Mi Lista', 'items': myList});
        }
      });
    }

    // 1.5 Cargar lo más reciente de la DB independientemente de TMDB
    await _loadRecentlyAddedSection();

    // 3. PERF-02: Géneros — recolectar TODOS los resultados en paralelo
    final genreResults = await Future.wait(
      selectedGenres.map((genre) async {
        try {
          final items = await _contentService.getDatabaseContentByGenre(
              'movie', genre['id'] as int);
          if (items.isNotEmpty) {
            return <String, dynamic>{
              'title': '${genre['emoji']} ${genre['name']}',
              'items': items,
            };
          }
        } catch (e) {
          debugPrint('[Dashboard] Error cargando género ${genre['name']}: $e');
        }
        return null;
      }),
    );

    if (mounted) {
      setState(() {
        _dynamicSections.addAll(genreResults.whereType<Map<String, dynamic>>());
      });
    }
  }

  Future<void> _loadRecentlyAddedSection() async {
    try {
      final recent = await _contentService.getRecentlyAdded();
      if (recent.isNotEmpty && mounted) {
        setState(() {
          _dynamicSections.insert(
            (_dynamicSections.isNotEmpty && _dynamicSections[0]['title'].contains('Tendencias')) ? 1 : 0, 
            {'title': '✨ Agregados Recientemente', 'items': recent}
          );
        });
      }
    } catch (e) {
      debugPrint('[Dashboard] Error cargando recientes: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_currentIndex == 0) {
      body = _buildHome();
    } else if (_currentIndex == 1) {
      body = const CategoryGridPage(title: 'Películas', categoryType: 'movie');
    } else if (_currentIndex == 2) {
      body = const CategoryGridPage(title: 'Series', categoryType: 'series');
    } else if (_currentIndex == 3) {
      body = const CategoryGridPage(title: 'Anime', categoryType: 'anime');
    } else {
      body = const LiveChannelsScreen();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          Container(decoration: AppTheme.backgroundDecoration),
          body,
        ],
      ),
      bottomNavigationBar: FloatingGlassNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }

  Widget _buildProfileAvatarWidget() {
    final profile = SessionService().currentProfile;
    final imageProvider = AvatarResolver.resolve(profile?.avatarUrl);

    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      onSelected: (value) async {
        if (value == 'switch') {
          context.go('/profiles');
        } else if (value == 'logout') {
          await SessionService().logout();
          if (mounted) context.go('/auth');
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.accent, size: 16),
              const SizedBox(width: 8),
              Text(
                SessionService().currentProfile?.name ?? 'Usuario',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'switch',
          child: Row(
            children: [
              Icon(Icons.people_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Cambiar Perfil', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.redAccent),
              SizedBox(width: 12),
              Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.accent, width: 1.5),
          color: AppTheme.accent.withOpacity(0.1),
          image: imageProvider != null ? DecorationImage(image: imageProvider, fit: BoxFit.cover) : null,
        ),
        child: imageProvider == null 
          ? Center(
              child: Text(
                (profile?.name.isNotEmpty == true) ? profile!.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            )
          : null,
      ),
    );
  }

  void _showJoinPartyDialog(BuildContext context) {
    final TextEditingController linkCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.navy,
          title: const Text('🎉 Unirse a Watch Party', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: linkCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Pega el Link o ID de la Sala',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () {
                Navigator.pop(context);
                final text = linkCtrl.text.trim();
                if (text.isEmpty) return;

                String partyId = text;
                if (text.contains('party=')) {
                  partyId = text.split('party=')[1].split('&')[0];
                }

                // Navegar a pantalla en modo Watch Party Guest
                context.push('/detail/movie/party_redirect', extra: {
                  'partyId': partyId,
                });
              },
              child: const Text('Ingresar'),
            ),
          ],
        );
      },
    );
  }


  Widget _buildHome() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppTheme.accent,
      backgroundColor: AppTheme.navy,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            floating: true,
            centerTitle: false,
            title: const Text(
              'VivoTv',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w900,
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
            actions: [
              // 🎭 Vibe Engine — Descubrimiento por estado de ánimo
              IconButton(
                icon: const Text('🎭', style: TextStyle(fontSize: 22)),
                tooltip: '¿Cómo te sientes hoy?',
                onPressed: () => context.push('/vibe-engine'),
              ),
              IconButton(
                icon: const Icon(Icons.group_add_outlined, color: Colors.purpleAccent, size: 28),
                tooltip: 'Unirse a Watch Party',
                onPressed: () => _showJoinPartyDialog(context),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 28), 
                onPressed: () => context.push('/search'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.download_for_offline_rounded, color: Colors.white, size: 28),
                tooltip: 'Mis Descargas',
                onPressed: () => context.push('/downloads'),
              ),
              const SizedBox(width: 8),
              _buildProfileAvatarWidget(),
              const SizedBox(width: 16),
            ],
          ),

          SliverToBoxAdapter(
            child: _isLoading && _dynamicSections.isEmpty
              ? const DashboardSkeleton()
              : Column(
                  children: [
                    if (_heroContent != null)
                      HeroBanner(
                        content: _heroContent!,
                        onPlay: () => context.push('/detail/${_heroContent!.type}/${_heroContent!.id}'),
                        onInfo: () => context.push('/detail/${_heroContent!.type}/${_heroContent!.id}'),
                      ),
                    
                    const SizedBox(height: 10),

                    // Renderización de secciones dinámicas
                    ..._dynamicSections.map((section) => ContentCarousel(
                      title: section['title'] as String,
                      items: List<ContentModel>.from(section['items']),
                      isRanked: section['isRanked'] ?? false,
                      onContentTap: (content) => context.push('/detail/${content.type}/${content.id}'),
                    )),

                    const SizedBox(height: 100),
                  ],
                ),
          ),
        ],
      ),
    );
  }
}
