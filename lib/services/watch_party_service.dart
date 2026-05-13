import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';

class WatchPartyService {
  static final WatchPartyService _instance = WatchPartyService._internal();
  factory WatchPartyService() => _instance;
  WatchPartyService._internal();

  final SupabaseClient _supabase = SupabaseService().client;
  RealtimeChannel? _channel;

  bool _isHost = false;
  String? _currentPartyId;

  // Callbacks para la UI
  Function(double time, bool isPlaying)? onSyncReceived;
  Function(String emote, String sender)? onEmoteReceived;

  /// Crea una nueva sala de Watch Party.
  /// tmdbId ahora es int para paridad con el motor de Live y el ContentModel.
  Future<String?> createParty(
      int tmdbId, String mediaType, String profileName) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('vivotv_watch_parties')
          .insert({
            'creator_id': userId,
            'creator_name': profileName,
            'tmdb_id': tmdbId
                .toString(), // Lo guardamos como string en DB por flexibilidad
            'media_type': mediaType,
            'is_playing': false,
            'room_time': 0,
          })
          .select()
          .single();

      _currentPartyId = response['id'];
      _isHost = true;
      _initChannel(_currentPartyId!, profileName);

      return _currentPartyId;
    } catch (e) {
      debugPrint('[WatchParty] Error creando sala: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> joinParty(
      String partyId, String profileName) async {
    try {
      final response = await _supabase
          .from('vivotv_watch_parties')
          .select()
          .eq('id', partyId)
          .maybeSingle();

      if (response == null) return null;

      _currentPartyId = partyId;
      _isHost = false;
      _initChannel(partyId, profileName);

      return response;
    } catch (e) {
      debugPrint('[WatchParty] Error uniéndose a sala: $e');
      return null;
    }
  }

  void _initChannel(String partyId, String profileName) {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }

    // Configurar canal con broadcast habilitado
    _channel = _supabase.channel('party:$partyId',
        opts: const RealtimeChannelConfig(ack: true));

    _channel!
        .onBroadcast(
            event: 'sync',
            callback: (payload) {
              // Solo los invitados sincronizan su tiempo con el host
              if (!_isHost && onSyncReceived != null) {
                final time = (payload['currentTime'] ?? 0).toDouble();
                final isPlaying = payload['isPlaying'] ?? false;
                onSyncReceived!(time, isPlaying);
              }
            })
        .onBroadcast(
            event: 'emote',
            callback: (payload) {
              // Todos reciben emotes de todos
              if (onEmoteReceived != null) {
                onEmoteReceived!(payload['emote']?.toString() ?? '🎬',
                    payload['sender']?.toString() ?? 'Usuario');
              }
            })
        .subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint(
            '[WatchParty] ✅ Conectado a la sala party:$partyId como ${_isHost ? "HOST" : "GUEST"}');

        // Track presence (Opcional por ahora, útil para ver lista de usuarios)
        _channel!.track({
          'user': profileName,
          'online_at': DateTime.now().toIso8601String(),
        });
      }
      if (error != null) {
        debugPrint('[WatchParty] ❌ Error en suscripción Realtime: $error');
      }
    });
  }

  /// Envía el estado de reproducción actual a todos los invitados.
  void broadcastSync(double currentTime, bool isPlaying) {
    if (!_isHost || _channel == null) return;

    // Usamos dynamic para evitar errores de compilación con RealtimeListenTypes
    // Este método es compatible con Supabase 1.x y 2.x
    try {
      (_channel as dynamic).send(
        type: 'broadcast',
        event: 'sync',
        payload: {
          'currentTime': currentTime,
          'isPlaying': isPlaying,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      debugPrint('[WatchParty] Error en broadcastSync: $e');
    }
  }

  /// Envía un emote/reacción a toda la sala.
  void broadcastEmote(String emote, String profileName) {
    if (_channel == null) return;

    try {
      (_channel as dynamic).send(
        type: 'broadcast',
        event: 'emote',
        payload: {
          'emote': emote,
          'sender': profileName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      debugPrint('[WatchParty] Error en broadcastEmote: $e');
    }
  }

  Future<void> leaveParty() async {
    try {
      if (_isHost && _currentPartyId != null) {
        // El host elimina la sala al salir
        await _supabase
            .from('vivotv_watch_parties')
            .delete()
            .eq('id', _currentPartyId!);
      }

      if (_channel != null) {
        await _supabase.removeChannel(_channel!);
      }
    } catch (e) {
      debugPrint('[WatchParty] Error saliendo de sala: $e');
    } finally {
      _currentPartyId = null;
      _isHost = false;
      _channel = null;
    }
  }
}
