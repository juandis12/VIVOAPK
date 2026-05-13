import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaybackState {
  final double currentTime;
  final bool isPlaying;
  final int timestamp;

  PlaybackState(this.currentTime, this.isPlaying, this.timestamp);
}

class WatchPartyEmote {
  final String emote;
  final String sender;

  WatchPartyEmote(this.emote, this.sender);
}

class WatchPartyManager {
  static final WatchPartyManager _instance = WatchPartyManager._internal();
  factory WatchPartyManager() => _instance;
  WatchPartyManager._internal();

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _currentChannel;
  String? _currentPartyId;
  bool isHost = false;
  String? currentUserName;

  // Streams / Notifiers
  final ValueNotifier<PlaybackState?> syncStream = ValueNotifier(null);
  final StreamController<WatchPartyEmote> emoteStreamCtrl = StreamController.broadcast();

  /// Unirse a una sala
  Future<Map<String, dynamic>?> joinParty(String partyId, String userName) async {
    try {
      final response = await _supabase
          .from('vivotv_watch_parties')
          .select('*')
          .eq('id', partyId)
          .maybeSingle();

      if (response == null) return null;

      _currentPartyId = partyId;
      isHost = false;
      currentUserName = userName;

      _initChannel(partyId);
      return response;
    } catch (e) {
      debugPrint('[WatchPartyManager] Error joinParty: $e');
      return null;
    }
  }

  /// Crear nueva sala
  Future<String?> createParty(String tmdbId, String type, String userName) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final data = await _supabase.from('vivotv_watch_parties').insert({
        'creator_id': userId,
        'creator_name': userName,
        'tmdb_id': tmdbId,
        'media_type': type,
        'is_playing': false,
        'room_time': 0,
      }).select().single();

      _currentPartyId = data['id'];
      isHost = true;
      currentUserName = userName;

      _initChannel(_currentPartyId!);
      return _currentPartyId;
    } catch (e) {
      debugPrint('[WatchPartyManager] Error createParty: $e');
      return null;
    }
  }

  void _initChannel(String partyId) {
    if (_currentChannel != null) {
      _supabase.removeChannel(_currentChannel!);
    }

    _currentChannel = _supabase.channel('party:$partyId');

    _currentChannel!.onBroadcast(
        event: 'sync',
        callback: (payload) {
          if (!isHost) {
            final double cTime = (payload['currentTime'] ?? 0).toDouble();
            final bool isPlay = payload['isPlaying'] ?? false;
            final int ts = payload['timestamp'] ?? 0;
            syncStream.value = PlaybackState(cTime, isPlay, ts);
          }
        });

    _currentChannel!.onBroadcast(
        event: 'emote',
        callback: (payload) {
          final emote = WatchPartyEmote(
            payload['emote'] ?? '😍',
            payload['sender'] ?? 'Usuario',
          );
          emoteStreamCtrl.add(emote);
        });

    _currentChannel!.onBroadcast(
        event: 'end_party',
        callback: (payload) {
          if (!isHost) {
            // Notificar a la UI para expulsar
            syncStream.value = PlaybackState(-1, false, -1); // Señal especial de fin
            leaveParty();
          }
        });

    _currentChannel!.subscribe((status, [error]) {
      debugPrint('[WatchPartyManager] Status: $status');
    });
  }

  void broadcastEndParty() {
    if (!isHost || _currentChannel == null) return;
    _currentChannel!.sendBroadcastMessage(
      event: 'end_party',
      payload: { 'timestamp': DateTime.now().millisecondsSinceEpoch },
    );
  }

  void broadcastSync(double currentTime, bool isPlaying) {
    if (!isHost || _currentChannel == null) return;

    _currentChannel!.sendBroadcastMessage(
      event: 'sync',
      payload: {
        'currentTime': currentTime,
        'isPlaying': isPlaying,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  void broadcastEmote(String emote) {
    if (_currentChannel == null) return;

    _currentChannel!.sendBroadcastMessage(
      event: 'emote',
      payload: {
        'emote': emote,
        'sender': currentUserName ?? 'App User',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
    // Auto-dibujar localmente
    emoteStreamCtrl.add(WatchPartyEmote(emote, currentUserName ?? 'App User'));
  }

  Future<void> leaveParty() async {
    if (isHost && _currentPartyId != null) {
      try {
        broadcastEndParty(); // Avisar invitados antes de salir
        await _supabase.from('vivotv_watch_parties').delete().eq('id', _currentPartyId!);
      } catch (e) {
        debugPrint('[WatchPartyManager] Error eliminando party.');
      }
    }
    if (_currentChannel != null) {
      await _supabase.removeChannel(_currentChannel!);
      _currentChannel = null;
    }
    _currentPartyId = null;
  }
}
