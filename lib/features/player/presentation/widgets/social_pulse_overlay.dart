import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';

/// Reacciones disponibles — mismas que la Web
const _reactions = [
  {'id': 'fire',  'emoji': '🔥', 'label': 'Épico'},
  {'id': 'laugh', 'emoji': '😂', 'label': 'Gracioso'},
  {'id': 'sad',   'emoji': '😢', 'label': 'Triste'},
  {'id': 'shock', 'emoji': '😱', 'label': 'Shock'},
  {'id': 'love',  'emoji': '❤️', 'label': 'Amor'},
  {'id': 'mind',  'emoji': '🤯', 'label': 'Impactante'},
];

/// SocialPulseOverlay
/// Widget que muestra la barra de reacciones en tiempo real sobre el player.
/// Sincroniza reacciones via Supabase Realtime Broadcast.
///
/// Uso — añadir como overlay en VideoPlayerScreen:
/// ```dart
/// SocialPulseOverlay(
///   tmdbId: widget.tmdbId,
///   type: widget.type,
///   profileId: widget.profileId,
/// )
/// ```
class SocialPulseOverlay extends StatefulWidget {
  final String tmdbId;
  final String type;
  final String profileId;

  const SocialPulseOverlay({
    super.key,
    required this.tmdbId,
    required this.type,
    required this.profileId,
  });

  @override
  State<SocialPulseOverlay> createState() => _SocialPulseOverlayState();
}

class _SocialPulseOverlayState extends State<SocialPulseOverlay>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  // Contadores por reacción
  final Map<String, int> _counts = {for (final r in _reactions) r['id']!: 0};

  // Emojis flotantes
  final List<_FloatingEmoji> _floaters = [];

  // Mensajes de chat
  final List<Map<String, String>> _messages = [];
  bool _showChatInput = false;
  final TextEditingController _chatCtrl = TextEditingController();

  // Throttle de envío
  DateTime _lastSent = DateTime(2000);

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _subscribeRealtime();
    _loadInitialCounts();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _loadInitialCounts() async {
    try {
      final data = await _supabase
          .from('content_reactions')
          .select('reaction_id')
          .eq('tmdb_id', widget.tmdbId);

      if (!mounted) return;
      final Map<String, int> newCounts = {for (final r in _reactions) r['id']!: 0};
      for (final row in data as List) {
        final id = row['reaction_id'] as String?;
        if (id != null && newCounts.containsKey(id)) {
          newCounts[id] = (newCounts[id] ?? 0) + 1;
        }
      }
      setState(() => _counts.addAll(newCounts));
    } catch (e) {
      debugPrint('[SocialPulse] Error cargando conteos: $e');
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('social_pulse_${widget.tmdbId}')
        .onBroadcast(
          event: 'reaction',
          callback: (payload) {
            final senderId = payload['profile_id'] as String?;
            if (senderId == widget.profileId) return; // ignorar propias
            final emoji = payload['emoji'] as String?;
            final id = payload['reaction_id'] as String?;
            if (emoji != null) _spawnFloater(emoji, isOwn: false);
            if (id != null && mounted) {
              setState(() => _counts[id] = (_counts[id] ?? 0) + 1);
            }
          },
        )
        .onBroadcast(
          event: 'chat',
          callback: (payload) {
            final username = payload['username'] as String? ?? 'Anónimo';
            final text = payload['text'] as String? ?? '';
            _addChatMessage(username, text);
          },
        )
        .subscribe();
  }

  void _addChatMessage(String username, String text) {
    if (!mounted) return;
    setState(() {
      _messages.add({'username': username, 'text': text});
      if (_messages.length > 5) _messages.removeAt(0);
    });
  }

  void _sendChatMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;

    final profile = await _supabase.from('vivotv_profiles').select('name').eq('id', widget.profileId).single();
    final username = profile['name'] as String? ?? 'Tú';

    _channel?.sendBroadcastMessage(
      event: 'chat',
      payload: {
        'username': username,
        'text': text,
      },
    );

    _addChatMessage('Tú', text);
    _chatCtrl.clear();
    setState(() => _showChatInput = false);
  }

  Future<void> _sendReaction(String reactionId, String emoji) async {
    final now = DateTime.now();
    if (now.difference(_lastSent).inSeconds < 1) return;
    _lastSent = now;

    // Feedback visual inmediato (optimistic)
    _spawnFloater(emoji, isOwn: true);
    if (mounted) setState(() => _counts[reactionId] = (_counts[reactionId] ?? 0) + 1);

    // Broadcast a otros
    _channel?.sendBroadcastMessage(
      event: 'reaction',
      payload: {
        'profile_id': widget.profileId,
        'tmdb_id': widget.tmdbId,
        'reaction_id': reactionId,
        'emoji': emoji,
      },
    );

    // Guardar en DB (fire-and-forget)
    _supabase.from('content_reactions').insert({
      'profile_id': widget.profileId,
      'tmdb_id': widget.tmdbId,
      'type': widget.type,
      'reaction_id': reactionId,
      'reacted_at': DateTime.now().toIso8601String(),
    }).catchError((_) {});
  }

  void _spawnFloater(String emoji, {required bool isOwn}) {
    if (!mounted || _floaters.length > 15) return; // Límite de seguridad para evitar sobrecarga de GPU
    final floater = _FloatingEmoji(
      emoji: emoji,
      x: 0.1 + (DateTime.now().millisecondsSinceEpoch % 80) / 100,
      isOwn: isOwn,
    );
    setState(() => _floaters.add(floater));

    // Remover después de la animación (Reducido a 2s para liberar memoria rápido)
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _floaters.remove(floater));
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Stack(
        children: [
          // Emojis flotantes envueltos en RepaintBoundary para ahorro de batería
          RepaintBoundary(
            child: Stack(
              children: _floaters.map((f) => _FloatingEmojiWidget(floater: f)).toList(),
            ),
          ),

          // Visualización de Chat (Mini)
          Positioned(
            left: 20,
            bottom: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _messages.map((m) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: '${m['username']}: ', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                      TextSpan(text: m['text'], style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              )).toList(),
            ),
          ),

          // Barra de reacciones y botón de chat
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botón para abrir chat
                  GestureDetector(
                    onTap: () => setState(() => _showChatInput = !_showChatInput),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withOpacity(0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _reactions.map((r) {
                        final id = r['id']!;
                        final emoji = r['emoji']!;
                        final count = _counts[id] ?? 0;
                        return _ReactionButton(
                          emoji: emoji,
                          count: count,
                          onTap: () => _sendReaction(id, emoji),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Input de Chat (cuando está activo)
          if (_showChatInput)
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatCtrl,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Comentar...',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendChatMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppTheme.accent),
                      onPressed: _sendChatMessage,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Botón de Reacción ─────────────────────────────────────────────────────────

class _ReactionButton extends StatefulWidget {
  final String emoji;
  final int count;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.emoji,
    required this.count,
    required this.onTap,
  });

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    _scaleCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 2),
              Text(
                widget.count > 0 ? '${widget.count}' : '',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Emoji Flotante ─────────────────────────────────────────────────────────────

class _FloatingEmoji {
  final String emoji;
  final double x;     // posición horizontal 0.0–1.0
  final bool isOwn;
  _FloatingEmoji({required this.emoji, required this.x, required this.isOwn});
}

class _FloatingEmojiWidget extends StatefulWidget {
  final _FloatingEmoji floater;
  const _FloatingEmojiWidget({required this.floater});

  @override
  State<_FloatingEmojiWidget> createState() => _FloatingEmojiWidgetState();
}

class _FloatingEmojiWidgetState extends State<_FloatingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _yAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..forward();

    _yAnim = Tween(begin: 0.0, end: -200.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _fadeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final x = widget.floater.x * screenW;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Positioned(
        bottom: 80 - _yAnim.value,
        left: x,
        child: Opacity(
          opacity: _fadeAnim.value,
          child: Text(
            widget.floater.emoji,
            style: TextStyle(
              fontSize: widget.floater.isOwn ? 28 : 22,
            ),
          ),
        ),
      ),
    );
  }
}
