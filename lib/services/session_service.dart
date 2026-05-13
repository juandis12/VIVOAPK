import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:vivoweb_flutter/models/profile_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vivoweb_flutter/services/content_service.dart';
import 'package:vivoweb_flutter/services/achievements_service.dart';

class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  ProfileModel? _currentProfile;
  String? _deviceId;
  Timer? _heartbeatTimer;
  
  ProfileModel? get currentProfile => _currentProfile;
  User? get currentUser => Supabase.instance.client.auth.currentUser;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Restaurar perfil local
    final profileJson = prefs.getString('vivotv_current_profile');
    if (profileJson != null) {
      try {
        _currentProfile = ProfileModel.fromJson(json.decode(profileJson));
      } catch (_) {
        _currentProfile = null;
      }
    }

    // 2. CROSS-PLATFORM SYNC: Resincronizar si cambió en otro dispositivo/web
    final user = currentUser;
    if (user != null && user.userMetadata != null) {
      final lastPid = user.userMetadata!['last_profile_id'];
      if (lastPid != null && (_currentProfile == null || _currentProfile!.id != lastPid)) {
        debugPrint('[Sync] Detectado cambio de perfil global ($lastPid). Resincronizando...');
        try {
          final response = await Supabase.instance.client
              .from('vivotv_profiles')
              .select()
              .eq('id', lastPid)
              .maybeSingle();
          
          if (response != null) {
            final syncedProfile = ProfileModel.fromJson(response);
            await setProfile(syncedProfile, syncToGlobal: false);
            debugPrint('[Sync] ✅ Perfil sincronizado desde la nube: ${syncedProfile.name}');
          }
        } catch (e) {
          debugPrint('[Sync] Error en resincronización automática: $e');
        }
      }
    }

    // Restore or generate device ID
    _deviceId = prefs.getString('vivotv_device_id');
    if (_deviceId == null) {
      _deviceId = 'vtv-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
      await prefs.setString('vivotv_device_id', _deviceId!);
    }
  }

  Future<void> setProfile(ProfileModel profile, {bool syncToGlobal = true}) async {
    _currentProfile = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vivotv_current_profile', json.encode(profile.toJson()));
    
    // Inicializar sistema de logros/XP
    await AchievementsService().init(profile.id);

    if (syncToGlobal) {
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'last_profile_id': profile.id}),
        );
        debugPrint('[Sync] ✅ Metadatos globales actualizados con perfil: ${profile.id}');
      } catch (e) {
        debugPrint('[Sync] Error actualizando metadatos en Supabase: $e');
      }
    }
  }

  Future<void> clearSession() async {
    _currentProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vivotv_current_profile');
  }

  Future<void> logout() async {
    stopPeriodicHeartbeat();
    await clearSession();
    // ARCH-01: Limpiar suscripciones Realtime del ContentService al cerrar sesión.
    // Sin esto, los canales filtrados por user_id del usuario anterior permanecen
    // activos cuando el nuevo usuario inicia sesión con otra cuenta.
    try {
      ContentService().dispose();
    } catch (e) {
      debugPrint('[SessionService] Error al limpiar ContentService: $e');
    }
    await Supabase.instance.client.auth.signOut();
  }

  // ─── HEARTBEAT PERIÓDICO ─────────────────────────────────────────────────────
  // Equivalente al heartbeat de la web (auth.js). Pulsa cada 15 segundos
  // mientras la app está activa para mantener la sesión registrada y detectar
  // límites de sesiones concurrentes igual que la versión web.
  void startPeriodicHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      updateProfileTelemetry(null); // null = sigue vivo pero sin reproducción activa
    });
    debugPrint('[Heartbeat] ✅ Latido periódico iniciado (cada 15s).');
  }

  void stopPeriodicHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    debugPrint('[Heartbeat] ⏹ Latido periódico detenido.');
  }

  // ─── TELEMETRÍA + HEARTBEAT ──────────────────────────────────────────────────
  // Corrección: el catch ya no repite el update de now_playing si ya tuvo éxito.
  // Solo hace el update directo como fallback si el RPC falla.
  Future<void> updateProfileTelemetry(Map<String, dynamic>? status) async {
    if (_currentProfile == null) return;
    
    try {
      // Primero el heartbeat RPC (registra sesión activa)
      await Supabase.instance.client.rpc('vivotv_heartbeat', params: {'pid': _currentProfile!.id});
      // Si el RPC tuvo éxito, también actualizamos now_playing
      await Supabase.instance.client
          .from('vivotv_profiles')
          .update({'now_playing': status})
          .eq('id', _currentProfile!.id);
    } catch (e) {
      // RPC no existe o falló — intentar solo el update de now_playing como fallback
      // (NO lo repetimos si el update ya funcionó arriba)
      debugPrint('[Telemetria] RPC falló, usando fallback directo: $e');
      try {
        await Supabase.instance.client
            .from('vivotv_profiles')
            .update({'now_playing': status, 'last_heartbeat': DateTime.now().toIso8601String()})
            .eq('id', _currentProfile!.id);
      } catch (fallbackErr) {
        debugPrint('[Telemetria] Fallback también falló: $fallbackErr');
      }
    }
  }

  RealtimeChannel? _profileChannel;

  void subscribeToProfileChanges(Function onKick) {
    if (_currentProfile == null) return;
    
    _profileChannel?.unsubscribe();
    
    _profileChannel = Supabase.instance.client
        .channel('profile-${_currentProfile!.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'vivotv_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _currentProfile!.id,
          ),
          callback: (payload) {
            final newData = payload.newRecord;
            // BUG-04 FIX: El check anterior (last_heartbeat == null) era demasiado
            // frágil: Supabase Realtime solo envía las columnas modificadas en el
            // diff, por lo que campos no modificados aparecen como null en el payload.
            // Ahora verificamos un campo dedicado `force_logout` para expulsión
            // explícita, o un campo `kicked_at` con timestamp reciente.
            final forceLogout = newData['force_logout'] == true;
            final kickedAt = newData['kicked_at'];
            if (forceLogout || kickedAt != null) {
              debugPrint('[Realtime] ⚠️ Expulsión remota detectada (force_logout=$forceLogout).');
              onKick();
            }
          },
        );
    
    _profileChannel!.subscribe();
  }

  Future<bool> isSessionAllowed() async {
    final user = currentUser;
    if (user == null || _deviceId == null) return true;

    try {
      final response = await Supabase.instance.client.rpc('vivotv_check_session_limit', params: {
        'uid': user.id,
        'did': _deviceId,
      });
      
      if (response != null && response['allowed'] == false) {
        return false;
      }
    } catch (e) {
      // Legacy fallback check
      try {
        final now = DateTime.now().toIso8601String();
        await Supabase.instance.client.from('active_sessions').upsert({
          'user_id': user.id,
          'device_id': _deviceId,
          'last_seen': now,
        });

        final twoMinAgo = DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String();
        final sessions = await Supabase.instance.client
            .from('active_sessions')
            .select('device_id')
            .eq('user_id', user.id)
            .gt('last_seen', twoMinAgo);
        
        if ((sessions as List).length > 2) {
          final isAuthorized = sessions.take(2).any((s) => s['device_id'] == _deviceId);
          return isAuthorized;
        }
      } catch (_) {}
    }
    return true;
  }

  bool get hasActiveProfile => _currentProfile != null;

  /// Obtiene los datos más recientes del perfil desde Supabase y actualiza
  /// el estado local. Retorna el perfil actualizado o null si falla.
  Future<ProfileModel?> getLatestProfileData(String profileId) async {
    try {
      final response = await Supabase.instance.client
          .from('vivotv_profiles')
          .select()
          .eq('id', profileId)
          .maybeSingle();

      if (response != null) {
        final updatedProfile = ProfileModel.fromJson(response);
        _currentProfile = updatedProfile;
        // Persistir localmente sin actualizar el servidor (evitar bucle)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('vivotv_current_profile', json.encode(updatedProfile.toJson()));
        return updatedProfile;
      }
    } catch (e) {
      print('[Sync] Error obteniendo datos frescos del perfil: $e');
    }
    return null;
  }
}
