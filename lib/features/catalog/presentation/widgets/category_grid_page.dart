import 'package:flutter/material.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/content_model.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:vivoweb_flutter/features/catalog/presentation/widgets/content_widgets.dart';
import 'package:go_router/go_router.dart';

class CategoryGridPage extends StatefulWidget {
  final String title;
  final String categoryType; // 'movie', 'tv', 'anime'

  const CategoryGridPage({
    super.key,
    required this.title,
    required this.categoryType,
  });

  @override
  State<CategoryGridPage> createState() => _CategoryGridPageState();
}

class _CategoryGridPageState extends State<CategoryGridPage> {
  final ContentService _contentService = ContentService();
  final ScrollController _scrollController = ScrollController();

  List<ContentModel> _allItems = [];
  List<ContentModel> _displayedItems = [];
  List<ContentModel> _popular = [];
  List<ContentModel> _topRated = [];
  List<ContentModel> _action = [];
  List<ContentModel> _comedy = [];
  List<ContentModel> _romance = [];
  List<ContentModel> _horror = [];

  bool _isLoading = true;
  int _currentLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didUpdateWidget(CategoryGridPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryType != widget.categoryType) {
      _loadInitialData();
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _contentService.initialize();
    _loadMoreData();
  }

  Future<void> _loadMoreData() async {
    // ── CARGA LAZY (PROGRESIVA) ──────────────────────────────────────────────
    // Paso 1: Cargamos 'Populares' primero y lo mostramos de INMEDIATO
    // Paso 2: El resto de secciones carga en segundo plano y se va añadiendo

    try {
      // Primer fetch: Popular (lo más importante, se muestra enseguida)
      final popular =
          await _contentService.getPopularDatabase(widget.categoryType);
      if (!mounted) return;
      setState(() {
        _popular = popular;
        _isLoading = false; // Ya podemos mostrar algo
      });
    } catch (e) {
      debugPrint('[CategoryGrid] Error cargando popular: $e');
      if (mounted) setState(() => _isLoading = false);
    }

    // Paso 2: Cargar el resto en paralelo, cada sección actualiza la UI al llegar
    await Future.wait([
      _contentService.getDatabaseContent(widget.categoryType).then((items) {
        if (mounted) {
          setState(() {
            _allItems = items;
            _displayedItems = _allItems.take(_currentLimit).toList();
          });
        }
      }).catchError((e) {
        debugPrint('[CategoryGrid] Error allItems: $e');
        return null;
      }),
      _contentService.getTopRatedDatabase(widget.categoryType).then((items) {
        if (mounted) setState(() => _topRated = items);
      }).catchError((e) {
        debugPrint('[CategoryGrid] Error topRated: $e');
        return null;
      }),
      _contentService
          .getDatabaseContentByGenre(widget.categoryType, 28)
          .then((items) {
        if (mounted) setState(() => _action = items);
      }).catchError((e) {
        debugPrint('[CategoryGrid] Error action: $e');
        return null;
      }),
      _contentService
          .getDatabaseContentByGenre(widget.categoryType, 35)
          .then((items) {
        if (mounted) setState(() => _comedy = items);
      }).catchError((e) {
        debugPrint('[CategoryGrid] Error comedy: $e');
        return null;
      }),
      _contentService
          .getDatabaseContentByGenre(widget.categoryType, 10749)
          .then((items) {
        if (mounted) setState(() => _romance = items);
      }).catchError((e) {
        debugPrint('[CategoryGrid] Error romance: $e');
        return null;
      }),
      _contentService
          .getDatabaseContentByGenre(widget.categoryType, 27)
          .then((items) {
        if (mounted) setState(() => _horror = items);
      }).catchError((e) {
        debugPrint('[CategoryGrid] Error horror: $e');
        return null;
      }),
    ]);
  }

  void _loadNextBatch() {
    setState(() {
      _currentLimit += 10;
      _displayedItems = _allItems.take(_currentLimit).toList();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppTheme.accent,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            floating: true,
            title: Text(
              widget.title.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 28),
                onPressed: () => context.push('/search'),
              ),
              const SizedBox(width: 16),
            ],
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: AppTheme.accent)),
            )
          else if (_allItems.isEmpty)
            const SliverFillRemaining(
              child: Center(
                  child: Text('No hay contenido disponible',
                      style: TextStyle(color: AppTheme.textSecondary))),
            )
          else
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (_popular.isNotEmpty)
                    ContentCarousel(
                      title: 'Populares',
                      items: _popular,
                      onContentTap: (content) =>
                          context.push('/detail/${content.type}/${content.id}'),
                    ),
                  if (_topRated.isNotEmpty)
                    ContentCarousel(
                      title: 'Mejor Valoradas',
                      items: _topRated,
                      onContentTap: (content) =>
                          context.push('/detail/${content.type}/${content.id}'),
                    ),
                  if (_action.isNotEmpty)
                    ContentCarousel(
                      title: 'Acción Pura y Adrenalina',
                      items: _action,
                      onContentTap: (content) =>
                          context.push('/detail/${content.type}/${content.id}'),
                    ),
                  if (_comedy.isNotEmpty)
                    ContentCarousel(
                      title: 'Para Morirse de Risa',
                      items: _comedy,
                      onContentTap: (content) =>
                          context.push('/detail/${content.type}/${content.id}'),
                    ),
                  if (_romance.isNotEmpty)
                    ContentCarousel(
                      title: 'De Amor',
                      items: _romance,
                      onContentTap: (content) =>
                          context.push('/detail/${content.type}/${content.id}'),
                    ),
                  if (_horror.isNotEmpty)
                    ContentCarousel(
                      title: 'De Terror',
                      items: _horror,
                      onContentTap: (content) =>
                          context.push('/detail/${content.type}/${content.id}'),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'TODAS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!_isLoading && _allItems.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.67,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return ContentCard(
                      content: _displayedItems[index],
                      onTap: () => context.push(
                          '/detail/${_displayedItems[index].type}/${_displayedItems[index].id}'),
                    );
                  },
                  childCount: _displayedItems.length,
                ),
              ),
            ),
          if (!_isLoading && _displayedItems.length < _allItems.length)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: TextButton(
                    onPressed: _loadNextBatch,
                    style: TextButton.styleFrom(
                      backgroundColor: AppTheme.accent.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                    ),
                    child: const Text(
                      'CARGAR MÁS',
                      style: TextStyle(
                          color: AppTheme.accent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
